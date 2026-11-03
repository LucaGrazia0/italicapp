import 'package:flutter/material.dart';
import 'package:url_launcher/link.dart';
import '../services/character_dictionary.dart';
import '../data/character_dictionary_repository.dart';

class CharacterDictionaryPage extends StatefulWidget {
  const CharacterDictionaryPage({
    super.key,
    this.sourceText = '',
    this.initialConcept,
    this.pickEvidence = false,
    this.dictionary,
  });
  final String sourceText;
  final String? initialConcept;
  final bool pickEvidence;
  final CharacterDictionary? dictionary;
  @override
  State<CharacterDictionaryPage> createState() =>
      _CharacterDictionaryPageState();
}

class _CharacterDictionaryPageState extends State<CharacterDictionaryPage> {
  late final TextEditingController source, query;
  CharacterDictionary? dictionary;
  bool failed = false;
  bool onlyRelevant = true;
  @override
  void initState() {
    super.initState();
    source = TextEditingController(text: widget.sourceText);
    query = TextEditingController();
    _load();
  }

  Future<void> _load() async {
    try {
      final loaded =
          widget.dictionary ?? await CharacterDictionaryRepository().load();
      if (mounted) {
        setState(() {
          dictionary = loaded;
          failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  void dispose() {
    source.dispose();
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = dictionary;
    final q = query.text.trim().toLowerCase();
    final entries =
        data?.characters
            .where(
              (c) =>
                  c.contains(q) &&
                  (!onlyRelevant ||
                      widget.initialConcept == null ||
                      c.id == widget.initialConcept ||
                      c.parent == widget.initialConcept),
            )
            .toList() ??
        [];
    return Scaffold(
      appBar: AppBar(title: const Text('Dizionario dei caratteri')),
      body: data == null
          ? Center(
              child: failed
                  ? TextButton(
                      onPressed: _load,
                      child: const Text('Caricamento non riuscito · Riprova'),
                    )
                  : const CircularProgressIndicator(),
            )
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      '${data.characters.length} gruppi · termini italiani, inglesi, forme e tipi',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Text(
                      'Le corrispondenze aiutano a leggere la descrizione: non confermano automaticamente un carattere. Nessuna parola trovata significa informazione non documentata, non assenza.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('dictionary-query'),
                      controller: query,
                      decoration: const InputDecoration(
                        labelText:
                            'Cerca un carattere, tipo o termine (es. simple, soralia, squarrose)',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (widget.initialConcept != null)
                      SwitchListTile(
                        value: onlyRelevant,
                        title: const Text(
                          'Solo caratteri collegati alla cella',
                        ),
                        onChanged: (v) => setState(() => onlyRelevant = v),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('dictionary-source'),
                      controller: source,
                      readOnly: widget.pickEvidence,
                      minLines: 3,
                      maxLines: 6,
                      decoration: InputDecoration(
                        labelText: widget.pickEvidence
                            ? 'Descrizione ITALIC originale'
                            : 'Incolla una descrizione da cercare',
                        alignLabelWithHint: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 14),
                    if (entries.isEmpty)
                      const Text(
                        'Nessuna voce del dizionario per questa ricerca.',
                      ),
                    for (final c in entries) _entry(data, c),
                    const Divider(height: 30),
                    const Text('Riferimenti terminologici'),
                    for (final ref in data.sources)
                      Link(
                        uri: Uri.parse(ref['url']!),
                        target: LinkTarget.blank,
                        builder: (_, follow) => TextButton(
                          onPressed: follow,
                          child: Text(ref['title']!),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _entry(CharacterDictionary data, DictionaryCharacter c) {
    final hits = data.find(source.text, c);
    return Card(
      key: ValueKey('dictionary-entry-${c.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.label, style: Theme.of(context).textTheme.titleMedium),
            Text(c.note),
            const SizedBox(height: 6),
            Text('Termini: ${c.allTerms.toSet().join(', ')}'),
            if (source.text.trim().isNotEmpty && hits.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Nessuna corrispondenza nel contesto richiesto.'),
              ),
            for (final hit in hits) ...[
              const Divider(height: 20),
              Text('${hit.label} · ${hit.statusLabel}'),
              Text('Termine trovato: ${hit.term}'),
              SelectableText('“${hit.quote}”'),
              if (widget.pickEvidence)
                TextButton(
                  key: ValueKey(
                    'dictionary-use-${c.id}-${hit.start}-${hit.state?.value ?? hit.status}',
                  ),
                  onPressed: () => Navigator.pop(context, hit),
                  child: const Text('Usa citazione come bozza'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
