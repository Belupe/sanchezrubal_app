class Announcement {
  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
  final String? authorName;
  final List<String> propertyNames;

  Announcement({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    this.authorName,
    this.propertyNames = const [],
  });

  factory Announcement.fromMap(Map<String, dynamic> m) {
    final author = m['profiles'];
    final aps = (m['announcement_properties'] as List?) ?? const [];
    final names = aps
        .map((e) => (e as Map)['properties']?['name'])
        .whereType<String>()
        .toList();
    return Announcement(
      id: m['id'] as String,
      title: m['title'] as String,
      content: m['content'] as String,
      createdAt: DateTime.parse(m['created_at'] as String),
      authorName: author is Map ? author['name'] as String? : null,
      propertyNames: names.cast<String>(),
    );
  }
}
