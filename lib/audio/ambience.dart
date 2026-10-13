import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';

/// audioplayers 封装：循环播放 / 音量 / 选源。
/// ambienceTracks 为空（素材未就位）时静默禁用，不报错。
class Ambience extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  int _index = -1;
  double _volume = 0.5;
  bool _playing = false;

  bool get available => ambienceTracks.isNotEmpty;
  List<AmbienceTrack> get tracks => ambienceTracks;
  int get index => _index;
  double get volume => _volume;
  bool get playing => _playing;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> select(int i) async {
    if (!available || i < 0 || i >= ambienceTracks.length) return;
    _index = i;
    if (_playing) {
      await _player.stop();
      await _playCurrent();
    }
    notifyListeners();
  }

  Future<void> toggle() async {
    if (!available) return;
    if (_playing) {
      await _player.pause();
      _playing = false;
    } else {
      await _playCurrent();
      _playing = true;
    }
    notifyListeners();
  }

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0.0, 1.0);
    await _player.setVolume(_volume);
    notifyListeners();
  }

  Future<void> _playCurrent() async {
    final int i = _index < 0 ? 0 : _index;
    _index = i;
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setVolume(_volume);
    await _player.play(AssetSource(ambienceTracks[i].asset));
  }
}
