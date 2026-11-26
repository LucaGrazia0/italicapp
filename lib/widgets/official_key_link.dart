import 'package:flutter/material.dart';
import '../data/identification_repository.dart';
import '../data/original_key_repository.dart';
import '../pages/original_key_page.dart';

class OfficialKeyLink extends StatelessWidget {
  const OfficialKeyLink({super.key, required this.entry});
  final GenusKey entry;
  @override
  Widget build(BuildContext context) => FutureBuilder<OriginalKeyArchive>(
    future: OriginalKeyArchive.load(),
    builder: (context, snapshot) {
      final available = snapshot.data?.forEntry(entry) != null;
      return TextButton.icon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => OriginalKeyPage(entry: entry),
          ),
        ),
        icon: Icon(
          available ? Icons.offline_pin_outlined : Icons.account_tree_outlined,
        ),
        label: Text(
          'Chiave ITALIC · ${entry.name}'
          '${snapshot.hasData ? (available ? " · offline" : " · copia non disponibile") : ""}',
        ),
      );
    },
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
          const Text('Chiavi originali ITALIC'),
          for (final entry in entries) OfficialKeyLink(entry: entry),
        ],
      );
    },
  );
}
