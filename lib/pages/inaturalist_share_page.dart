import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/link.dart';
import '../models/observation.dart';
import '../services/field_dataset.dart';
import '../services/dataset_export_jobs.dart';
import '../services/diary_filter.dart';
import 'observation_export_page.dart';
import '../services/inaturalist_auth.dart';
import '../services/inaturalist_upload.dart';
import '../widgets/inaturalist_connection.dart';

class INaturalistSharePage extends StatefulWidget {
  const INaturalistSharePage({
    super.key,
    required this.observations,
    this.sender,
    this.dataset,
    this.recordedBy = '',
    this.identifiedBy = '',
    this.auth,
    this.uploader,
  });
  final List<Observation> observations;
  final ObservationShareSender? sender;
  final FieldDataset? dataset;
  final String recordedBy, identifiedBy;
  final INaturalistAuth? auth;
  final INaturalistUploader? uploader;
  @override
  State<INaturalistSharePage> createState() => _INaturalistSharePageState();
}

class _INaturalistSharePageState extends State<INaturalistSharePage> {
  bool busy = false, includeGps = false;
  ItalianRegions? regions;
  INaturalistAuth get auth => widget.auth ?? INaturalistAuth.shared;
  late final INaturalistUploader uploader =
      widget.uploader ?? INaturalistUploader(auth: auth);
  final sent = <String, Uri>{};
  INaturalistPrivacy privacy = INaturalistPrivacy.private;
  @override
  void initState() {
    super.initState();
    regions = widget.dataset?.regions;
    auth.addListener(refresh);
    ItalianRegions.load()
        .then((value) {
          if (mounted) setState(() => regions = value);
        })
        .catchError((Object _) {});
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    auth.removeListener(refresh);
    super.dispose();
  }

  Future<void> publish(Observation observation) async {
    final payload = inaturalistObservationPayload(
      observation,
      data,
      includeGps: includeGps,
      privacy: privacy,
      recordedBy: widget.recordedBy,
      identifiedBy: widget.identifiedBy,
    );
    final point = includeGps && data.effective(observation).hasPosition;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invia a iNaturalist'),
        content: SingleChildScrollView(
          child: Text(
            [
              'Account: ${auth.session?.login}',
              observation.taxonName ?? 'Specie da determinare',
              'Data: ${data.effective(observation).eventDate}',
              if (point)
                'Coordinate: ${payload['latitude']}, ${payload['longitude']}',
              if (payload['positional_accuracy'] != null)
                'Incertezza: ${payload['positional_accuracy']} m',
              if (!point) 'Senza coordinate',
              'Visibilità: ${privacyLabel(privacy)}',
              'Foto e scheda DoLichens incluse. Il nome è una determinazione da verificare su iNaturalist.',
            ].join('\n\n'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Conferma invio'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      final result = await uploader.send(observation, payload);
      if (!mounted) return;
      setState(() => sent[observation.id] = result.url);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.alreadySent
                ? 'Già inviata: apri l’osservazione su iNaturalist.'
                : 'Osservazione e foto inviate a iNaturalist.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is INaturalistFailure
                  ? e.message
                  : 'Invio non confermato. Riprova: il controllo evita di creare duplicati.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
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
      final file = await buildDatasetExport(
        DatasetExportJob(
          data,
          forINaturalist: true,
          includeGps: includeGps,
          recordedBy: widget.recordedBy,
          identifiedBy: widget.identifiedBy,
        ),
      );
      if (!mounted) return;
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
      final imageOnly = defaultTargetPlatform == TargetPlatform.iOS;
      // iNaturalist's iOS extension activates for images, not mixed image/text
      // items. share_plus creates a separate activity item for non-empty text.
      // Keep the iPhone payload image-only; the complete record remains in the
      // explicit copy action and package export. Android can keep EXTRA_TEXT.
      await (widget.sender ?? SharePlus.instance.share)(
        ShareParams(
          // Also applies to the iPhone web app when Web Share is supported.
          title: imageOnly ? null : o.taxonName ?? 'Foto per iNaturalist',
          text: imageOnly ? null : notesFor(o),
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
        INaturalistConnection(auth: auth),
        if (auth.configured && auth.session != null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Invia direttamente foto, nome e posizione. Controlla i dati prima di confermare.',
            ),
          ),
        const Text(
          'Puoi anche scegliere iNaturalist dal menu di condivisione del telefono.',
        ),
        const SizedBox(height: 12),
        const Text(
          'Su iPhone usa la nuova app iNaturalist; Classic non riceve foto condivise. Nel browser si scarica il file.',
        ),
        const SizedBox(height: 12),
        const Text(
          'Su iPhone viene condivisa solo la foto, così iNaturalist può comparire nel menu. La scheda completa si copia con il pulsante dedicato. Le foto originali possono contenere proprie coordinate. L’invio diretto usa invece i dati del diario.',
        ),
        SwitchListTile(
          key: const ValueKey('inat-include-location'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Includi posizione e quota'),
          value: includeGps,
          onChanged: busy ? null : (v) => setState(() => includeGps = v),
        ),
        if (auth.session != null)
          DropdownButtonFormField<INaturalistPrivacy>(
            initialValue: privacy,
            decoration: const InputDecoration(
              labelText: 'Posizione su iNaturalist',
            ),
            items: [
              for (final value in INaturalistPrivacy.values)
                DropdownMenuItem(
                  value: value,
                  child: Text(privacyLabel(value)),
                ),
            ],
            onChanged: busy
                ? null
                : (v) {
                    if (v != null) setState(() => privacy = v);
                  },
          ),
        const Text(
          'Con il menu del telefono puoi copiare la scheda DoLichens e incollarla nelle note di iNaturalist.',
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
          'Il pacchetto ZIP contiene tabelle DoLichens, CSV per il sito iNaturalist e foto da associare dopo l’importazione.',
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
                  if (auth.session != null)
                    FilledButton.icon(
                      key: ValueKey('inat-publish-${o.id}'),
                      onPressed: busy ? null : () => publish(o),
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: Text(
                        sent.containsKey(o.id)
                            ? 'Verifica invio'
                            : 'Invia foto e dati',
                      ),
                    ),
                  if (sent[o.id] != null)
                    Link(
                      uri: sent[o.id]!,
                      target: LinkTarget.blank,
                      builder: (_, follow) => TextButton(
                        onPressed: follow,
                        child: const Text('Apri osservazione su iNaturalist'),
                      ),
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

String privacyLabel(INaturalistPrivacy value) => switch (value) {
  INaturalistPrivacy.private => 'Privata',
  INaturalistPrivacy.obscured => 'Oscurata',
  INaturalistPrivacy.open => 'Pubblica',
};
