import 'package:audio_service/audio_service.dart';

// Separate converter since MediaItem.toJson() MediaItem.fromJson() are removed in audio_service v0.18+
class MediaItemConverter {
  static MediaItem mediaItemFromMap(Map<String, dynamic> json) {
    final id = _text(json['id']);
    if (id == null || id.isEmpty) throw const FormatException('Missing media ID');
    final duration = _integer(json['duration']);
    return MediaItem(
      id: id,
      album: _text(json['album']),
      title: _text(json['title']) ?? _text(json['displayTitle']) ?? '',
      artist: _text(json['artist']),
      genre: _text(json['genre']),
      duration: duration == null ? null : Duration(milliseconds: duration < 0 ? 0 : duration),
      artUri: _uri(json['artUri']),
      artHeaders: json['artHeaders'] is Map ? {
        for (final entry in (json['artHeaders'] as Map).entries)
          if (entry.key is String && entry.value is String) entry.key as String: entry.value as String,
      } : null,
      playable: json['playable'] is bool ? json['playable'] : true,
      displayTitle: _text(json['displayTitle']),
      displaySubtitle: _text(json['displaySubtitle']),
      displayDescription: _text(json['displayDescription']),
      rating: null,
      extras: json['extras'] is Map ? {
        for (final entry in (json['extras'] as Map).entries)
          if (entry.key is String) entry.key as String: entry.value,
      } : null,
    );
  }

  static Map<String, dynamic> mediaItemToMap(MediaItem mi) => <String, dynamic>{
        'id': mi.id,
        'title': mi.title,
        'album': mi.album,
        'artist': mi.artist,
        'genre': mi.genre,
        'duration': mi.duration?.inMilliseconds,
        'artUri': mi.artUri?.toString(),
        'artHeaders': mi.artHeaders,
        'playable': mi.playable,
        'displayTitle': mi.displayTitle,
        'displaySubtitle': mi.displaySubtitle,
        'displayDescription': mi.displayDescription,
        'rating': null,
        'extras': mi.extras,
      };

  static String? _text(dynamic value) => value is String ? value : value is num ? value.toString() : null;
  static int? _integer(dynamic value) => value is num ? value.toInt() : value is String ? int.tryParse(value) : null;
  static Uri? _uri(dynamic value) => value is String && value.isNotEmpty && value != 'null' ? Uri.tryParse(value) : null;

  static String artworkUrl(MediaItem? item) {
    final thumb = item?.extras?['thumb'];
    if (thumb is String && thumb.isNotEmpty && thumb != 'null') return thumb;
    if (thumb is Uri) return thumb.toString();
    return item?.artUri?.toString() ?? '';
  }

  /// Preserve the selected occurrence while skipping unusable legacy entries.
  static RestoredMediaQueue restoreQueue(Map<String, dynamic> json) {
    final raw = json['queue'] is List ? json['queue'] as List : const [];
    final requested = raw.isEmpty ? 0 : (_integer(json['index']) ?? 0).clamp(0, raw.length - 1);
    final items = <MediaItem>[];
    final positions = <int>[];
    for (var index = 0; index < raw.length; index++) {
      if (raw[index] is! Map) continue;
      try {
        items.add(mediaItemFromMap(Map<String, dynamic>.from(raw[index])));
        positions.add(index);
      } on FormatException { /* An invalid row does not erase the entire queue. */ }
        on TypeError { /* Legacy malformed keys are skipped. */ }
    }
    var selected = positions.indexOf(requested);
    final exact = selected >= 0;
    if (!exact) {
      selected = positions.indexWhere((index) => index > requested);
      if (selected < 0) selected = items.isEmpty ? 0 : items.length - 1;
    }
    final milliseconds = _integer(json['position']) ?? 0;
    return RestoredMediaQueue(items, selected, exact ? Duration(milliseconds: milliseconds < 0 ? 0 : milliseconds) : Duration.zero);
  }
}

class RestoredMediaQueue {
  final List<MediaItem> items;
  final int index;
  final Duration position;
  const RestoredMediaQueue(this.items, this.index, this.position);
}
