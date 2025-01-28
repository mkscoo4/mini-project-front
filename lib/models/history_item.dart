class HistoryItem {
  final String icon;        // 아이콘 초록색 or 빨간색
  final String title;       // 문자 제목 (또는 내용 일부)
  final String content;     // 문자 본문 (좀 더 긴 내용)
  final String dateTime;    // 날짜/시간
  final double spamScore;   // 스팸 판단 점수 (예: 83.0)
  final String spamReason;  // 스팸 판단 사유 (AI 분석 결과 등)
  final String chatGptText; // ChatGPT가 생성한 문구

  const HistoryItem({
    required this.icon,
    required this.title,
    required this.content,
    required this.dateTime,
    required this.spamScore,
    required this.spamReason,
    required this.chatGptText,
  });

  // toJson
  Map<String, dynamic> toJson() {
    return {
      'icon': icon,
      'title': title,
      'content': content,
      'dateTime': dateTime,
      'spamScore': spamScore,
      'spamReason': spamReason,
      'chatGptText': chatGptText,
    };
  }

  // fromJson
  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    return HistoryItem(
      icon: json['icon'] as String? ?? '',
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      dateTime: json['dateTime'] as String? ?? '',
      spamScore: (json['spamScore'] as num?)?.toDouble() ?? 0.0,
      spamReason: json['spamReason'] as String? ?? '',
      chatGptText: json['chatGptText'] as String? ?? '',
    );
  }
}
