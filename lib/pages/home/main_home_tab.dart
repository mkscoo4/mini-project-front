import 'package:flutter/material.dart';

class MainHomeTab extends StatelessWidget {
  const MainHomeTab({Key? key}) : super(key: key);

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
                          hintStyle: TextStyle(
                            color: Colors.grey[700],
                          ),
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
                        _buildDivider(),
                        _buildStep(
                          iconPath: 'assets/icons/1.png',
                          title: '1. 사용자 신고',
                          description: '홈페이지(spam.kisa.or.kr), Spamcop 프로그램, '
                              '118 콜센터, 휴대폰 단말기의 간편신고 서비스 이용',
                        ),
                        _buildDivider(),
                        _buildStep(
                          iconPath: 'assets/icons/2.png',
                          title: '2. 신고접수 및 위법사실 확인',
                          description: '신고 접수 후, 해당 스팸이 법을 위반하였는지에 대한 확인',
                        ),
                        _buildDivider(),
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

            /// 금융 사기 및 스팸 유형
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
                          child: Image.asset('assets/icons/search_medium.png'),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '금융 사기 및 스팸 유형',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    /// 설명 텍스트
                    Text(
                      spamInfo,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 14,
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
