// lib/managers/message_manager.dart

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:telephony/telephony.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

import 'package:koscom_test1/models/history_item.dart';
import 'package:koscom_test1/pages/detail/detail_page.dart';
import 'package:koscom_test1/main.dart' show navigatorKey, receivePort;
// or adjust import if main.dart references them differently.

const String smsBgPortName = 'sms_bg_port';

@pragma('vm:entry-point')
void backgroundMessageHandler(SmsMessage message) async {
  final plugin = FlutterLocalNotificationsPlugin();

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await plugin.initialize(initSettings);

  const androidDetails = AndroidNotificationDetails(
    'sms_channel',
    'SMS Notifications',
    importance: Importance.high,
    priority: Priority.high,
    showWhen: true,
  );
  const notificationDetails = NotificationDetails(android: androidDetails);

  final sender = message.address ?? 'Unknown';
  final body = message.body ?? '';
  final nowMillis = DateTime.now().millisecondsSinceEpoch;
  final hasDudungtak = body.contains('dudungtak');

  if (hasDudungtak) {
    final previewLen = body.length < 20 ? body.length : 20;
    final previewBody = body.substring(0, previewLen);

    final uniqueId = nowMillis ~/ 1000;
    final titleText = '$sender 에게서 온 메시지';
    final bodyText =
        '“$previewBody” 가 스팸 문자일 가능성이 높습니다! 여기서 확인하세요!';

    await plugin.show(
      uniqueId,
      titleText,
      bodyText,
      notificationDetails,
      payload: jsonEncode({
        'address': sender,
        'body': body,
        'timestamp': nowMillis,
        'hasDudungtak': true,
      }),
    );
  }

  final sp = IsolateNameServer.lookupPortByName(smsBgPortName);
  if (sp != null) {
    sp.send({
      'address': sender,
      'body': body,
      'timestamp': nowMillis,
      'hasDudungtak': hasDudungtak,
    });
  }
}

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

    _insertDummyData();
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
    final hasDudungtak = data['hasDudungtak'] as bool? ?? false;

    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    final iconPath =
    hasDudungtak ? 'assets/icons/check_green.png' : 'assets/icons/list.png';

    final item = HistoryItem(
      icon: iconPath,
      title: '[$addr]\n$body',
      content: '',
      dateTime: dt.toString().substring(0, 19),
      spamScore: hasDudungtak ? 90.0 : 30.0,
      spamReason: hasDudungtak
          ? '메시지 dudungtak 포함'
          : '일반 메시지로 보임',
      chatGptText: 'AI 분석...',
    );

    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => DetailPage(historyItem: item)),
    );
  }

  Future<void> _requestPermissions() async {
    // SMS
    if (await Permission.sms.isDenied) {
      await Permission.sms.request();
    }
    // 알림 (안드로이드13)
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
    final jsonList =
    items.value.map((item) => jsonEncode(item.toJson())).toList();
    await prefs.setStringList(_prefsKey, jsonList);
  }

  void _listenSms() {
    telephony.listenIncomingSms(
      onNewMessage: (msg) {
        final sender = msg.address ?? 'Unknown';
        final body = msg.body ?? '';
        final nowMillis = DateTime.now().millisecondsSinceEpoch;
        final hasDudungtak = body.contains('dudungtak');

        if (hasDudungtak) {
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

          final uniqueId = nowMillis ~/ 1000;
          _notificationsPlugin.show(
            uniqueId,
            titleText,
            bodyText,
            notificationDetails,
            payload: jsonEncode({
              'address': sender,
              'body': body,
              'timestamp': nowMillis,
              'hasDudungtak': true,
            }),
          );
        }

        _addHistoryItem(
          address: sender,
          body: body,
          timestamp: nowMillis,
          hasDudungtak: hasDudungtak,
        );
      },
      onBackgroundMessage: backgroundMessageHandler,
      listenInBackground: true,
    );

    // BG -> 메인 Isolate
    receivePort.listen((data) {
      if (data is Map) {
        _addHistoryItem(
          address: data['address'] as String? ?? 'Unknown',
          body: data['body'] as String? ?? '',
          timestamp: data['timestamp'] as int? ?? 0,
          hasDudungtak: data['hasDudungtak'] as bool? ?? false,
        );
      }
    });
  }

  void _addHistoryItem({
    required String address,
    required String body,
    required int timestamp,
    required bool hasDudungtak,
  }) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final iconPath =
    hasDudungtak ? 'assets/icons/check_green.png' : 'assets/icons/list.png';

    final newItem = HistoryItem(
      icon: iconPath,
      title: '[$address]\n$body',
      content: '',
      dateTime: dt.toString().substring(0, 19),
      spamScore: hasDudungtak ? 90.0 : 30.0,
      spamReason: hasDudungtak
          ? '메시지 dudungtak 포함'
          : '일반 메시지로 보임',
      chatGptText: 'AI 분석...',
    );

    final current = List<HistoryItem>.from(items.value);
    current.insert(0, newItem);
    items.value = current;

    _saveMessages();
  }

  void _insertDummyData() {
    final dummyList = <HistoryItem>[
      const HistoryItem(
        icon: 'assets/icons/check_green.png',
        title: '오늘의 종목 추천\n오늘 놓치면 안됩니다....',
        content: '상세 내용이 더 있을 수 있음',
        dateTime: '2025-10-19 12:12:12',
        spamScore: 83.0,
        spamReason: 'AI를 활용한 분석 결과 비정상적인 URL, 발신자 정보 부족 등으로\n'
            '위험도가 70 이상이므로 해당 번호는 차단해주세요.',
        chatGptText: 'ChatGPT가 생성한 문구 예시.\n\n1. 주의\n2. 의심\n3. 계속',
      ),
    ];
    items.value = [...items.value, ...dummyList];
  }
}
