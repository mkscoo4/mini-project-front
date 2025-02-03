import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class MainHomeTab extends StatefulWidget {
  const MainHomeTab({Key? key}) : super(key: key);

  @override
  State<MainHomeTab> createState() => _MainHomeTabState();
}

class _MainHomeTabState extends State<MainHomeTab> {
  // 코스피/코스닥 지수 상태 저장
  String _kospiIndex = '';
  String _kosdaqIndex = '';

  Timer? _timer; // 주기적 폴링용 타이머

  @override
  void initState() {
    super.initState();
    // 앱 시작 시 즉시 한 번 호출
    _fetchStockIndexes();
    // 5초마다 반복 호출
    _timer = Timer.periodic(
      const Duration(seconds: 5),
          (timer) => _fetchStockIndexes(),
    );
  }

  @override
  void dispose() {
    // 화면 종료 시 타이머 해제
    _timer?.cancel();
    super.dispose();
  }

  /// 코스피/코스닥 지수를 서버에서 가져오는 함수
  Future<void> _fetchStockIndexes() async {
    final url = Uri.parse(
      'http://ec2-3-39-250-8.ap-northeast-2.compute.amazonaws.com:3000/api/v1/info',
    );
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _kospiIndex = data['KOSPIIndex']?.toString() ?? 'N/A';
          _kosdaqIndex = data['KOSDAQIndex']?.toString() ?? 'N/A';
        });
      } else {
        // 서버 오류 등
        setState(() {
          _kospiIndex = 'Error';
          _kosdaqIndex = 'Error';
        });
      }
    } catch (e) {
      // 네트워크 에러 등
      setState(() {
        _kospiIndex = 'Error';
        _kosdaqIndex = 'Error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String spamInfo = '[주식 투자 관련 스팸 문자]\n종목 추천\n\n'
        '[사칭 및 투자를 가장한 불법 스팸 문자]\n\n'
        '[불법 도박 사이트 접속 유도 문자]\nURL 접속 유도\n\n';

    return SafeArea(
      child: Container(
        color: const Color(0xFFF2F7FF),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const SizedBox(height: 10),

            /// 상단 로고 (왼쪽 정렬)
            Padding(
              padding: const EdgeInsets.only(left: 15),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Image.asset(
                  'assets/icons/logo.png', // 로고 이미지
                  width: 180, // 크기 조정
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 8),

            /// 검색 박스
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: '검색어를 입력하세요',
                          hintStyle: TextStyle(color: Colors.grey[700]),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        // 검색 동작
                      },
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: Image.asset('assets/icons/search_small.png'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 11),

            /// 📢 금융 스팸 신고 안내 (신고 절차 포함)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    /// 제목 영역
                    Row(
                      children: [
                        SizedBox(
                          width: 33,
                          height: 33,
                          child: Image.asset('assets/icons/finance_coin.png'),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '금융 스팸 신고 안내',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),

                    /// 신고 절차 안내
                    Column(
                      children: [
                        const SizedBox(height: 10),
                        _buildStep(
                          iconPath: 'assets/icons/1.png',
                          title: '1. 사용자 신고',
                          description: '홈페이지(spam.kisa.or.kr), Spamcop 프로그램, '
                              '118 콜센터, 휴대폰 단말기의 간편신고 서비스 이용',
                        ),
                        const SizedBox(height: 10),
                        _buildStep(
                          iconPath: 'assets/icons/2.png',
                          title: '2. 신고접수 및 위법사실 확인',
                          description: '신고 접수 후, 해당 스팸이 법을 위반하였는지에 대한 확인',
                        ),
                        const SizedBox(height: 10),
                        _buildStep(
                          iconPath: 'assets/icons/3.png',
                          title: '3. 신고처리',
                          description: '법 위반의 정도에 따른 과태료 및 수사',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            /// (원래 있었던 "금융 사기 및 스팸 유형" 카드 대신)
            /// "코스피/코스닥 지수" 카드 표시
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    /// 제목 영역
                    Row(
                      children: [
                        SizedBox(
                          width: 29,
                          height: 29,
                          child: Image.asset('assets/icons/stock_chart.png'),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '코스피/코스닥 지수',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'KOSPI: $_kospiIndex\nKOSDAQ: $_kosdaqIndex',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black87,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '(5초 간격으로 자동 업데이트)',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// 단계별 신고 절차 UI 요소
  Widget _buildStep({
    required String iconPath,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Image.asset(
          iconPath,
          width: 40,
          height: 40,
          fit: BoxFit.contain,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 단계 간 구분선
  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Divider(
        thickness: 1,
        color: Colors.grey.shade300,
      ),
    );
  }
}
