import 'package:flutter/material.dart';

class MainHomeTab extends StatelessWidget {
  const MainHomeTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 가정: 실제로는 API에서 받아온 텍스트
    // (아래 예시는 임시 placeholder 문자열)
    final String financeInfo = 'API에서 받아온 금융 정보\n예) 금리 동향, 주가 정보 등';
    final String spamInfo = '[주식 투자 관련 스팸 문자]\n종목 추천\n\n'
        '[사칭 및 투자를 가장한 불법 스팸 문자]\n\n'
        '[불법 도박 사이트 접속 유도 문자]\nURL 접속 유도\n\n';

    return SafeArea(
      child: Container(
        color: const Color(0xFFF2F7FF),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const SizedBox(height: 16),

            /// 상단 K-Spam 로고
            Padding(
              padding: const EdgeInsets.only(left: 25),
              child: Text(
                'K-Spamify',
                style: TextStyle(
                  color: Color(0xFF0D144B),
                  fontWeight: FontWeight.w900,
                  fontSize: 30,
                ),
              ),
            ),
            const SizedBox(height: 24),

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
            const SizedBox(height: 16),

            /// 첫 번째 컨텐츠 박스:  금융 정보
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
                          '금융 정보',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    /// 실제 내용(API 데이터)
                    Text(
                      financeInfo,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            /// 두 번째 컨텐츠 박스:  금융 사기 및 스팸 유형
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

                    /// 실제 내용(API 데이터)
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
}
