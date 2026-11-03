import 'dart:convert';
import '../data/scientific_data.dart';
import '../data/italic_reference_repository.dart';
import 'physcia_review_engine.dart';

class ReconstructedChoice {
  const ReconstructedChoice(this.target, this.label, this.bindings, this.note);
  final String target, label, note;
  final Map<String, String> bindings;

  /// Mentions only: no presence/absence or state is inferred from a word.
  List<String> get terms => [
    for (final e in <String, String>{
      r'\b(soredi\w*|sorali\w*)': 'Sorali / soredi',
      r'\bisidi\w*': 'Isidi / strutture isidioidi',
      r'\bcilia\w*': 'Ciglia',
      r'\brhizin\w*': 'Rizine',
      r'\bapotheci\w*': 'Apoteci',
      r'\bascospor\w*': 'Ascospore',
      r'\bthall\w*': 'Tallo',
      r'\bpruin\w*|\bepruin\w*': 'Pruina',
      r'\bmaculat\w*|\bemaculat\w*': 'Macule',
      r'\bmedulla\b': 'Medulla',
    }.entries)
      if (RegExp(e.key, caseSensitive: false).hasMatch(label)) e.value,
  ];
  factory ReconstructedChoice.read(Map raw) {
    final bindings = Map<String, String>.from(raw['bindings'] as Map);
    if (bindings.entries.any(
      (e) => PhysciaPilot.character(e.key)?.stable(e.value) != true,
    )) {
      throw const FormatException('Unknown character binding');
    }
    return ReconstructedChoice(
      raw['target'] as String,
      raw['label'] as String,
      bindings,
      raw['note'] as String? ?? '',
    );
  }
}

class ReconstructedNode {
  const ReconstructedNode(
    this.id,
    this.choices,
    this.taxonId,
    this.officialNode, {
    this.unresolvedLabel,
    this.unresolvedKind,
  });
  final String id;
  final List<ReconstructedChoice> choices;
  final int? taxonId, officialNode;
  final String? unresolvedLabel, unresolvedKind;
  bool get terminal => choices.isEmpty;
}

class AssociatedKey {
  const AssociatedKey(this.title, this.url);
  final String title;
  final Uri url;
  factory AssociatedKey.read(Map raw) {
    final uri = Uri.parse(raw['url'] as String);
    if (uri.scheme != 'https' ||
        !{'italic.units.it', 'dryades.units.it'}.contains(uri.host) ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasFragment ||
        !{'/home/index.php', '/flora/index.php'}.contains(uri.path) ||
        uri.queryParameters['procedure'] != 'ext_key_home' ||
        int.tryParse(uri.queryParameters['key_id'] ?? '') == null) {
      throw const FormatException('Unexpected associated key URL');
    }
    return AssociatedKey(raw['title'] as String, uri);
  }
}

class ReconstructedStep {
  const ReconstructedStep(this.node, this.choice);
  final ReconstructedNode node;
  final ReconstructedChoice choice;
}

class ReconstructedKey {
  ReconstructedKey._(
    this.title,
    this.root,
    this.nodes,
    this.taxa,
    this.keyUrl,
    this.citation,
    this.unavailableRecords, {
    this.identity = id,
    this.language = 'it',
    this.scopeGenus,
    this.preFilters = const {},
    this.unrepresented = const {},
    this.extraTaxa = const <int>{},
    this.associatedKeys = const {},
    this.aliases = const [],
  });
  static const id = 'italic-physcia-reconstructed-v1';
  static const asset = 'assets/italic/physcia_reconstructed_key_v1.json';
  static const generalId = 'italic-general-reconstructed-v1';
  static const generalAsset = 'assets/italic/general_reconstructed_key_v1.json';
  final String identity, language;
  final String? scopeGenus;
  final Map<String, String> preFilters;
  final Map<int, ItalicTaxon> unrepresented;
  final Set<int> extraTaxa;
  final Map<int, List<AssociatedKey>> associatedKeys;
  final List<Map> aliases;
  bool get general => identity == generalId;
  final String title, root, citation;
  final Map<String, ReconstructedNode> nodes;
  final Map<int, ItalicTaxon> taxa;
  final Uri keyUrl;
  final List<String> unavailableRecords;
  int get occurrences => nodes.values.where((n) => n.taxonId != null).length;
  int get couplets => nodes.values.where((n) => !n.terminal).length;
  int get coveredLocal => taxa.length - extraTaxa.length;
  Map<int, ItalicTaxon> get catalog => {
    for (final e in taxa.entries)
      if (!extraTaxa.contains(e.key)) e.key: e.value,
    ...unrepresented,
  };
  List<String> get genera =>
      (catalog.values
          .map((t) => t.scientificName.split(' ').first)
          .toSet()
          .toList()
        ..sort());

  static Future<ReconstructedKey> load({int? revision}) async {
    final reference = ItalicReferenceRepository();
    await reference.load(revision: revision);
    return ReconstructedKey.fromMap(
      jsonDecode(await ScientificData.loadString(asset, revision: revision))
          as Map,
      reference.taxa,
    );
  }

  static Future<ReconstructedKey>? _generalLoading;
  static Future<ReconstructedKey> loadGeneral({int? revision}) =>
      revision == null
      ? (_generalLoading ??= _readGeneral())
      : _readGeneral(revision: revision);
  static void clearCache() {
    _generalLoading = null;
  }

  static Future<ReconstructedKey> _readGeneral({int? revision}) async {
    try {
      final reference = ItalicReferenceRepository();
      await reference.load(revision: revision);
      return ReconstructedKey.fromMap(
        jsonDecode(
              await ScientificData.loadString(generalAsset, revision: revision),
            )
            as Map,
        reference.taxa,
      );
    } catch (_) {
      _generalLoading = null;
      rethrow;
    }
  }

  factory ReconstructedKey.fromMap(Map raw, List<ItalicTaxon> reference) {
    final isGeneral = raw['id'] == generalId;
    if (raw['schemaVersion'] != 1 ||
        (!isGeneral && (raw['id'] != id || raw['genus'] != 'Physcia')) ||
        raw['status'] != 'reconstructed_key_conditions') {
      throw const FormatException('Unsupported reconstructed key');
    }
    final source = raw['source'] as Map;
    final keyId = source['keyId'] as String;
    final uri = Uri.parse(source['keyUrl'] as String);
    if ((isGeneral
            ? keyId != 'full'
            : !RegExp(r'^[a-f0-9-]{36}$').hasMatch(keyId)) ||
        uri.toString() !=
            'https://italic.units.it/key-maker/$keyId/nodes/1/interactive') {
      throw const FormatException('Unexpected source URL');
    }
    final taxa = <int, ItalicTaxon>{};
    final referenceById = {for (final t in reference) t.italicId: t};
    for (final t in (raw['taxa'] as List).cast<Map>()) {
      final id = t['italicId'] as int;
      final match = referenceById[id];
      if (match == null ||
          match.scientificName != t['scientificName'] ||
          (!isGeneral && !PhysciaPilot.inScope(match)) ||
          taxa.containsKey(id)) {
        throw const FormatException('Taxon identity changed');
      }
      taxa[id] = match;
    }
    final extra = <int>{},
        missing = <int, ItalicTaxon>{},
        links = <int, List<AssociatedKey>>{};
    if (isGeneral) {
      for (final t in (raw['additionalSourceTaxa'] as List).cast<Map>()) {
        final id = t['italicId'] as int;
        if (referenceById.containsKey(id) ||
            taxa.containsKey(id) ||
            !extra.add(id)) {
          throw const FormatException('Extra taxon identity changed');
        }
        taxa[id] = ItalicTaxon(
          italicId: id,
          scientificName: t['scientificName'] as String,
        );
      }
      for (final t in (raw['unrepresentedTaxa'] as List).cast<Map>()) {
        final id = t['italicId'] as int;
        final match = referenceById[id];
        if (match == null ||
            match.scientificName != t['scientificName'] ||
            taxa.containsKey(id) ||
            missing.containsKey(id)) {
          throw const FormatException('Missing taxon identity changed');
        }
        missing[id] = match;
        links[id] = (t['associatedKeys'] as List)
            .cast<Map>()
            .map(AssociatedKey.read)
            .toList();
      }
      if (raw['referenceCount'] != reference.length ||
          taxa.length - extra.length + missing.length != reference.length) {
        throw const FormatException('Checklist coverage changed');
      }
    }
    final nodes = <String, ReconstructedNode>{};
    for (final n in (raw['nodes'] as List).cast<Map>()) {
      final id = n['id'] as String;
      final choices = (n['choices'] as List)
          .cast<Map>()
          .map(ReconstructedChoice.read)
          .toList();
      final taxonId = n['taxonId'] as int?;
      final ordinal = n['officialNode'] as int?;
      final unresolved = n['unresolvedLabel'] as String?;
      if (nodes.containsKey(id) ||
          (taxonId != null || unresolved != null
              ? choices.isNotEmpty ||
                    (taxonId != null && !taxa.containsKey(taxonId)) ||
                    (unresolved != null &&
                        (!isGeneral || taxonId != null || unresolved.isEmpty))
              : choices.length != 2 || ordinal == null || ordinal < 1)) {
        throw const FormatException('Invalid key node');
      }
      nodes[id] = ReconstructedNode(
        id,
        choices,
        taxonId,
        ordinal,
        unresolvedLabel: unresolved,
        unresolvedKind: n['unresolvedKind'] as String?,
      );
    }
    final root = raw['root'] as String;
    final seen = <String>{}, covered = <int>{}, ordinals = <int>{};
    void visit(String id) {
      final node = nodes[id];
      if (node == null || !seen.add(id)) {
        throw const FormatException('Cycle, repeated target or missing node');
      }
      if (node.taxonId case final taxonId?) covered.add(taxonId);
      if (node.officialNode case final ordinal?) {
        if (!ordinals.add(ordinal)) {
          throw const FormatException('Duplicate source couplet');
        }
      }
      for (final choice in node.choices) {
        visit(choice.target);
      }
    }

    visit(root);
    if (seen.length != nodes.length || covered.length != taxa.length) {
      throw const FormatException('Incomplete key');
    }
    return ReconstructedKey._(
      raw['title'] as String,
      root,
      nodes,
      taxa,
      uri,
      source['citation'] as String,
      ((raw['diagnostics'] as Map)['unavailableRecords'] as List)
          .cast<String>(),
      identity: isGeneral ? generalId : id,
      language: isGeneral ? 'en' : 'it',
      unrepresented: missing,
      extraTaxa: extra,
      associatedKeys: links,
      aliases: ((raw['identityAliases'] as List?) ?? []).cast<Map>(),
    );
  }

  Map<String, String> normalize(Map<String, String> input) {
    var current = nodes[root]!;
    final result = <String, String>{
      if (scopeGenus != null) '_genus': scopeGenus!,
      for (final e in preFilters.entries) '_trait:${e.key}': e.value,
    };
    while (!current.terminal) {
      final value = input[current.id];
      if (value == 'unknown') {
        result[current.id] = value!;
        break;
      }
      final found = current.choices.where((c) => c.target == value);
      if (found.isEmpty) break;
      result[current.id] = value!;
      current = nodes[value]!;
    }
    return result;
  }

  List<ReconstructedStep> trail(Map<String, String> input) {
    final selections = normalize(input);
    var node = nodes[root]!;
    final result = <ReconstructedStep>[];
    while (selections[node.id] != null && selections[node.id] != 'unknown') {
      final choice = node.choices.singleWhere(
        (c) => c.target == selections[node.id],
      );
      result.add(ReconstructedStep(node, choice));
      node = nodes[choice.target]!;
    }
    return result;
  }

  ReconstructedNode current(Map<String, String> input) {
    final steps = trail(input);
    return nodes[steps.isEmpty ? root : steps.last.choice.target]!;
  }

  final _candidateCache = <String, Set<int>>{};
  Set<int> candidates(String nodeId) => _candidateCache.putIfAbsent(nodeId, () {
    final node = nodes[nodeId]!;
    if (node.taxonId case final id?) return {id};
    return {for (final choice in node.choices) ...candidates(choice.target)};
  });
  final _unresolvedCache = <String, Set<String>>{};
  Set<String> unresolved(String nodeId) =>
      _unresolvedCache.putIfAbsent(nodeId, () {
        final node = nodes[nodeId]!;
        return node.unresolvedLabel != null
            ? {nodeId}
            : {for (final c in node.choices) ...unresolved(c.target)};
      });

  late final _parents = <String, ReconstructedStep>{
    for (final n in nodes.values)
      for (final c in n.choices) c.target: ReconstructedStep(n, c),
  };
  late final Map<int, List<String>> _leaves = () {
    final result = <int, List<String>>{};
    for (final n in nodes.values) {
      if (n.taxonId != null) (result[n.taxonId!] ??= []).add(n.id);
    }
    return result;
  }();
  int pathCountFor(int taxonId) => _leaves[taxonId]?.length ?? 0;
  List<List<ReconstructedStep>> pathsFor(int taxonId) {
    return [
      for (final leaf in _leaves[taxonId] ?? <String>[]) _path(leaf, _parents),
    ];
  }

  List<ReconstructedStep> _path(
    String id,
    Map<String, ReconstructedStep> parents,
  ) {
    final backwards = <ReconstructedStep>[];
    while (parents[id] != null) {
      final step = parents[id]!;
      backwards.add(step);
      id = step.node.id;
    }
    return backwards.reversed.toList();
  }

  ReconstructedKey forGenus(String genus) {
    if (!general || !genera.contains(genus)) {
      throw const FormatException('Unknown genus');
    }
    final selected = {
      for (final t in taxa.values)
        if (t.scientificName.split(' ').first == genus) t.italicId!,
    };
    final kept = <String, ReconstructedNode>{};
    String? retain(String id) {
      final node = nodes[id]!;
      if (node.terminal) {
        if (selected.contains(node.taxonId) ||
            (node.unresolvedLabel?.startsWith('$genus ') ?? false)) {
          kept[id] = node;
          return id;
        }
        return null;
      }
      final cs = <ReconstructedChoice>[];
      for (final c in node.choices) {
        final target = retain(c.target);
        if (target != null) {
          cs.add(ReconstructedChoice(target, c.label, c.bindings, c.note));
        }
      }
      if (cs.length == 1) return cs.single.target;
      if (cs.isEmpty) return null;
      kept[id] = ReconstructedNode(id, cs, null, node.officialNode);
      return id;
    }

    final newRoot = retain(root);
    if (newRoot == null) {
      throw const FormatException('Genus has no available path');
    }
    return ReconstructedKey._(
      '$genus · chiave ITALIC',
      newRoot,
      kept,
      {for (final id in selected) id: taxa[id]!},
      keyUrl,
      citation,
      unavailableRecords,
      identity: identity,
      language: language,
      scopeGenus: genus,
      unrepresented: {
        for (final e in unrepresented.entries)
          if (e.value.scientificName.split(' ').first == genus) e.key: e.value,
      },
      extraTaxa: extraTaxa.intersection(selected),
      associatedKeys: associatedKeys,
      aliases: aliases,
    );
  }

  /// Prune only documented mismatches. Unresolved source continuations survive.
  ReconstructedKey filtered(Set<int> eligible, Map<String, String> filters) {
    final kept = <String, ReconstructedNode>{};
    String? retain(String id) {
      final node = nodes[id]!;
      if (node.terminal) {
        if (node.unresolvedLabel != null || eligible.contains(node.taxonId)) {
          kept[id] = node;
          return id;
        }
        return null;
      }
      final choices = <ReconstructedChoice>[];
      for (final c in node.choices) {
        final target = retain(c.target);
        if (target != null) {
          choices.add(ReconstructedChoice(target, c.label, c.bindings, c.note));
        }
      }
      if (choices.isEmpty) return null;
      if (choices.length == 1) return choices.single.target;
      kept[id] = ReconstructedNode(id, choices, null, node.officialNode);
      return id;
    }

    final newRoot = retain(root);
    if (newRoot == null) throw const FormatException('No remaining paths');
    return ReconstructedKey._(
      title,
      newRoot,
      kept,
      {
        for (final e in taxa.entries)
          if (eligible.contains(e.key)) e.key: e.value,
      },
      keyUrl,
      citation,
      unavailableRecords,
      identity: identity,
      language: language,
      scopeGenus: scopeGenus,
      preFilters: Map.unmodifiable(filters),
      unrepresented: {
        for (final e in unrepresented.entries)
          if (eligible.contains(e.key)) e.key: e.value,
      },
      extraTaxa: extraTaxa.intersection(eligible),
      associatedKeys: associatedKeys,
      aliases: aliases,
    );
  }

  Uri sourceFor(ReconstructedNode node) => keyUrl.replace(
    path: keyUrl.path.replaceFirst(
      '/nodes/1/',
      '/nodes/${node.officialNode ?? 1}/',
    ),
  );
}
