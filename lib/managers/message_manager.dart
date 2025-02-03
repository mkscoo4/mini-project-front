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

// flutter_contacts 라이브러리
import 'package:flutter_contacts/flutter_contacts.dart';

import 'package:koscom_test1/models/history_item.dart';
import 'package:koscom_test1/pages/detail/detail_page.dart';
import 'package:koscom_test1/main.dart' show navigatorKey, receivePort;

// 스팸 판별 임계값 상수
const double spamScoreThreshold = 70.0;
const String smsBgPortName = 'sms_bg_port';
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
  required double spamScore,
  required String spamReason,
  required String chatGptText,
}) async {
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

  // 메인 isolate로 placeholder 데이터 전송
  final sp = IsolateNameServer.lookupPortByName(smsBgPortName);
  if (sp != null) {
    sp.send({
      'address': sender,
      'body': body,
      'timestamp': nowMillis,
      'spamScore': 0.0,
      'spamReason': '분석 중...',
      'chatGptText': '분석 중...',
      'update': false,
    });
  }

  // 실제 분석
  final analysis = await analyzeMessage(body);
  final spamScore = analysis['spamScore'] as double;
  final spamReason = analysis['spamReason'] as String;
  final chatGptText = analysis['chatGptText'] as String;

  // 알림
  if (spamScore >= spamScoreThreshold) {
    await showNotification(
      plugin: plugin,
      sender: sender,
      body: body,
      timestamp: nowMillis,
      spamScore: spamScore,
      spamReason: spamReason,
      chatGptText: chatGptText,
    );
  }

  // 메인 isolate로 최종 데이터 전송 (update: true)
  if (sp != null) {
    sp.send({
      'address': sender,
      'body': body,
      'timestamp': nowMillis,
      'spamScore': spamScore,
      'spamReason': spamReason,
      'chatGptText': chatGptText,
      'update': true,
    });
  }
}

/// ─────────────────────────────
/// 메인 클래스
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

  // MMS 폴링 관련
  Timer? _mmsPollingTimer;
  int _lastMmsTimestamp = 0;

  // 연락처 목록(전화번호) 저장용 Set
  Set<String> _contactPhoneNumbers = {};

  Future<void> init() async {
    await _initializeNotifications();
    await _requestPermissions();
    // 먼저 연락처 목록 로드
    await _loadContacts();
    // 기존 메시지 목록 로드
    await _loadMessages();
    // SMS/MMS 수신 리스너 등록
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
      spamScore: spamScore.toDouble(),
      spamReason: spamReason,
      chatGptText: chatGptText,
    );

    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => DetailPage(historyItem: item)),
    );
  }

  /// 연락처 권한 및 알림 권한 요청
  Future<void> _requestPermissions() async {
    // SMS 권한
    if (await Permission.sms.isDenied) {
      await Permission.sms.request();
    }
    // 알림 권한(안드로이드 13 이상)
    if (Platform.isAndroid) {
      final ns = await Permission.notification.status;
      if (ns.isDenied || ns.isPermanentlyDenied) {
        await Permission.notification.request();
      }
    }
    // 연락처 권한
    if (await Permission.contacts.isDenied) {
      await Permission.contacts.request();
    }
  }

  /// flutter_contacts 로 연락처 불러와서 Set<String>에 저장
  Future<void> _loadContacts() async {
    try {
      // 사용자에게 연락처 권한 요청
      final hasPermission = await FlutterContacts.requestPermission();
      if (!hasPermission) {
        debugPrint("Contacts permission denied!");
        return;
      }

      // withProperties: 전화번호, 이메일 등 자세한 정보를 가져옴
      final List<Contact> contacts =
      await FlutterContacts.getContacts(withProperties: true);

      final Set<String> phoneNumbers = {};
      for (var c in contacts) {
        for (var phone in c.phones) {
          final normalized = _normalizePhoneNumber(phone.number);
          if (normalized.isNotEmpty) {
            phoneNumbers.add(normalized);
          }
        }
      }
      _contactPhoneNumbers = phoneNumbers;
      debugPrint('Loaded contacts. Count: ${_contactPhoneNumbers.length}');
    } catch (e) {
      debugPrint("Error loading contacts: $e");
    }
  }

  /// 불필요한 문자를 제거하는 간단한 예시
  /// (기호, 공백 등)
  String _normalizePhoneNumber(String phone) {
    return phone
        .replaceAll(RegExp(r'[\s\-\(\)\+]', multiLine: true), '')
        .trim();
  }

  /// 이 번호가 연락처에 있는지 여부 판별
  bool _isContactNumber(String? number) {
    if (number == null) return false;
    final normalized = _normalizePhoneNumber(number);
    return _contactPhoneNumbers.contains(normalized);
  }

  /// SharedPreferences에서 기존 메시지 목록 로드
  Future<void> _loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_prefsKey) ?? [];
    final list =
    jsonList.map((e) => HistoryItem.fromJson(jsonDecode(e))).toList();
    items.value = list;
  }

  /// SharedPreferences에 메시지 목록 저장
  Future<void> _saveMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList =
    items.value.map((item) => jsonEncode(item.toJson())).toList();
    await prefs.setStringList(_prefsKey, jsonList);
  }

  /// HistoryItem 추가/수정
  void _addOrUpdateHistoryItem({
    required int timestamp,
    required String address,
    required String body,
    required double spamScore,
    required String spamReason,
    required String chatGptText,
  }) {
    final current = List<HistoryItem>.from(items.value);
    final index = current.indexWhere((item) => item.timestamp == timestamp);

    String iconPath;
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

  /// SMS 리스너
  void _listenSms() {
    telephony.listenIncomingSms(
      onNewMessage: (msg) async {
        final sender = msg.address ?? 'Unknown';
        final body = msg.body ?? '';
        final nowMillis = DateTime.now().millisecondsSinceEpoch;

        // 1) 연락처에 저장된 번호인지 먼저 확인
        if (_isContactNumber(sender)) {
          // 연락처 번호면, API 요청 & 내역 추가 스킵
          return;
        }

        // 2) placeholder(분석중)
        _addOrUpdateHistoryItem(
          timestamp: nowMillis,
          address: sender,
          body: body,
          spamScore: 0.0,
          spamReason: '분석 중...',
          chatGptText: '분석 중...',
        );

        // 3) 분석
        final analysis = await analyzeMessage(body);
        final spamScore = analysis['spamScore'] as double;
        final spamReason = analysis['spamReason'] as String;
        final chatGptText = analysis['chatGptText'] as String;

        // 4) 스팸 알림
        if (spamScore >= spamScoreThreshold) {
          await showNotification(
            plugin: _notificationsPlugin,
            sender: sender,
            body: body,
            timestamp: nowMillis,
            spamScore: spamScore,
            spamReason: spamReason,
            chatGptText: chatGptText,
          );
        }

        // 5) 최종 내역 갱신
        _addOrUpdateHistoryItem(
          timestamp: nowMillis,
          address: sender,
          body: body,
          spamScore: spamScore,
          spamReason: spamReason,
          chatGptText: chatGptText,
        );
      },
      onBackgroundMessage: backgroundMessageHandler,
      listenInBackground: true,
    );

    // 백그라운드 isolate -> 메인 isolate 데이터 수신
    receivePort.listen((data) {
      if (data is Map) {
        final ts = data['timestamp'] as int? ?? 0;
        final address = data['address'] as String? ?? 'Unknown';
        final body = data['body'] as String? ?? '';
        final spamScore = (data['spamScore'] as num?)?.toDouble() ?? 0.0;
        final spamReason = data['spamReason'] as String? ?? '';
        final chatGptText = data['chatGptText'] as String? ?? '';

        // 연락처에 저장된 번호인지 확인
        if (_isContactNumber(address)) {
          // 연락처 번호면 추가 안 함
          return;
        }

        // 그렇지 않다면 히스토리에 추가/업데이트
        _addOrUpdateHistoryItem(
          timestamp: ts,
          address: address,
          body: body,
          spamScore: spamScore,
          spamReason: spamReason,
          chatGptText: chatGptText,
        );
      }
    });
  }

  /// MMS 수신(폴링)
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

          // 연락처에 저장된 번호인지 확인
          if (_isContactNumber(address)) {
            // 연락처 번호면 MMS 분석/내역 추가 스킵
            return;
          }

          // 1) MMS 본문 가져오기
          final mmsText = await _mmsChannel.invokeMethod(
            'getMmsText',
            {'mmsId': mmsId},
          ) as String? ??
              '';

          // 2) placeholder 추가
          _addOrUpdateHistoryItem(
            timestamp: timestamp,
            address: address,
            body: mmsText,
            spamScore: 0.0,
            spamReason: '분석 중...',
            chatGptText: '분석 중...',
          );

          // 3) 분석
          final analysis = await analyzeMessage(mmsText);
          final spamScore = analysis['spamScore'] as double;
          final spamReason = analysis['spamReason'] as String;
          final chatGptText = analysis['chatGptText'] as String;

          // 4) 스팸 알림
          if (spamScore >= spamScoreThreshold) {
            await showNotification(
              plugin: _notificationsPlugin,
              sender: address,
              body: mmsText,
              timestamp: timestamp,
              spamScore: spamScore,
              spamReason: spamReason,
              chatGptText: chatGptText,
            );
          }

          // 5) 최종 내역 갱신
          _addOrUpdateHistoryItem(
            timestamp: timestamp,
            address: address,
            body: mmsText,
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

  /// 메시지 삭제
  void deleteMessage(int index) {
    final current = List<HistoryItem>.from(items.value);
    if (index >= 0 && index < current.length) {
      current.removeAt(index);
      items.value = current;
      _saveMessages();
    }
  }
}
