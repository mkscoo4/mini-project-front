// lib/main.dart

import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:koscom_test1/pages/landing/landing_page.dart';
import 'package:koscom_test1/managers/message_manager.dart';

// 전역 ReceivePort (메인 Isolate)
final ReceivePort receivePort = ReceivePort();

// 포트 이름 (백그라운드 -> 메인)
const String smsBgPortName = 'sms_bg_port';

// 전역 navigatorKey (알림 클릭 시 페이지 이동)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // IsolateNameServer 등록
  IsolateNameServer.removePortNameMapping(smsBgPortName);
  IsolateNameServer.registerPortWithName(receivePort.sendPort, smsBgPortName);

  // MessageManager init
  await MessageManager.instance.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'K-Spam App',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      home: const LandingPage(),
      // 라우팅을 사용해도 되고, 필요한 경우 routes/initialRoute 등을 설정 가능
    );
  }
}
