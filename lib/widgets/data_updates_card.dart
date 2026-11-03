import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/scientific_data.dart';
import '../services/data_updates.dart';

class DataUpdatesCard extends StatefulWidget {
  const DataUpdatesCard({super.key, this.updates});
  final DataUpdates? updates;
  @override
  State<DataUpdatesCard> createState() => _DataUpdatesCardState();
}

class _DataUpdatesCardState extends State<DataUpdatesCard> {
  late final updates = widget.updates ?? DataUpdates();
  DataRelease? release;
  String? message;
  bool busy = false;
  double? progress;
  @override
  void dispose() {
    if (widget.updates == null) updates.close();
    super.dispose();
  }

  Future<void> run(bool install) async {
    setState(() {
      busy = true;
      message = null;
      progress = null;
    });
    try {
      if (install) {
        await updates.install(
          release!,
          progress: (p) {
            if (mounted) setState(() => progress = p);
          },
        );
        if (mounted) {
          setState(() {
            release = null;
            message =
                'Dati aggiornati e disponibili offline. Diario, revisioni e percorsi salvati sono conservati.';
          });
        }
      } else {
        final value = await updates.check();
        if (mounted) {
          setState(() {
            release = value;
            message = value == null
                ? 'Non sono ancora pubblicati nuovi pacchetti per l’app. La copia inclusa resta disponibile offline.'
                : value.revision <= ScientificData.currentRevision
                ? 'Hai già questa edizione dei dati.'
                : 'Nuovi dati disponibili: ${value.version} · ${(value.bytes / 1024 / 1024).toStringAsFixed(1)} MB.';
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Aggiornamento non completato. I dati precedenti restano attivi. Controlla la connessione e riprova.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Aggiornamenti ITALIC',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(ScientificData.currentVersion),
          const Text(
            'Controlla i pacchetti verificati per checklist, matrice, dizionario e chiavi. Il controllo usa internet; i dati installati funzionano anche offline. Le modifiche sul sito ITALIC diventano disponibili nell’app dopo la preparazione di un nuovo pacchetto.',
          ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(message!),
            ),
          if (busy) LinearProgressIndicator(value: progress),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('check-data-updates'),
                onPressed: busy ? null : () => run(false),
                icon: const Icon(Icons.system_update_alt),
                label: const Text('Controlla aggiornamenti'),
              ),
              if (release != null &&
                  release!.revision > ScientificData.currentRevision &&
                  release!.minimumAppBuild <= DataUpdates.appBuild)
                FilledButton(
                  onPressed: busy ? null : () => run(true),
                  child: const Text('Scarica dati offline'),
                ),
              if (release?.apkUrl != null &&
                  release!.appBuild > DataUpdates.appBuild)
                TextButton(
                  onPressed: busy
                      ? null
                      : () => launchUrl(
                          release!.apkUrl!,
                          mode: LaunchMode.externalApplication,
                        ),
                  child: const Text('Scarica nuovo APK'),
                ),
            ],
          ),
          if (release != null &&
              release!.minimumAppBuild > DataUpdates.appBuild)
            const Text(
              'Prima di installare questi dati occorre aggiornare l’app.',
            ),
        ],
      ),
    ),
  );
}
