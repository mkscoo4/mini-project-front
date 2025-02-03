// lib/managers/message_manager.dart

import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'dart:io';
import 'package:flutter/services.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:telephony/telephony.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:koscom_test1/models/history_item.dart';
import 'package:koscom_test1/pages/detail/detail_page.dart';
import 'package:koscom_test1/main.dart' show navigatorKey, receivePort;

// 스팸 판별 임계값 상수 (한 곳에서 수정 가능)
const double spamScoreThreshold = 70.0;

// 백그라운드 isolate → 메인 isolate 통신용 포트 이름
const String smsBgPortName = 'sms_bg_port';

// MethodChannel 객체 (MMS 관련)
const MethodChannel _mmsChannel = MethodChannel('com.example.koscom_test1/mms');

/// ─────────────────────────────
/// 공통 함수: SMS 메시지 분석 API 호출
/// ─────────────────────────────
Future<Map<String, dynamic>> analyzeMessage(String body) async {
  final escapedBody = body.replaceAll('\n', '\\n');
  try {
    final response = await http.post(
      Uri.parse(
          'http://ec2-3-39-250-8.ap-northeast-2.compute.amazonaws.com:3000/api/v1/analyze'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'message': escapedBody}),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      // description 필드가 list 형태일 경우, 각 요소를 '\n'로 이어 붙인다.
      final dynamic descData = data['description'];
      String chatGptText;
      if (descData is List) {
        chatGptText = descData.join('\n');
      } else if (descData != null) {
        chatGptText = descData.toString();
      } else {
        chatGptText = '';
      }

      return {
        // 기존 is_suspicious 값은 나중에 사용할 수 있도록 주석 처리
        // 'is_suspicious': data['is_suspicious'] as bool,
        'spamScore': (data['score'] as num).toDouble(),
        'spamReason': data['summary'] as String,
        'chatGptText': chatGptText,
      };
    } else {
      debugPrint("API Error: ${response.statusCode} ${response.body}");
    }
  } catch (e) {
    debugPrint("API request failed: $e");
  }
  return {
    // 'is_suspicious': false,
    'spamScore': 0.0,
    'spamReason': '',
    'chatGptText': '',
  };
}

/// ─────────────────────────────
/// 공통 함수: 스팸 메시지일 경우 알림 표시
/// ─────────────────────────────
Future<void> showNotification({
  required FlutterLocalNotificationsPlugin plugin,
  required String sender,
  required String body,
  required int timestamp,
  // required bool isSuspicious, // 기존 isSuspicious 값 (나중에 사용할 수 있음)
  required double spamScore,
  required String spamReason,
  required String chatGptText,
}) async {
  // spam 판별은 spamScore 기준으로 함
  if (spamScore >= spamScoreThreshold) {
    final previewLen = body.length < 20 ? body.length : 20;
    final previewBody = body.substring(0, previewLen);
    final titleText = '$sender 에게서 온 메시지';
    final bodyText =
        '“$previewBody” 가 스팸 문자일 가능성이 높습니다! 여기서 확인하세요!';

    const androidDetails = AndroidNotificationDetails(
      'sms_channel',
      'SMS Notifications',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );
    const notificationDetails = NotificationDetails(android: androidDetails);
    final uniqueId = timestamp ~/ 1000;
    await plugin.show(
      uniqueId,
      titleText,
      bodyText,
      notificationDetails,
      payload: jsonEncode({
        'address': sender,
        'body': body,
        'timestamp': timestamp,
        // 'is_suspicious': isSuspicious, // 기존 isSuspicious 값 (보존)
        'spamScore': spamScore,
        'spamReason': spamReason,
        'chatGptText': chatGptText,
      }),
    );
  }
}

/// ─────────────────────────────
/// 백그라운드 SMS 수신 시 호출되는 핸들러
/// ─────────────────────────────
@pragma('vm:entry-point')
void backgroundMessageHandler(SmsMessage message) async {
  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await plugin.initialize(initSettings);

  final sender = message.address ?? 'Unknown';
  final body = message.body ?? '';
  final nowMillis = DateTime.now().millisecondsSinceEpoch;

  // placeholder 데이터를 먼저 전달 (전체 메시지 사용)
  final sp = IsolateNameServer.lookupPortByName(smsBgPortName);
  if (sp != null) {
    sp.send({
      'address': sender,
      'body': body,
      'timestamp': nowMillis,
      // 'is_suspicious': false, // 기존 값 (보존)
      'spamScore': 0.0,
      'spamReason': '분석 중...',
      'chatGptText': '분석 중...',
      'update': false,
    });
  }

  final analysis = await analyzeMessage(body);
  // final isSuspicious = analysis['is_suspicious'] as bool; // 기존 변수 (보존)
  final spamScore = analysis['spamScore'] as double;
  final spamReason = analysis['spamReason'] as String;
  final chatGptText = analysis['chatGptText'] as String;

  if (spamScore >= spamScoreThreshold) {
    await showNotification(
      plugin: plugin,
      sender: sender,
      body: body,
      timestamp: nowMillis,
      // isSuspicious: isSuspicious, // 기존 값 (보존)
      spamScore: spamScore,
      spamReason: spamReason,
      chatGptText: chatGptText,
    );
  }

  if (sp != null) {
    sp.send({
      'address': sender,
      'body': body,
      'timestamp': nowMillis,
      // 'is_suspicious': isSuspicious, // 기존 값 (보존)
      'spamScore': spamScore,
      'spamReason': spamReason,
      'chatGptText': chatGptText,
      'update': true,
    });
  }
}

/// ─────────────────────────────
/// 메인 클래스: 포그라운드 SMS 및 MMS 수신 및 처리
/// ─────────────────────────────
class MessageManager {
  static final MessageManager instance = MessageManager._internal();
  MessageManager._internal();

  final Telephony telephony = Telephony.instance;
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  final ValueNotifier<List<HistoryItem>> items =
  ValueNotifier<List<HistoryItem>>([]);

  static const _prefsKey = 'my_sms_list';

  // MMS 폴링 관련 변수: 최신 MMS의 타임스탬프 저장
  Timer? _mmsPollingTimer;
  int _lastMmsTimestamp = 0;

  Future<void> init() async {
    await _initializeNotifications();
    await _requestPermissions();
    await _loadMessages();
    _listenSms();
    _listenMms();
  }

  Future<void> _initializeNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        final payload = details.payload;
        if (payload != null) {
          final data = jsonDecode(payload);
          _handleNotificationClick(data);
        }
      },
    );
  }

  void _handleNotificationClick(Map<String, dynamic> data) {
    final addr = data['address'] as String? ?? 'Unknown';
    final body = data['body'] as String? ?? '';
    final ts = data['timestamp'] as int? ?? 0;
    final spamScore = data['spamScore'] as num? ?? 0;
    final spamReason = data['spamReason'] as String? ?? '';
    final chatGptText = data['chatGptText'] as String? ?? '';

    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    String iconPath;
    // placeholder 상태이면 spinner, 아니면 spamScore 기준으로 아이콘 결정
    if (spamReason == '분석 중...') {
      iconPath = 'spinner';
    } else {
      iconPath = (spamScore >= spamScoreThreshold)
          ? 'assets/icons/check_red.png'
          : 'assets/icons/check_green.png';
    }

    final item = HistoryItem(
      timestamp: ts,
      icon: iconPath,
      title: '[$addr]\n$body',
      content: '',
      dateTime: dt.toString().substring(0, 19),
      // spamScore, spamReason, chatGptText는 그대로 사용
      spamScore: spamScore.toDouble(),
      spamReason: spamReason,
      chatGptText: chatGptText,
    );

    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => DetailPage(historyItem: item)),
    );
  }

  Future<void> _requestPermissions() async {
    if (await Permission.sms.isDenied) {
      await Permission.sms.request();
    }
    if (Platform.isAndroid) {
      final ns = await Permission.notification.status;
      if (ns.isDenied || ns.isPermanentlyDenied) {
        await Permission.notification.request();
      }
    }
  }

  Future<void> _loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_prefsKey) ?? [];
    final list =
    jsonList.map((e) => HistoryItem.fromJson(jsonDecode(e))).toList();
    items.value = list;
  }

  Future<void> _saveMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList =
    items.value.map((item) => jsonEncode(item.toJson())).toList();
    await prefs.setStringList(_prefsKey, jsonList);
  }

  /// placeholder 항목 추가 후 나중에 분석 결과로 업데이트하는 함수
  /// (timestamp를 고유 식별자로 사용)
  /// isSuspicious 관련 변수는 추후 사용을 위해 주석으로 보존함.
  void _addOrUpdateHistoryItem({
    required int timestamp,
    required String address,
    required String body,
    // required bool isSuspicious, // 기존 변수 (보존, 추후 사용 예정)
    required double spamScore,
    required String spamReason,
    required String chatGptText,
  }) {
    final current = List<HistoryItem>.from(items.value);
    final index = current.indexWhere((item) => item.timestamp == timestamp);

    String iconPath;
    // placeholder 상태이면 spinner, 아니면 spamScore 기준에 따라 아이콘 결정
    if (spamReason == '분석 중...') {
      iconPath = 'spinner';
    } else {
      iconPath = (spamScore >= spamScoreThreshold)
          ? 'assets/icons/check_red.png'
          : 'assets/icons/check_green.png';
    }

    final dtStr = DateTime.fromMillisecondsSinceEpoch(timestamp)
        .toString()
        .substring(0, 19);

    final newItem = HistoryItem(
      timestamp: timestamp,
      icon: iconPath,
      title: '[$address]\n$body',
      content: '',
      dateTime: dtStr,
      spamScore: spamScore,
      spamReason: spamReason,
      chatGptText: chatGptText,
    );

    if (index >= 0) {
      current[index] = newItem;
    } else {
      current.insert(0, newItem);
    }
    items.value = current;
    _saveMessages();
  }

  void _listenSms() {
    telephony.listenIncomingSms(
      onNewMessage: (msg) async {
        final sender = msg.address ?? 'Unknown';
        final body = msg.body ?? '';
        final nowMillis = DateTime.now().millisecondsSinceEpoch;

        // ① placeholder 항목 즉시 추가 (SMS: 전체 body 사용)
        _addOrUpdateHistoryItem(
          timestamp: nowMillis,
          address: sender,
          body: body,
          // isSuspicious: false, // 기존 값 (보존)
          spamScore: 0.0,
          spamReason: '분석 중...',
          chatGptText: '분석 중...',
        );

        // ② 분석 API 호출 후 결과로 업데이트
        final analysis = await analyzeMessage(body);
        // final isSuspicious = analysis['is_suspicious'] as bool; // 기존 값 (보존)
        final spamScore = analysis['spamScore'] as double;
        final spamReason = analysis['spamReason'] as String;
        final chatGptText = analysis['chatGptText'] as String;

        if (spamScore >= spamScoreThreshold) {
          await showNotification(
            plugin: _notificationsPlugin,
            sender: sender,
            body: body,
            timestamp: nowMillis,
            // isSuspicious: isSuspicious, // 기존 값 (보존)
            spamScore: spamScore,
            spamReason: spamReason,
            chatGptText: chatGptText,
          );
        }

        _addOrUpdateHistoryItem(
          timestamp: nowMillis,
          address: sender,
          body: body,
          // isSuspicious: isSuspicious, // 기존 값 (보존)
          spamScore: spamScore,
          spamReason: spamReason,
          chatGptText: chatGptText,
        );
      },
      onBackgroundMessage: backgroundMessageHandler,
      listenInBackground: true,
    );

    receivePort.listen((data) {
      if (data is Map) {
        final ts = data['timestamp'] as int? ?? 0;
        _addOrUpdateHistoryItem(
          timestamp: ts,
          address: data['address'] as String? ?? 'Unknown',
          body: data['body'] as String? ?? '',
          // isSuspicious: data['is_suspicious'] as bool? ?? false, // 기존 값 (보존)
          spamScore: (data['spamScore'] as num?)?.toDouble() ?? 0.0,
          spamReason: data['spamReason'] as String? ?? '',
          chatGptText: data['chatGptText'] as String? ?? '',
        );
      }
    });
  }

  /// MMS를 0.5초마다 폴링하여 처리하는 함수 (실시간 처리)
  void _listenMms() {
    const pollInterval = Duration(milliseconds: 500);
    _mmsPollingTimer = Timer.periodic(pollInterval, (timer) async {
      try {
        final result = await _mmsChannel.invokeMethod('getLatestMms');
        if (result != null && result is Map) {
          final mmsId = result['id'] as String?;
          final address = result['address'] as String? ?? 'Unknown';
          final timestamp = result['timestamp'] as int? ??
              DateTime.now().millisecondsSinceEpoch;
          if (mmsId == null) return;
          if (timestamp <= _lastMmsTimestamp) return;
          _lastMmsTimestamp = timestamp;

          // MMS 본문을 가져와서 전체 본문 사용
          final mmsText = await _mmsChannel.invokeMethod(
            'getMmsText',
            {'mmsId': mmsId},
          ) as String? ??
              '';

          // placeholder 항목 추가 (전체 mmsText 사용, 아이콘은 spinner 처리)
          _addOrUpdateHistoryItem(
            timestamp: timestamp,
            address: address,
            body: mmsText,
            // isSuspicious: false, // 기존 값 (보존)
            spamScore: 0.0,
            spamReason: '분석 중...',
            chatGptText: '분석 중...',
          );

          // 분석 및 알림 처리
          final analysis = await analyzeMessage(mmsText);
          // final isSuspicious = analysis['is_suspicious'] as bool; // 기존 값 (보존)
          final spamScore = analysis['spamScore'] as double;
          final spamReason = analysis['spamReason'] as String;
          final chatGptText = analysis['chatGptText'] as String;

          if (spamScore >= spamScoreThreshold) {
            await showNotification(
              plugin: _notificationsPlugin,
              sender: address,
              body: mmsText,
              timestamp: timestamp,
              // isSuspicious: isSuspicious, // 기존 값 (보존)
              spamScore: spamScore,
              spamReason: spamReason,
              chatGptText: chatGptText,
            );
          }

          _addOrUpdateHistoryItem(
            timestamp: timestamp,
            address: address,
            body: mmsText,
            // isSuspicious: isSuspicious, // 기존 값 (보존)
            spamScore: spamScore,
            spamReason: spamReason,
            chatGptText: chatGptText,
          );
        }
      } catch (e) {
        debugPrint("Error polling MMS: $e");
      }
    });
  }
  /// ─────────────────────────────
  /// 삭제 기능: 인덱스를 받아서 삭제
  /// ─────────────────────────────
  void deleteMessage(int index) {
    final current = List<HistoryItem>.from(items.value);
    if (index >= 0 && index < current.length) {
      current.removeAt(index);
      items.value = current;
      _saveMessages();
    }
  }
}
