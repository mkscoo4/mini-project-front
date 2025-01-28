// pages/detail/detail_page.dart

import 'package:flutter/material.dart';
import 'package:koscom_test1/models/history_item.dart'; // HistoryItem 모델 import

class DetailPage extends StatelessWidget {
  final HistoryItem historyItem; // 어떤 항목을 눌렀는지 받음

  const DetailPage({Key? key, required this.historyItem}) : super(key: key);

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
      backgroundColor: const Color(0xFFF2F7FF),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// 상단 타이틀 (상세 보기)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Text(
                '상세 보기',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF19214C),
                ),
              ),
            ),

            /// 본문 스크롤 영역
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      /// 1) 문자 내용 박스
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: boxShadow,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [

                            const Text(
                              '문자 내용',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(height: 7),
                            // 작은 구분선(Decorative)
                            Container(
                              width: 70,
                              height: 1,
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: Color(0xFF19214C),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 1),
                            // 실제 메시지(HistoryItem에서 넘겨받은 정보)
                            Text(
                              '${historyItem.title}\n${historyItem.content}',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),

                      /// 2) 스팸 점수 박스
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          // 스팸 분석 박스를 살짝 붉은톤(핑크 계열)으로?
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: boxShadow,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 스팸 점수를 크게 표시
                            Text(
                              historyItem.spamScore.toStringAsFixed(0),
                              style: TextStyle(
                                fontSize: 48,
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                historyItem.spamReason,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      /// 3) ChatGPT 생성 텍스트 박스
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: boxShadow,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  color: Colors.blueAccent,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'ChatGPT 분석',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blueAccent,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              historyItem.chatGptText,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),

      /// 하단 '뒤로가기' 버튼
      bottomNavigationBar: BottomAppBar(
        color: Colors.white,
        child: SizedBox(
          height: 56,
          child: Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                '뒤로가기',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: Colors.blueAccent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
