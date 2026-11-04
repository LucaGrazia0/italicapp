import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../models/observation.dart';
import '../services/observation_export.dart';
import 'inaturalist_share_page.dart';

typedef ObservationShareSender =
    Future<ShareResult> Function(ShareParams params);

class ObservationExportPage extends StatefulWidget {
  const ObservationExportPage({
    super.key,
    required this.observations,
    this.sender,
  });
  final List<Observation> observations;
  final ObservationShareSender? sender;
  @override
  State<ObservationExportPage> createState() => _ObservationExportPageState();
}

class _ObservationExportPageState extends State<ObservationExportPage> {
  late final observations = widget.observations
      .map((o) => Observation.fromMap(o.toMap()))
      .toList();
  late final selectedIds = observations.map((o) => o.id).toSet();
  ObservationExportFormat format = ObservationExportFormat.summary;
  bool includeGps = false, includePhoto = false, working = false;
  List<Observation> get selected =>
      observations.where((o) => selectedIds.contains(o.id)).toList();

  Future<void> share(BuildContext buttonContext) async {
    if (working || selectedIds.isEmpty) return;
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => working = true);
    try {
      final data = exportObservations(
        selected,
        format,
        includeGps: includeGps,
        includePhoto: includePhoto,
      );
      final result = await (widget.sender ?? SharePlus.instance.share)(
        ShareParams(
          title: 'Risultati Italic Go',
          subject: 'Osservazioni Italic Go',
          text: data.text,
          files: data.files.isEmpty
              ? null
              : [
                  for (final file in data.files)
                    XFile.fromData(file.bytes, mimeType: file.mimeType),
                ],
          fileNameOverrides: data.files.isEmpty
              ? null
              : [for (final file in data.files) file.name],
          sharePositionOrigin: origin,
          downloadFallbackEnabled: true,
          mailToFallbackEnabled: false,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.status == ShareResultStatus.dismissed
                  ? 'Condivisione annullata.'
                  : 'Richiesta di condivisione completata. Nel browser il file può essere scaricato.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Condivisione non disponibile. Puoi copiare il riepilogo oppure scegliere CSV per scaricare un file dal browser.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chosen = selected;
    final hasSinglePhoto =
        chosen.length == 1 && chosen.single.photoBytes != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Condividi risultati')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (observations.isEmpty)
                const Text(
                  'Il diario è vuoto. Salva un’osservazione per condividere i risultati.',
                )
              else ...[
                Text(
                  '${chosen.length} osservazioni selezionate',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (observations.length > 1)
                  ExpansionTile(
                    title: const Text('Scegli osservazioni'),
                    children: [
                      Wrap(
                        spacing: 12,
                        children: [
                          TextButton(
                            onPressed: working
                                ? null
                                : () => setState(() {
                                    selectedIds.addAll(
                                      observations.map((o) => o.id),
                                    );
                                    includePhoto = false;
                                  }),
                            child: const Text('Tutte'),
                          ),
                          TextButton(
                            onPressed: working
                                ? null
                                : () => setState(() {
                                    selectedIds.clear();
                                    includePhoto = false;
                                  }),
                            child: const Text('Nessuna'),
                          ),
                        ],
                      ),
                      for (final o in observations)
                        CheckboxListTile(
                          key: ValueKey('export-select-${o.id}'),
                          title: Text(o.taxonName ?? 'Non determinato'),
                          subtitle: Text(
                            '${o.createdAt.day}/${o.createdAt.month}/${o.createdAt.year} · ${o.id}',
                          ),
                          value: selectedIds.contains(o.id),
                          onChanged: working
                              ? null
                              : (value) => setState(() {
                                  if (value == true) {
                                    selectedIds.add(o.id);
                                  } else {
                                    selectedIds.remove(o.id);
                                  }
                                  includePhoto = false;
                                }),
                        ),
                    ],
                  ),
                const SizedBox(height: 16),
                DropdownButtonFormField<ObservationExportFormat>(
                  key: const ValueKey('export-format'),
                  initialValue: format,
                  decoration: const InputDecoration(labelText: 'Formato'),
                  isExpanded: true,
                  items: [
                    for (final f in ObservationExportFormat.values)
                      DropdownMenuItem(value: f, child: Text(f.label)),
                  ],
                  onChanged: working
                      ? null
                      : (value) {
                          if (value != null) setState(() => format = value);
                        },
                ),
                SwitchListTile(
                  key: const ValueKey('export-gps'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Includi posizione e quota'),
                  subtitle: const Text(
                    'Comprende posizione GPS o scelta sulla mappa e, se disponibili, accuratezza e quota. Le coordinate sono escluse inizialmente.',
                  ),
                  value: includeGps,
                  onChanged: working
                      ? null
                      : (value) => setState(() => includeGps = value),
                ),
                if (format == ObservationExportFormat.geojson && !includeGps)
                  const Text(
                    'Per vedere i punti su una mappa, includi la posizione.',
                  ),
                if (hasSinglePhoto)
                  SwitchListTile(
                    key: const ValueKey('export-photo'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Allega la foto'),
                    subtitle: const Text(
                      'La foto originale può contenere propri metadati di posizione.',
                    ),
                    value: includePhoto,
                    onChanged: working
                        ? null
                        : (value) => setState(() => includePhoto = value),
                  )
                else if (chosen.length > 1)
                  const Text(
                    'Per allegare una foto, seleziona una sola osservazione.',
                  ),
                const SizedBox(height: 12),
                const Text(
                  'Sceglierai tu l’app o la destinazione nel menu di condivisione. Il diario originale resta sul dispositivo.',
                ),
                const SizedBox(height: 16),
                Builder(
                  builder: (buttonContext) => FilledButton.icon(
                    key: const ValueKey('share-observations'),
                    onPressed: working || chosen.isEmpty
                        ? null
                        : () => share(buttonContext),
                    icon: const Icon(Icons.ios_share),
                    label: Text(working ? 'Preparazione…' : 'Condividi'),
                  ),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('share-inaturalist'),
                  onPressed: working || chosen.isEmpty
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => INaturalistSharePage(
                              observations: chosen,
                              sender: widget.sender,
                            ),
                          ),
                        ),
                  icon: const Icon(Icons.nature_people_outlined),
                  label: const Text('Condividi con iNaturalist'),
                ),
                TextButton.icon(
                  key: const ValueKey('copy-observations-summary'),
                  onPressed: working || chosen.isEmpty
                      ? null
                      : () async {
                          await Clipboard.setData(
                            ClipboardData(
                              text: observationSummary(
                                chosen,
                                includeGps: includeGps,
                              ),
                            ),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Riepilogo copiato.')),
                          );
                        },
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copia riepilogo'),
                ),
                if (chosen.isNotEmpty)
                  ExpansionTile(
                    title: const Text('Anteprima del riepilogo'),
                    initiallyExpanded: chosen.length == 1,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: SelectableText(
                          observationSummary(chosen, includeGps: includeGps),
                        ),
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
