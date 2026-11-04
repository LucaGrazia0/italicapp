import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/link.dart';
import '../models/observation.dart';
import '../services/field_dataset.dart';
import '../services/diary_filter.dart';
import 'observation_export_page.dart';

class INaturalistSharePage extends StatefulWidget {
  const INaturalistSharePage({
    super.key,
    required this.observations,
    this.sender,
    this.dataset,
    this.recordedBy = '',
    this.identifiedBy = '',
  });
  final List<Observation> observations;
  final ObservationShareSender? sender;
  final FieldDataset? dataset;
  final String recordedBy, identifiedBy;
  @override
  State<INaturalistSharePage> createState() => _INaturalistSharePageState();
}

class _INaturalistSharePageState extends State<INaturalistSharePage> {
  bool busy = false, includeGps = false;
  ItalianRegions? regions;
  @override
  void initState() {
    super.initState();
    regions = widget.dataset?.regions;
    ItalianRegions.load()
        .then((value) {
          if (mounted) setState(() => regions = value);
        })
        .catchError((Object _) {});
  }

  FieldDataset get data => FieldDataset(
    observations: widget.dataset?.observations ?? widget.observations,
    plots: widget.dataset?.plots ?? [],
    regions: regions,
  );
  String notesFor(Observation o) {
    final record = data
        .records(
          includeGps: includeGps,
          recordedBy: widget.recordedBy,
          identifiedBy: widget.identifiedBy,
        )
        .where((r) => r['occurrenceID'] == 'urn:italicgo:occurrence:${o.id}')
        .firstOrNull;
    return record == null ? '' : data.completeNotes(record);
  }

  Future<void> package(BuildContext ctx) async {
    final box = ctx.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => busy = true);
    try {
      final file = data.inaturalistPackage(
        includeGps: includeGps,
        recordedBy: widget.recordedBy,
        identifiedBy: widget.identifiedBy,
      );
      await (widget.sender ?? SharePlus.instance.share)(
        ShareParams(
          title: 'Dati DoLichens / iNaturalist',
          files: [XFile.fromData(file.bytes, mimeType: file.mimeType)],
          fileNameOverrides: [file.name],
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
              'Pacchetto non creato. Riprova con un numero minore di foto.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

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
          title: const Text(
            'Includi posizione e quota nei dati da condividere',
          ),
          value: includeGps,
          onChanged: busy ? null : (v) => setState(() => includeGps = v),
        ),
        const Text(
          'Per conservare tutti i dati disponibili usa la scheda DoLichens/Darwin Core: copiala nelle note di iNaturalist dopo aver inviato la foto. L’app ricevente non importa automaticamente una tabella Darwin Core. I campi senza equivalente nativo restano nelle note.',
        ),
        const SizedBox(height: 12),
        Builder(
          builder: (ctx) => OutlinedButton.icon(
            key: const ValueKey('inat-complete-package'),
            onPressed: busy ? null : () => package(ctx),
            icon: const Icon(Icons.folder_zip_outlined),
            label: const Text('Esporta pacchetto completo'),
          ),
        ),
        const Text(
          'Il pacchetto contiene Excel/CSV DoLichens, CSV adattato al caricatore web di iNaturalist, schede e foto. Estrai il ZIP prima dell’importazione; le foto vanno associate alle osservazioni e i nomi verificati. I dati mancanti restano vuoti.',
        ),
        const SizedBox(height: 16),
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
                              ClipboardData(text: notesFor(o)),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Scheda DoLichens copiata. Incollala nelle note di iNaturalist.',
                                  ),
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copia scheda DoLichens completa'),
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
