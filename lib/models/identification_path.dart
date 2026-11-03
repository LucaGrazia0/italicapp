enum KeyAnswer { a, b, unknown }

class IdentificationPath {
  IdentificationPath({
    required this.keyId,
    required Map<String, KeyAnswer> answers,
    required this.savedAt,
    this.dataRevision,
    Map<String, String> selections = const {},
  }) : answers = Map.unmodifiable(answers),
       selections = Map.unmodifiable(selections);

  final String keyId;
  final int? dataRevision;
  final Map<String, KeyAnswer> answers;
  final DateTime savedAt;
  final Map<String, String> selections;
  int get answerCount => answers.length + selections.length;

  Map<String, Object?> toMap() => {
    'keyId': keyId,
    if (dataRevision != null) 'dataRevision': dataRevision,
    'answers': answers.map((key, value) => MapEntry(key, value.name)),
    'savedAt': savedAt.toIso8601String(),
    if (selections.isNotEmpty) 'selections': selections,
  };

  static IdentificationPath? fromMap(dynamic value) {
    if (value is! Map ||
        value['keyId'] is! String ||
        value['answers'] is! Map) {
      return null;
    }
    final date = DateTime.tryParse(value['savedAt']?.toString() ?? '');
    if (date == null) return null;
    final answers = <String, KeyAnswer>{};
    for (final entry in (value['answers'] as Map).entries) {
      for (final answer in KeyAnswer.values) {
        if (entry.value == answer.name && entry.key is String) {
          answers[entry.key] = answer;
        }
      }
    }
    final selections = <String, String>{};
    if (value['selections'] is Map) {
      for (final entry in (value['selections'] as Map).entries) {
        if (entry.key is String && entry.value is String) {
          selections[entry.key] = entry.value;
        }
      }
    }
    return IdentificationPath(
      keyId: value['keyId'],
      dataRevision: (value['dataRevision'] as num?)?.toInt(),
      answers: answers,
      selections: selections,
      savedAt: date,
    );
  }
}
