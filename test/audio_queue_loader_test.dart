import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart'
    as api;
import 'package:refreezer/service/audio_queue_loader.dart';

class TestAudioPlatform extends api.JustAudioPlatform {
  late TestPlayer lastPlayer;
  final players = <TestPlayer>[];
  @override
  Future<api.AudioPlayerPlatform> init(api.InitRequest request) async {
    lastPlayer = TestPlayer(request.id);
    players.add(lastPlayer);
    return lastPlayer;
  }

  @override
  Future<api.DisposePlayerResponse> disposePlayer(
    api.DisposePlayerRequest request,
  ) async => api.DisposePlayerResponse();
}

class TestPlayer extends api.AudioPlayerPlatform {
  TestPlayer(super.id);
  final events = StreamController<api.PlaybackEventMessage>.broadcast();
  final requests = <api.LoadRequest>[];
  @override
  Stream<api.PlaybackEventMessage> get playbackEventMessageStream =>
      events.stream;
  @override
  Future<api.LoadResponse> load(api.LoadRequest request) async {
    requests.add(request);
    // Index zero is unavailable: an addAll followed by seek would fail first.
    if ((request.initialIndex ?? 0) == 0)
      throw StateError('first source unavailable');
    events.add(
      api.PlaybackEventMessage(
        processingState: api.ProcessingStateMessage.ready,
        updateTime: DateTime.now(),
        updatePosition: request.initialPosition ?? Duration.zero,
        bufferedPosition: const Duration(seconds: 5),
        duration: const Duration(minutes: 3),
        icyMetadata: null,
        currentIndex: request.initialIndex,
        androidAudioSessionId: null,
      ),
    );
    return api.LoadResponse(duration: const Duration(minutes: 3));
  }

  final inserts = <api.ConcatenatingInsertAllRequest>[];
  @override
  Future<api.ConcatenatingInsertAllResponse> concatenatingInsertAll(
    api.ConcatenatingInsertAllRequest request,
  ) async {
    inserts.add(request);
    return api.ConcatenatingInsertAllResponse();
  }

  @override
  Future<api.SetVolumeResponse> setVolume(api.SetVolumeRequest request) async =>
      api.SetVolumeResponse();
  @override
  Future<api.SetSpeedResponse> setSpeed(api.SetSpeedRequest request) async =>
      api.SetSpeedResponse();
  @override
  Future<api.SetPitchResponse> setPitch(api.SetPitchRequest request) async =>
      api.SetPitchResponse();
  @override
  Future<api.SetSkipSilenceResponse> setSkipSilence(
    api.SetSkipSilenceRequest request,
  ) async => api.SetSkipSilenceResponse();
  @override
  Future<api.SetLoopModeResponse> setLoopMode(
    api.SetLoopModeRequest request,
  ) async => api.SetLoopModeResponse();
  @override
  Future<api.SetShuffleModeResponse> setShuffleMode(
    api.SetShuffleModeRequest request,
  ) async => api.SetShuffleModeResponse();
  @override
  Future<api.SetShuffleOrderResponse> setShuffleOrder(
    api.SetShuffleOrderRequest request,
  ) async => api.SetShuffleOrderResponse();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'selected source loads directly even when the first cannot load',
    () async {
      final previous = api.JustAudioPlatform.instance;
      final platform = TestAudioPlatform();
      api.JustAudioPlatform.instance = platform;
      final player = AudioPlayer(
        handleInterruptions: false,
        handleAudioSessionActivation: false,
        androidApplyAudioAttributes: false,
      );
      try {
        await loadAudioQueue(
          player,
          [
              AudioSource.uri(Uri.parse('http://127.0.0.1:36958/?id=bad')),
              AudioSource.uri(Uri.parse('http://127.0.0.1:36958/?id=good')),
          ],
          1,
          position: const Duration(seconds: 12),
        );
        expect(player.audioSources.length, 2);
        expect(platform.lastPlayer.requests.length, 1);
        expect(platform.lastPlayer.requests.single.initialIndex, 1);
        expect(
          platform.lastPlayer.requests.single.initialPosition,
          const Duration(seconds: 12),
        );
        expect(player.currentIndex, 1);
      } finally {
        await player.dispose();
        api.JustAudioPlatform.instance = previous;
        await Future.wait(platform.players.map((p) => p.events.close()));
      }
    },
  );
  test(
    'a failed initial source can be followed by a new selection in the same queue',
    () async {
      final previous = api.JustAudioPlatform.instance;
      final platform = TestAudioPlatform();
      api.JustAudioPlatform.instance = platform;
      final player = AudioPlayer(
        handleInterruptions: false,
        handleAudioSessionActivation: false,
        androidApplyAudioAttributes: false,
      );
      final playlist = <AudioSource>[
          AudioSource.uri(Uri.parse('http://127.0.0.1:36958/?id=bad')),
          AudioSource.uri(Uri.parse('http://127.0.0.1:36958/?id=good')),
      ];
      try {
        await expectLater(
          loadAudioQueue(player, playlist, 0),
          throwsA(isA<StateError>()),
        );
        await loadAudioQueue(player, playlist, 1);
        expect(player.currentIndex, 1);
        expect(player.sequence.length, 2);
        expect(platform.players.last.requests.last.initialIndex, 1);
      } finally {
        await player.dispose();
        api.JustAudioPlatform.instance = previous;
        await Future.wait(platform.players.map((p) => p.events.close()));
      }
    },
  );
  for (final shuffled in [false, true]) {
    test('queue edits reach native player and preserve current track (shuffle=$shuffled)', () async {
      final previous = api.JustAudioPlatform.instance;
      final platform = TestAudioPlatform();
      api.JustAudioPlatform.instance = platform;
      final player = AudioPlayer(handleInterruptions: false,
        handleAudioSessionActivation: false, androidApplyAudioAttributes: false);
      AudioSource song(String id) => AudioSource.uri(Uri.parse('file:///$id.mp3'), tag: id);
      final order = QueueShuffleOrder();
      try {
        await loadAudioQueue(player, [song('a'), song('b'), song('c')], 1,
          position: const Duration(seconds: 12), shuffleOrder: order);
        if (shuffled) {
          await player.shuffle();
          await player.setShuffleModeEnabled(true);
        }
        final originalOrder = player.effectiveSequence.map((s) => s.tag).toList();
        await player.addAudioSource(song('tail'));
        expect(player.effectiveSequence.map((s) => s.tag), [...originalOrder, 'tail']);
        await insertNextAudioSource(player, song('next'), order);
        final effective = player.effectiveSequence.map((s) => s.tag).toList();
        final expected = [...originalOrder, 'tail'];
        expected.insert(expected.indexOf('b') + 1, 'next');
        expect(effective, expected);
        expect(player.sequence[player.nextIndex!].tag, 'next');
        expect(player.sequence[player.currentIndex!].tag, 'b');
        expect(player.position, const Duration(seconds: 12));
        expect(platform.lastPlayer.requests.length, 1, reason: 'No reload or seek to zero');
        expect(platform.lastPlayer.inserts.map((r) => r.index), [3, 2]);
        await insertNextAudioSource(player, song('next2'), order);
        expect(player.sequence[player.nextIndex!].tag, 'next2');
        expect(player.sequence.length, 6);
      } finally {
        await player.dispose();
        api.JustAudioPlatform.instance = previous;
        await Future.wait(platform.players.map((p) => p.events.close()));
      }
    });
  }
  test('empty queue accepts a next item and keeps duplicate occurrences', () async {
    final player = AudioPlayer(handleInterruptions: false,
      handleAudioSessionActivation: false, androidApplyAudioAttributes: false);
    final order = QueueShuffleOrder();
    try {
      await player.setAudioSources([], preload: false, shuffleOrder: order);
      await insertNextAudioSource(player, AudioSource.uri(Uri.parse('file:///a.mp3'), tag: 'a'), order);
      await player.addAudioSource(AudioSource.uri(Uri.parse('file:///a.mp3'), tag: 'a'));
      expect(player.sequence.map((s) => s.tag), ['a', 'a']);
    } finally { await player.dispose(); }
  });

}
