import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:equalizer_flutter/equalizer_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:just_audio/just_audio.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:refreezer/utils/env.dart';
import 'package:rxdart/rxdart.dart';
import 'package:scrobblenaut/scrobblenaut.dart';

import 'network_monitor.dart';
import 'audio_queue_loader.dart';
import 'app_diagnostics.dart';
import '../api/download.dart';
import 'queue_selection.dart';
import '../api/cache.dart';
import '../api/deezer.dart';
import '../api/definitions.dart';
import '../settings.dart';
import '../translations.i18n.dart';
import '../ui/android_auto.dart';
import '../utils/mediaitem_converter.dart';

Future<AudioPlayerHandler> initAudioService() async {
  return await AudioService.init(
    builder: () => AudioPlayerHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'r.r.refreezer.audio',
      androidNotificationChannelName: 'ReFreezer',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationClickStartsActivity: true,
      androidNotificationChannelDescription: 'ReFreezer',
      androidNotificationIcon: 'drawable/ic_logo',
    ),
  );
}

class AudioPlayerHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  AudioPlayerHandler() {
    _initialization = _init();
    unawaited(
      _initialization.catchError((Object _) {
        AppDiagnostics.instance.record('playerInitialization', 'FAILED');
      }),
    );
  }

  int? _audioSession;
  int? _prevAudioSession;
  bool _equalizerOpen = false;

  final AndroidAuto _androidAuto =
      AndroidAuto(); // Create an instance of AndroidAuto

  late final Future<void> _initialization;
  late AudioPlayer _player;
  var _playlist = ConcatenatingAudioSource(children: []);
  // Prevent MediaItem change while shuffling or otherwise rearranging the queue by just_audio internals
  bool _rearranging = false;

  Scrobblenaut? _scrobblenaut;
  bool _scrobblenautReady = false;
  // Last logged track id
  String? _loggedTrackId;

  //Visualizer
  final StreamController _visualizerController = StreamController.broadcast();
  Stream get visualizerStream => _visualizerController.stream;
  late StreamSubscription? _visualizerSubscription;

  QueueSource? queueSource;
  StreamSubscription? _queueStateSub;
  StreamSubscription? _mediaItemSub;
  final BehaviorSubject<QueueState> _queueStateSubject =
      BehaviorSubject<QueueState>.seeded(QueueState.empty);
  Stream<QueueState> get queueStateStream => _queueStateSubject.stream;
  QueueState get queueState => _queueStateSubject.value;
  int currentIndex = 0;
  int _requestedIndex = -1;
  Future<String>? _offlineDirectory;
  Future<String> _getOfflineDirectory() =>
      _offlineDirectory ??= getExternalStorageDirectory().then((directory) {
        if (directory == null) throw StateError('External storage unavailable');
        return p.join(directory.path, 'offline');
      });
  Future<void> _queueMutation = Future.value();
  int _selectionGeneration = 0;
  bool _recovering = false;
  bool _extending = false;
  Future<void> _queueSave = Future.value();
  int _checkpoint = -1;
  int _sourceOffset = 0;
  bool _sourceExhausted = false;
  final Set<int> _failedIndices = {};
  final Set<String> _retriedIds = {};

  Future<void> _serialize(Future<void> Function() action) {
    final next = _queueMutation.then((_) => action());
    _queueMutation = next.catchError((Object e, StackTrace st) {
      Logger.root.warning('Queue operation failed (${e.runtimeType})');
    });
    return next;
  }

  Future<void> _init() async {
    await _startSession();

    // Broadcast the current queue when just_audio sequence changes.
    // Only emit value when MediaItem list contents is different from previous queue
    _player.sequenceStateStream
        .map((state) {
          try {
            return state.sequence
                .map((source) => source.tag as MediaItem)
                .toList();
          } catch (e) {
            if (e is RangeError) {
              // This is caused by just_audio not updating the currentIndex first in the _broadcastSequence method.
              // Because in shufflemode it's out of range after removing items from the playlist.
              // Might be fixed in future
              Logger.root.severe(
                'RangeError occurred while accessing effectiveSequence: $e',
              );
              // Return null to indicate that the queue could/should not be broadcasted
              return null;
            }
            rethrow;
          }
        })
        .whereType<List<MediaItem>>() // Filter out null values (error occured).
        .distinct((a, b) => listEquals(a, b))
        .pipe(queue);

    // Update current QueueState
    _queueStateSub =
        Rx.combineLatest3<
              List<MediaItem>,
              PlaybackState,
              List<int>,
              QueueState
            >(
              queue,
              playbackState,
              _player.shuffleIndicesStream.whereType<List<int>>(),
              (queue, playbackState, shuffleIndices) => QueueState(
                queue,
                playbackState.queueIndex,
                playbackState.shuffleMode == AudioServiceShuffleMode.all
                    ? shuffleIndices
                    : null,
                playbackState.repeatMode,
                playbackState.shuffleMode,
              ),
            )
            .where(
              (state) =>
                  state.shuffleIndices == null ||
                  state.queue.length == state.shuffleIndices!.length,
            )
            .distinct()
            .listen(_queueStateSubject.add);

    // Broadcast media item changes after track or position in queue change,
    // only emit value when different from previous item
    _mediaItemSub =
        Rx.combineLatest3<int?, List<MediaItem>, bool, MediaItem?>(
          _player.currentIndexStream,
          queue,
          _player.shuffleModeEnabledStream,
          (index, queue, shuffleModeEnabled) {
            // Don't broadcast while shuffling to avoid intermediate MediaItem change
            if (_rearranging) return null;

            // Prevent broadcasting first item from new queue when other index is requested
            if (_requestedIndex != -1 && _requestedIndex != index) return null;

            final queueIndex = _getQueueIndex(
              index ?? 0,
              shuffleModeEnabled: shuffleModeEnabled,
            );
            return (queueIndex >= 0 && queueIndex < queue.length)
                ? queue[queueIndex]
                : null;
          },
        ).whereType<MediaItem>().distinct().listen((item) {
          // Change track
          mediaItem.add(item);

          final int queueIndex = queue.value.indexOf(item);
          final int queueLength = queue.value.length;

          if (queueLength - queueIndex == 1) {
            Logger.root.info('loaded last track of queue, adding more tracks');
            _onQueueEnd();
          }

          //Save queue
          _saveQueueToFile();
          //Add to history
          _addToHistory(item);
        });

    // Propagate all events from the audio player to AudioService clients.
    _player.playbackEventStream.listen(
      _broadcastState,
      onError: _playbackError,
    );

    _player.shuffleModeEnabledStream.listen(
      (enabled) => _broadcastState(_player.playbackEvent),
    );

    _player.loopModeStream.listen(
      (mode) => _broadcastState(_player.playbackEvent),
    );

    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && _player.playing) {
        pause();
        _saveQueueToFile();
      }
    });

    //Audio session
    _player.androidAudioSessionIdStream.listen((session) {
      if (!settings.enableEqualizer) return;

      //Save
      _prevAudioSession = _audioSession;
      _audioSession = session;
      if (_audioSession == null) return;

      //Open EQ
      if (!_equalizerOpen) {
        EqualizerFlutter.open(session!);
        _equalizerOpen = true;
        return;
      }

      //Change session id
      if (_prevAudioSession != _audioSession) {
        if (_prevAudioSession != null) {
          EqualizerFlutter.removeAudioSessionId(_prevAudioSession!);
        }
        EqualizerFlutter.setAudioSessionId(_audioSession!);
      }
    });

    // When 75% of item played, save loggedTrackId to cache & log listen (if enabled)
    AudioService.position.listen((position) {
      if (mediaItem.value == null || !playbackState.value.playing) {
        return;
      }

      final checkpoint = position.inSeconds ~/ 15;
      if (checkpoint != _checkpoint) {
        _checkpoint = checkpoint;
        unawaited(_saveQueueToFile());
      }
      final duration = mediaItem.value!.duration;
      if (duration != null && position.inSeconds > duration.inSeconds * 0.75) {
        if (cache.loggedTrackId == mediaItem.value!.id) return;
        cache.loggedTrackId = mediaItem.value!.id;
        cache.save();

        //Log to Deezer
        if (settings.logListen) {
          deezerAPI.logListen(mediaItem.value!.id);
        }
      }
    });
  }

  @override
  Future<void> play() async {
    unawaited(
      _player.play().catchError((Object error) {
        _playbackError(error);
      }),
    );

    //Scrobble to LastFM
    MediaItem? newMediaItem = mediaItem.value;
    if (newMediaItem != null && newMediaItem.id != _loggedTrackId) {
      // Add to history if new track
      _addToHistory(newMediaItem);
    }
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    // Check if the mediaId is for Android Auto
    if (mediaId.startsWith(AndroidAuto.prefix)) {
      // Forward the event to Android Auto
      await _androidAuto.playItem(mediaId);
      return;
    }

    // Handle other mediaIds by seeking to the appropriate item in the queue
    final index = queue.value.indexWhere((item) => item.id == mediaId);
    if (index != -1) {
      await skipToQueueItem(index);
    } else {
      Logger.root.severe('playFromMediaId: MediaItem not found');
    }
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    // Save queue before stopping player to save player details
    Logger.root.info('saving queue');
    await _saveQueueToFile();
    Logger.root.info('stopping player');
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    await _serialize(() async {
      final source = await _itemToSource(mediaItem);
      if (source != null) await _playlist.add(source);
    });
  }

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {
    await _serialize(() async {
      await _playlist.addAll(await _itemsToSources(mediaItems));
    });
  }

  @override
  Future<void> insertQueueItem(int index, MediaItem mediaItem) async {
    await _serialize(() async {
      final source = await _itemToSource(mediaItem);
      if (source == null) return;
      final insertion = index == -1 ? (_player.currentIndex ?? -1) + 1 : index;
      await _playlist.insert(
        insertion.clamp(0, _playlist.children.length),
        source,
      );
      _failedIndices.clear();
      _retriedIds.clear();
    });
  }

  @override
  Future<void> updateQueue(List<MediaItem> queue) async {
    ++_selectionGeneration;
    await _serialize(() async {
      final sources = await _itemsToSources(queue);
      _rearranging = true;
      try {
        await _playlist.clear();
        await _playlist.addAll(sources);
      } finally {
        _rearranging = false;
      }
      if (sources.isEmpty)
        mediaItem.add(null);
      else
        _publishCurrentItem();
    });
  }

  Future<void> clearQueue() async {
    await updateQueue([]);
    await removeSavedQueueFile();
  }

  @override
  Future<void> removeQueueItem(MediaItem mediaItem) async {
    await _serialize(() async {
      final index = queue.value.indexOf(mediaItem);
      if (index >= 0) await _playlist.removeAt(index);
      _failedIndices.clear();
      _retriedIds.clear();
      _publishCurrentItem();
    });
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    await _serialize(() async {
      if (index >= 0 && index < _playlist.children.length)
        await _playlist.removeAt(index);
      _failedIndices.clear();
      _retriedIds.clear();
      _publishCurrentItem();
    });
  }

  Future<void> moveQueueItem(int currentIndex, int newIndex) async {
    await _serialize(() async {
      _rearranging = true;
      try {
        await _playlist.move(currentIndex, newIndex);
      } finally {
        _rearranging = false;
      }
      _failedIndices.clear();
      _retriedIds.clear();
      _publishCurrentItem();
    });
  }

  @override
  Future<void> skipToNext() {
    ++_selectionGeneration;
    return _serialize(() async {
      await _player.seekToNext();
      _publishCurrentItem();
    });
  }

  @override
  Future<void> skipToPrevious() async {
    ++_selectionGeneration;
    if ((_player.position.inSeconds) <= 5) {
      await _serialize(() async {
        await _player.seekToPrevious();
        _publishCurrentItem();
      });
    } else {
      await _player.seek(Duration.zero);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    ++_selectionGeneration;
    await _serialize(() async {
      if (index < 0 || index >= _playlist.children.length) return;
      _failedIndices.clear();
      _retriedIds.clear();
      await _player.seek(Duration.zero, index: index);
      _publishCurrentItem();
    });
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
    await _player.setLoopMode(LoopMode.values[repeatMode.index]);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) =>
      _serialize(() async {
        final enabled = shuffleMode == AudioServiceShuffleMode.all;
        _rearranging = true;
        try {
          if (enabled) await _player.shuffle();
          await _player.setShuffleModeEnabled(enabled);
        } finally {
          _rearranging = false;
        }
        _publishCurrentItem();
        playbackState.add(
          playbackState.value.copyWith(shuffleMode: shuffleMode),
        );
      });

  @override
  Future<void> onTaskRemoved() async {
    dispose();
  }

  @override
  Future<void> onNotificationDeleted() async {
    dispose();
  }

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    //Android audio callback
    return _androidAuto.getScreen(parentMediaId);
  }

  //----------------------------------------------
  // Start internal methods native to AudioHandler
  //----------------------------------------------

  Future<void> _startSession() async {
    Logger.root.info('starting audio service...');
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    if (settings.ignoreInterruptions == true) {
      _player = AudioPlayer(handleInterruptions: false);
      // Handle audio interruptions. (ignore)
      session.interruptionEventStream.listen((_) {});
      // Handle unplugged headphones. (ignore)
      session.becomingNoisyEventStream.listen((_) {});
    } else {
      _player = AudioPlayer();
    }

    await _loadEmptyPlaylist().then(
      (_) => Logger.root.info('audio player initialized!'),
    );
  }

  /// Broadcasts the current state to all clients.
  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    currentIndex = _getQueueIndex(
      _player.currentIndex ?? 0,
      shuffleModeEnabled: _player.shuffleModeEnabled,
    );

    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          // Custom Stop
          const MediaControl(
            androidIcon: 'drawable/ic_action_stop',
            label: 'stop',
            action: MediaAction.stop,
          ),
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_player.processingState]!,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: currentIndex,
      ),
    );
  }

  /// Resolve the effective queue index taking into account shuffleMode.
  int _getQueueIndex(int currentIndex, {bool shuffleModeEnabled = false}) {
    return currentIndex;
  }

  Future<void> _loadEmptyPlaylist() async {
    try {
      Logger.root.info('Loading empty playlist...');
      await _player.setAudioSource(_playlist);
    } catch (e) {
      Logger.root.severe('Error loading empty playlist: $e');
    }
  }

  Future<List<AudioSource>> _itemsToSources(List<MediaItem> mediaItems) async {
    final quality = NetworkMonitor.instance.offline
        ? 1
        : await getStreamQuality();
    var sources = await Future.wait(
      mediaItems.map((item) async {
        try {
          return await _itemToSource(item, streamQuality: quality);
        } catch (_) {
          return null;
        }
      }),
    );
    return sources.whereType<AudioSource>().toList();
  }

  Future<AudioSource?> _itemToSource(
    MediaItem mi, {
    bool preferLocal = true,
    int? streamQuality,
  }) async {
    String? url = await _getTrackUrl(
      mi,
      preferLocal: preferLocal,
      streamQuality: streamQuality,
    );
    if (url == null) return null;
    if (url.startsWith('http')) {
      return ProgressiveAudioSource(Uri.parse(url), tag: mi);
    }
    return AudioSource.uri(Uri.parse(url), tag: mi);
  }

  Future _getTrackUrl(
    MediaItem mediaItem, {
    bool preferLocal = true,
    int? streamQuality,
  }) async {
    //Check if offline
    String offlinePath = await _getOfflineDirectory();
    File f = File(p.join(offlinePath, mediaItem.id));
    if (preferLocal && await f.exists() && await f.length() > 0) {
      //return f.path;
      //Stream server URL
      return 'http://127.0.0.1:36958/?id=${mediaItem.id}';
    }

    if (NetworkMonitor.instance.offline) return null;

    //Show episode direct link
    if (mediaItem.extras?['showUrl'] != null) {
      return mediaItem.extras?['showUrl'];
    }

    //Due to current limitations of just_audio, quality fallback moved to DeezerDataSource in ExoPlayer
    //This just returns fake url that contains metadata
    int quality = streamQuality ?? await getStreamQuality();

    List? streamPlaybackDetails = _playbackDetails(
      mediaItem.extras?['playbackDetails'],
    );
    String streamItemId = mediaItem.id;

    //If Deezer provided a FALLBACK track, use the playbackDetails and id from the fallback track
    //for streaming (original stream unavailable)
    if (mediaItem.extras?['fallbackId'] != null) {
      streamItemId = mediaItem.extras?['fallbackId'];
      streamPlaybackDetails = _playbackDetails(
        mediaItem.extras?['playbackDetailsFallback'],
      );
    }

    // Missing catalog tokens are refreshed by the server only when opened.
    final details = List<dynamic>.of(streamPlaybackDetails ?? []);
    while (details.length < 3) {
      details.add(null);
    }
    return Uri.http('127.0.0.1:36958', '/', {
      'q': quality.toString(),
      'id': mediaItem.id,
      'streamTrackId': streamItemId,
      'trackToken': details[2]?.toString() ?? '',
      'mv': details[1]?.toString() ?? '',
      'md5origin': details[0]?.toString() ?? '',
      if (!preferLocal) 'forceOnline': '1',
    }).toString();
  }

  List? _playbackDetails(dynamic value) {
    if (value is List) return value;
    if (value is! String) return null;
    try {
      final decoded = jsonDecode(value);
      return decoded is List ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Get requested stream quality based on connection and settings.
  Future<int> getStreamQuality() async {
    int quality = settings.getQualityInt(settings.mobileQuality);
    List<ConnectivityResult> conn = await Connectivity().checkConnectivity();
    if (conn.contains(ConnectivityResult.wifi)) {
      quality = settings.getQualityInt(settings.wifiQuality);
    }
    return quality;
  }

  /// Load new queue of MediaItems to just_audio & seek to given index & position
  Future _loadQueueAtIndex(
    List<MediaItem> newQueue,
    int index, {
    Duration position = Duration.zero,
  }) async {
    if (newQueue.isEmpty) return;
    final requested = index.clamp(0, newQueue.length - 1);
    final selected = newQueue[requested];
    final sources = await _itemsToSources(newQueue);
    if (sources.isEmpty) return;
    final matching = sources.indexWhere(
      (source) =>
          source is IndexedAudioSource && identical(source.tag, selected),
    );
    // Restore at the next surviving occurrence, preserving the saved order.
    final available = sources
        .map((source) => (source as IndexedAudioSource).tag)
        .toList();
    final next = newQueue
        .skip(requested + 1)
        .where((item) => available.any((tag) => identical(tag, item)));
    final resolved = matching >= 0
        ? matching
        : next.isNotEmpty
        ? available.indexWhere((tag) => identical(tag, next.first))
        : sources.length - 1;
    _rearranging = true;
    try {
      _requestedIndex = resolved;
      await _player.setShuffleModeEnabled(false);
      _playlist = await loadAudioQueue(
        _player,
        sources,
        resolved,
        position: matching >= 0 ? position : Duration.zero,
      );
    } finally {
      _requestedIndex = -1;
      _rearranging = false;
    }
    _publishCurrentItem();
  }

  //Replace queue, play specified item index
  Future _loadQueueAndPlayAtIndex(
    QueueSource newQueueSource,
    List<MediaItem> newQueue,
    int index,
  ) async {
    final generation = ++_selectionGeneration;
    await _serialize(() async {
      if (generation != _selectionGeneration ||
          index < 0 ||
          index >= newQueue.length)
        return;
      final sources = await _itemsToSources(newQueue);
      if (generation != _selectionGeneration) return;
      final resolved = resolveQueueSelection(
        newQueue,
        index,
        sources
            .map((source) => (source as IndexedAudioSource).tag as MediaItem)
            .toList(),
      );
      if (resolved < 0) {
        Fluttertoast.showToast(
          msg: 'Brano non disponibile con la connessione attuale',
        );
        return;
      }
      await pause();
      _rearranging = true;
      try {
        await _player.setShuffleModeEnabled(false);
        _requestedIndex = resolved;
        queueSource = newQueueSource;
        _playlist = await loadAudioQueue(_player, sources, resolved);
        _sourceOffset = newQueue.length;
        _sourceExhausted = false;
        _failedIndices.clear();
        _retriedIds.clear();
        AppDiagnostics.instance.record('player', 'QUEUE_LOADED');
      } catch (_) {
        AppDiagnostics.instance.record('player', 'SOURCE_LOAD_FAILED');
        await _showPlaybackFailure();
        return;
      } finally {
        _requestedIndex = -1;
        _rearranging = false;
      }
      if (generation == _selectionGeneration) {
        _publishCurrentItem();
        unawaited(play());
      }
    });
  }

  /// Attempt to load more tracks when queue ends
  Future _onQueueEnd() async {
    if (_extending ||
        _rearranging ||
        NetworkMonitor.instance.offline ||
        queueSource == null ||
        (queueSource!.source == 'playlist' && _sourceExhausted))
      return;
    _extending = true;
    final source = queueSource;
    final generation = _selectionGeneration;
    try {
      List<Track> tracks = [];
      switch (queueSource!.source) {
        case 'flow':
          tracks = await deezerAPI.flow();
          break;
        //SmartRadio/Artist radio
        case 'smartradio':
          tracks = await deezerAPI.smartRadio(queueSource!.id ?? '');
          break;
        //Library shuffle
        case 'libraryshuffle':
          tracks = await deezerAPI.libraryShuffle(start: queue.value.length);
          break;
        case 'mix':
          tracks = await deezerAPI.playMix(queueSource!.id ?? '');
          break;
        case 'playlist':
          // Get current position
          int pos = _sourceOffset;
          // Load 25 more tracks from playlist
          tracks = await deezerAPI.playlistTracksPage(
            queueSource!.id!,
            pos,
            nb: 25,
          );
          break;
        default:
          Logger.root.info(
            'Reached end of queue source: ${queueSource!.source}',
          );
          break;
      }

      if (generation != _selectionGeneration || !identical(source, queueSource))
        return;
      final fetchedCount = tracks.length;
      // Playlist occurrences are intentional. Radio recommendations deduplicate.
      if (source!.source != 'playlist') {
        final queueIds = queue.value.map((mi) => mi.id).toSet();
        tracks.removeWhere((track) => queueIds.contains(track.id));
      }
      List<MediaItem> extraTracks = tracks
          .map<MediaItem>((t) => t.toMediaItem())
          .toList();
      await _serialize(() async {
        if (generation != _selectionGeneration ||
            !identical(source, queueSource))
          return;
        final sources = await _itemsToSources(extraTracks);
        if (generation != _selectionGeneration ||
            !identical(source, queueSource))
          return;
        if (source.source == 'playlist') {
          _sourceOffset += fetchedCount;
          _sourceExhausted = fetchedCount < 25;
        }
        if (sources.isNotEmpty) await _playlist.addAll(sources);
      });
    } catch (_) {
      Logger.root.warning('Could not extend queue; keeping current playback');
    } finally {
      _extending = false;
    }
  }

  void _playbackError(err) {
    Logger.root.warning(
      'Playback failed (${err.runtimeType}); attempting next available source',
    );
    if (err is PlatformException &&
        err.code == 'abort' &&
        err.message == 'Connection aborted') {
      return;
    }
    unawaited(_handlePlaybackError());
  }

  Future<void> _handlePlaybackError() async {
    if (_rearranging) return;
    if (await _showPlaybackFailure()) {
      await pause();
      return;
    }
    await _recoverPlayback();
  }

  Future<bool> _showPlaybackFailure() async {
    String code = 'SOURCE_UNAVAILABLE';
    bool fatal = false;
    try {
      final data = await DownloadManager.platform
          .invokeMapMethod<String, dynamic>('getPlaybackDiagnostics');
      final candidate = data?['errorCode'];
      if (candidate is String &&
          candidate != 'NONE' &&
          RegExp(r'^[A-Z0-9_]{1,64}$').hasMatch(candidate))
        code = candidate;
      fatal = data?['fatal'] == true;
    } catch (_) {}
    AppDiagnostics.instance.record('stream', code);
    await Fluttertoast.showToast(
      msg: 'Audio non disponibile: $code. Apri Impostazioni > Diagnostica.',
    );
    return fatal;
  }

  void _publishCurrentItem() {
    final index = _player.currentIndex;
    final sequence = _player.sequence;
    if (index != null && index >= 0 && index < sequence.length) {
      mediaItem.add(sequence[index].tag as MediaItem);
      if (index == sequence.length - 1) unawaited(_onQueueEnd());
    }
    _broadcastState(_player.playbackEvent);
    unawaited(_saveQueueToFile());
  }

  Future<void> _recoverPlayback() async {
    if (_recovering || _rearranging) return;
    _recovering = true;
    final generation = _selectionGeneration;
    final originalIndex = _player.currentIndex;
    try {
      await NetworkMonitor.instance.refresh();
      if (generation != _selectionGeneration ||
          originalIndex != _player.currentIndex)
        return;
      final failed = _player.currentIndex;
      if (failed != null && failed < queue.value.length) {
        final item = queue.value[failed];
        if (!NetworkMonitor.instance.offline && _retriedIds.add(item.id)) {
          try {
            final fresh = await deezerAPI
                .track(item.id)
                .timeout(const Duration(seconds: 8));
            final replacement = await _itemToSource(
              fresh.toMediaItem(),
              preferLocal: false,
            );
            if (generation != _selectionGeneration) return;
            if (replacement != null) {
              bool replaced = false;
              await _serialize(() async {
                if (generation != _selectionGeneration ||
                    _player.currentIndex != failed ||
                    failed >= queue.value.length ||
                    queue.value[failed].id != item.id)
                  return;
                _rearranging = true;
                try {
                  await _playlist.removeAt(failed);
                  await _playlist.insert(failed, replacement);
                  await _player.seek(Duration.zero, index: failed);
                  replaced = true;
                } finally {
                  _rearranging = false;
                }
                _publishCurrentItem();
              });
              if (replaced) unawaited(play());
              return;
            }
          } catch (_) {
            /* One refresh only, then advance. */
          }
        }
        _failedIndices.add(failed);
      }
      final order = _player.effectiveIndices;
      for (final candidate in nextQueueCandidates(
        order,
        failed,
        _failedIndices,
      )) {
        if (generation != _selectionGeneration) return;
        if (NetworkMonitor.instance.offline) {
          final url = await _getTrackUrl(queue.value[candidate]);
          if (url == null) continue;
        }
        try {
          await _player.seek(Duration.zero, index: candidate);
          unawaited(play());
          Fluttertoast.showToast(
            msg: 'Brano non disponibile: passo al successivo',
          );
          return;
        } catch (_) {
          _failedIndices.add(candidate);
        }
      }
      await pause();
      Fluttertoast.showToast(msg: 'Nessun altro brano disponibile');
    } finally {
      _recovering = false;
    }
  }

  Future<void> _addToHistory(MediaItem item) async {
    if (!_player.playing) return;

    // Scrobble to LastFM
    if (_scrobblenautReady && !(_loggedTrackId == item.id)) {
      Logger.root.info('scrobbling track ${item.id} to recently LastFM');
      _loggedTrackId = item.id;
      await _scrobblenaut?.track.scrobble(
        track: item.title,
        artist: item.artist ?? '',
        album: item.album,
      );
    }

    if (cache.history.isNotEmpty && cache.history.last.id == item.id) return;
    Logger.root.info('adding track ${item.id} to recently played history');
    cache.history.add(Track.fromMediaItem(item));
    cache.save();
  }

  //Get queue save file path
  Future<String> _getQueueFilePath() async {
    Directory dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'playback.json');
  }

  //Export queue to JSON
  Future<void> _saveQueueToFile() {
    if (_rearranging || queue.value.isEmpty) return Future.value();
    final snapshot = jsonEncode({
      'index': _player.currentIndex,
      'queue': queue.value.map(MediaItemConverter.mediaItemToMap).toList(),
      'position': _player.position.inMilliseconds,
      'queueSource': (queueSource ?? QueueSource()).toJson(),
      'loopMode': LoopMode.values.indexOf(_player.loopMode),
      'sourceOffset': _sourceOffset,
      'sourceExhausted': _sourceExhausted,
    });
    final next = _queueSave.then((_) async {
      final path = await _getQueueFilePath();
      final temporary = File('$path.tmp');
      await temporary.writeAsString(snapshot, flush: true);
      await temporary.rename(path);
    });
    _queueSave = next.catchError((Object _) {
      Logger.root.warning('Unable to save playback checkpoint');
    });
    return _queueSave;
  }

  //----------------------------------------------------------------------------------------------
  // Start app specific public methods.
  // Candidates for refactoring to "customAction"s to be called from the UI (PlayerHelper class)?
  //----------------------------------------------------------------------------------------------

  Future<void> waitForPlayerInitialization() async {
    await _initialization.timeout(const Duration(seconds: 20));
  }

  Future dispose() async {
    _queueStateSub?.cancel();
    _mediaItemSub?.cancel();
    await stop();
    await _player.dispose();
  }

  //Restore queue & playback info from path
  Future loadQueueFromFile() async {
    Logger.root.info('looking for saved queue file...');
    try {
      File f = File(await _getQueueFilePath());
      if (await f.exists()) {
        Logger.root.info('saved queue file found, loading...');

        try {
          String fileContent = await f.readAsString();
          if (fileContent.isEmpty) {
            Logger.root.warning('saved queue file is empty');
            return;
          }

          Map<String, dynamic> json = jsonDecode(fileContent);
          List<MediaItem> savedQueue = (json['queue'] ?? [])
              .map<MediaItem>((mi) => (MediaItemConverter.mediaItemFromMap(mi)))
              .toList();

          final int lastIndex = json['index'] ?? 0;
          final Duration lastPos = Duration(
            milliseconds: json['position'] ?? 0,
          );
          queueSource = QueueSource.fromJson(json['queueSource'] ?? {});
          _sourceOffset = json['sourceOffset'] ?? savedQueue.length;
          _sourceExhausted = json['sourceExhausted'] ?? false;
          var repeatType = LoopMode.values[(json['loopMode'] ?? 0)];

          await _player.setLoopMode(repeatType);

          // Restore queue & Broadcast
          await _loadQueueAtIndex(savedQueue, lastIndex, position: lastPos);
          Logger.root.info('saved queue loaded from file!');
        } catch (e) {
          Logger.root.severe('Error parsing queue file: $e');
          // Delete corrupted file to prevent future errors
          await f.delete();
          await _loadEmptyPlaylist();
        }
      }
    } catch (e, st) {
      Logger.root.severe('Error loading queue from file', e, st);
      await _loadEmptyPlaylist();
    }
  }

  Future removeSavedQueueFile() async {
    await _queueSave;
    String path = await _getQueueFilePath();
    File f = File(path);
    if (await f.exists()) {
      await f.delete();
      Logger.root.info('saved queue file removed!');
    }
  }

  Future authorizeLastFM() async {
    if (settings.lastFMPassword == null) return;
    String username = settings.lastFMUsername ?? '';
    String password = settings.lastFMPassword ?? '';
    try {
      LastFM lastFM = await LastFM.authenticateWithPasswordHash(
        apiKey: Env.lastFmApiKey,
        apiSecret: Env.lastFmApiSecret,
        username: username,
        passwordHash: password,
      );
      _scrobblenaut = Scrobblenaut(lastFM: lastFM);
      _scrobblenautReady = true;
    } catch (e) {
      Logger.root.severe('Error authorizing LastFM: $e');
      Fluttertoast.showToast(msg: 'Authorization error!'.i18n);
    }
  }

  Future<void> disableLastFM() async {
    _scrobblenaut = null;
    _scrobblenautReady = false;
  }

  Future toggleShuffle() async {
    await setShuffleMode(
      _player.shuffleModeEnabled
          ? AudioServiceShuffleMode.none
          : AudioServiceShuffleMode.all,
    );
  }

  LoopMode getLoopMode() {
    return _player.loopMode;
  }

  //Repeat toggle
  Future changeRepeat() async {
    //Change to next repeat type
    switch (_player.loopMode) {
      case LoopMode.one:
        setRepeatMode(AudioServiceRepeatMode.none);
        break;
      case LoopMode.all:
        setRepeatMode(AudioServiceRepeatMode.one);
        break;
      default:
        setRepeatMode(AudioServiceRepeatMode.all);
        break;
    }
  }

  Future<void> updateQueueQuality() async {
    // Update quality by reconverting all items in the queue to new AudioSources
    if (_player.playing) {
      // Pauze playback if playing (Player seems to crash on some devices otherwise)
      await pause();
      await _loadQueueAtIndex(
        queue.value,
        queueState.queueIndex ?? 0,
        position: _player.position,
      );
      await _player.play();
    } else {
      await _loadQueueAtIndex(
        queue.value,
        queueState.queueIndex ?? 0,
        position: _player.position,
      );
    }
  }

  //Play track from album
  Future playFromAlbum(
    Album album,
    String trackId, {
    int? selectedIndex,
  }) async {
    await playFromTrackList(
      album.tracks ?? [],
      trackId,
      QueueSource(id: album.id, text: album.title, source: 'album'),
      selectedIndex: selectedIndex,
    );
  }

  //Play mix by track
  Future playMix(String trackId, String trackTitle) async {
    List<Track> tracks = await deezerAPI.playMix(trackId);
    if (tracks.isEmpty) {
      Fluttertoast.showToast(msg: 'Nessun brano disponibile');
      return;
    }
    await playFromTrackList(
      tracks,
      tracks[0].id ?? '',
      QueueSource(
        id: trackId,
        text: 'Mix based on'.i18n + ' $trackTitle',
        source: 'mix',
      ),
    );
  }

  //Play from artist top tracks
  Future playFromTopTracks(
    List<Track> tracks,
    String trackId,
    Artist artist, {
    int? selectedIndex,
  }) async {
    await playFromTrackList(
      tracks,
      trackId,
      QueueSource(
        id: artist.id,
        text: 'Top ${artist.name}',
        source: 'topTracks',
      ),
      selectedIndex: selectedIndex,
    );
  }

  Future playFromPlaylist(Playlist playlist, String trackId) async {
    await playFromTrackList(
      playlist.tracks ?? [],
      trackId,
      QueueSource(id: playlist.id, text: playlist.title, source: 'playlist'),
    );
  }

  //Play episode from show, load whole show as queue
  Future playShowEpisode(
    Show show,
    List<ShowEpisode> episodes, {
    int index = 0,
  }) async {
    QueueSource showQueueSource = QueueSource(
      id: show.id,
      text: show.name,
      source: 'show',
    );
    //Generate media items
    List<MediaItem> episodeQueue = episodes
        .map<MediaItem>((e) => e.toMediaItem(show))
        .toList();

    //Load and play
    await _loadQueueAndPlayAtIndex(showQueueSource, episodeQueue, index);
  }

  //Load tracks as queue, play track id, set queue source
  Future playFromTrackList(
    List<Track> tracks,
    String trackId,
    QueueSource trackQueueSource, {
    int? selectedIndex,
  }) async {
    //Generate media items
    List<MediaItem> trackQueue = tracks
        .map<MediaItem>((track) => track.toMediaItem())
        .toList();

    //Load and play
    await _loadQueueAndPlayAtIndex(
      trackQueueSource,
      trackQueue,
      selectedIndex ?? trackQueue.indexWhere((m) => m.id == trackId),
    );
  }

  //Load smart track list as queue, start from beginning
  Future playFromSmartTrackList(SmartTrackList stl) async {
    //Load from API if no tracks
    if ((stl.tracks?.length ?? 0) == 0) {
      if (settings.offlineMode) {
        Fluttertoast.showToast(
          msg: "Offline mode, can't play flow or smart track lists.".i18n,
          gravity: ToastGravity.BOTTOM,
          toastLength: Toast.LENGTH_SHORT,
        );
        return;
      }

      //Flow songs cannot be accessed by smart track list call
      if (stl.id == 'flow') {
        stl.tracks = await deezerAPI.flow(type: stl.flowType);
      } else {
        stl = await deezerAPI.smartTrackList(stl.id ?? '');
      }
    }
    QueueSource queueSource = QueueSource(
      id: stl.id,
      source: (stl.id == 'flow') ? 'flow' : 'smarttracklist',
      text:
          stl.title ??
          ((stl.id == 'flow') ? 'Flow'.i18n : 'Smart track list'.i18n),
    );
    if (stl.tracks == null || stl.tracks!.isEmpty) {
      Fluttertoast.showToast(msg: 'Nessun brano disponibile');
      return;
    }
    await playFromTrackList(
      stl.tracks ?? [],
      stl.tracks?[0].id ?? '',
      queueSource,
    );
  }

  //Start visualizer
  Future startVisualizer() async {
    /* Needs experimental 'visualizer' branch of just_audio
        _player.startVisualizer(enableWaveform: false, enableFft: true, captureRate: 15000, captureSize: 128);
        _visualizerSubscription = _player.visualizerFftStream.listen((event) {
          //Calculate actual values
          List<double> out = [];
          for (int i = 0; i < event.length / 2; i++) {
            int rfk = event[i * 2].toSigned(8);
            int ifk = event[i * 2 + 1].toSigned(8);
            out.add(log(hypot(rfk, ifk) + 1) / 5.2);
          }
          //Visualizer data
          _visualizerController.add(out);
        });
        */
  }

  //Stop visualizer
  Future stopVisualizer() async {
    if (_visualizerSubscription != null) {
      await _visualizerSubscription!.cancel();
      _visualizerSubscription = null;
    }
  }
}

class QueueState {
  static const QueueState empty = QueueState(
    [],
    0,
    [],
    AudioServiceRepeatMode.none,
    AudioServiceShuffleMode.none,
  );

  final List<MediaItem> queue;
  final int? queueIndex;
  final List<int>? shuffleIndices;
  final AudioServiceRepeatMode repeatMode;
  final AudioServiceShuffleMode shuffleMode;

  const QueueState(
    this.queue,
    this.queueIndex,
    this.shuffleIndices,
    this.repeatMode,
    this.shuffleMode,
  );

  bool get hasPrevious =>
      queue.isNotEmpty &&
      (repeatMode != AudioServiceRepeatMode.none ||
          indices.indexOf(queueIndex ?? 0) > 0);
  bool get hasNext =>
      queue.isNotEmpty &&
      (repeatMode != AudioServiceRepeatMode.none ||
          indices.indexOf(queueIndex ?? 0) + 1 < queue.length);

  List<int> get indices =>
      shuffleIndices ?? List.generate(queue.length, (i) => i);
}
