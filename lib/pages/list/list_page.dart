import 'package:flutter/material.dart';
import 'package:koscom_test1/models/history_item.dart';
import 'package:koscom_test1/pages/detail/detail_page.dart';

class ListPage extends StatelessWidget {
  const ListPage({Key? key}) : super(key: key);

  // 샘플 더미 데이터 (실제로는 API 결과 등)
  final List<HistoryItem> _dummyList = const [
    HistoryItem(
      icon: 'assets/icons/check_green.png',
      title: '오늘의 종목 추천\n오늘 놓치면 안됩니다....',
      content: '상세 내용이 더 있을 수 있음',
      dateTime: '2025-10-19 12:12:12',
      spamScore: 83.0,
      spamReason: 'AI를 활용한 분석 결과 비정상적인 URL, 발신자 정보 부족 등으로\n'
          '위험도가 70 이상이므로 해당 번호는 차단해주세요.',
      chatGptText: 'ChatGPT가 생성한 문구 예시.\n\n1. 주의\n2. 의심\n3. 계속',
    ),
    // ...다른 항목들
  ];

  @override
  Widget build(BuildContext context) {
    final boxShadow = [
      BoxShadow(
        color: Colors.grey.shade200,
        spreadRadius: 2,
        blurRadius: 8,
        offset: const Offset(0, 4),
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FE),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// 상단 타이틀 (내역 보기)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Text(
                '내역 보기',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF19214C),
                ),
              ),
            ),

            /// 리스트
            Expanded(
              child: ListView.separated(
                itemCount: _dummyList.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = _dummyList[index];
                  return InkWell(
                    onTap: () {
                      // 탭 시 상세 페이지로 이동
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DetailPage(historyItem: item),
                        ),
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: boxShadow,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: Image.asset(item.icon),
                          ),
                          const SizedBox(width: 12),

                          /// 제목 + 날짜
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 제목
                                Text(
                                  item.title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 4),

                                // 날짜
                                Text(
                                  item.dateTime,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
