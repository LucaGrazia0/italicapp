import '../brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../theme/app_theme.dart';
import '../widgets/offline_card.dart';
import '../widgets/data_updates_card.dart';
import '../widgets/iphone_install_card.dart';
import '../app_store.dart';
import 'share_results_page.dart';
import 'identification_page.dart';

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
        'ITALIC GO',
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
      const SizedBox(height: 24),
      FilledButton.icon(
        key: const ValueKey('settings-sharing'),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(100),
          padding: const EdgeInsets.all(24),
          textStyle: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ShareResultsPage(store: store)),
        ),
        icon: const Icon(Icons.ios_share, size: 30),
        label: const Text('Condividi risultati'),
      ),
      const SizedBox(height: 16),
      const DataUpdatesCard(compact: true),
      const SizedBox(height: 20),
      _section(context, 'Dati e archiviazione', [
        ListTile(
          key: const ValueKey('settings-identification-tools'),
          leading: const Icon(Icons.tune),
          title: const Text('Strumenti e dati'),
          subtitle: const Text('Matrici, revisioni e percorsi alternativi'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const DeterminationStartPage(toolsOnly: true),
            ),
          ),
        ),
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
        const Padding(padding: EdgeInsets.all(8), child: OfflineCard()),
        if (kIsWeb)
          Padding(
            padding: const EdgeInsets.all(8),
            child: IphoneInstallCard(address: Uri.base),
          ),
      ]),
      const SizedBox(height: 24),
      Text(
        '${AppBrand.name} · versione ${AppBrand.version}',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );

  Widget _section(BuildContext context, String title, List<Widget> tiles) =>
      Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          key: const PageStorageKey('settings-data-storage'),
          leading: const Icon(Icons.storage_outlined),
          title: Text(title),
          children: tiles,
        ),
      );
}
