import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../api/deezer.dart';
import '../api/definitions.dart';
import 'network_monitor.dart';

class LyricsRepository {
  static Future<Lyrics> load(String trackId) async {
    if (trackId.startsWith('local:')) throw const FormatException('Local file has no Deezer track ID');
    final directory = Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'lyrics'),
    );
    final file = File(
      p.join(directory.path, '${Uri.encodeComponent(trackId)}.json'),
    );
    try {
      if (await file.exists()) {
        final cached = LyricsFull.fromJson(
          jsonDecode(await file.readAsString()),
        );
        if (cached.errorMessage == null && cached.isLoaded()) return cached;
      }
    } catch (_) {
      /* A broken cache must not prevent a network lookup. */
    }
    if (NetworkMonitor.instance.offline)
      throw const SocketException('Lyrics not cached');
    final lyrics = await deezerAPI
        .lyrics(trackId)
        .timeout(const Duration(seconds: 12));
    if (lyrics.errorMessage == null && lyrics.isLoaded()) {
      final normalized = LyricsFull(
        id: lyrics.id,
        writers: lyrics.writers,
        syncedLyrics: lyrics.syncedLyrics,
        unsyncedLyrics: lyrics.unsyncedLyrics,
        isExplicit: lyrics.isExplicit,
        copyright: lyrics.copyright,
      );
      try {
        await directory.create(recursive: true);
        await file.writeAsString(jsonEncode(normalized.toJson()));
      } catch (_) {
        // Storage exhaustion must not hide lyrics already fetched.
      }
    }
    return lyrics;
  }
}
