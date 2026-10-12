import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart' as api;
import 'package:refreezer/service/audio_queue_loader.dart';
class TestAudioPlatform extends api.JustAudioPlatform {
  late TestPlayer lastPlayer;
  @override Future<api.AudioPlayerPlatform> init(api.InitRequest request)async{lastPlayer=TestPlayer(request.id);return lastPlayer;}
  @override Future<api.DisposePlayerResponse> disposePlayer(api.DisposePlayerRequest request)async=>api.DisposePlayerResponse();
}
class TestPlayer extends api.AudioPlayerPlatform {
  TestPlayer(super.id);
  final events=StreamController<api.PlaybackEventMessage>.broadcast();
  final requests=<api.LoadRequest>[];
  @override Stream<api.PlaybackEventMessage> get playbackEventMessageStream=>events.stream;
  @override Future<api.LoadResponse> load(api.LoadRequest request)async{
    requests.add(request);
    // Index zero is unavailable: an addAll followed by seek would fail first.
    if((request.initialIndex??0)==0)throw StateError('first source unavailable');
    events.add(api.PlaybackEventMessage(processingState:api.ProcessingStateMessage.ready,
      updateTime:DateTime.now(),updatePosition:request.initialPosition??Duration.zero,
      bufferedPosition:const Duration(seconds:5),duration:const Duration(minutes:3),
      icyMetadata:null,currentIndex:request.initialIndex,androidAudioSessionId:null));
    return api.LoadResponse(duration:const Duration(minutes:3));
  }
  @override Future<api.SetVolumeResponse> setVolume(api.SetVolumeRequest request)async=>api.SetVolumeResponse();
  @override Future<api.SetSpeedResponse> setSpeed(api.SetSpeedRequest request)async=>api.SetSpeedResponse();
  @override Future<api.SetPitchResponse> setPitch(api.SetPitchRequest request)async=>api.SetPitchResponse();
  @override Future<api.SetSkipSilenceResponse> setSkipSilence(api.SetSkipSilenceRequest request)async=>api.SetSkipSilenceResponse();
  @override Future<api.SetLoopModeResponse> setLoopMode(api.SetLoopModeRequest request)async=>api.SetLoopModeResponse();
  @override Future<api.SetShuffleModeResponse> setShuffleMode(api.SetShuffleModeRequest request)async=>api.SetShuffleModeResponse();
  @override Future<api.SetShuffleOrderResponse> setShuffleOrder(api.SetShuffleOrderRequest request)async=>api.SetShuffleOrderResponse();
}
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  test('selected source loads directly even when the first cannot load',()async{
    final previous=api.JustAudioPlatform.instance;final platform=TestAudioPlatform();api.JustAudioPlatform.instance=platform;
    final player=AudioPlayer(handleInterruptions:false,handleAudioSessionActivation:false,androidApplyAudioAttributes:false);
    try{
      final playlist=await loadAudioQueue(player,[
        AudioSource.uri(Uri.parse('http://127.0.0.1:36958/?id=bad')),
        AudioSource.uri(Uri.parse('http://127.0.0.1:36958/?id=good')),
      ],1,position:const Duration(seconds:12));
      expect(playlist.children.length,2);expect(platform.lastPlayer.requests.length,1);
      expect(platform.lastPlayer.requests.single.initialIndex,1);
      expect(platform.lastPlayer.requests.single.initialPosition,const Duration(seconds:12));expect(player.currentIndex,1);
    }finally{await player.dispose();api.JustAudioPlatform.instance=previous;await platform.lastPlayer.events.close();}
  });
}
