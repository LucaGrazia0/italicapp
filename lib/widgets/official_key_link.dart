import 'package:flutter/material.dart';
import 'package:url_launcher/link.dart';
import '../data/identification_repository.dart';

class OfficialKeyLink extends StatelessWidget {
  const OfficialKeyLink({super.key, required this.entry});
  final GenusKey entry;
  @override
  Widget build(BuildContext context) => Link(
    uri: entry.url,
    target: LinkTarget.blank,
    builder: (context, followLink) => TextButton.icon(
      onPressed: followLink,
      icon: const Icon(Icons.open_in_new),
      label: Text('Chiave ITALIC · ${entry.name}'),
    ),
  );
}

class GenusKeyLinks extends StatelessWidget {
  const GenusKeyLinks({super.key, required this.genus});
  final String genus;
  @override
  Widget build(BuildContext context) => FutureBuilder<List<GenusKey>>(
    future: GenusKeyCatalog.load(),
    builder: (context, snapshot) {
      final entries =
          snapshot.data?.where((entry) => entry.genus == genus).toList() ?? [];
      if (snapshot.hasError) {
        return const Text('Collegamenti alle chiavi non disponibili.');
      }
      if (entries.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          const Text('Chiavi originali ITALIC · richiedono una connessione'),
          for (final entry in entries) OfficialKeyLink(entry: entry),
        ],
      );
    },
  );
}
