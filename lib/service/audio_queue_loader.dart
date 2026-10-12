import 'package:just_audio/just_audio.dart';

/// Pass the initial index to the native loader; addAll then seek preloads zero.
Future<ConcatenatingAudioSource> loadAudioQueue(
  AudioPlayer player,
  List<AudioSource> sources,
  int index, {
  Duration position = Duration.zero,
}) async {
  if (index < 0 || index >= sources.length)
    throw RangeError.index(index, sources);
  final playlist = ConcatenatingAudioSource(children: sources);
  await player.setAudioSource(
    playlist,
    initialIndex: index,
    initialPosition: position,
  );
  return playlist;
}
