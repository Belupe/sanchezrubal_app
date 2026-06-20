class Property {
  final String id;
  final String name;
  final String? description;
  final String? image;

  Property({required this.id, required this.name, this.description, this.image});

  factory Property.fromMap(Map<String, dynamic> m) => Property(
        id: m['id'] as String,
        name: m['name'] as String,
        description: m['description'] as String?,
        image: m['image'] as String?,
      );
}
