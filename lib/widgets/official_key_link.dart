import 'package:flutter/material.dart';
import '../data/identification_repository.dart';
import '../data/original_key_repository.dart';
import '../pages/original_key_page.dart';
import '../theme/app_theme.dart';

class OfficialKeyLink extends StatelessWidget {
  const OfficialKeyLink({super.key, required this.entry});
  final GenusKey entry;
  @override
  Widget build(BuildContext context) => FutureBuilder<OriginalKeyArchive>(
    future: OriginalKeyArchive.load(),
    builder: (context, snapshot) {
      final available = snapshot.data?.forEntry(entry) != null;
      return TextButton(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.all(18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => OriginalKeyPage(entry: entry),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFE9F0E7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                available
                    ? Icons.offline_pin_outlined
                    : Icons.account_tree_outlined,
                color: AppTheme.forest,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.name,
                    softWrap: true,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                      color: AppTheme.forest,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    snapshot.hasData
                        ? (available
                              ? 'Chiave ITALIC · offline'
                              : 'Copia offline non disponibile')
                        : 'Chiave originale ITALIC',
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppTheme.charcoal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Icon(
                Icons.chevron_right,
                size: 22,
                color: AppTheme.forest,
              ),
            ),
          ],
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
