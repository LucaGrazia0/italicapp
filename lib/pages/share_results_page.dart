import 'package:flutter/material.dart';
import '../app_store.dart';
import '../services/field_dataset.dart';
import 'dataset_export_page.dart';
import 'inaturalist_share_page.dart';
import 'observation_export_page.dart';

class ShareResultsPage extends StatelessWidget {
  const ShareResultsPage({super.key, required this.store, this.sender});
  final AppStore store;
  final ObservationShareSender? sender;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Condividi risultati')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _choice(
          context,
          key: const ValueKey('sharing-export'),
          title: 'Esporta dati',
          detail: 'Excel, CSV e foto',
          icon: Icons.table_view_outlined,
          open: () => DatasetExportPage(store: store, sender: sender),
        ),
        const SizedBox(height: 16),
        _choice(
          context,
          key: const ValueKey('sharing-inaturalist'),
          title: 'Condividi con iNaturalist',
          detail: 'Foto e dati del ritrovamento',
          icon: Icons.nature_people_outlined,
          open: () {
            final data = FieldDataset.fromStore(store);
            return INaturalistSharePage(
              observations: data.observations.map(data.effective).toList(),
              dataset: data,
              sender: sender,
            );
          },
        ),
      ],
    ),
  );

  Widget _choice(
    BuildContext context, {
    required Key key,
    required String title,
    required String detail,
    required IconData icon,
    required Widget Function() open,
  }) => FilledButton.tonal(
    key: key,
    style: FilledButton.styleFrom(
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
      foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
      padding: const EdgeInsets.all(24),
      minimumSize: const Size.fromHeight(132),
      alignment: Alignment.centerLeft,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    onPressed: () =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => open())),
    child: Row(
      children: [
        Icon(icon, size: 34),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(height: 6),
              Text(detail),
            ],
          ),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.chevron_right),
      ],
    ),
  );
}
