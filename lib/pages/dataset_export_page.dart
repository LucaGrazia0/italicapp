import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../app_store.dart';
import '../services/field_dataset.dart';
import '../services/dataset_export_jobs.dart';
import 'inaturalist_share_page.dart';
import 'observation_export_page.dart';

class DatasetExportPage extends StatefulWidget {
  const DatasetExportPage({
    super.key,
    required this.store,
    this.plotId,
    this.sender,
  });
  final AppStore store;
  final String? plotId;
  final ObservationShareSender? sender;
  @override
  State<DatasetExportPage> createState() => _DatasetExportPageState();
}

class _DatasetExportPageState extends State<DatasetExportPage> {
  late final data = FieldDataset.fromStore(widget.store, plotId: widget.plotId);
  final observer = TextEditingController(),
      identifier = TextEditingController();
  bool excel = true, gps = false, photos = false, busy = false;
  String? error;
  @override
  void dispose() {
    observer.dispose();
    identifier.dispose();
    super.dispose();
  }

  Future<void> share(BuildContext ctx) async {
    if (busy) return;
    final box = ctx.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final file = await buildDatasetExport(
        DatasetExportJob(
          data,
          excel: excel,
          includeGps: gps,
          includePhotos: photos,
          recordedBy: observer.text,
          identifiedBy: identifier.text,
        ),
      );
      if (!mounted) return;
      await (widget.sender ?? SharePlus.instance.share)(
        ShareParams(
          title: 'Diario Italic Go',
          files: [XFile.fromData(file.bytes, mimeType: file.mimeType)],
          fileNameOverrides: [file.name],
          sharePositionOrigin: origin,
          downloadFallbackEnabled: true,
          mailToFallbackEnabled: false,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Esportazione non completata. Riprova, eventualmente escludendo le foto.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.plotId == null ? 'Esporta diario' : 'Condividi plot'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          '${data.occurrences().length - 1} occorrenze · ${data.plots.length} plot · ${data.photos.length} foto',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          widget.plotId == null && widget.store.diaryFilter.active
              ? 'Esporti soltanto i dati che rispettano i filtri del diario.'
              : 'Esporti i dati selezionati. Nessun invio automatico.',
        ),
        const SizedBox(height: 16),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Excel .xlsx')),
            ButtonSegment(value: false, label: Text('CSV')),
          ],
          selected: {excel},
          onSelectionChanged: busy
              ? null
              : (v) => setState(() => excel = v.single),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: observer,
          decoration: const InputDecoration(
            labelText: 'Osservatore · recordedBy (facoltativo)',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: identifier,
          decoration: const InputDecoration(
            labelText: 'Determinatore · identifiedBy (facoltativo)',
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Includi posizione e quota s.l.m.'),
          subtitle: const Text(
            'Comprende la regione dedotta dalle coordinate. Inizialmente esclusi.',
          ),
          value: gps,
          onChanged: busy ? null : (v) => setState(() => gps = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Allega le foto in un file ZIP'),
          subtitle: const Text(
            'Le foto originali possono contenere metadati propri di posizione. Il ZIP include tabella e foto con nomi collegati.',
          ),
          value: photos,
          onChanged: busy || data.photos.isEmpty
              ? null
              : (v) => setState(() => photos = v),
        ),
        const Text(
          'Campi allineati a DoLichens / Darwin Core. Excel contiene anche plot, lista specie e spiegazione dei campi. L’abbondanza non assume un metodo di misura. Le determinazioni sono personali, non convalidate.',
        ),
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 16),
        Builder(
          builder: (ctx) => FilledButton.icon(
            key: const ValueKey('share-dataset'),
            onPressed: busy || (data.observations.isEmpty && data.plots.isEmpty)
                ? null
                : () => share(ctx),
            icon: const Icon(Icons.ios_share),
            label: Text(busy ? 'Preparazione…' : 'Esporta / condividi'),
          ),
        ),
        const Divider(height: 32),
        OutlinedButton.icon(
          key: const ValueKey('dataset-inaturalist'),
          onPressed: busy
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => INaturalistSharePage(
                      observations: data.observations
                          .map(data.effective)
                          .toList(),
                      sender: widget.sender,
                      dataset: data,
                      recordedBy: observer.text,
                      identifiedBy: identifier.text,
                    ),
                  ),
                ),
          icon: const Icon(Icons.nature_people_outlined),
          label: const Text('Condividi con iNaturalist'),
        ),
      ],
    ),
  );
}
