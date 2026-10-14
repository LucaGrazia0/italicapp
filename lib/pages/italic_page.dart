import 'package:flutter/material.dart';
import '../data/italic_reference_repository.dart';
import 'italic_taxon_page.dart';
import '../services/ecological_compatibility_engine.dart';
import '../theme/app_theme.dart';

class ItalicPage extends StatefulWidget {
  const ItalicPage({super.key});
  @override
  State<ItalicPage> createState() => _ItalicPageState();
}

class _ItalicPageState extends State<ItalicPage> {
  final repo = ItalicReferenceRepository();
  final controller = TextEditingController();
  bool loading = true;
  bool showSnapshotDetails = false;
  String? error;
  List<ItalicTaxon> results = [];
  List<ItalicTaxon> filteredTaxa = [];
  int visibleCount = 50;
  static const int pageSize = 50;
  final ScrollController scrollController = ScrollController();

  void onScroll() {
    if (!scrollController.hasClients) return;

    if (scrollController.position.extentAfter < 350 &&
        visibleCount < filteredTaxa.length) {
      setState(() {
        visibleCount = (visibleCount + pageSize).clamp(0, filteredTaxa.length);
        results = filteredTaxa.take(visibleCount).toList();
      });
    }
  }

  String selectedLetter = '';

  String selectedSubstrate = 'Tutti';
  String selectedGrowthForm = 'Tutte';
  bool includeUnknownEcology = false;
  bool compatibilityMode = false;
  final compatibilityEngine = EcologicalCompatibilityEngine();

  EcologicalQuery get ecologicalQuery => EcologicalQuery(
    region: selectedRegion,
    belt: selectedBelt,
    substrate: selectedSubstrate,
    growthForm: selectedGrowthForm,
  );

  static const substrateOptions = <String>[
    'Tutti',
    'Roccia',
    'Corteccia',
    'Legno',
    'Suolo, muschi e detriti',
    'Foglie',
  ];
  static const growthOptions = <String>[
    'Tutte',
    'Crostoso',
    'Foglioso',
    'Fruticoso',
    'Squamuloso',
    'Leproso',
    'Fungo lichenicolo',
    'Non lichenizzato',
  ];

  // Il database non distingue sistematicamente rocce silicee e calcaree.
  // I testi Photobiont eventualmente accodati non sono substrati.
  String cleanEcology(String? raw) => (raw ?? '')
      .split(RegExp(r'\s+Photobiont\s*:', caseSensitive: false))
      .first
      .trim()
      .toLowerCase();

  bool matchesSubstrate(ItalicTaxon taxon) {
    if (selectedSubstrate == 'Tutti') return true;
    final value = cleanEcology(taxon.substrata);
    if (value.isEmpty) return includeUnknownEcology;
    switch (selectedSubstrate) {
      case 'Roccia':
        return RegExp(r'\brocks?\b').hasMatch(value);
      case 'Corteccia':
        return RegExp(r'\bbark\b').hasMatch(value);
      case 'Legno':
        return RegExp(r'\blignum\b').hasMatch(value);
      case 'Suolo, muschi e detriti':
        return RegExp(
          r'\bsoil\b|\bterricolous mosses\b|\bplant debris\b',
        ).hasMatch(value);
      case 'Foglie':
        return RegExp(r'\bleaves\b').hasMatch(value);
      default:
        return true;
    }
  }

  bool matchesGrowthForm(ItalicTaxon taxon) {
    if (selectedGrowthForm == 'Tutte') return true;
    final value = cleanEcology(taxon.growthForm);
    if (value.isEmpty) return includeUnknownEcology;
    switch (selectedGrowthForm) {
      case 'Crostoso':
        return value.startsWith('crustose');
      case 'Foglioso':
        return value.startsWith('foliose');
      case 'Fruticoso':
        return value.startsWith('fruticose');
      case 'Squamuloso':
        return value.startsWith('squamulose');
      case 'Leproso':
        return value.startsWith('leprose');
      case 'Fungo lichenicolo':
        return value.startsWith('lichenicolous fungus');
      case 'Non lichenizzato':
        return value.startsWith('non-lichenised');
      default:
        return true;
    }
  }

  String selectedRegion = 'Tutte';
  String selectedBelt = 'Tutte';
  bool includeUnknownRegion = false;
  bool enableAltitudeRange = false;
  RangeValues altitudeRange = const RangeValues(1000, 2000);
  bool includeUnknownAltitude = false;

  // Intervalli euristici, NON equivalenze ufficiali della scala ITALIC.
  // Usare come preselezione indicativa, non come prova di assenza.
  static const altitudeBands = <int, (double, double)>{
    1: (0, 600),
    2: (400, 1100),
    3: (900, 1600),
    4: (1400, 2200),
    5: (2000, 3000),
    6: (2700, 4500),
  };

  static const regionCodes = <String, String>{
    'Abruzzo': 'Abr',
    'Basilicata': 'Bas',
    'Calabria': 'Cal',
    'Campania': 'Camp',
    'Emilia-Romagna': 'Emil',
    'Friuli-Venezia Giulia': 'Frl',
    'Lazio': 'Laz',
    'Liguria': 'Lig',
    'Lombardia': 'Lomb',
    'Marche': 'Marc',
    'Molise': 'Mol',
    'Piemonte': 'Piem',
    'Puglia': 'Pugl',
    'Sardegna': 'Sar',
    'Sicilia': 'Si',
    'Toscana': 'Tosc',
    'Trentino-Alto Adige': 'TAA',
    'Umbria': 'Umb',
    "Valle d'Aosta": 'VA',
    'Veneto': 'Ven',
  };

  static const climateBelts = <String>[
    'Tutte',
    'Alpine belt',
    'Subalpine belt',
    'Oromediterranean belt',
    'Montane belt',
    'Submediterranean belt',
    'Padanian area',
    'Humid submediterranean belt',
    'Humid mediterranean belt',
    'Dry mediterranean belt',
  ];

  String geographyWithoutCitations(String input) {
    final output = StringBuffer();
    var depth = 0;
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        if (depth > 0) depth--;
      } else if (depth == 0) {
        output.write(ch);
      }
    }
    return output.toString();
  }

  bool matchesRegion(ItalicTaxon taxon) {
    if (selectedRegion == 'Tutte') return true;
    final distribution = taxon.distribution;
    if (distribution == null || distribution.trim().isEmpty) {
      return includeUnknownRegion;
    }
    final code = regionCodes[selectedRegion];
    if (code == null) return false;
    final geography = geographyWithoutCitations(distribution);
    final codes = selectedRegion == 'Friuli-Venezia Giulia'
        ? <String>[code, 'VG']
        : <String>[code];
    return codes.any(
      (candidate) => RegExp(
        r'(^|[^A-Za-z])' + RegExp.escape(candidate) + r'(?=[^A-Za-z]|$)',
        caseSensitive: false,
      ).hasMatch(geography),
    );
  }

  bool matchesAltitude(ItalicTaxon taxon) {
    if (!enableAltitudeRange) return true;
    final scale = taxon.ecologicalScales['Altitudinal distribution'];
    if (scale is! Map) return includeUnknownAltitude;
    final values = scale['values'];
    if (values is! List || values.isEmpty) return includeUnknownAltitude;
    final codes = values.whereType<num>().map((v) => v.toInt());
    for (final code in codes) {
      final band = altitudeBands[code];
      if (band != null &&
          band.$1 <= altitudeRange.end &&
          band.$2 >= altitudeRange.start) {
        return true;
      }
    }
    return false;
  }

  bool matchesBelt(ItalicTaxon taxon) {
    if (selectedBelt == 'Tutte') return true;
    final frequency = taxon.belts[selectedBelt]
        ?.toString()
        .trim()
        .toLowerCase();
    return frequency != null && frequency.isNotEmpty && frequency != 'absent';
  }

  void applyFilters() {
    final query = controller.text.trim().toLowerCase();

    final filtered = repo.taxa.where((taxon) {
      final name = taxon.scientificName.toLowerCase();
      final matchesLetter =
          selectedLetter.isEmpty ||
          name.startsWith(selectedLetter.toLowerCase());
      final matchesQuery = query.isEmpty || name.contains(query);
      return matchesLetter &&
          matchesQuery &&
          (compatibilityMode ||
              (matchesRegion(taxon) &&
                  matchesBelt(taxon) &&
                  matchesAltitude(taxon) &&
                  matchesSubstrate(taxon) &&
                  matchesGrowthForm(taxon)));
    }).toList();

    if (compatibilityMode) {
      final querySnapshot = ecologicalQuery;
      final assessments = <ItalicTaxon, EcologicalAssessment>{
        for (final taxon in filtered)
          taxon: compatibilityEngine.evaluate(taxon, querySnapshot),
      };
      filtered.sort((a, b) {
        final aa = assessments[a]!;
        final bb = assessments[b]!;
        // Ordina per evidenze positive, poi per assenza di contraddizioni.
        // Dati mancanti non equivalgono a compatibilità accertata.
        final matches = bb.compatible.compareTo(aa.compatible);
        if (matches != 0) return matches;
        final contradictions = (aa.incompatible + aa.reportedAbsent).compareTo(
          bb.incompatible + bb.reportedAbsent,
        );
        if (contradictions != 0) return contradictions;
        final coverageComparison = bb.evaluated.compareTo(aa.evaluated);
        if (coverageComparison != 0) return coverageComparison;
        return a.scientificName.toLowerCase().compareTo(
          b.scientificName.toLowerCase(),
        );
      });
    } else {
      filtered.sort(
        (a, b) => a.scientificName.toLowerCase().compareTo(
          b.scientificName.toLowerCase(),
        ),
      );
    }

    setState(() {
      filteredTaxa = filtered;
      visibleCount = pageSize;
      results = filteredTaxa.take(visibleCount).toList();
    });
  }

  void selectLetter(String letter) {
    selectedLetter = letter;
    applyFilters();
  }

  @override
  void initState() {
    super.initState();
    scrollController.addListener(onScroll);
    load();
  }

  @override
  void dispose() {
    scrollController.dispose();
    controller.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      await repo.load();
      if (mounted) {
        setState(() {
          loading = false;
        });
        applyFilters();
      }
    } catch (e) {
      if (mounted)
        setState(() {
          error = e.toString();
          loading = false;
        });
    }
  }

  void search(String q) => applyFilters();

  @override
  Widget build(BuildContext context) {
    final m = repo.metadata;
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'ITALIC',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: AppTheme.forest,
          ),
        ),
        const Text('Checklist scientifica dei licheni italiani • ITALIC 8.0'),
        const SizedBox(height: 18),
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (!loading && m != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.storage_outlined,
                        color: AppTheme.forest,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${repo.taxa.length} taxa',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: AppTheme.forest,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const Text(
                              'Checklist ITALIC 8.0 disponibile localmente',
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Informazioni sul database',
                        icon: Icon(
                          showSnapshotDetails
                              ? Icons.expand_less
                              : Icons.info_outline,
                        ),
                        onPressed: () => setState(
                          () => showSnapshotDetails = !showSnapshotDetails,
                        ),
                      ),
                    ],
                  ),
                  if (showSnapshotDetails) ...[
                    const Divider(),
                    Text('Fonte: ${m.sourceName}'),
                    Text('Generato: ${m.generatedAt ?? "—"}'),
                    Text('Stato: ${m.status}'),
                  ],
                ],
              ),
            ),
          ),
        const SizedBox(height: 14),
        TextField(
          controller: controller,
          enabled: repo.taxa.isNotEmpty,
          onChanged: search,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Cerca una specie o un sinonimo…',
            border: InputBorder.none,
          ),
        ),
        const SizedBox(height: 12),
        if (repo.taxa.isNotEmpty)
          ExpansionTile(
            title: const Text('Filtri territoriali'),
            shape: const Border(),
            collapsedShape: const Border(),
            leading: const Icon(Icons.public),
            initiallyExpanded: false,
            children: [
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('region-$selectedRegion'),
                initialValue: selectedRegion,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Regione italiana',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 18,
                  ),
                  border: OutlineInputBorder(),
                ),
                items: ['Tutte', ...regionCodes.keys]
                    .map(
                      (name) =>
                          DropdownMenuItem(value: name, child: Text(name)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  selectedRegion = value;
                  applyFilters();
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('belt-$selectedBelt'),
                initialValue: selectedBelt,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Fascia bioclimatica ITALIC',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 18,
                  ),
                  border: OutlineInputBorder(),
                ),
                items: climateBelts
                    .map(
                      (name) =>
                          DropdownMenuItem(value: name, child: Text(name)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  selectedBelt = value;
                  applyFilters();
                },
              ),
              CheckboxListTile(
                title: const Text('Includi taxa senza distribuzione regionale'),
                subtitle: const Text(
                  'Dati mancanti: presenza non verificabile',
                ),
                value: includeUnknownRegion,
                onChanged: (value) {
                  includeUnknownRegion = value ?? false;
                  applyFilters();
                },
              ),
              const Divider(height: 24),
              SwitchListTile(
                title: const Text('Filtra per intervallo di quota'),
                subtitle: const Text(
                  'Conversione indicativa dalla scala altitudinale ITALIC 1–6',
                ),
                value: enableAltitudeRange,
                onChanged: (value) {
                  setState(() => enableAltitudeRange = value);
                  applyFilters();
                },
              ),
              if (enableAltitudeRange) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quota: ${altitudeRange.start.round()}–${altitudeRange.end.round()} m',
                      ),
                      RangeSlider(
                        min: 0,
                        max: 4500,
                        divisions: 45,
                        labels: RangeLabels(
                          '${altitudeRange.start.round()} m',
                          '${altitudeRange.end.round()} m',
                        ),
                        values: altitudeRange,
                        onChanged: (values) {
                          setState(() => altitudeRange = values);
                          applyFilters();
                        },
                      ),
                      const Text(
                        'Quote approssimative: le classi ITALIC non corrispondono a soglie metriche ufficiali. '
                        'Non usare il filtro per escludere definitivamente un taxon.',
                      ),
                    ],
                  ),
                ),
                CheckboxListTile(
                  title: const Text('Includi taxa senza dati altitudinali'),
                  value: includeUnknownAltitude,
                  onChanged: (value) {
                    includeUnknownAltitude = value ?? false;
                    applyFilters();
                  },
                ),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    selectedRegion = 'Tutte';
                    selectedBelt = 'Tutte';
                    includeUnknownRegion = false;
                    enableAltitudeRange = false;
                    includeUnknownAltitude = false;
                    altitudeRange = const RangeValues(1000, 2000);
                    applyFilters();
                  },
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Azzera filtri territoriali'),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'Filtro regionale sperimentale: le sigle devono essere validate con la legenda ITALIC.',
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        if (repo.taxa.isNotEmpty)
          ExpansionTile(
            title: const Text('Filtri ecologici'),
            shape: const Border(),
            collapsedShape: const Border(),
            leading: const Icon(Icons.eco_outlined),
            initiallyExpanded: false,
            children: [
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('substrate-$selectedSubstrate'),
                initialValue: selectedSubstrate,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Substrato',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 18,
                  ),
                  border: OutlineInputBorder(),
                ),
                items: substrateOptions
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  selectedSubstrate = value;
                  applyFilters();
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey('growth-$selectedGrowthForm'),
                initialValue: selectedGrowthForm,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Forma di crescita',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 18,
                  ),
                  border: OutlineInputBorder(),
                ),
                items: growthOptions
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  selectedGrowthForm = value;
                  applyFilters();
                },
              ),
              CheckboxListTile(
                title: const Text('Includi taxa con dati ecologici mancanti'),
                subtitle: const Text(
                  'Vale per i filtri ecologici attivi; non implica compatibilità',
                ),
                value: includeUnknownEcology,
                onChanged: (value) {
                  includeUnknownEcology = value ?? false;
                  applyFilters();
                },
              ),
              TextButton.icon(
                onPressed: () {
                  selectedSubstrate = 'Tutti';
                  selectedGrowthForm = 'Tutte';
                  includeUnknownEcology = false;
                  applyFilters();
                },
                icon: const Icon(Icons.restart_alt),
                label: const Text('Azzera filtri ecologici'),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'ITALIC distingue la roccia in generale, non sempre la sua natura '
                  'silicea o calcarea. I filtri sono orientativi.',
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        if (repo.taxa.isNotEmpty)
          SwitchListTile(
            title: const Text('Classifica per compatibilità ecologica'),
            subtitle: const Text(
              'Disattivata: filtri classici v0.8.5. Attivata: classifica spiegabile; quota esclusa dal punteggio.',
            ),
            value: compatibilityMode,
            onChanged: (value) {
              compatibilityMode = value;
              applyFilters();
            },
          ),
        if (compatibilityMode && repo.taxa.isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Classifica: prima le evidenze positive, poi le evidenze contrarie e la completezza. Le regioni non segnalate non sono assenze accertate. Il punteggio riguarda solo i dati disponibili, NON è una probabilità di identificazione. Tocca un taxon per vedere i dettagli. La quota non partecipa alla classifica.',
            ),
          ),
        const SizedBox(height: 12),
        if (repo.taxa.isNotEmpty)
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final letter in [
                  '',
                  ...'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split(''),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(letter.isEmpty ? 'Tutti' : letter),
                      selected: selectedLetter == letter,
                      onSelected: (_) => selectLetter(letter),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        if (repo.taxa.isNotEmpty)
          Text(
            '${filteredTaxa.length} taxa trovati · ${results.length} visualizzati',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: 8),
        for (final taxon in results)
          if (compatibilityMode)
            Builder(
              builder: (context) {
                final assessment = compatibilityEngine.evaluate(
                  taxon,
                  ecologicalQuery,
                );
                final score = assessment.score;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ExpansionTile(
                    key: ValueKey(
                      'compat-${taxon.italicId ?? taxon.scientificName}',
                    ),
                    leading: const Icon(Icons.eco_outlined),
                    title: Text(
                      taxon.scientificName,
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                    subtitle: Text(
                      assessment.requested == 0
                          ? 'Seleziona almeno un criterio ecologico o territoriale'
                          : 'Riscontro sui dati valutabili: ${score == null ? "non valutabile" : "$score/100"} · '
                                'dati ${assessment.evaluated}/${assessment.requested} · '
                                '✓ ${assessment.compatible}  ✕ ${assessment.incompatible}  ◌ ${assessment.notDocumented}  − ${assessment.reportedAbsent}  ? ${assessment.unknown}',
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
                    expandedAlignment: Alignment.centerLeft,
                    children: [
                      for (final criterion in assessment.criteria)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text(
                              '${criterion.status == EvidenceStatus.compatible
                                  ? "✓"
                                  : criterion.status == EvidenceStatus.incompatible
                                  ? "✕"
                                  : criterion.status == EvidenceStatus.notDocumented
                                  ? "◌"
                                  : criterion.status == EvidenceStatus.reportedAbsent
                                  ? "−"
                                  : "?"} ${criterion.explanation}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Apri scheda del taxon'),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ItalicTaxonPage(taxon: taxon),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            )
          else
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.eco_outlined, color: AppTheme.forest),
                title: Text(
                  taxon.scientificName,
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
                subtitle: Text(
                  selectedBelt == 'Tutte'
                      ? 'ITALIC 8.0 • checklist nazionale'
                      : 'Fascia: $selectedBelt • Frequenza: ${taxon.belts[selectedBelt] ?? 'non disponibile'}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ItalicTaxonPage(taxon: taxon),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
