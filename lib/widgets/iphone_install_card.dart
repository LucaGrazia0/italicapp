import 'package:flutter/material.dart';

class IphoneInstallCard extends StatelessWidget {
  const IphoneInstallCard({super.key, required this.address});
  final Uri address;

  @override
  Widget build(BuildContext context) {
    final published =
        address.scheme == 'https' &&
        !{'localhost', '127.0.0.1', '::1', '[::1]'}.contains(address.host);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Usa Italic Go su iPhone',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (!published) ...[
              const Text(
                'Questa anteprima non è il link per iPhone. Serve un indirizzo HTTPS della versione pubblicata.',
              ),
              const SizedBox(height: 8),
            ],
            const Text('1. Apri il link di Italic Go in Safari sull’iPhone.'),
            const Text(
              '2. Tocca Condividi → Aggiungi alla schermata Home. Se compare, attiva Apri come app web, poi tocca Aggiungi.',
            ),
            const Text(
              '3. Apri l’icona Italic Go dalla Home. In Impostazioni apri Dati e archiviazione, poi tocca Prepara uso offline e attendi «Copia offline pronta».',
            ),
            const SizedBox(height: 8),
            const Text(
              'Prima di uscire, prova a riaprire l’app dalla stessa icona in modalità aereo. Le osservazioni del Mac non vengono trasferite automaticamente: il diario resta sul dispositivo e nell’app in cui lo crei.',
            ),
          ],
        ),
      ),
    );
  }
}
