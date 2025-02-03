import 'package:flutter/material.dart';
import 'package:koscom_test1/pages/home/home_page.dart'; // LandingPage 이후 이동할 화면

class LandingPage extends StatefulWidget {
  const LandingPage({Key? key}) : super(key: key);

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  @override
  void initState() {
    super.initState();
    // 2초 뒤 자동으로 HomePage로 이동
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F7FF),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 로고 이미지
            Image.asset(
              'assets/icons/logo.png', // 로고 이미지 경로
              width: 210, // 적절한 크기로 조정
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 3),
            // 서브 타이틀
            Text(
              '금융 사기 및 탐지 서비스',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
