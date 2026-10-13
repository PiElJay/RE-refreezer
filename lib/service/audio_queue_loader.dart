import 'package:just_audio/just_audio.dart';

/// Keep additions at the end of the effective queue, including in shuffle mode.
/// Explicit "play next" inserts immediately after the current occurrence.
class QueueShuffleOrder extends DefaultShuffleOrder {
  int? insertAfter;

  @override
  void insert(int index, int count) {
    final current = insertAfter;
    for (var i = 0; i < indices.length; i++) {
      if (indices[i] >= index) indices[i] += count;
    }
    final adjusted = current == null ? null : current + (current >= index ? count : 0);
    final position = adjusted == null ? indices.length : indices.indexOf(adjusted) + 1;
    indices.insertAll(position, List.generate(count, (i) => index + i));
  }
}

Future<void> insertNextAudioSource(
  AudioPlayer player, AudioSource source, QueueShuffleOrder order,
) async {
  final current = player.currentIndex;
  order.insertAfter = current;
  try {
    await player.insertAudioSource(
      ((current ?? -1) + 1).clamp(0, player.audioSources.length), source);
  } finally {
    order.insertAfter = null;
  }
}

/// Pass the selected occurrence to the native loader without loading index zero.
Future<void> loadAudioQueue(
  AudioPlayer player,
  List<AudioSource> sources,
  int index, {
  Duration position = Duration.zero,
  ShuffleOrder? shuffleOrder,
}) async {
  if (index < 0 || index >= sources.length) throw RangeError.index(index, sources);
  await player.setAudioSources(sources,
    initialIndex: index, initialPosition: position, shuffleOrder: shuffleOrder);
}
