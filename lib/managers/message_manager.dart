// lib/managers/message_manager.dart

import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'dart:io';

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

/// ─────────────────────────────
/// 공통 함수: SMS 메시지 분석 API 호출
/// ─────────────────────────────
Future<Map<String, dynamic>> analyzeMessage(String body) async {
  // 개행문자 이스케이프
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
  // 에러 시 기본값 반환
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
  // 백그라운드에서는 로컬 플러그인 인스턴스를 직접 생성합니다.
  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await plugin.initialize(initSettings);

  final sender = message.address ?? 'Unknown';
  final body = message.body ?? '';
  final nowMillis = DateTime.now().millisecondsSinceEpoch;

  // 공통 API 호출
  final analysis = await analyzeMessage(body);
  final isSuspicious = analysis['is_suspicious'] as bool;
  final spamScore = analysis['spamScore'] as double;
  final spamReason = analysis['spamReason'] as String;
  final chatGptText = analysis['chatGptText'] as String;

  // 스팸 메시지이면 알림 표시
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

  // 메인 Isolate로 결과 전달
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
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  final ValueNotifier<List<HistoryItem>> items =
  ValueNotifier<List<HistoryItem>>([]);

  static const _prefsKey = 'my_sms_list';

  Future<void> init() async {
    await _initializeNotifications();
    await _requestPermissions();
    await _loadMessages();
    _listenSms();

    _insertDummyData(); // 필요 없으면 제거 가능
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
    final iconPath = isSuspicious
        ? 'assets/icons/check_green.png'
        : 'assets/icons/list.png';

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
    final list = jsonList
        .map((e) => HistoryItem.fromJson(jsonDecode(e)))
        .toList();
    items.value = list;
  }

  Future<void> _saveMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList =
    items.value.map((item) => jsonEncode(item.toJson())).toList();
    await prefs.setStringList(_prefsKey, jsonList);
  }

  void _listenSms() {
    telephony.listenIncomingSms(
      onNewMessage: (msg) async {
        final sender = msg.address ?? 'Unknown';
        final body = msg.body ?? '';
        final nowMillis = DateTime.now().millisecondsSinceEpoch;

        // 포그라운드에서도 공통 API 호출 및 알림 표시
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

    // 백그라운드 isolate로부터 전달받은 데이터를 메인 isolate에서 처리
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
    final iconPath = isSuspicious
        ? 'assets/icons/check_green.png'
        : 'assets/icons/list.png';

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
        spamScore: 83.0, // 70 이상 (빨간 UI)
        spamReason: 'AI를 활용한 분석 결과 비정상적인 URL, 발신자 정보 부족 등으로\n위험도가 70 이상이므로 해당 번호는 차단해주세요.',
        chatGptText: 'ChatGPT가 생성한 문구 예시.\n\n1. 주의\n2. 의심\n3. 계속',
      ),

      // 70 이하인 추가 더미 데이터 (초록색 UI)
      const HistoryItem(
        icon: 'assets/icons/re',
        title: '안전한 메시지\n이 문자는 위험 요소가 없습니다. 정상이므로 차단할 필요가 없습니다.',
        content: '해당 메시지는 AI 분석 결과 정상적으로 판단되었습니다.',
        dateTime: '2025-10-20 14:05:33',
        spamScore: 45.0, // 70 이하 (초록 UI)
        spamReason: 'AI 분석 결과 정상적인 메시지로 판단되었습니다.',
        chatGptText: 'ChatGPT가 분석한 결과 정상적인 문자입니다.',
      ),
    ];

    items.value = [...items.value, ...dummyList];
  }
}
