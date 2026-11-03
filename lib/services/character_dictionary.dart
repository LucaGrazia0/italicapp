class DictionaryState {
  DictionaryState(Map data)
    : value = data['value'] as String,
      label = data['label'] as String,
      terms = List<String>.from(data['terms'] as List);
  final String value, label;
  final List<String> terms;
}

class DictionaryCharacter {
  DictionaryCharacter(Map data)
    : id = data['id'] as String,
      label = data['label'] as String,
      parent = data['parent'] as String,
      kind = data['kind'] as String,
      note = data['note'] as String,
      terms = List<String>.from(data['terms'] as List),
      implied = List<String>.from(data['impliedTerms'] as List),
      context = List<String>.from(data['context'] as List),
      scope = data['scope'] as String?,
      multiple = data['multiple'] == true,
      states = (data['states'] as List)
          .cast<Map>()
          .map(DictionaryState.new)
          .toList();
  final String id, label, parent, kind, note;
  final String? scope;
  final bool multiple;
  final List<String> terms, implied, context;
  final List<DictionaryState> states;
  Iterable<String> get allTerms => [
    ...terms,
    ...implied,
    ...context,
    ...states.expand((s) => s.terms),
  ];
  bool contains(String query) =>
      query.isEmpty ||
      [
        label,
        id,
        ...allTerms,
        ...states.map((s) => s.label),
      ].any((t) => t.toLowerCase().contains(query));
}

class DictionaryHit {
  const DictionaryHit(
    this.character,
    this.quote,
    this.start,
    this.end,
    this.term,
    this.status, {
    this.state,
  });
  final DictionaryCharacter character;
  final String quote, term, status;
  final int start, end;
  final DictionaryState? state;
  String get label =>
      state?.label ??
      switch (status) {
        'present' => 'Presenza documentata nel testo',
        'absent' => 'Assenza esplicita nel testo',
        _ => 'Menzione da verificare',
      };
  String get statusLabel => switch (status) {
    'present' => 'Proposta · da revisionare',
    'absent' => 'Negazione esplicita · da revisionare',
    'type' => 'Tipo candidato · da revisionare',
    _ => 'Contesto incerto / confronto / negazione',
  };
}

/// One conservative decision shared by the review UI and the batch report.
class DictionaryAnalysis {
  DictionaryAnalysis(this.hits, {this.multiple = false});
  final List<DictionaryHit> hits;
  final bool multiple;
  Set<String> get _values =>
      hits.map((h) => h.state?.value ?? h.status).toSet();
  bool get isCandidate =>
      hits.isNotEmpty &&
      hits.every((h) => ['present', 'absent', 'type'].contains(h.status)) &&
      (_values.length == 1 || multiple);
  List<String> get values => isCandidate ? (_values.toList()..sort()) : [];
  String? get value => isCandidate ? values.join('|') : null;
  String get status => isCandidate
      ? 'candidate'
      : hits.isEmpty
      ? 'not_documented'
      : 'needs_review';
}

class CharacterDictionary {
  CharacterDictionary.fromMap(Map data) {
    if (data['schemaVersion'] != 1) {
      throw const FormatException('Versione dizionario non supportata');
    }
    characters = (data['characters'] as List)
        .cast<Map>()
        .map(DictionaryCharacter.new)
        .toList();
    sources = (data['sources'] as List)
        .cast<Map>()
        .map((m) => Map<String, String>.from(m))
        .toList();
    blockers = List<String>.from(data['blockedContext'] as List);
    if (characters.map((c) => c.id).toSet().length != characters.length ||
        characters.any(
          (c) =>
              !['presence', 'type'].contains(c.kind) ||
              c.allTerms.any((s) => s.trim().isEmpty),
        )) {
      throw const FormatException('Voci del dizionario non valide');
    }
  }
  late final List<DictionaryCharacter> characters;
  late final List<Map<String, String>> sources;
  late final List<String> blockers;
  DictionaryAnalysis analyze(String text, DictionaryCharacter character) =>
      DictionaryAnalysis(find(text, character), multiple: character.multiple);
  static RegExp words(Iterable<String> terms) => RegExp(
    r'\b(?:' +
        (terms.toSet().toList()..sort((a, b) => b.length.compareTo(a.length)))
            .map(RegExp.escape)
            .join('|') +
        r')\b',
    caseSensitive: false,
  );

  // Keep decimal measurements within a clause and retain exact source offsets.
  Iterable<(String, int, int)> _clauses(String text) sync* {
    var start = 0;
    for (var i = 0; i <= text.length; i++) {
      final atEnd = i == text.length;
      if (!atEnd) {
        final char = text[i];
        if (!'.;\n'.contains(char)) continue;
        if (char == '.' &&
            i > 0 &&
            i + 1 < text.length &&
            RegExp(r'\d').hasMatch(text[i - 1]) &&
            RegExp(r'\d').hasMatch(text[i + 1])) {
          continue;
        }
      }
      final end = atEnd ? i : i + 1;
      final raw = text.substring(start, end);
      final quote = raw.trim();
      if (quote.isNotEmpty) {
        final offset = start + raw.indexOf(quote);
        yield (quote, offset, offset + quote.length);
      }
      start = end;
    }
  }

  bool _boundToContext(
    String quote,
    RegExpMatch descriptor,
    DictionaryCharacter c,
  ) {
    final anchors = words(c.context).allMatches(quote);
    final otherTerms = [
      ...blockers,
      ...characters
          .where((e) => e.kind == 'presence')
          .expand((e) => [...e.terms, ...e.implied]),
      'apothecia',
      'apothecium',
      'apoteci',
      'apotecio',
    ];
    final others = words(otherTerms.where((t) => !c.context.contains(t)));
    for (final anchor in anchors) {
      final gapStart = descriptor.end <= anchor.start
          ? descriptor.end
          : anchor.end;
      final gapEnd = descriptor.end <= anchor.start
          ? anchor.start
          : descriptor.start;
      if (gapEnd < gapStart || gapEnd - gapStart > 100) continue;
      if (!others.hasMatch(quote.substring(gapStart, gapEnd))) return true;
    }
    return false;
  }

  // Restrict descriptors to the structure being described. Quotations and
  // offsets always retain the complete original clause, including qualifiers.
  Iterable<(String, int, int)> _regions(String quote) sync* {
    final anchors = RegExp(
      r'\b(?:upper surface|lower surface|superficie superiore|superficie inferiore|thallus|tallo|lobes|lobi|medulla|upper cortex|lower cortex|cortex|corteccia|apothecia|apothecium|apoteci|apotecio|thalline margin|margin|disc|disco|epithecium|hymenium|hypothecium|paraphyses|asci|ascospores|pycnidia|conidia|soralia|soralium|soredia|isidia|cilia|cilium|rhizines|rhizine|photobiont|cells|cell|hyphae|spores|spore|lobules|phyllidia|pustules)\b',
      caseSensitive: false,
    );
    final boundaries = <(String, int)>[];
    var previousEnd = 0;
    for (final match in anchors.allMatches(quote)) {
      final term = match.group(0)!.toLowerCase();
      final scope = switch (term) {
        'upper surface' || 'superficie superiore' => 'upper_surface',
        'lower surface' || 'superficie inferiore' => 'lower_surface',
        'thallus' || 'tallo' => 'thallus',
        'lobes' || 'lobi' => 'lobes',
        'medulla' => 'medulla',
        'apothecia' || 'apothecium' || 'apoteci' || 'apotecio' => 'apothecia',
        'disc' || 'disco' => 'apothecia_disc',
        _ => 'other',
      };
      if (scope == 'lobes' &&
          match.start > 0 &&
          !RegExp(
            r'(?:^|,)\s*(?:the\s+)?$',
            caseSensitive: false,
          ).hasMatch(quote.substring(0, match.start))) {
        continue;
      }
      // "with pale, brown-tipped rhizines" belongs to the rhizines from
      // "with", so those colours cannot leak into the lower surface.
      var boundary = match.start;
      if (scope == 'other' || scope == 'apothecia_disc') {
        final introducers = RegExp(
          r'\b(?:with|without|bearing|producing|and)\b',
          caseSensitive: false,
        ).allMatches(quote.substring(previousEnd, match.start));
        if (introducers.isNotEmpty) {
          boundary = previousEnd + introducers.last.start;
        }
      }
      boundaries.add((scope, boundary));
      previousEnd = match.end;
    }
    for (var i = 0; i < boundaries.length; i++) {
      final (scope, start) = boundaries[i];
      final end = i + 1 < boundaries.length
          ? boundaries[i + 1].$2
          : quote.length;
      if (end > start) yield (scope, start, end);
    }
  }

  List<DictionaryHit> _findScoped(String text, DictionaryCharacter c) {
    final cutoff =
        RegExp(
          r'\b(?:spot tests|chemistry|reazioni|chimica)\s*:',
          caseSensitive: false,
        ).firstMatch(text)?.start ??
        text.length;
    final out = <DictionaryHit>[];
    for (final (quote, start, end) in _clauses(text.substring(0, cutoff))) {
      for (final (scope, from, to) in _regions(quote)) {
        final allowed = switch (c.scope) {
          'upper_surface' => ['upper_surface', 'lobes', 'thallus'],
          'lobes' => ['lobes', 'thallus'],
          _ => [c.scope],
        };
        if (!allowed.contains(scope)) continue;
        final rawRegion = quote.substring(from, to);
        final reaction = RegExp(
          r'\b(?:K|C|KC|P|UV)\s*[+-]',
          caseSensitive: false,
        ).firstMatch(rawRegion)?.start;
        final region = reaction == null
            ? rawRegion
            : rawRegion.substring(0, reaction);
        final accessory = <(int, int)>[];
        if (c.id.endsWith('_colour')) {
          for (final match in words(
            c.states.expand((s) => s.terms),
          ).allMatches(region)) {
            final suffix = RegExp(
              r'^[-\s]+(?:maculat\w*|maculae|pruinos\w*|pruina)\b',
              caseSensitive: false,
            ).firstMatch(region.substring(match.end));
            if (suffix != null) {
              accessory.add((match.start, match.end + suffix.end));
            }
          }
        }
        final candidates = <(RegExpMatch, DictionaryState)>[];
        for (final state in c.states) {
          for (final match in words(state.terms).allMatches(region)) {
            // White macules and white pruina are surface features, not a
            // statement that the underlying upper surface is white.
            if (accessory.any(
              (range) => match.start < range.$2 && range.$1 < match.end,
            )) {
              continue;
            }
            candidates.add((match, state));
          }
        }
        candidates.sort(
          (a, b) => (b.$1.end - b.$1.start).compareTo(a.$1.end - a.$1.start),
        );
        final accepted = <(RegExpMatch, DictionaryState)>[];
        for (final candidate in candidates) {
          if (!accepted.any(
            (old) =>
                candidate.$1.start < old.$1.end &&
                old.$1.start < candidate.$1.end,
          )) {
            accepted.add(candidate);
          }
        }
        // Negative state aliases (epruinose, not maculate) are explicit
        // absences. Other negations and conditions require human inspection.
        var context = region;
        for (final (match, state) in accepted) {
          if (state.value == 'absent') {
            context = context.replaceFirst(match.group(0)!, '');
          }
        }
        if (c.scope == 'apothecia') {
          // Frequency before the comma describes the occurrence of apothecia,
          // not an alternative margin type or mode of insertion.
          context = context.replaceFirst(
            RegExp(
              r'^\s*(?:apothecia|apothecium|apoteci)\s+(?:(?:very|extremely|rather)\s+)?rare\s*,',
              caseSensitive: false,
            ),
            'Apothecia,',
          );
        }
        final uncertain =
            RegExp(
              r'\b(?:rare|rarely|sometimes|occasionally|may|can|when|except|otherwise|or|not|no|without|resembling|similar|unlike|compared|talvolta|raramente|oppure|senza)\b|[- ]like\b',
              caseSensitive: false,
            ).hasMatch(context) ||
            (!c.multiple && accepted.map((a) => a.$2.value).toSet().length > 1);
        for (final (match, state) in accepted) {
          out.add(
            DictionaryHit(
              c,
              quote,
              start,
              end,
              match.group(0)!,
              uncertain ? 'uncertain' : 'type',
              state: state,
            ),
          );
        }
      }
    }
    final seen = <String>{};
    return out
        .where((h) => seen.add('${h.start}:${h.state!.value}:${h.status}'))
        .toList();
  }

  List<DictionaryHit> find(String text, DictionaryCharacter c) {
    if (c.scope != null) return _findScoped(text, c);
    final out = <DictionaryHit>[];
    for (final (quote, start, end) in _clauses(text)) {
      final conditional = RegExp(
        r'\b(?:rare|rarely|sometimes|occasionally|may|can|when|except|otherwise|or|talvolta|raramente|oppure|variabile)\b',
        caseSensitive: false,
      ).hasMatch(quote);
      final comparison = RegExp(
        r'\b(?:resembling|resembles|similar|unlike|compared|refers|other taxa|other species)\b|[- ]like\b',
        caseSensitive: false,
      ).hasMatch(quote);
      if (c.kind == 'presence') {
        final tokens = [...c.terms, ...c.implied];
        for (final match in words(tokens).allMatches(quote)) {
          final term = match.group(0)!;
          final escaped = RegExp.escape(term);
          final negative = RegExp(
            r'\b(?:without|lacking|no|not|senza|assente|assenti)\s+(?:(?:\w+)[ ,]+){0,3}' +
                escaped +
                r'\b|\b' +
                escaped +
                r'\s+(?:(?:is|are)\s+)?(?:absent|lacking|assente|assenti)\b',
            caseSensitive: false,
          ).hasMatch(quote);
          final implied = c.implied.any(
            (t) => t.toLowerCase() == term.toLowerCase(),
          );
          final positive =
              match.start == 0 ||
              RegExp(
                r'\b(?:with|con)\b',
                caseSensitive: false,
              ).hasMatch(quote.substring(0, match.start));
          final status = conditional || comparison || negative && implied
              ? 'uncertain'
              : negative
              ? 'absent'
              : positive
              ? 'present'
              : 'uncertain';
          out.add(DictionaryHit(c, quote, start, end, term, status));
        }
      } else {
        final candidates = <(RegExpMatch, DictionaryState)>[];
        for (final state in c.states) {
          for (final match in words(state.terms).allMatches(quote)) {
            if (_boundToContext(quote, match, c)) {
              candidates.add((match, state));
            }
          }
        }
        candidates.sort(
          (a, b) => (b.$1.end - b.$1.start).compareTo(a.$1.end - a.$1.start),
        );
        final accepted = <(RegExpMatch, DictionaryState)>[];
        for (final candidate in candidates) {
          if (accepted.any(
            (old) =>
                candidate.$1.start < old.$1.end &&
                old.$1.start < candidate.$1.end,
          )) {
            continue;
          }
          accepted.add(candidate);
        }
        final multiple = accepted.map((a) => a.$2.value).toSet().length > 1;
        final negative = RegExp(
          r'\b(?:without|lacking|absent|no|not|senza|assente|assenti)\b',
          caseSensitive: false,
        ).hasMatch(quote);
        for (final (match, state) in accepted) {
          out.add(
            DictionaryHit(
              c,
              quote,
              start,
              end,
              match.group(0)!,
              conditional || comparison || negative || multiple
                  ? 'uncertain'
                  : 'type',
              state: state,
            ),
          );
        }
      }
    }
    final seen = <String>{};
    return out
        .where((h) => seen.add('${h.start}:${h.state?.value ?? h.status}'))
        .toList();
  }
}
