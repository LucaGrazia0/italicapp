import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../theme/app_theme.dart';
import '../widgets/offline_card.dart';
import '../widgets/data_updates_card.dart';
import '../widgets/iphone_install_card.dart';
import '../app_store.dart';
import 'observation_export_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.store,
    this.onOpenDiary,
    this.onOpenItalic,
  });
  final AppStore store;
  final VoidCallback? onOpenDiary, onOpenItalic;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'ITALICAPP',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: AppTheme.forest,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'Impostazioni',
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          color: AppTheme.charcoal,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Informazioni sul progetto e sui dati disponibili sul dispositivo.',
      ),
      const SizedBox(height: 20),
      const OfflineCard(),
      const SizedBox(height: 14),
      const DataUpdatesCard(),
      if (kIsWeb) ...[
        const SizedBox(height: 14),
        IphoneInstallCard(address: Uri.base),
      ],
      const SizedBox(height: 14),
      _section(context, 'Dati e archiviazione', [
        ListTile(
          leading: const Icon(Icons.storage_outlined),
          title: const Text('Archivio osservazioni'),
          subtitle: const Text('Apri il diario salvato su questo dispositivo'),
          trailing: const Icon(Icons.chevron_right),
          onTap: onOpenDiary,
        ),
        ListTile(
          leading: const Icon(Icons.menu_book_outlined),
          title: const Text('Database ITALIC'),
          subtitle: const Text(
            'Apri la checklist nazionale disponibile offline',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: onOpenItalic,
        ),
      ]),
      const SizedBox(height: 14),
      _section(context, 'Rilievi sul campo', [
        const ListTile(
          leading: Icon(Icons.gps_fixed),
          title: Text('GPS'),
          subtitle: Text('Coordinate e accuratezza originali preservate'),
        ),
        ListTile(
          leading: const Icon(Icons.ios_share),
          title: const Text('Condividi ed esporta risultati'),
          subtitle: const Text('Riepilogo, foto, CSV, GeoJSON e Darwin Core'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  ObservationExportPage(observations: store.observations),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 24),
      Text(
        'Italicapp · versione 0.8.6',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );

  Widget _section(BuildContext context, String title, List<Widget> tiles) =>
      Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.forest,
                  ),
                ),
              ),
              ...tiles,
            ],
          ),
        ),
      );
}
