import 'package:flutter/material.dart';
import 'package:url_launcher/link.dart';
import '../data/italic_reference_repository.dart';
import '../data/taxon_photo_repository.dart';

class TaxonPhotoCard extends StatefulWidget {
  const TaxonPhotoCard({super.key, required this.taxon, this.repository});
  final ItalicTaxon taxon;
  final Future<TaxonPhotoRepository>? repository;

  @override
  State<TaxonPhotoCard> createState() => _TaxonPhotoCardState();
}

class _TaxonPhotoCardState extends State<TaxonPhotoCard> {
  late Future<TaxonPhotoRepository> repository;
  @override
  void initState() {
    super.initState();
    repository = widget.repository ?? TaxonPhotoRepository.load();
  }

  @override
  void didUpdateWidget(TaxonPhotoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      repository = widget.repository ?? TaxonPhotoRepository.load();
    }
  }

  Uri get source => Uri.https('italic.units.it', '/dolichens/index.php', {
    'procedure': 'taxonpage',
    'num': '${widget.taxon.italicId}',
  });

  Widget sourceLink(Uri url) => Link(
    uri: url,
    target: LinkTarget.blank,
    builder: (context, follow) => TextButton.icon(
      key: const ValueKey('taxon-photo-source'),
      onPressed: follow,
      icon: const Icon(Icons.open_in_new, size: 18),
      label: const Text('Scheda DoLichens · online'),
    ),
  );

  void enlarge(TaxonPhoto photo) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(photo.scientificName)),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: InteractiveViewer(
                  maxScale: 5,
                  child: Center(child: image(photo)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 140),
                  child: SingleChildScrollView(
                    child: Text(
                      photo.credit,
                      style: const TextStyle(
                        fontFamilyFallback: ['NotoSansArmenian'],
                      ),
                    ),
                  ),
                ),
              ),
              sourceLink(photo.pageUrl),
            ],
          ),
        ),
      ),
    ),
  );

  Widget image(TaxonPhoto photo) => Image.asset(
    photo.asset,
    fit: BoxFit.contain,
    semanticLabel: 'Foto dimostrativa di ${photo.scientificName}',
    errorBuilder: (_, _, _) =>
        const Center(child: Text('Immagine offline non disponibile.')),
  );

  @override
  Widget build(BuildContext context) {
    if (widget.taxon.italicId == null) return const SizedBox.shrink();
    return FutureBuilder<TaxonPhotoRepository>(
      future: repository,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(height: 4);
        }
        final photo = snapshot.data?.forTaxon(widget.taxon);
        return Card(
          key: const ValueKey('taxon-photo-card'),
          margin: const EdgeInsets.symmetric(vertical: 12),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (photo != null) ...[
                  Semantics(
                    button: true,
                    label: 'Ingrandisci foto di ${photo.scientificName}',
                    child: InkWell(
                      key: const ValueKey('taxon-photo-enlarge'),
                      onTap: () => enlarge(photo),
                      child: SizedBox(
                        width: double.infinity,
                        height: 260,
                        child: image(photo),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Foto offline · tocca per ingrandire'),
                  const SizedBox(height: 6),
                  Text(
                    '${photo.credit}\nImmagine ridimensionata e compressa dall’originale.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamilyFallback: const ['NotoSansArmenian'],
                    ),
                  ),
                ] else
                  const Text('Foto offline non disponibile per questa scheda.'),
                sourceLink(photo?.pageUrl ?? source),
              ],
            ),
          ),
        );
      },
    );
  }
}
