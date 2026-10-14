import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

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
      _section(context, 'Dati e archiviazione', [
        const ListTile(
          leading: Icon(Icons.storage_outlined),
          title: Text('Archivio osservazioni'),
          subtitle: Text('IndexedDB locale • v1'),
        ),
        const ListTile(
          leading: Icon(Icons.menu_book_outlined),
          title: Text('Database ITALIC'),
          subtitle: Text('Snapshot locale della checklist nazionale'),
        ),
      ]),
      const SizedBox(height: 14),
      _section(context, 'Rilievi sul campo', [
        const ListTile(
          leading: Icon(Icons.gps_fixed),
          title: Text('GPS'),
          subtitle: Text('Coordinate e accuratezza originali preservate'),
        ),
        const ListTile(
          leading: Icon(Icons.ios_share),
          title: Text('Esportazione'),
          subtitle: Text('CSV / GeoJSON / Darwin Core • funzionalità futura'),
        ),
      ]),
      const SizedBox(height: 24),
      Text(
        'italicapp • Natural Theme v0.8.8',
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
