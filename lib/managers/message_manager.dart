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

// flutter_contacts (연락처)
import 'package:flutter_contacts/flutter_contacts.dart';

import 'package:koscom_test1/models/history_item.dart';
import 'package:koscom_test1/pages/detail/detail_page.dart';
import 'package:koscom_test1/main.dart' show navigatorKey, receivePort;

// 스팸 판별 임계값
const double spamScoreThreshold = 70.0;
const String smsBgPortName = 'sms_bg_port';
const MethodChannel _mmsChannel = MethodChannel('com.example.koscom_test1/mms');

/// 한국 시간대 (UTC+9) 기준 08:00~21:00 사이 여부
bool _isWithinKRWorkingHours() {
  final nowUtc = DateTime.now().toUtc();
  final nowKr = nowUtc.add(const Duration(hours: 9));
  final hour = nowKr.hour; // 0~23
  return hour >= 8 && hour < 21;
}

/// ─────────────────────────────
/// 화이트리스트 로드 및 체크 함수들
/// ─────────────────────────────
Set<String> _whiteListUrls = {};

/// 앱 시작 시, assets/whitelist.txt를 읽어 _whiteListUrls에 저장
Future<void> _loadWhiteList() async {
  try {
    final text = await rootBundle.loadString('assets/whitelist.txt');
    final lines = text.split(RegExp(r'\r?\n'));
    _whiteListUrls = lines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toSet();
    debugPrint("Whitelist loaded: ${_whiteListUrls.length} items");
  } catch (e) {
    debugPrint("Failed to load whitelist: $e");
  }
}

/// 메시지 본문이 화이트리스트 URL을 포함하고 있는지 검사
/// - "subdomain이어도 가능" → 실제로는 다양한 패턴 매칭이 필요할 수 있으나,
///   예시에서는 단순히 "line이 body에 포함되는지"로 처리.
bool _containsWhitelistedUrl(String body) {
  // 소문자 변환 후 검사(대소문자 구분 안하려면)
  final lowerBody = body.toLowerCase();
  for (final url in _whiteListUrls) {
    if (url.isNotEmpty) {
      final lowerUrl = url.toLowerCase();
      // 단순 substring 포함 여부
      if (lowerBody.contains(lowerUrl)) {
        return true;
      }
    }
  }
  return false;
}

/// ─────────────────────────────
/// 메시지 분석 (GPT API)
/// ─────────────────────────────
Future<Map<String, dynamic>> analyzeMessage(String body) async {
  final escapedBody = body.replaceAll('\n', '\\n');
  try {
    final response = await http.post(
      Uri.parse(
          'http://221.168.37.187:3000/api/v1/analyze'),
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
/// 스팸 알림 표시
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
/// 백그라운드 SMS 수신 (isolate)
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

  // 1) 시간대 체크
  if (!_isWithinKRWorkingHours()) {
    // 작업 시간대가 아니라면 스킵
    return;
  }

  // 2) 화이트리스트 체크
  if (_containsWhitelistedUrl(body)) {
    // 화이트리스트에 해당 → GPT 분석 X
    // 1) 직접 spamScore=0 / spamReason='화이트리스트 URL => 안전한 메시지' 로 처리
    final sp = IsolateNameServer.lookupPortByName(smsBgPortName);
    if (sp != null) {
      sp.send({
        'address': sender,
        'body': body,
        'timestamp': nowMillis,
        'spamScore': 0.0, // "안전"을 의미(원하시면 100점 등 다른 값 사용)
        'spamReason': '해당 문자는 스팸이 아닌 것으로 판단됩니다. '
            '메시지에 포함된 링크가 검증된 공식 웹사이트로 확인되었기 때문입니다. '
            '따라서 신뢰할 수 있는 출처에서 발송된 정상적인 문자로 보입니다.',
        'chatGptText': '이 문자는 검증된 신뢰할 수 있는 링크를 포함하고 있어 스팸이 아닐 가능성이 높습니다. '
            '스팸 메시지는 일반적으로 출처가 불분명하거나, 악성 링크 또는 피싱을 유도하는 내용을 포함하는 경우가 많습니다. '
            '반면, 해당 메시지는 검증된 출처에서 발송한 공식적인 정보로 확인되므로, 사용자가 안심하고 내용을 확인할 수 있습니다.',
        'update': true, // 바로 최종 상태
      });
    }
    return; // GPT 호출하지 않음
  }

  // 3) placeholder 전송 (아직 분석 전)
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

  // 4) GPT 분석
  final analysis = await analyzeMessage(body);
  final spamScore = analysis['spamScore'] as double;
  final spamReason = analysis['spamReason'] as String;
  final chatGptText = analysis['chatGptText'] as String;

  // 5) 알림
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

  // 6) 최종 데이터 전송
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

  Timer? _mmsPollingTimer;
  int _lastMmsTimestamp = 0;

  Set<String> _contactPhoneNumbers = {};

  Future<void> init() async {
    await _initializeNotifications();
    await _requestPermissions();

    // 1) 화이트리스트 파일 로드
    await _loadWhiteList();

    // 2) 연락처 로드
    await _loadContacts();

    // 3) 기존 메시지 로드
    await _loadMessages();

    // 4) SMS/MMS 리스너 등록
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
    if (await Permission.contacts.isDenied) {
      await Permission.contacts.request();
    }
  }

  Future<void> _loadContacts() async {
    try {
      final hasPermission = await FlutterContacts.requestPermission();
      if (!hasPermission) {
        debugPrint("Contacts permission denied!");
        return;
      }

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

  String _normalizePhoneNumber(String phone) {
    return phone.replaceAll(RegExp(r'[\s\-\(\)\+]', multiLine: true), '').trim();
  }

  bool _isContactNumber(String? number) {
    if (number == null) return false;
    final normalized = _normalizePhoneNumber(number);
    return _contactPhoneNumbers.contains(normalized);
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

  /// history item 추가/수정
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

        // 연락처인지 확인
        if (_isContactNumber(sender)) {
          return;
        }
        // 시간대 확인
        if (!_isWithinKRWorkingHours()) {
          return;
        }
        // 화이트리스트 체크
        if (_containsWhitelistedUrl(body)) {
          // 화이트리스트 → GPT 스킵, spamScore=0 (또는 100), 이유=공공기관 링크
          _addOrUpdateHistoryItem(
            timestamp: nowMillis,
            address: sender,
            body: body,
            spamScore: 0.0,
            spamReason: '해당 문자는 스팸이 아닌 것으로 판단됩니다. '
            '메시지에 포함된 링크가 검증된 공식 웹사이트로 확인되었기 때문입니다. '
            '따라서 신뢰할 수 있는 출처에서 발송된 정상적인 문자로 보입니다.',
            chatGptText: '이 문자는 검증된 신뢰할 수 있는 링크를 포함하고 있어 스팸이 아닐 가능성이 높습니다. '
            '스팸 메시지는 일반적으로 출처가 불분명하거나, 악성 링크 또는 피싱을 유도하는 내용을 포함하는 경우가 많습니다. '
            '반면, 해당 메시지는 검증된 출처에서 발송한 공식적인 정보로 확인되므로, 사용자가 안심하고 내용을 확인할 수 있습니다.',
          );
          return;
        }

        // 화이트리스트가 아니면 -> 기존 GPT 로직
        _addOrUpdateHistoryItem(
          timestamp: nowMillis,
          address: sender,
          body: body,
          spamScore: 0.0,
          spamReason: '분석 중...',
          chatGptText: '분석 중...',
        );

        final analysis = await analyzeMessage(body);
        final spamScore = analysis['spamScore'] as double;
        final spamReason = analysis['spamReason'] as String;
        final chatGptText = analysis['chatGptText'] as String;

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

    // 백그라운드 isolate -> 메인 isolate
    receivePort.listen((data) {
      if (data is Map) {
        final ts = data['timestamp'] as int? ?? 0;
        final address = data['address'] as String? ?? 'Unknown';
        final body = data['body'] as String? ?? '';
        final spamScore = (data['spamScore'] as num?)?.toDouble() ?? 0.0;
        final spamReason = data['spamReason'] as String? ?? '';
        final chatGptText = data['chatGptText'] as String? ?? '';

        // 연락처 / 시간대 체크
        if (_isContactNumber(address)) {
          return;
        }
        if (!_isWithinKRWorkingHours()) {
          return;
        }

        // 백그라운드에서 "화이트리스트 => 0점" 으로 받은 경우도 있을 수 있음
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

  /// MMS 폴링
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

          // 연락처 / 시간대
          if (_isContactNumber(address)) {
            return;
          }
          if (!_isWithinKRWorkingHours()) {
            return;
          }

          // 1) MMS 본문
          final mmsText = await _mmsChannel.invokeMethod(
            'getMmsText',
            {'mmsId': mmsId},
          ) as String? ??
              '';

          // 2) 화이트리스트 체크
          if (_containsWhitelistedUrl(mmsText)) {
            _addOrUpdateHistoryItem(
              timestamp: timestamp,
              address: address,
              body: mmsText,
              spamScore: 0.0,
              spamReason: '해당 문자는 스팸이 아닌 것으로 판단됩니다. '
              '메시지에 포함된 링크가 검증된 공식 웹사이트로 확인되었기 때문입니다. '
              '따라서 신뢰할 수 있는 출처에서 발송된 정상적인 문자로 보입니다.',
              chatGptText: '이 문자는 검증된 신뢰할 수 있는 링크를 포함하고 있어 스팸이 아닐 가능성이 높습니다. '
              '스팸 메시지는 일반적으로 출처가 불분명하거나, 악성 링크 또는 피싱을 유도하는 내용을 포함하는 경우가 많습니다. '
              '반면, 해당 메시지는 검증된 출처에서 발송한 공식적인 정보로 확인되므로, 사용자가 안심하고 내용을 확인할 수 있습니다.',
            );
            return;
          }

          // 그 외 -> GPT 분석
          _addOrUpdateHistoryItem(
            timestamp: timestamp,
            address: address,
            body: mmsText,
            spamScore: 0.0,
            spamReason: '분석 중...',
            chatGptText: '분석 중...',
          );

          final analysis = await analyzeMessage(mmsText);
          final spamScore = analysis['spamScore'] as double;
          final spamReason = analysis['spamReason'] as String;
          final chatGptText = analysis['chatGptText'] as String;

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

  void deleteMessage(int index) {
    final current = List<HistoryItem>.from(items.value);
    if (index >= 0 && index < current.length) {
      current.removeAt(index);
      items.value = current;
      _saveMessages();
    }
  }
}
