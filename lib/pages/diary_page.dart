import 'package:flutter/material.dart';
import '../app_store.dart';
import '../models/observation.dart';
import '../widgets/photo_view.dart';
import 'observation_page.dart';
import '../theme/app_theme.dart';

class DiaryPage extends StatefulWidget {
  const DiaryPage({super.key, required this.store});
  final AppStore store;

  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(refresh);
  }

  @override
  void dispose() {
    widget.store.removeListener(refresh);
    super.dispose();
  }

  void refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    if (widget.store.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final groups = <DateTime, List<Observation>>{};
    for (final o in widget.store.observations) {
      final d = DateTime(o.createdAt.year, o.createdAt.month, o.createdAt.day);
      groups.putIfAbsent(d, () => []).add(o);
    }
    final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'italicapp',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppTheme.forest,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'Diario di campo',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: AppTheme.charcoal,
          ),
        ),
        const SizedBox(height: 18),
        if (days.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Column(
                children: [
                  Icon(Icons.eco_outlined, size: 52),
                  SizedBox(height: 12),
                  Text('Nessuna osservazione'),
                  SizedBox(height: 5),
                  Text('Apri Fotocamera per creare la prima osservazione.'),
                ],
              ),
            ),
          ),
        for (final day in days) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Text(
              dayLabel(day),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 250,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: .9,
            ),
            itemCount: groups[day]!.length,
            itemBuilder: (_, i) {
              final o = groups[day]![i];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ObservationPage(observation: o, store: widget.store),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: ObservationPhoto(o)),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${two(o.createdAt.hour)}:${two(o.createdAt.minute)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              o.taxonName ?? 'Non determinato',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              o.positionLabel,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

String two(int n) => n.toString().padLeft(2, '0');
String dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  if (d == today) return 'OGGI';
  return '${two(d.day)}/${two(d.month)}/${d.year}';
}
