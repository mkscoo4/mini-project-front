import 'package:flutter/material.dart';
import 'package:koscom_test1/pages/landing/landing_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'K-Spam App',
      debugShowCheckedModeBanner: false,
      home: const LandingPage(),
      // 라우팅을 사용해도 되고, 필요한 경우 routes/initialRoute 등을 설정 가능
    );
  }
}
