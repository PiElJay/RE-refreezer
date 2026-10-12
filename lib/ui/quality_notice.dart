import 'package:flutter/material.dart';

import '../settings.dart';

Future<bool> confirmOnlineQuality(BuildContext context, AudioQuality quality) async {
  if (quality != AudioQuality.MP3_320 && quality != AudioQuality.FLAC) return true;
  final label = quality == AudioQuality.FLAC ? 'FLAC' : 'MP3 320 kbps';
  return await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('$label richiede un abbonamento'),
      content: const Text(
        'Deezer Free consente fino a MP3 128 kbps. Per questa qualità serve '
        'un abbonamento Deezer che la includa, come Premium. '
        'Se il tuo account non è abilitato, Deezer può rifiutare la riproduzione '
        'o il download. I file già presenti sul telefono mantengono il loro formato.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Annulla')),
        TextButton(onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Seleziona comunque')),
      ],
    ),
  ) ?? false;
}
