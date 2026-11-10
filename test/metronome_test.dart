import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:francy_pages/services/metronome_controller.dart';

void main() {
  test('genera un WAV PCM valido lungo una battuta', () {
    final bytes = MetronomeTone.barWav(
      bpm: 120,
      beatsPerBar: 4,
      accentFirst: true,
    );
    final data = ByteData.sublistView(bytes);

    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    expect(data.getUint16(20, Endian.little), 1);
    expect(data.getUint16(22, Endian.little), 1);
    expect(data.getUint32(24, Endian.little), MetronomeTone.sampleRate);
    expect(data.getUint16(34, Endian.little), 16);

    final samplesPerBeat = (MetronomeTone.sampleRate * 60 / 120).round();
    expect(data.getUint32(40, Endian.little), samplesPerBeat * 4 * 2);
  });

  test('limita BPM e battiti e calcola la durata del battito', () async {
    final controller = MetronomeController(bpm: 500, beatsPerBar: 99);
    addTearDown(controller.dispose);

    expect(controller.bpm, MetronomeController.maxBpm);
    expect(controller.beatsPerBar, 12);

    await controller.setBpm(10);
    expect(controller.bpm, MetronomeController.minBpm);

    await controller.setBpm(60);
    expect(controller.beatDuration, const Duration(seconds: 1));
    expect(controller.isPlaying, isFalse);
    expect(controller.currentBeat, 0);
  });
}
