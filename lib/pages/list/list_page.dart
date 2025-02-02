import 'package:flutter/material.dart';
import 'package:koscom_test1/models/history_item.dart';
import 'package:koscom_test1/pages/detail/detail_page.dart';

// main.dart에서 MessageManager 불러오기
import 'package:koscom_test1/main.dart' show MessageManager;
import '../../managers/message_manager.dart';

class ListPage extends StatelessWidget {
  const ListPage({Key? key}) : super(key: key);

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

            /// 리스트 (ValueListenableBuilder)
            Expanded(
              child: ValueListenableBuilder<List<HistoryItem>>(
                valueListenable: MessageManager.instance.items,
                builder: (context, itemList, child) {
                  if (itemList.isEmpty) {
                    return const Center(child: Text('아직 수신된 문자가 없습니다.'));
                  }

                  return ListView.separated(
                    itemCount: itemList.length,
                    separatorBuilder: (context, index) =>
                    const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = itemList[index];

                      // spamScore에 따라 아이콘 결정
                      final String iconPath = item.spamScore >= 70.0
                          ? 'assets/icons/check_red.png' // 스팸 위험 높음
                          : 'assets/icons/check_green.png'; // 스팸 위험 낮음

                      return InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DetailPage(historyItem: item),
                            ),
                          );
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          padding: const EdgeInsets.all(20),
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
                                child: Image.asset(iconPath), // 변경된 아이콘 적용
                              ),
                              const SizedBox(width: 12),
                              // 제목 + 날짜
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 제목
                                    Text(
                                      item.title,
                                      maxLines: 3, // 최대 3줄까지 표시
                                      overflow: TextOverflow.ellipsis, // 초과 시 ... 표시
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
