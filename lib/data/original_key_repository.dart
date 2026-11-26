import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'identification_repository.dart';

/// A published FRIDA textual key, independent from the general Keymaker tree.
/// Names and numbered continuations are retained verbatim; no network client.
class OriginalLead {
  const OriginalLead({
    required this.label,
    this.target,
    this.name,
    this.italicId,
    this.description = '',
  });
  final String label, description;
  final int? target, italicId;
  final String? name;
  factory OriginalLead.read(Map raw) {
    final label = raw['label'] as String;
    final target = raw['target'] as int?;
    final name = raw['name'] as String?;
    if (label.trim().isEmpty ||
        (target == null) == (name == null) ||
        (target != null && target <= 0) ||
        (name != null && name.trim().isEmpty) ||
        (target != null && raw['italicId'] != null)) {
      throw const FormatException('Alternativa della chiave non valida.');
    }
    return OriginalLead(
      label: label,
      target: target,
      name: name,
      italicId: raw['italicId'] as int?,
      description: raw['description'] as String? ?? '',
    );
  }
}

class OriginalCouplet {
  const OriginalCouplet(this.number, this.choices);
  final int number;
  final List<OriginalLead> choices;
}

class OriginalKey {
  OriginalKey._({
    required this.id,
    required this.title,
    required this.credits,
    required this.introduction,
    required this.accessedOn,
    required this.sourceUrl,
    required this.nodes,
    required this.missingTargets,
    required this.unreachableCouplets,
  });
  final int id;
  final String title, credits, introduction, accessedOn;
  final Uri sourceUrl;
  final Map<int, OriginalCouplet> nodes;
  final Set<int> missingTargets;
  final Set<int> unreachableCouplets;

  factory OriginalKey.read(Map raw) {
    final id = raw['id'] as int;
    final source = Uri.parse(raw['sourceUrl'] as String);
    final expected = Uri.parse(
      'https://italic.units.it/flora/index.php?procedure=ext_key_home&key_id=$id',
    );
    if (id <= 0 ||
        source != expected ||
        raw['status'] != 'available' ||
        (raw['title'] as String).trim().isEmpty ||
        raw['license'] != 'CC BY-SA 4.0' ||
        DateTime.tryParse(raw['accessedOn'] as String) == null ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(raw['sha256'] as String)) {
      throw const FormatException('Fonte della chiave non valida.');
    }
    final nodes = <int, OriginalCouplet>{};
    for (final n in (raw['nodes'] as List).cast<Map>()) {
      final number = n['number'] as int;
      final choices = (n['choices'] as List)
          .cast<Map>()
          .map(OriginalLead.read)
          .toList();
      if (number <= 0 || nodes.containsKey(number) || choices.length != 2) {
        throw const FormatException('Bivio della chiave non valido.');
      }
      nodes[number] = OriginalCouplet(number, choices);
    }
    final active = <int>{}, visited = <int>{}, missing = <int>{};
    void visit(int number) {
      if (active.contains(number)) {
        throw const FormatException('La chiave contiene un ciclo.');
      }
      if (visited.contains(number)) return;
      final node = nodes[number];
      if (node == null) {
        missing.add(number);
        return;
      }
      active.add(number);
      for (final lead in node.choices) {
        if (lead.target case final target?) visit(target);
      }
      active.remove(number);
      visited.add(number);
    }

    if (!nodes.containsKey(1)) {
      throw const FormatException('Primo bivio non disponibile.');
    }
    visit(1);
    final unreachable = nodes.keys.toSet().difference(visited);
    for (final number in unreachable) {
      visit(number);
    }
    final declared = (raw['missingTargets'] as List).cast<int>().toSet();
    final declaredUnreachable = ((raw['unreachableCouplets'] as List?) ?? [])
        .cast<int>()
        .toSet();
    if (visited.length != nodes.length ||
        missing.length != declared.length ||
        !missing.containsAll(declared) ||
        unreachable.length != declaredUnreachable.length ||
        !unreachable.containsAll(declaredUnreachable)) {
      throw const FormatException('Collegamenti della chiave incoerenti.');
    }
    return OriginalKey._(
      id: id,
      title: raw['title'] as String,
      credits: raw['credits'] as String,
      introduction: raw['introduction'] as String,
      accessedOn: raw['accessedOn'] as String,
      sourceUrl: source,
      nodes: nodes,
      missingTargets: missing,
      unreachableCouplets: unreachable,
    );
  }

  final _candidates = <int, Set<String>>{};
  Set<String> candidates(int number) => _candidates.putIfAbsent(number, () {
    final node = nodes[number];
    if (node == null) return {};
    return {
      for (final lead in node.choices)
        if (lead.name case final name?) name,
      for (final lead in node.choices)
        if (lead.target case final target?) ...candidates(target),
    };
  });

  Set<int> unresolved(int number) {
    final node = nodes[number];
    if (node == null) return {number};
    return {
      for (final lead in node.choices)
        if (lead.target case final target?) ...unresolved(target),
    };
  }
}

class OriginalKeyArchive {
  OriginalKeyArchive(this.keys, this.unavailable);
  static const asset = 'assets/italic/original_keys_v1.json';
  final Map<int, OriginalKey> keys;
  final Set<int> unavailable;
  static Future<OriginalKeyArchive>? _loading;
  static Future<OriginalKeyArchive> load() => _loading ??= _read();
  static Future<OriginalKeyArchive> _read() async {
    try {
      return await compute(
        _decodeOriginalKeys,
        await rootBundle.loadString(asset),
      );
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }

  factory OriginalKeyArchive.fromMap(Map raw) {
    if (raw['schemaVersion'] != 1 ||
        raw['source'] != 'Published ITALIC/FRIDA original textual keys') {
      throw const FormatException('Archivio delle chiavi non riconosciuto.');
    }
    final keys = <int, OriginalKey>{}, unavailable = <int>{}, seen = <int>{};
    for (final item in (raw['keys'] as List).cast<Map>()) {
      final id = item['id'] as int;
      if (id <= 0 || !seen.add(id)) {
        throw const FormatException('Chiave duplicata o non valida.');
      }
      if (item['status'] == 'available') {
        keys[id] = OriginalKey.read(item);
      } else if (item['status'] == 'unavailable') {
        unavailable.add(id);
      } else {
        throw const FormatException('Stato della chiave non valido.');
      }
    }
    return OriginalKeyArchive(keys, unavailable);
  }

  static int keyId(GenusKey entry) =>
      int.parse(entry.url.queryParameters['key_id']!);
  OriginalKey? forEntry(GenusKey entry) => keys[keyId(entry)];
}

OriginalKeyArchive _decodeOriginalKeys(String text) =>
    OriginalKeyArchive.fromMap(jsonDecode(text) as Map);
