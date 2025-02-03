// list_page.dart
import 'package:flutter/material.dart';
import 'package:koscom_test1/models/history_item.dart';
import 'package:koscom_test1/pages/detail/detail_page.dart';
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
            // 상단 타이틀
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

            // 리스트
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

                      // 아이콘: 분석 중일 경우 'spinner'면 spinner 표시, 아니면 spamScore 기준 결정
                      Widget iconWidget;
                      if (item.icon == 'spinner') {
                        iconWidget = const SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        );
                      } else {
                        // spamScore에 따라 아이콘 결정 (여기서는 item.icon을 그대로 사용해도 됨)
                        iconWidget = SizedBox(
                          width: 40,
                          height: 40,
                          child: Image.asset(item.icon),
                        );
                      }

                      // 삭제
                      return Dismissible(
                        key: Key(item.timestamp.toString()),
                        direction: DismissDirection.endToStart, // 오른쪽→왼쪽 스와이프
                        background: Container(
                          color: Colors.redAccent,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        confirmDismiss: (direction) async {
                          // 삭제 전 사용자 확인 Dialog
                          return await showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('삭제 확인'),
                              content: const Text('이 항목을 삭제하시겠습니까?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(false),
                                  child: const Text('취소'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(true),
                                  child: const Text('삭제'),
                                ),
                              ],
                            ),
                          );
                        },
                        onDismissed: (direction) {
                          // 사용자가 확인 후 스와이프 완전히 하면 실제 삭제
                          MessageManager.instance.deleteMessage(index);
                        },
                        // ↑↑↑ 여기까지 Dismissible 관련 코드 ↑↑↑
                        child: InkWell(
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    iconWidget,
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          // 제목 (발신자와 일부 문자 내용)
                                          Text(
                                            item.title,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              color: Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          // 날짜/시간
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
                                // 분석 중일 경우 하단에 spinner 표시 (추가적인 안내)
                                if (item.spamReason == '분석 중...')
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Row(
                                      children: const [
                                        SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Text('분석 중...'),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
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
