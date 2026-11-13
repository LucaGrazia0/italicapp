import 'package:flutter/material.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import '../services/inaturalist_auth.dart';

class INaturalistConnection extends StatefulWidget {
  const INaturalistConnection({super.key, this.auth});
  final INaturalistAuth? auth;
  @override
  State<INaturalistConnection> createState() => _INaturalistConnectionState();
}

class _INaturalistConnectionState extends State<INaturalistConnection> {
  INaturalistAuth get auth => widget.auth ?? INaturalistAuth.shared;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    auth.addListener(refresh);
    auth.load().catchError((Object _) {
      if (mounted) {
        setState(() => error = 'Account non letto. Puoi ricollegarlo.');
      }
    });
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    auth.removeListener(refresh);
    super.dispose();
  }

  Future<void> act() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (auth.session == null) {
        await auth.connect();
      } else {
        await auth.disconnect();
      }
    } on FlutterAppAuthUserCancelledException {
      // Closing the official login is a cancellation, not an error.
    } on INaturalistFailure catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Collegamento non completato. Riprova con connessione internet.';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('iNaturalist', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            auth.session == null
                ? auth.configured
                      ? 'Accedi con il tuo account per inviare foto, specie e posizione.'
                      : 'Invio completo in preparazione: manca la registrazione di Italic Go su iNaturalist.'
                : 'Collegato come ${auth.session!.login}',
          ),
          if (auth.configured && auth.supported) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const ValueKey('inat-connect'),
              onPressed: busy ? null : act,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(auth.session == null ? Icons.link : Icons.link_off),
              label: Text(
                auth.session == null
                    ? 'Collega iNaturalist'
                    : 'Scollega account',
              ),
            ),
          ] else if (auth.configured)
            const Text('Il login è disponibile nelle app Android e iPhone.'),
          if (error != null) Text(error!),
        ],
      ),
    ),
  );
}
