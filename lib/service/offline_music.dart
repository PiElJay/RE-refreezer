import '../api/definitions.dart';
import '../api/download.dart';
import 'app_diagnostics.dart';
import 'local_music.dart';

/// One offline view over completed downloads and indexed device files.
class OfflineMusicLibrary {
  final LocalMusicLibrary local;
  final Future<List<Track>> Function() downloads;
  final Future<bool> Function(Track) available;
  OfflineMusicLibrary({LocalMusicLibrary? local,
    Future<List<Track>> Function()? downloads,
    Future<bool> Function(Track)? available})
      : local = local ?? LocalMusicLibrary.instance,
        downloads = downloads ?? (() => downloadManager.allOfflineTracks()),
        available = available ?? ((track) => downloadManager.checkOffline(track: track));

  Future<List<Track>> load() async {
    final tracks = <String, Track>{};
    bool downloadsFailed = false, localFailed = false;
    try {
      for (final track in await downloads()) {
        try {
          if (track.id != null && await available(track)) tracks.putIfAbsent(track.id!, () => track);
        } catch (_) {
          AppDiagnostics.instance.record('offlineLibrary', 'DOWNLOAD_FILE_UNAVAILABLE');
        }
      }
    } catch (_) {
      downloadsFailed = true;
      AppDiagnostics.instance.record('offlineLibrary', 'DOWNLOAD_INDEX_UNAVAILABLE');
    }
    try {
      for (final song in await local.load()) {
        final track = song.toTrack();
        tracks.putIfAbsent(track.id!, () => track);
      }
    } catch (_) {
      localFailed = true;
      AppDiagnostics.instance.record('offlineLibrary', 'LOCAL_INDEX_UNAVAILABLE');
    }
    if (downloadsFailed && localFailed) throw const OfflineMusicReadException();
    return tracks.values.toList();
  }
}

class OfflineMusicReadException implements Exception {
  const OfflineMusicReadException();
}
