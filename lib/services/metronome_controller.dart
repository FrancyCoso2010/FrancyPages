import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Genera il click del metronomo come WAV PCM in memoria.
///
/// Una battuta intera viene riprodotta in loop: il tempo resta campionato e
/// preciso invece di dipendere da un timer per ogni battito.
class MetronomeTone {
  MetronomeTone._();

  static const int sampleRate = 44100;

  static Uint8List barWav({
    required int bpm,
    required int beatsPerBar,
    required bool accentFirst,
  }) {
    final safeBpm = bpm < 30 ? 30 : (bpm > 240 ? 240 : bpm);
    final beats = beatsPerBar < 1 ? 1 : (beatsPerBar > 12 ? 12 : beatsPerBar);
    final samplesPerBeat = (sampleRate * 60 / safeBpm).round();
    final totalSamples = samplesPerBeat * beats;
    final samples = Int16List(totalSamples);

    for (var beat = 0; beat < beats; beat++) {
      final accent = accentFirst && beat == 0;
      final frequency = accent ? 1760.0 : 1174.66;
      final duration = (sampleRate * (accent ? 0.055 : 0.04)).round();
      final gain = accent ? 0.6 : 0.38;
      final decay = accent ? 80.0 : 110.0;

      for (var i = 0; i < duration; i++) {
        final index = beat * samplesPerBeat + i;
        if (index >= totalSamples) break;
        final t = i / sampleRate;
        final envelope = math.exp(-t * decay);
        final value = math.sin(2 * math.pi * frequency * t) * envelope * gain;
        samples[index] = (value * 32767).round();
      }
    }

    return _wavBytes(samples);
  }

  static Uint8List _wavBytes(Int16List samples) {
    const channels = 1;
    const bitsPerSample = 16;
    final dataSize = samples.length * 2;
    final bytes = ByteData(44 + dataSize);

    void ascii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    bytes.setUint32(4, 36 + dataSize, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, channels, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(
      28,
      sampleRate * channels * bitsPerSample ~/ 8,
      Endian.little,
    );
    bytes.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little);
    bytes.setUint16(34, bitsPerSample, Endian.little);
    ascii(36, 'data');
    bytes.setUint32(40, dataSize, Endian.little);

    for (var i = 0; i < samples.length; i++) {
      bytes.setInt16(44 + i * 2, samples[i], Endian.little);
    }
    return bytes.buffer.asUint8List();
  }
}

/// Metronomo con BPM, metro e accento configurabili.
class MetronomeController extends ChangeNotifier {
  MetronomeController({
    int bpm = 120,
    int beatsPerBar = 4,
    bool accentFirst = true,
    bool soundEnabled = true,
  }) : _bpm = bpm.clamp(minBpm, maxBpm).toInt(),
       _beatsPerBar = beatsPerBar.clamp(1, 12).toInt() {
    _accentFirst = accentFirst;
    _soundEnabled = soundEnabled;
  }

  static const int minBpm = 30;
  static const int maxBpm = 240;

  int _bpm;
  int _beatsPerBar;
  late bool _accentFirst;
  late bool _soundEnabled;
  bool _isPlaying = false;
  bool _audioUnavailable = false;
  int _currentBeat = 0;
  Timer? _ticker;
  AudioPlayer? _player;
  int _audioToken = 0;

  int get bpm => _bpm;
  int get beatsPerBar => _beatsPerBar;
  bool get accentFirst => _accentFirst;
  bool get soundEnabled => _soundEnabled;
  bool get isPlaying => _isPlaying;
  int get currentBeat => _currentBeat;
  bool get audioUnavailable => _audioUnavailable;

  Duration get beatDuration =>
      Duration(microseconds: (60000000 / _bpm).round());

  Future<void> start() async {
    if (_isPlaying) return;
    _isPlaying = true;
    _currentBeat = 0;
    notifyListeners();
    await _startAudio();
    _startTicker();
    _emitFallback();
  }

  Future<void> stop() async {
    if (!_isPlaying) return;
    _isPlaying = false;
    _ticker?.cancel();
    _ticker = null;
    _currentBeat = 0;
    _audioToken++;
    notifyListeners();
    try {
      await _player?.stop();
    } catch (_) {
      return;
    }
  }

  Future<void> toggle() => _isPlaying ? stop() : start();

  Future<void> setBpm(int value) async {
    final next = value.clamp(minBpm, maxBpm).toInt();
    if (next == _bpm) return;
    _bpm = next;
    notifyListeners();
    if (_isPlaying) {
      _restartTicker();
      await _startAudio();
      _emitFallback();
    }
  }

  Future<void> setBeatsPerBar(int value) async {
    final next = value.clamp(1, 12).toInt();
    if (next == _beatsPerBar) return;
    _beatsPerBar = next;
    _currentBeat = _currentBeat >= next ? 0 : _currentBeat;
    notifyListeners();
    if (_isPlaying) {
      _restartTicker();
      await _startAudio();
    }
  }

  Future<void> setAccentFirst(bool value) async {
    if (value == _accentFirst) return;
    _accentFirst = value;
    notifyListeners();
    if (_isPlaying) await _startAudio();
  }

  Future<void> setSoundEnabled(bool value) async {
    if (value == _soundEnabled) return;
    _soundEnabled = value;
    notifyListeners();
    if (!_isPlaying) return;
    if (value) {
      await _startAudio();
    } else {
      _audioToken++;
      try {
        await _player?.stop();
      } catch (_) {
        return;
      }
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(beatDuration, (_) {
      if (!_isPlaying) return;
      _currentBeat = (_currentBeat + 1) % _beatsPerBar;
      notifyListeners();
      _emitFallback();
    });
  }

  void _restartTicker() {
    if (_isPlaying) _startTicker();
  }

  /// Quando l'audio non è disponibile (o è disattivato) il battito resta
  /// percepibile con un click di sistema e un feedback sul primo tempo.
  void _emitFallback() {
    if (!_isPlaying) return;
    final needsSound = _soundEnabled && _audioUnavailable;
    if (needsSound) {
      unawaited(SystemSound.play(SystemSoundType.click));
    }
    if (_accentFirst && _currentBeat == 0) {
      unawaited(HapticFeedback.mediumImpact());
    }
  }

  Future<void> _startAudio() async {
    if (!_soundEnabled) return;
    final token = ++_audioToken;
    try {
      final player = _player ??= AudioPlayer();
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setSourceBytes(
        MetronomeTone.barWav(
          bpm: _bpm,
          beatsPerBar: _beatsPerBar,
          accentFirst: _accentFirst,
        ),
        mimeType: 'audio/wav',
      );
      if (token != _audioToken || !_isPlaying) return;
      await player.resume();
      _audioUnavailable = false;
    } catch (_) {
      _audioUnavailable = true;
    }
    if (_isPlaying) notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    _isPlaying = false;
    unawaited(_player?.dispose() ?? Future<void>.value());
    super.dispose();
  }
}
