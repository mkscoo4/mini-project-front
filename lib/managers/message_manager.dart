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
      Uri.parse('http://ec2-3-39-250-8.ap-northeast-2.compute.amazonaws.com:3000/api/v1/analyze'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'message': escapedBody}),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return {
        'is_suspicious': data['is_suspicious'] as bool,
        'spamScore': (data['score'] as num).toDouble(),
        'spamReason': data['summary'] as String,
        'chatGptText': data['description'] as String,
      };
    } else {
      debugPrint("API Error: ${response.statusCode} ${response.body}");
    }
  } catch (e) {
    debugPrint("API request failed: $e");
  }
  return {
    'is_suspicious': false,
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
  required bool isSuspicious,
  required double spamScore,
  required String spamReason,
  required String chatGptText,
}) async {
  if (isSuspicious) {
    final previewLen = body.length < 20 ? body.length : 20;
    final previewBody = body.substring(0, previewLen);
    final titleText = '$sender 에게서 온 메시지';
    final bodyText = '“$previewBody” 가 스팸 문자일 가능성이 높습니다! 여기서 확인하세요!';

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
        'is_suspicious': isSuspicious,
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

  final analysis = await analyzeMessage(body);
  final isSuspicious = analysis['is_suspicious'] as bool;
  final spamScore = analysis['spamScore'] as double;
  final spamReason = analysis['spamReason'] as String;
  final chatGptText = analysis['chatGptText'] as String;

  await showNotification(
    plugin: plugin,
    sender: sender,
    body: body,
    timestamp: nowMillis,
    isSuspicious: isSuspicious,
    spamScore: spamScore,
    spamReason: spamReason,
    chatGptText: chatGptText,
  );

  final sp = IsolateNameServer.lookupPortByName(smsBgPortName);
  if (sp != null) {
    sp.send({
      'address': sender,
      'body': body,
      'timestamp': nowMillis,
      'is_suspicious': isSuspicious,
      'spamScore': spamScore,
      'spamReason': spamReason,
      'chatGptText': chatGptText,
    });
  }
}

/// ─────────────────────────────
/// 메인 클래스: 포그라운드 SMS 수신 및 처리
/// ─────────────────────────────
class MessageManager {
  static final MessageManager instance = MessageManager._internal();
  MessageManager._internal();

  final Telephony telephony = Telephony.instance;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  final ValueNotifier<List<HistoryItem>> items = ValueNotifier<List<HistoryItem>>([]);

  static const _prefsKey = 'my_sms_list';

  // MMS 폴링 관련 변수: 최신 MMS의 타임스탬프 저장
  Timer? _mmsPollingTimer;
  int _lastMmsTimestamp = 0;

  Future<void> init() async {
    await _initializeNotifications();
    await _requestPermissions();
    await _loadMessages();
    _listenSms();
    _listenMms(); // MMS 폴링 시작

    _insertDummyData(); // 테스트용 더미 데이터 (필요없으면 제거)
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
    final isSuspicious = data['is_suspicious'] as bool? ?? false;
    final spamScore = data['spamScore'] as num? ?? 0;
    final spamReason = data['spamReason'] as String? ?? '';
    final chatGptText = data['chatGptText'] as String? ?? '';

    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    final iconPath = isSuspicious ? 'assets/icons/check_green.png' : 'assets/icons/list.png';

    final item = HistoryItem(
      icon: iconPath,
      title: '[$addr]\n$body',
      content: '',
      dateTime: dt.toString().substring(0, 19),
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
    final list = jsonList.map((e) => HistoryItem.fromJson(jsonDecode(e))).toList();
    items.value = list;
  }

  Future<void> _saveMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = items.value.map((item) => jsonEncode(item.toJson())).toList();
    await prefs.setStringList(_prefsKey, jsonList);
  }

  void _listenSms() {
    telephony.listenIncomingSms(
      onNewMessage: (msg) async {
        final sender = msg.address ?? 'Unknown';
        final body = msg.body ?? '';
        final nowMillis = DateTime.now().millisecondsSinceEpoch;

        final analysis = await analyzeMessage(body);
        final isSuspicious = analysis['is_suspicious'] as bool;
        final spamScore = analysis['spamScore'] as double;
        final spamReason = analysis['spamReason'] as String;
        final chatGptText = analysis['chatGptText'] as String;

        await showNotification(
          plugin: _notificationsPlugin,
          sender: sender,
          body: body,
          timestamp: nowMillis,
          isSuspicious: isSuspicious,
          spamScore: spamScore,
          spamReason: spamReason,
          chatGptText: chatGptText,
        );

        _addHistoryItem(
          address: sender,
          body: body,
          timestamp: nowMillis,
          isSuspicious: isSuspicious,
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
        _addHistoryItem(
          address: data['address'] as String? ?? 'Unknown',
          body: data['body'] as String? ?? '',
          timestamp: data['timestamp'] as int? ?? 0,
          isSuspicious: data['is_suspicious'] as bool? ?? false,
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
        // 네이티브에서 최신 MMS 정보를 가져옵니다.
        // getLatestMms는 MMS가 없으면 null 또는 빈 Map을 반환하도록 구현되어 있습니다.
        final result = await _mmsChannel.invokeMethod('getLatestMms');
        if (result != null && result is Map) {
          // 예시 반환 Map: { "id": "12345", "address": "+821012345678", "timestamp": 1670000000000 }
          final mmsId = result['id'] as String?;
          final address = result['address'] as String? ?? 'Unknown';
          final timestamp = result['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;
          if (mmsId == null) return;

          // 중복 처리를 위해 마지막 처리 시각보다 이후 MMS만 처리
          if (timestamp <= _lastMmsTimestamp) return;
          _lastMmsTimestamp = timestamp;

          // 네이티브 메소드 getMmsText를 호출하여 MMS 텍스트를 가져옵니다.
          final body = await _mmsChannel.invokeMethod('getMmsText', {'mmsId': mmsId}) as String? ?? '';

          // SMS와 동일하게 분석 및 알림 처리
          final analysis = await analyzeMessage(body);
          final isSuspicious = analysis['is_suspicious'] as bool;
          final spamScore = analysis['spamScore'] as double;
          final spamReason = analysis['spamReason'] as String;
          final chatGptText = analysis['chatGptText'] as String;

          await showNotification(
            plugin: _notificationsPlugin,
            sender: address,
            body: body,
            timestamp: timestamp,
            isSuspicious: isSuspicious,
            spamScore: spamScore,
            spamReason: spamReason,
            chatGptText: chatGptText,
          );

          _addHistoryItem(
            address: address,
            body: body,
            timestamp: timestamp,
            isSuspicious: isSuspicious,
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

  void _addHistoryItem({
    required String address,
    required String body,
    required int timestamp,
    required bool isSuspicious,
    required double spamScore,
    required String spamReason,
    required String chatGptText,
  }) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final iconPath = isSuspicious ? 'assets/icons/check_green.png' : 'assets/icons/list.png';
    final newItem = HistoryItem(
      icon: iconPath,
      title: '[$address]\n$body',
      content: '',
      dateTime: dt.toString().substring(0, 19),
      spamScore: spamScore,
      spamReason: spamReason,
      chatGptText: chatGptText,
    );
    final current = List<HistoryItem>.from(items.value);
    current.insert(0, newItem);
    items.value = current;
    _saveMessages();
  }

  // (테스트용) 더미 데이터 삽입
  void _insertDummyData() {
    final dummyList = <HistoryItem>[
      const HistoryItem(
        icon: 'assets/icons/check_green.png',
        title: '오늘의 종목 추천\n오늘 놓치면 안됩니다.!!!!!!오늘의 종목 추천 오늘 놓치면 안됩니다.오늘의 종목 추천~~!!오늘 놓치면 안됩니다.!!!!!!오늘의 종목 추천 오늘 놓치면 안됩니다.',
        content: '상세 내용이 더 있을 수 있음',
        dateTime: '2025-10-19 12:12:12',
        spamScore: 83.0,
        spamReason: 'AI를 활용한 분석 결과 비정상적인 URL, 발신자 정보 부족 등으로\n위험도가 70 이상이므로 해당 번호는 차단해주세요.',
        chatGptText: 'ChatGPT가 생성한 문구 예시.\n\n1. 주의\n2. 의심\n3. 계속',
      ),
      const HistoryItem(
        icon: 'assets/icons/re',
        title: '안전한 메시지\n이 문자는 위험 요소가 없습니다. 정상이므로 차단할 필요가 없습니다.',
        content: '해당 메시지는 AI 분석 결과 정상적으로 판단되었습니다.',
        dateTime: '2025-10-20 14:05:33',
        spamScore: 45.0,
        spamReason: 'AI 분석 결과 정상적인 메시지로 판단되었습니다.',
        chatGptText: 'ChatGPT가 분석한 결과 정상적인 문자입니다.',
      ),
    ];
    items.value = [...items.value, ...dummyList];
  }
}
