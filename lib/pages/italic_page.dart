import 'package:flutter/material.dart';

import '../data/italic_reference_repository.dart';
import 'italic_taxon_page.dart';
import '../services/ecological_compatibility_engine.dart';
import '../theme/app_theme.dart';
import '../widgets/ecological_filters.dart';
import 'determination_page.dart';

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
  String selectedPhotobiont = '';
  String selectedReproduction = '';
  final selectedScales = <String, int>{};
  final compatibilityEngine = EcologicalCompatibilityEngine();

  EcologicalQuery get ecologicalQuery => EcologicalQuery(
    region: selectedRegion,
    belt: selectedBelt,
    substrate: selectedSubstrate,
    growthForm: selectedGrowthForm,
    photobiont: selectedPhotobiont,
    reproductiveStrategy: selectedReproduction,
    scales: selectedScales,
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

  bool matchesEcology(ItalicTaxon taxon) {
    final assessment = compatibilityEngine.evaluate(
      taxon,
      EcologicalQuery(
        substrate: selectedSubstrate,
        growthForm: selectedGrowthForm,
        photobiont: selectedPhotobiont,
        reproductiveStrategy: selectedReproduction,
        scales: selectedScales,
      ),
    );
    return assessment.criteria.every(
      (criterion) =>
          criterion.status == EvidenceStatus.compatible ||
          (includeUnknownEcology && criterion.status == EvidenceStatus.unknown),
    );
  }

  String selectedRegion = 'Tutte';
  String selectedBelt = 'Tutte';
  bool includeUnknownRegion = false;
  static const regionCodes = EcologicalCompatibilityEngine.regionCodes;

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

  bool matchesRegion(ItalicTaxon taxon) {
    if (selectedRegion == 'Tutte') return true;
    return EcologicalCompatibilityEngine.regionMatch(taxon, selectedRegion) ??
        includeUnknownRegion;
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
      final matchesQuery =
          query.isEmpty ||
          name.contains(query) ||
          taxon.synonyms.any(
            (synonym) => synonym.toLowerCase().contains(query),
          );
      return matchesLetter &&
          matchesQuery &&
          (compatibilityMode ||
              (matchesRegion(taxon) &&
                  matchesBelt(taxon) &&
                  matchesEcology(taxon)));
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
        final comparison = EcologicalCompatibilityEngine.compare(aa, bb);
        if (comparison != 0) return comparison;
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
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
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
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w800, color: AppTheme.forest),
        ),
        const Text('Checklist scientifica dei licheni italiani • ITALIC 8.0'),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const ValueKey('open-identification-keys'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.all(20)),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DeterminationStartPage()),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_tree_outlined, size: 32),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chiavi di determinazione',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text('Identifica un campione con i bivi ITALIC.'),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward),
              ],
            ),
          ),
        ),
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
                    if (m.ecologyTaxa > 0)
                      Text(
                        'Dati ecologici strutturati per ${m.ecologyTaxa} taxa',
                      ),
                  ],
                ],
              ),
            ),
          ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('italic-species-search'),
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
          SwitchListTile(
            key: const ValueKey('compatibility-mode'),
            title: const Text('Classifica per compatibilità ecologica'),
            subtitle: const Text(
              'Confronta tutti i criteri selezionati e mostra le evidenze per ogni taxon.',
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
              'Prima le evidenze positive, poi le evidenze contrarie e la completezza. '
              'Le regioni non segnalate non sono assenze accertate. '
              'Il punteggio riguarda i criteri valutabili, comprese le fasce indicate come assenti; '
              'non è una probabilità di identificazione. Espandi un risultato per leggere il confronto.',
            ),
          ),
        const SizedBox(height: 12),
        if (repo.taxa.isNotEmpty)
          ExpansionTile(
            key: const PageStorageKey('territorial-filters'),
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
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    selectedRegion = 'Tutte';
                    selectedBelt = 'Tutte';
                    includeUnknownRegion = false;
                    applyFilters();
                  },
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Azzera filtri territoriali'),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'La mancata segnalazione in una regione non dimostra l’assenza del taxon.',
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        if (repo.taxa.isNotEmpty)
          ExpansionTile(
            key: const PageStorageKey('ecological-filters'),
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
              EcologicalFilters(
                scales: selectedScales,
                photobiont: selectedPhotobiont,
                reproduction: selectedReproduction,
                onScaleChanged: (key, value) {
                  if (value == null) {
                    selectedScales.remove(key);
                  } else {
                    selectedScales[key] = value;
                  }
                  applyFilters();
                },
                onPhotobiontChanged: (value) {
                  selectedPhotobiont = value;
                  applyFilters();
                },
                onReproductionChanged: (value) {
                  selectedReproduction = value;
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
                  selectedPhotobiont = '';
                  selectedReproduction = '';
                  selectedScales.clear();
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
