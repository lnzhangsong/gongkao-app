/// 归一化后的轮播卡片。三份源 JSON 结构相近，统一成此形状。
class CardItem {
  const CardItem({
    required this.kind,
    required this.title,
    required this.body,
    this.group,
    this.extra,
    this.example,
  });

  factory CardItem.fromJson(Map<String, dynamic> json) => CardItem(
        kind: json['kind'] as String,
        group: json['group'] as String?,
        title: json['title'] as String,
        body: json['body'] as String,
        extra: json['extra'] as String?,
        example: json['example'] as String?,
      );

  final String kind; // '常识' | '成语' | '时政'
  final String? group; // 常识的 group（法律/科技…）、时政的 group（重要会议…）
  final String title; // term 或 word
  final String body; // meaning
  final String? extra; // distinction（辨析）
  final String? example;
}
