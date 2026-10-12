import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:refreezer/api/definitions.dart';
import 'package:refreezer/service/local_music.dart';

Map<String, dynamic> candidate({String path = 'Music/', String name = 'Track.mp3',
  String uri = 'content://media/external/audio/media/42', int duration = 210000}) => {
  'uri': uri, 'path': path, 'name': name, 'title': 'Track', 'artist': 'Artist',
  'album': 'Album', 'durationMs': duration, 'size': 4000000, 'isMusic': true,
};
void main() {
  test('excludes voice messages and system sounds even if marked as music', () {
    for (final path in ['Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Audio/',
      'WhatsApp Voice Notes/', 'Telegram/Voice Messages/', 'Recordings/',
      'Registrazioni/', 'Ringtones/', 'Notifications/', 'Alarms/', 'Podcasts/']) {
      expect(LocalSong.isMusic(candidate(path: path)), isFalse, reason: path);
    }
    expect(LocalSong.isMusic(candidate(name: 'PTT-20261012-WA0001.opus')), isFalse);
    expect(LocalSong.isMusic(candidate()..['isNotification'] = true), isFalse);
    expect(LocalSong.isMusic(candidate(uri: 'https://example.com/audio.mp3')), isFalse);
    expect(LocalSong.isMusic(candidate()..['size'] = 0), isFalse);
  });
  test('accepts FLAC and Opus music while short audio requires folder selection', () {
    expect(LocalSong.isMusic(candidate(name: 'Music.flac')), isTrue);
    expect(LocalSong.isMusic(candidate(name: 'Music.opus')), isTrue);
    expect(LocalSong.isMusic(candidate(duration: 29999)), isFalse);
    expect(LocalSong.isMusic(candidate(duration: 15000)..['selectedFolder'] = true), isTrue);
    expect(LocalSong.isMusic(candidate(name: '12345678')..['selectedFolder'] = true), isTrue);
    expect(LocalSong.isMusic(candidate(path: 'content://documents/tree/primary%3AWhatsApp%20Voice%20Notes')..['selectedFolder'] = true), isFalse);
    expect(LocalSong.isMusic(candidate(name: '100%music.mp3')), isTrue);
  });
  test('local content URI cannot resolve to a network source', () {
    expect(LocalSong.sourceUri(candidate()['uri']), 'content://media/external/audio/media/42');
    expect(LocalSong.sourceUri('https://example.com/audio'), isNull);
    expect(LocalSong.sourceUri('file:///private/data'), isNull);
    expect(LocalSong.sourceUri('content:no-authority'), isNull);
    expect(LocalSong.sourceUri(null), isNull);
  });
  test('URI and metadata survive player, queue and history serialization', () {
    final original = LocalSong.fromMap(candidate()).toTrack();
    final restored = Track.fromMediaItem(original.toMediaItem());
    final history = Track.fromJson(jsonDecode(jsonEncode(restored.toJson())));
    expect(history.localUri, original.localUri);
    expect(history.toMediaItem().extras?['localUri'], original.localUri);
    expect(history.id, startsWith('local:content://'));
    expect(history.title, 'Track');
    expect(history.duration, const Duration(seconds: 210));
  });
  test('concurrent imports persist once and removal preserves original bytes', () async {
    final dir = await Directory.systemTemp.createTemp('vybe-import-');
    addTearDown(() => dir.delete(recursive: true));
    final original = File('${dir.path}/original.mp3');
    await original.writeAsBytes([1,2,3,4]);
    final index = File('${dir.path}/local-music.json');
    final library = LocalMusicLibrary(fileProvider: () async => index);
    final song = LocalSong.fromMap(candidate());
    final results = await Future.wait(List.generate(30, (_) => library.importSongs([song])));
    expect(results.reduce((a,b) => a+b), 1);
    expect(await library.load(), hasLength(1));
    final alias = LocalSong.fromMap(candidate(uri: 'content://documents/tree/music/document/42'));
    expect(await library.importSongs([alias]), 0);
    final reopened = LocalMusicLibrary(fileProvider: () async => index);
    expect((await reopened.load()).single.uri, song.uri);
    await reopened.remove(song.uri);
    expect(await reopened.load(), isEmpty);
    expect(await original.readAsBytes(), [1,2,3,4]);
  });
}
