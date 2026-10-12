import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../api/definitions.dart';

/// Importing indexes existing audio; it never uploads, copies or deletes it.
class LocalSong {
  final String uri, name, title, artist, album;
  final int durationMs, size;
  const LocalSong({required this.uri, required this.name, required this.title,
    required this.artist, required this.album, required this.durationMs, required this.size});
  factory LocalSong.fromMap(Map<dynamic, dynamic> map) => LocalSong(
    uri: map['uri'] as String, name: map['name'] as String? ?? '',
    title: map['title'] as String? ?? '', artist: map['artist'] as String? ?? '',
    album: map['album'] as String? ?? '', durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
    size: (map['size'] as num?)?.toInt() ?? 0);
  Map<String, dynamic> toMap() => {'uri': uri, 'name': name, 'title': title,
    'artist': artist, 'album': album, 'durationMs': durationMs, 'size': size};
  String get identity => jsonEncode([name.toLowerCase(), title.toLowerCase(), artist.toLowerCase(), durationMs, size]);
  Track toTrack() => Track(id: 'local:$uri', localUri: uri, title: title.isEmpty ? name : title,
    artists: [Artist(name: artist.isEmpty ? 'Artista sconosciuto' : artist)],
    album: Album(title: album), duration: Duration(milliseconds: durationMs), offline: true);
  static String? sourceUri(dynamic value) {
    if (value is! String) return null;
    final uri = Uri.tryParse(value);
    return uri?.scheme == 'content' && uri!.authority.isNotEmpty ? value : null;
  }
  static bool isMusic(Map<dynamic, dynamic> row) {
    if (sourceUri(row['uri']) == null) return false;
    String location = '${row['path'] ?? ''}/${row['name'] ?? ''}';
    try { location = Uri.decodeFull(location); } on FormatException { /* Raw file name can contain percent signs. */ }
    location = location.toLowerCase().replaceAll('\\', '/');
    if (RegExp(r'whatsapp|voice notes|voice_notes|voicenotes|voice messages|recordings?|registrazioni|ringtones?|notifications?|alarms?|audiobooks?|podcasts?').hasMatch(location)) return false;
    if (RegExp(r'(^|/)(ptt|aud)-\d').hasMatch(location)) return false;
    if (row['isRingtone'] == true || row['isAlarm'] == true || row['isNotification'] == true) return false;
    final duration = (row['durationMs'] as num?)?.toInt() ?? 0;
    if (duration <= 0 || ((row['size'] as num?)?.toInt() ?? 0) <= 0) return false;
    if (row['selectedFolder'] != true && duration < 30000) return false;
    final artist = row['artist']?.toString() ?? '';
    return row['selectedFolder'] == true || row['isMusic'] == true ||
      (artist.isNotEmpty && artist != '<unknown>') || RegExp(r'(^|/)music/').hasMatch(location) ||
      RegExp(r'\.(mp3|flac|m4a|aac|ogg|opus|wav|aiff|alac)$').hasMatch(location);
  }
}

class LocalMusicLibrary {
  static const channel = MethodChannel('r.r.refreezer/native');
  static final instance = LocalMusicLibrary();
  final Future<File> Function() fileProvider;
  Future<void> _writes = Future.value();
  LocalMusicLibrary({Future<File> Function()? fileProvider}) : fileProvider = fileProvider ?? _file;
  static Future<File> _file() async => File('${(await getApplicationDocumentsDirectory()).path}/local-music.json');
  Future<List<LocalSong>> load() async { await _writes; return _read(); }
  Future<List<LocalSong>> _read() async {
    final file = await fileProvider();
    if (!await file.exists()) return [];
    return (jsonDecode(await file.readAsString()) as List).map((e) => LocalSong.fromMap(e as Map)).toList();
  }
  Future<Map<String, dynamic>> discover({bool folder = false}) async =>
    await channel.invokeMapMethod<String, dynamic>(folder ? 'pickMusicFolder' : 'scanLocalMusic') ?? {'items': [], 'cancelled': true};
  Future<void> _save(List<LocalSong> songs) async {
    final file = await fileProvider();
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(songs.map((e) => e.toMap()).toList()), flush: true);
    await temp.rename(file.path);
  }
  Future<int> importSongs(List<LocalSong> songs) async {
    int added = 0;
    final operation = _writes.then((_) async {
      final existing = await _read();
      final uris = existing.map((e) => e.uri).toSet(), identities = existing.map((e) => e.identity).toSet();
      for (final song in songs) {
        if (uris.contains(song.uri) || identities.contains(song.identity)) continue;
        existing.add(song); uris.add(song.uri); identities.add(song.identity); added++;
      }
      await _save(existing);
    });
    _writes = operation.catchError((Object _) {});
    await operation; return added;
  }
  Future<void> remove(String uri) async {
    final operation = _writes.then((_) async { final songs = await _read(); songs.removeWhere((e) => e.uri == uri); await _save(songs); });
    _writes = operation.catchError((Object _) {}); await operation;
  }
}
