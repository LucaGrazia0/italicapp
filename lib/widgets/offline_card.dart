import 'dart:async';
import 'package:flutter/material.dart';
import '../services/offline_pack.dart';

class OfflineCard extends StatefulWidget {
  const OfflineCard({super.key});
  @override
  State<OfflineCard> createState() => _OfflineCardState();
}

class _OfflineCardState extends State<OfflineCard> {
  bool ready = false, working = false;
  String? error;
  int? bytes;
  double? progress;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    if (offlinePackSupported) _run(false);
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _run(bool prepare) async {
    if (working) return;
    setState(() {
      working = true;
      error = null;
    });
    if (prepare) {
      timer = Timer.periodic(const Duration(milliseconds: 400), (_) {
        if (mounted) setState(() => progress = offlinePackProgress());
      });
    }
    try {
      final result = await (prepare
          ? prepareOfflinePack()
          : offlinePackStatus());
      if (mounted) {
        setState(() {
          ready = result['ready'] == true;
          error = result['error'] as String?;
          bytes = result['bytes'] as int?;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Verifica offline non disponibile. Ricarica l’app e riprova.',
        );
      }
    } finally {
      timer?.cancel();
      if (mounted) {
        setState(() {
          working = false;
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
            'Uso senza connessione',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            !offlinePackSupported
                ? 'Le chiavi e la matrice sono incluse nell’app.'
                : ready
                ? 'Copia offline pronta su questo browser.'
                : 'Prepara una copia completa delle chiavi, della matrice e del dizionario prima di uscire sul campo.',
          ),
          const Text(
            'Le pagine e le immagini sul sito ITALIC, il download di nuove descrizioni e la creazione online di nuove chiavi richiedono internet. Le osservazioni e le revisioni restano su questo dispositivo: la copia offline non è un backup.',
          ),
          if (offlinePackSupported) ...[
            const Text(
              'Riapri lo stesso indirizzo nello stesso browser. La cancellazione dei dati del sito o lo spazio insufficiente possono rimuovere la copia: ricontrolla prima di partire.',
            ),
            if (bytes != null)
              Text(
                'Dati dell’app: ${(bytes! / 1024 / 1024).toStringAsFixed(1)} MB',
              ),
            if (working) LinearProgressIndicator(value: progress),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Wrap(
              spacing: 12,
              children: [
                FilledButton.icon(
                  key: const ValueKey('prepare-offline'),
                  onPressed: working ? null : () => _run(true),
                  icon: const Icon(Icons.download_for_offline_outlined),
                  label: Text(
                    ready ? 'Verifica copia offline' : 'Prepara uso offline',
                  ),
                ),
                TextButton(
                  onPressed: working ? null : () => _run(false),
                  child: const Text('Controlla stato'),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}
