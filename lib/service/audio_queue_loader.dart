import 'package:just_audio/just_audio.dart';

/// Pass the initial index to the native loader; addAll then seek preloads zero.
Future<ConcatenatingAudioSource> loadAudioQueue(
  AudioPlayer player,
  ConcatenatingAudioSource playlist,
  int index, {
  Duration position = Duration.zero,
}) async {
  if (index < 0 || index >= playlist.children.length)
    throw RangeError.index(index, playlist.children);
  await player.setAudioSource(
    playlist,
    initialIndex: index,
    initialPosition: position,
  );
  return playlist;
}
