import 'package:flutter/material.dart';
import 'package:koscom_test1/pages/home/main_home_tab.dart'; // 홈 탭 UI
import 'package:koscom_test1/pages/list/list_page.dart';     // 내역 페이지

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  // 탭별로 표시할 화면 목록
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = const [
      MainHomeTab(),
      ListPage(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final boxShadow = [
      BoxShadow(
        color: Colors.grey.shade300,
        spreadRadius: 1,
        blurRadius: 5,
        offset: const Offset(0, -2),
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF2F7FF),

      body: SafeArea(
        child: _pages[_currentIndex],
      ),

      // 하단 바
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: boxShadow,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(12),
          ),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(12),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (int index) {
              setState(() {
                _currentIndex = index;
              });
            },
            backgroundColor: Colors.white,
            selectedItemColor: const Color(0xFF0D144B),
            unselectedItemColor: Colors.grey,
            showUnselectedLabels: true,
            items: [
              BottomNavigationBarItem(
                icon: Image.asset('assets/icons/home.png', width: 24, height: 24),
                label: '홈',
              ),
              BottomNavigationBarItem(
                icon: Image.asset('assets/icons/list.png', width: 24, height: 24),
                label: '내역',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
