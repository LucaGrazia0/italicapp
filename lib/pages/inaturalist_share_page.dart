import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/link.dart';
import '../models/observation.dart';
import '../services/field_dataset.dart';
import '../services/observation_export.dart';
import 'observation_export_page.dart';

class INaturalistSharePage extends StatefulWidget {
  const INaturalistSharePage({
    super.key,
    required this.observations,
    this.sender,
  });
  final List<Observation> observations;
  final ObservationShareSender? sender;
  @override
  State<INaturalistSharePage> createState() => _INaturalistSharePageState();
}

class _INaturalistSharePageState extends State<INaturalistSharePage> {
  bool busy = false, includeGps = false;
  Future<void> share(Observation o, BuildContext buttonContext) async {
    final bytes = o.photoBytes;
    if (bytes == null || bytes.isEmpty || busy) return;
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => busy = true);
    try {
      final name = FieldDataset.photoFileName(o).split('/').last;
      final extension = name.split('.').last;
      // Images only: mixing a CSV/ZIP with the photo hides image receivers such
      // as iNaturalist from the native share sheet. Metadata is separately copied.
      await (widget.sender ?? SharePlus.instance.share)(
        ShareParams(
          title: 'Foto per iNaturalist',
          files: [
            XFile.fromData(
              bytes,
              mimeType: extension == 'jpg' || extension == 'jpeg'
                  ? 'image/jpeg'
                  : 'image/$extension',
            ),
          ],
          fileNameOverrides: [name],
          sharePositionOrigin: origin,
          downloadFallbackEnabled: true,
          mailToFallbackEnabled: false,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Condivisione non disponibile. Puoi salvare la foto e importarla da iNaturalist.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Condividi con iNaturalist')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Scegli una foto e poi iNaturalist nel menu di condivisione del telefono. Accedi e conferma la pubblicazione nell’app iNaturalist con il tuo account.',
        ),
        const SizedBox(height: 12),
        const Text(
          'Su iPhone usa la nuova app iNaturalist: Classic non accetta questo tipo di condivisione. Se iNaturalist non compare, cerca in “Altro” oppure importa la foto dalla galleria. Nel browser la foto viene scaricata.',
        ),
        const SizedBox(height: 12),
        const Text(
          'Condividiamo la foto originale. Controlla specie, data e posizione nell’app ricevente: i dati aggiunti nel diario potrebbero non essere importati. Le foto originali possono già contenere coordinate proprie. Per più specie ripeti l’invio di ciascuna foto.',
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Includi posizione nel riepilogo da copiare'),
          value: includeGps,
          onChanged: busy ? null : (v) => setState(() => includeGps = v),
        ),
        if (widget.observations.every((o) => o.photoBytes?.isNotEmpty != true))
          const Text(
            'Non ci sono foto da condividere. Per una specie annotata nella lista puoi creare manualmente un’osservazione su iNaturalist.',
          ),
        for (final o in widget.observations.where(
          (o) => o.photoBytes?.isNotEmpty == true,
        ))
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    o.taxonName ?? 'Non determinato',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${o.eventDate.day}/${o.eventDate.month}/${o.eventDate.year}',
                  ),
                  Builder(
                    builder: (ctx) => FilledButton.icon(
                      key: ValueKey('inat-photo-${o.id}'),
                      onPressed: busy ? null : () => share(o, ctx),
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Condividi foto → iNaturalist'),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: busy
                        ? null
                        : () async {
                            await Clipboard.setData(
                              ClipboardData(
                                text: observationSummary([
                                  Observation.fromMap({
                                    ...o.toMap(),
                                    'createdAt': o.eventDate.toIso8601String(),
                                  }),
                                ], includeGps: includeGps),
                              ),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Dati copiati. Puoi incollarli nelle note di iNaturalist.',
                                  ),
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copia specie, data e note'),
                  ),
                ],
              ),
            ),
          ),
        Link(
          uri: Uri.parse('https://www.inaturalist.org/observations/upload'),
          target: LinkTarget.blank,
          builder: (_, follow) => TextButton(
            onPressed: follow,
            child: const Text('Apri caricamento sul sito iNaturalist'),
          ),
        ),
      ],
    ),
  );
}
