class HistoryItem {
  final int timestamp;      // SMS 도착 시각 (밀리초 단위, 필요시 마이크로초 단위로 사용)
  final String icon;        // 아이콘 (예: 초록색, 빨간색)
  final String title;       // 문자 제목 (또는 내용 일부)
  final String content;     // 문자 본문 (좀 더 긴 내용)
  final String dateTime;    // 날짜/시간 (예: 포맷된 문자열)
  final double spamScore;   // 스팸 판단 점수 (예: 83.0)
  final String spamReason;  // 스팸 판단 사유 (AI 분석 결과 등)
  final String chatGptText; // ChatGPT가 생성한 문구

  const HistoryItem({
    required this.timestamp,
    required this.icon,
    required this.title,
    required this.content,
    required this.dateTime,
    required this.spamScore,
    required this.spamReason,
    required this.chatGptText,
  });

  // toJson: timestamp도 함께 저장합니다.
  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp,
      'icon': icon,
      'title': title,
      'content': content,
      'dateTime': dateTime,
      'spamScore': spamScore,
      'spamReason': spamReason,
      'chatGptText': chatGptText,
    };
  }

  // fromJson: 저장된 timestamp 값을 불러옵니다.
  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    return HistoryItem(
      timestamp: json['timestamp'] as int? ?? 0,
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
