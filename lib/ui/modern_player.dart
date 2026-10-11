import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../api/definitions.dart';
import '../api/download.dart';
import '../service/audio_service.dart';
import 'cached_image.dart';
import 'lyrics.dart';
import 'menu.dart';
import 'player_screen.dart';

class ModernPlayer extends StatelessWidget {
  final Stream<Duration>? positionStream;
  const ModernPlayer({super.key, this.positionStream});
  @override
  Widget build(BuildContext context) {
    final handler = GetIt.I<AudioPlayerHandler>();
    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      builder: (context, snapshot) {
        final item = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Chiudi player',
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: const Column(
              children: [
                Text(
                  'IN RIPRODUZIONE',
                  style: TextStyle(fontSize: 11, letterSpacing: 2),
                ),
                Text(
                  'Deezer',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            centerTitle: true,
            actions: [
              if (item != null)
                IconButton(
                  tooltip: 'Opzioni brano',
                  icon: const Icon(Icons.more_horiz_rounded),
                  onPressed: () => MenuSheet().defaultTrackMenu(
                    Track.fromMediaItem(item),
                    context: context,
                  ),
                ),
            ],
          ),
          body: item == null
              ? const Center(child: Text('Scegli un brano per iniziare'))
              : SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide =
                          constraints.maxWidth > 650 &&
                          constraints.maxWidth > constraints.maxHeight;
                      final size = math.min(
                        wide
                            ? constraints.maxWidth * .4
                            : constraints.maxWidth - 64,
                        440.0,
                      );
                      final art = Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(
                                context,
                              ).primaryColor.withOpacity(.18),
                              blurRadius: 50,
                              offset: const Offset(0, 20),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: CachedImage(
                            url: item.artUri?.toString() ?? '',
                            width: size,
                            height: size,
                          ),
                        ),
                      );
                      final controls = ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 28),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  item.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    height: 1.15,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  item.artist ?? '',
                                  maxLines: 2,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              _PositionControl(
                                item: item,
                                handler: handler,
                                positionStream: positionStream,
                              ),
                              const SizedBox(height: 12),
                              StreamBuilder<PlaybackState>(
                                stream: handler.playbackState,
                                builder: (context, stateSnapshot) {
                                  final state =
                                      stateSnapshot.data ??
                                      handler.playbackState.value;
                                  return Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      IconButton(
                                        tooltip: 'Riproduzione casuale',
                                        isSelected:
                                            state.shuffleMode ==
                                            AudioServiceShuffleMode.all,
                                        onPressed: handler.toggleShuffle,
                                        icon: const Icon(Icons.shuffle_rounded),
                                        selectedIcon: Icon(
                                          Icons.shuffle_rounded,
                                          color: Theme.of(context).primaryColor,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Brano precedente',
                                        iconSize: 36,
                                        onPressed: handler.skipToPrevious,
                                        icon: const Icon(
                                          Icons.skip_previous_rounded,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 68,
                                        height: 68,
                                        child: FilledButton(
                                          style: FilledButton.styleFrom(
                                            padding: EdgeInsets.zero,
                                            shape: const CircleBorder(),
                                          ),
                                          onPressed: state.playing
                                              ? handler.pause
                                              : handler.play,
                                          child: Icon(
                                            state.playing
                                                ? Icons.pause_rounded
                                                : Icons.play_arrow_rounded,
                                            size: 40,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Brano successivo',
                                        iconSize: 36,
                                        onPressed: handler.skipToNext,
                                        icon: const Icon(
                                          Icons.skip_next_rounded,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Ripetizione',
                                        onPressed: handler.changeRepeat,
                                        icon: Icon(
                                          state.repeatMode ==
                                                  AudioServiceRepeatMode.one
                                              ? Icons.repeat_one_rounded
                                              : Icons.repeat_rounded,
                                          color:
                                              state.repeatMode ==
                                                  AudioServiceRepeatMode.none
                                              ? null
                                              : Theme.of(context).primaryColor,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 28),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 10,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            LyricsScreen(trackId: item.id),
                                      ),
                                    ),
                                    icon: const Icon(Icons.lyrics_rounded),
                                    label: const Text('Testo'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const QueueScreen(),
                                      ),
                                    ),
                                    icon: const Icon(Icons.queue_music_rounded),
                                    label: const Text('Coda'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      final track = Track.fromMediaItem(item);
                                      if (await downloadManager.checkOffline(
                                        track: track,
                                      )) {
                                        if (context.mounted)
                                          MenuSheet().defaultTrackMenu(
                                            track,
                                            context: context,
                                          );
                                      } else {
                                        await downloadManager.addOfflineTrack(
                                          track,
                                          private: true,
                                        );
                                        MenuSheet().showDownloadStartedToast();
                                      }
                                    },
                                    icon: const Icon(Icons.offline_pin_rounded),
                                    label: const Text('Download'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                      );
                      return SingleChildScrollView(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 20),
                            child: wide
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      art,
                                      const SizedBox(width: 24),
                                      Flexible(child: controls),
                                    ],
                                  )
                                : Column(children: [art, controls]),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        );
      },
    );
  }
}

class _PositionControl extends StatefulWidget {
  final MediaItem item;
  final AudioPlayerHandler handler;
  final Stream<Duration>? positionStream;
  const _PositionControl({
    required this.item,
    required this.handler,
    this.positionStream,
  });
  @override
  State<_PositionControl> createState() => _PositionControlState();
}

class _PositionControlState extends State<_PositionControl> {
  double? _drag;
  String _time(Duration value) =>
      '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
  @override
  void didUpdateWidget(covariant _PositionControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) _drag = null;
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(
    stream: widget.positionStream ?? AudioService.position,
    builder: (context, snapshot) {
      final duration = widget.item.duration ?? Duration.zero;
      final max = duration.inMilliseconds.toDouble();
      final value =
          (_drag ?? (snapshot.data ?? Duration.zero).inMilliseconds.toDouble())
              .clamp(0.0, max > 0 ? max : 1.0);
      return Column(
        children: [
          Slider(
            value: value,
            max: max > 0 ? max : 1,
            onChanged: max > 0 ? (v) => setState(() => _drag = v) : null,
            onChangeEnd: max > 0
                ? (v) async {
                    await widget.handler.seek(
                      Duration(milliseconds: v.round()),
                    );
                    if (mounted) setState(() => _drag = null);
                  }
                : null,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_time(Duration(milliseconds: value.round()))),
              Text(_time(duration)),
            ],
          ),
        ],
      );
    },
  );
}
