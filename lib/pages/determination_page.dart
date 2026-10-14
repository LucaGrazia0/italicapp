import 'package:flutter/material.dart';
import '../app_store.dart';
import '../models/observation.dart';

class DeterminationStartPage extends StatelessWidget {
  const DeterminationStartPage({
    super.key,
    required this.observation,
    required this.store,
  });

  final Observation observation;
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Determina')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Come vuoi procedere?',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'La determinazione appartiene a questa osservazione. '
                'Puoi usare un percorso completo oppure partire dai macrocaratteri.',
              ),
              const SizedBox(height: 22),
              _MethodCard(
                icon: Icons.account_tree_outlined,
                title: 'Determinazione completa',
                subtitle: 'Percorso dettagliato. Sarà collegato ai caratteri scientifici ITALIC.',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const _ComingSoonPage(
                      title: 'Determinazione completa',
                      text: 'Il percorso completo verrà alimentato dal database scientifico ITALIC.',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _MethodCard(
                icon: Icons.filter_alt_outlined,
                title: 'Determinazione per macrocaratteri',
                subtitle: 'Riduci progressivamente i taxa usando caratteri osservabili sul campo.',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MacroDeterminationPage(
                      observation: observation,
                      store: store,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.all(16),
      leading: Icon(icon, size: 30),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(subtitle),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

class MacroDeterminationPage extends StatefulWidget {
  const MacroDeterminationPage({
    super.key,
    required this.observation,
    required this.store,
  });
  final Observation observation;
  final AppStore store;

  @override
  State<MacroDeterminationPage> createState() => _MacroDeterminationPageState();
}

class _MacroDeterminationPageState extends State<MacroDeterminationPage> {
  int step = 0;
  final answers = <String, String>{};

  static const questions = [
    (
      'Forma di crescita',
      'Qual è la forma generale del tallo?',
      ['Crostoso', 'Foglioso', 'Fruticoso', 'Leproso', 'Squamuloso', 'Non so']
    ),
    (
      'Substrato',
      'Su quale substrato cresce?',
      ['Roccia', 'Corteccia', 'Legno', 'Suolo', 'Muschio', 'Altro', 'Non so']
    ),
    (
      'Strutture riproduttive',
      'Quali strutture sono chiaramente visibili?',
      ['Apoteci', 'Periteci', 'Soredi', 'Isidi', 'Nessuna evidente', 'Non so']
    ),
  ];

  void choose(String value) {
    final q = questions[step];
    answers[q.$1] = value;
    if (step < questions.length - 1) {
      setState(() => step++);
    } else {
      _showResult();
    }
  }

  void _showResult() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Risultato preliminare')),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Icon(Icons.science_outlined, size: 52),
                  const SizedBox(height: 16),
                  Text(
                    'Percorso macrocaratteri completato',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'In questa v0.5 le risposte vengono raccolte, ma non viene assegnato '
                    'un taxon automaticamente: il ranking scientifico sarà collegato ai '
                    'dati ITALIC strutturati, evitando risultati inventati.',
                  ),
                  const SizedBox(height: 20),
                  for (final e in answers.entries)
                    ListTile(
                      leading: const Icon(Icons.check_circle_outline),
                      title: Text(e.key),
                      subtitle: Text(e.value),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = questions[step];
    return Scaffold(
      appBar: AppBar(title: const Text('Macrocaratteri')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              LinearProgressIndicator(value: (step + 1) / questions.length),
              const SizedBox(height: 18),
              Text(
                q.$1,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              Text(
                q.$2,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 20),
              for (final answer in q.$3)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.all(18),
                      alignment: Alignment.centerLeft,
                    ),
                    onPressed: () => choose(answer),
                    child: Text(answer),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComingSoonPage extends StatelessWidget {
  const _ComingSoonPage({required this.title, required this.text});
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center),
        ),
      ),
    ),
  );
}
