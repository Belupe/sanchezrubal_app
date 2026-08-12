class SorteoResultado {
  final String groupName;
  final String premio;
  SorteoResultado({required this.groupName, required this.premio});
}

class Sorteo {
  final String id;
  final String name;
  final DateTime createdAt;
  final String? createdByName;
  final String? seed;
  final List<SorteoResultado> resultados;

  Sorteo({
    required this.id,
    required this.name,
    required this.createdAt,
    this.createdByName,
    this.seed,
    this.resultados = const [],
  });

  factory Sorteo.fromMap(Map<String, dynamic> m) {
    final res = ((m['sorteo_resultados'] as List?) ?? const [])
        .map((e) => SorteoResultado(
              premio: ((e as Map)['premio'] as String?) ?? '',
              groupName: (e['family_groups']?['name'] as String?) ?? '',
            ))
        .toList();
    return Sorteo(
      id: m['id'] as String,
      name: m['name'] as String,
      createdAt: DateTime.parse(m['created_at'] as String),
      createdByName: m['profiles'] is Map ? m['profiles']['name'] as String? : null,
      seed: m['seed'] as String?,
      resultados: res,
    );
  }
}
