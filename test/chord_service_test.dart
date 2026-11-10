import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:francy_pages/services/chord_service.dart';

void main() {
  test('riconosce le scritture di accordo comuni', () {
    for (final chord in [
      'C',
      'Am7',
      'F#m7b5',
      'Bb/D',
      'C6/9',
      'G7sus4',
      'C°',
      'Cø7',
      'Cmaj7#11',
      'A7#9',
      'Cadd9',
      'Do',
      'Rem',
      'Fa#-',
      'Si-9',
      'Fa#-5+',
      'Fa#-6',
      'Fa#-7+',
      'Fa#-7/do#',
      'Fa#-/mi',
      'Si-/Re',
    ]) {
      expect(ChordService.isChord(chord), isTrue, reason: chord);
    }

    for (final notChord in [
      'Ciao',
      'Bella',
      '3/4',
      'Dove',
      'Sole',
      'Am7 test',
      '',
    ]) {
      expect(ChordService.isChord(notChord), isFalse, reason: notChord);
    }
  });

  test('trasporta radice e basso mantenendo la qualità', () {
    expect(ChordService.transpose('C', 2), 'D');
    expect(ChordService.transpose('Am', 3), 'Cm');
    expect(ChordService.transpose('F#m7', -1), 'Fm7');
    expect(ChordService.transpose('C/G', 2), 'D/A');
    expect(ChordService.transpose('Cmaj7', -2, preferFlats: true), 'Bbmaj7');
    expect(ChordService.transpose('C', 1, preferFlats: true), 'Db');
    expect(ChordService.transpose('C', 1), 'C#');
    expect(ChordService.transpose('Fa#-', 2), 'Sol#-');
    expect(ChordService.transpose('Si-9', 2), 'Do#-9');
    expect(ChordService.transpose('Fa#-/mi', 2), 'Sol#-/fa#');
    expect(ChordService.transpose('Si-/Re', 2), 'Do#-/Mi');
    expect(ChordService.transpose('Fa#-6', 2), 'Sol#-6');
    expect(ChordService.transpose('Fa#-7+', 2), 'Sol#-7+');
    expect(ChordService.transpose('Fa#-7/do#', 2), 'Sol#-7/re#');
    expect(ChordService.transpose('H7', 1), isNull);
  });

  test('riconosce e trasporta le qualità comuni', () {
    const cases = {
      'Do': 'Re',
      'Dom': 'Rem',
      'Do-': 'Re-',
      'Do7': 'Re7',
      'Domaj7': 'Remaj7',
      'DoM7': 'ReM7',
      'Do7+': 'Re7+',
      'Do4': 'Re4',
      'Dosus4': 'Resus4',
      'Dosus2': 'Resus2',
      'Dodim': 'Redim',
      'Dodim7': 'Redim7',
      'Doaug': 'Reaug',
      'Do+': 'Re+',
      'Do7sus4': 'Re7sus4',
      'Do9': 'Re9',
      'Do13': 'Re13',
      'Dom7b5': 'Rem7b5',
      'Doø7': 'Reø7',
      'Do°7': 'Re°7',
    };

    for (final entry in cases.entries) {
      expect(ChordService.isChord(entry.key), isTrue, reason: entry.key);
      expect(
        ChordService.transpose(entry.key, 2),
        entry.value,
        reason: entry.key,
      );
    }
  });

  test('sceglie i bemolli per le tonalità opportune', () {
    expect(ChordService.preferFlatsForKey('Fa maggiore'), isTrue);
    expect(ChordService.preferFlatsForKey('Si♭ maggiore'), isTrue);
    expect(ChordService.preferFlatsForKey('Re minore'), isTrue);
    expect(ChordService.preferFlatsForKey('La maggiore'), isFalse);
    expect(ChordService.preferFlatsForKey('Mi minore'), isFalse);
    expect(ChordService.preferFlatsForKey(''), isFalse);
  });

  test('trova gli accordi dentro una riga più lunga', () {
    final found = ChordService.findChordsInText(
      'Intro: C Am7 | F#m7b5 Bb/D, poi Ciao Bella',
    );

    expect(found.map((token) => token.chord), ['C', 'Am7', 'F#m7b5', 'Bb/D']);
    expect(found.first.start, 7);
    expect(found.first.end, 8);
  });

  test('riconosce la notazione italiana e ignora le parole comuni', () {
    final found = ChordService.findChordsInText('Fa#-     Fa#-5+');
    expect(found.map((token) => token.chord), ['Fa#-', 'Fa#-5+']);

    expect(ChordService.findChordsInText('La notte'), isEmpty);
    expect(ChordService.findChordsInText('Mi ami'), isEmpty);
    expect(ChordService.findChordsInText('La'), hasLength(1));
  });

  test('estrae gli accordi dai frammenti con la posizione normalizzata', () {
    final marks = ChordService.detectFromSpans([
      (text: 'C', bounds: const Rect.fromLTWH(0.1, 0.2, 0.05, 0.03)),
      (text: 'Am7', bounds: const Rect.fromLTWH(0.3, 0.2, 0.08, 0.03)),
      (text: 'Bella', bounds: const Rect.fromLTWH(0.5, 0.2, 0.1, 0.03)),
      (text: 'C', bounds: const Rect.fromLTWH(0.1, 0.2, 0.05, 0.03)),
    ]);

    expect(marks, hasLength(2));
    expect(marks.map((mark) => mark.chord), ['C', 'Am7']);
    expect(marks.first.bounds.left, closeTo(0.1, 0.0001));
  });
}
