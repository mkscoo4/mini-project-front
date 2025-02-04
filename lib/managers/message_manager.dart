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

/// 화이트리스트 URL 목록
Set<String> _whiteListUrls = {};

/// 앱 시작 시 assets/whitelist.txt 읽어서 _whiteListUrls에 저장
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

/// 메시지에 화이트리스트된 URL이 포함되는지 확인
bool _containsWhitelistedUrl(String body) {
  final lowerBody = body.toLowerCase();
  for (final url in _whiteListUrls) {
    if (url.isNotEmpty) {
      final lowerUrl = url.toLowerCase();
      if (lowerBody.contains(lowerUrl)) {
        return true;
      }
    }
  }
  return false;
}

/// ──────────────────────────────────────────
/// 룰 베이스 체크용 헬퍼 (최대 +20점)
/// ──────────────────────────────────────────
bool _isOverseasNumber(String address) {
  // +82로 시작하면 국내, + 로 시작하면 해외
  if (address.startsWith('+82')) return false;
  if (address.startsWith('+')) return true;
  return false;
}

bool _hasRepeatedSpecialCharacters(String body) {
  // 동일 특수문자가 3회 이상 연속
  final regex = RegExp(r'([^A-Za-z0-9\s])\1\1');
  return regex.hasMatch(body);
}

bool _containsShortUrl(String body) {
  // 대표적인 단축 URL 목록
  final shortUrlDomains = [
    'tinyurl.com',
    'bit.ly',
    'goo.gl',
    't.co',
    'ow.ly',
    'buff.ly',
    'adf.ly',
    'cutt.ly',
    'is.gd',
    'tiny.cc',
    't.ly',
  ];
  final lowerBody = body.toLowerCase();
  for (final domain in shortUrlDomains) {
    if (lowerBody.contains(domain)) {
      return true;
    }
  }
  return false;
}

/// ──────────────────────────────────────────
/// GPT + 룰 베이스 통합 분석
/// ──────────────────────────────────────────
Future<Map<String, dynamic>> analyzeMessage(String address, String body) async {
  final escapedBody = body.replaceAll('\n', '\\n');

  // GPT 분석 결과
  double rawGptScore = 0.0;     // GPT 원본 점수(0~100)
  String spamReason = '';       // summary
  String chatGptText = '';      // description

  try {
    final response = await http.post(
      Uri.parse('http://221.168.37.187:3000/api/v1/analyze'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'message': escapedBody}),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      rawGptScore = (data['score'] as num).toDouble();  // 예: 78
      spamReason = data['summary'] as String? ?? '';

      final dynamic descData = data['description'];
      if (descData is List) {
        chatGptText = descData.join('\n');
      } else if (descData != null) {
        chatGptText = descData.toString();
      }
    } else {
      debugPrint("API Error: ${response.statusCode} ${response.body}");
    }
  } catch (e) {
    debugPrint("API request failed: $e");
  }

  // 1) GPT 점수를 80점 만점으로 스케일링
  //    (ex: rawGptScore=78 → scaled=78*0.8=62.4 → 반올림=62)
  final int rawGptScoreInt = rawGptScore.round();           // 예: 78
  final int scaledGptScoreInt = (rawGptScore * 0.8).round(); // 예: 62

  // 2) 룰 베이스 점수(최대 +20)
  double ruleScore = 0.0;
  if (_isOverseasNumber(address)) {
    ruleScore += 5.0;
  }
  if (_hasRepeatedSpecialCharacters(body)) {
    ruleScore += 5.0;
  }
  if (_containsShortUrl(body)) {
    ruleScore += 5.0;
  }

  // 주소록 여부 (MessageManager.instance 사용)
  final bool isInContacts = MessageManager.instance.isContactNumber(address);
  if (!isInContacts) {
    ruleScore += 5.0;
  }

  final int ruleScoreInt = ruleScore.round(); // ex: 10
  // 3) 최종 스팸 점수
  final int finalSpamScoreInt = scaledGptScoreInt + ruleScoreInt; // ex: 62+10=72

  // ─────────────────────────────────────────────
  // 4) summary / description 내에 원본 점수(예: "78") → 최종 점수("72")로 치환
  //   (단순 치환이므로, 실제로는 정규식 등으로 안전하게 처리 권장)
  // ─────────────────────────────────────────────
  final oldScoreStr = rawGptScoreInt.toString();         // "78"
  final newScoreStr = finalSpamScoreInt.toString();      // "72"

  if (spamReason.contains(oldScoreStr)) {
    spamReason = spamReason.replaceAll(oldScoreStr, newScoreStr);
  }
  if (chatGptText.contains(oldScoreStr)) {
    chatGptText = chatGptText.replaceAll(oldScoreStr, newScoreStr);
  }

  // 최종 double 형태로 반환
  return {
    'spamScore': finalSpamScoreInt.toDouble(),
    'spamReason': spamReason,
    'chatGptText': chatGptText,
  };
}

/// 스팸 알림
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

/// 백그라운드 SMS 핸들러
@pragma('vm:entry-point')
void backgroundMessageHandler(SmsMessage message) async {
  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await plugin.initialize(initSettings);

  final sender = message.address ?? 'Unknown';
  final body = message.body ?? '';
  final nowMillis = DateTime.now().millisecondsSinceEpoch;

  // 한국 08:00~21:00 외면 무시
  if (!_isWithinKRWorkingHours()) {
    return;
  }

  // 화이트리스트 체크
  if (_containsWhitelistedUrl(body)) {
    final sp = IsolateNameServer.lookupPortByName(smsBgPortName);
    if (sp != null) {
      sp.send({
        'address': sender,
        'body': body,
        'timestamp': nowMillis,
        'spamScore': 0.0,
        'spamReason': '화이트리스트 URL → 안전한 메시지로 판단합니다.',
        'chatGptText': '해당 링크는 신뢰할 수 있는 출처로 보입니다.',
        'update': true,
      });
    }
    return;
  }

  // 메인 isolate에 "분석 중..."
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

  // GPT + 룰베이스 분석
  final analysis = await analyzeMessage(sender, body);
  final spamScore = analysis['spamScore'] as double;
  final spamReason = analysis['spamReason'] as String;
  final chatGptText = analysis['chatGptText'] as String;

  // 스팸이면 알림
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

  // 메인 isolate에 최종 업데이트
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
/// MessageManager
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

    await _loadWhiteList();
    await _loadContacts();
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

  bool isContactNumber(String? number) {
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

  void _listenSms() {
    telephony.listenIncomingSms(
      onNewMessage: (msg) async {
        final sender = msg.address ?? 'Unknown';
        final body = msg.body ?? '';
        final nowMillis = DateTime.now().millisecondsSinceEpoch;

        // 시간대
        if (!_isWithinKRWorkingHours()) {
          return;
        }
        // 주소록이면 스킵
        if (isContactNumber(sender)) {
          return;
        }
        // 화이트리스트
        if (_containsWhitelistedUrl(body)) {
          _addOrUpdateHistoryItem(
            timestamp: nowMillis,
            address: sender,
            body: body,
            spamScore: 0.0,
            spamReason: '화이트리스트 URL → 안전한 메시지로 판단합니다.',
            chatGptText: '해당 링크는 신뢰할 수 있는 출처로 보입니다.',
          );
          return;
        }

        // "분석 중..."
        _addOrUpdateHistoryItem(
          timestamp: nowMillis,
          address: sender,
          body: body,
          spamScore: 0.0,
          spamReason: '분석 중...',
          chatGptText: '분석 중...',
        );

        // GPT + 룰 베이스
        final analysis = await analyzeMessage(sender, body);
        final spamScore = analysis['spamScore'] as double;
        final spamReason = analysis['spamReason'] as String;
        final chatGptText = analysis['chatGptText'] as String;

        // 스팸 알림
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

        // 최종 업데이트
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

    receivePort.listen((data) {
      if (data is Map) {
        final ts = data['timestamp'] as int? ?? 0;
        final address = data['address'] as String? ?? 'Unknown';
        final body = data['body'] as String? ?? '';
        final spamScore = (data['spamScore'] as num?)?.toDouble() ?? 0.0;
        final spamReason = data['spamReason'] as String? ?? '';
        final chatGptText = data['chatGptText'] as String? ?? '';

        // 시간대
        if (!_isWithinKRWorkingHours()) {
          return;
        }
        // 주소록?
        if (isContactNumber(address)) {
          return;
        }

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

  void _listenMms() {
    const pollInterval = Duration(milliseconds: 500);
    _mmsPollingTimer = Timer.periodic(pollInterval, (timer) async {
      try {
        final result = await _mmsChannel.invokeMethod('getLatestMms');
        if (result != null && result is Map) {
          final mmsId = result['id'] as String?;
          final address = result['address'] as String? ?? 'Unknown';
          final timestamp =
              result['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;
          if (mmsId == null) return;
          if (timestamp <= _lastMmsTimestamp) return;
          _lastMmsTimestamp = timestamp;

          if (!_isWithinKRWorkingHours()) {
            return;
          }
          if (isContactNumber(address)) {
            return;
          }

          // MMS 본문
          final mmsText = await _mmsChannel.invokeMethod(
            'getMmsText',
            {'mmsId': mmsId},
          ) as String? ??
              '';

          if (_containsWhitelistedUrl(mmsText)) {
            _addOrUpdateHistoryItem(
              timestamp: timestamp,
              address: address,
              body: mmsText,
              spamScore: 0.0,
              spamReason: '화이트리스트 URL → 안전한 메시지로 판단합니다.',
              chatGptText: '해당 링크는 신뢰할 수 있는 출처로 보입니다.',
            );
            return;
          }

          // "분석 중..."
          _addOrUpdateHistoryItem(
            timestamp: timestamp,
            address: address,
            body: mmsText,
            spamScore: 0.0,
            spamReason: '분석 중...',
            chatGptText: '분석 중...',
          );

          final analysis = await analyzeMessage(address, mmsText);
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
