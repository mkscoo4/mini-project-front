import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:koscom_test1/models/history_item.dart'; // HistoryItem 모델 import

class DetailPage extends StatelessWidget {
  final HistoryItem historyItem; // 어떤 항목을 눌렀는지 받음

  const DetailPage({Key? key, required this.historyItem}) : super(key: key);

  /// 스팸 신고(118) 버튼 누르면 다이얼러 앱으로 이동
  Future<void> _launchDialerFor118(BuildContext context) async {
    final Uri telUri = Uri(scheme: 'tel', path: '118');
    if (await canLaunchUrl(telUri)) {
      // 다이얼 화면을 띄움
      await launchUrl(telUri, mode: LaunchMode.externalApplication);
    } else {
      // 만약 다이얼 화면을 열 수 없으면 에러 메시지를 띄움
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('전화를 걸 수 없습니다.')),
      );
    }
  }

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
            /// 상단 영역: "상세 보기" + 오른쪽 "신고하기" 버튼
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '상세 보기',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF19214C),
                    ),
                  ),
                  OutlinedButton.icon(
                    // 스타일 지정
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                        color: Color(0xFF19214C), // 테두리 색
                        width: 2,
                      ),
                      // foregroundColor를 지정해도 일부 아이콘은 테마 영향으로 보라색 뜰 수 있으므로
                      // 아래처럼 아이콘, 텍스트에 직접 색상 지정하는 방법이 더 확실합니다.
                    ),
                    onPressed: () => _launchDialerFor118(context),
                    icon: const Icon(
                      Icons.report_gmailerrorred,
                      color: Color(0xFF19214C), // 아이콘 색 지정
                    ),
                    label: Text(
                      '신고하기',
                      style: const TextStyle(
                        color: Color(0xFF19214C), // 텍스트 색 지정
                      ),
                    ),
                  ),
                ],
              ),
            ),

            /// 본문 스크롤 영역
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      /// 1) 📜 문자 내용 박스
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(30),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF009), // 임의 색
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: boxShadow,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.sticky_note_2_rounded,
                                  color: Colors.orange,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  '메시지 내용',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                    color: Colors.orangeAccent,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 7),
                            const SizedBox(height: 2),
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

                      /// 2) ⚠️ 스팸 점수 박스
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: historyItem.spamScore >= 70
                              ? Colors.red.shade50
                              : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: boxShadow,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 70,
                                  height: 70,
                                  decoration: BoxDecoration(
                                    color: historyItem.spamScore >= 70
                                        ? Colors.red.withOpacity(0.2)
                                        : Colors.green.withOpacity(0.2),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Text(
                                  historyItem.spamScore.toStringAsFixed(0),
                                  style: TextStyle(
                                    fontSize: 48,
                                    color: historyItem.spamScore >= 70
                                        ? Colors.redAccent
                                        : Colors.green,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
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

                      /// 3) 💬 ChatGPT 분석 박스
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(30),
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
    );
  }
}
