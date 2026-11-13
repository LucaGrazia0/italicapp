# Italic Go 0.8.18+32

- Preparato collegamento iNaturalist con login OAuth/PKCE, sessione protetta e
  invio confermato di foto, nome, data, coordinate, incertezza e note DoLichens.
  Richiede ancora il Client ID pubblico di una registrazione dedicata: il login
  è disattivato nelle build prive di configurazione. Nessun invio reale testato.
- Ripresa controllata di invii parziali, UUID e checkpoint distinti per account,
  collegamento alla stessa osservazione per invii già completati.
- Foto di invio senza EXIF preesistenti; originali del diario conservati.
- Condivisione del telefono: oltre alla foto viene allegata la scheda testuale.
  L'importazione automatica di quel testo dipende dall'app ricevente.
- Diario con schede caricate durante lo scorrimento; copie dei metadati senza
  duplicare immagini; elaborazione Excel/ZIP separata su Android e iPhone.

Dettagli di attivazione e limiti: `reports/inaturalist-activation-0.8.18.md`.
