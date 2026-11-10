import 'package:flutter_test/flutter_test.dart';

import 'package:francy_pages/services/pdf_metadata_service.dart';

void main() {
  test('legge tempo, metro, tonalità, titolo e autore dal testo', () {
    final result = PdfMetadataService.fromTextAndName(
      'Notturno\nAutore: F. Chopin\n♩ = 72\n3/4\nLa minore',
      'notturno.pdf',
    );

    expect(result.title, 'Notturno');
    expect(result.author, 'F. Chopin');
    expect(result.bpm, 72);
    expect(result.timeSignature, '3/4');
    expect(result.keySignature, 'La minore');
  });

  test('riconosce il tempo da BPM, M.M. e indicazioni italiane', () {
    expect(PdfMetadataService.fromTextAndName('BPM: 96', 'x.pdf').bpm, 96);
    expect(PdfMetadataService.fromTextAndName('M.M. 108', 'x.pdf').bpm, 108);
    expect(PdfMetadataService.fromTextAndName('Allegro', 'x.pdf').bpm, 132);
  });

  test('riconosce tonalità inglesi e italiane', () {
    expect(
      PdfMetadataService.fromTextAndName(
        'Sonata in Bb major',
        'x.pdf',
      ).keySignature,
      'Si♭ maggiore',
    );
    expect(
      PdfMetadataService.fromTextAndName(
        'Cantabile in do# minore',
        'x.pdf',
      ).keySignature,
      'Do♯ minore',
    );
  });

  test('ricava la tonalità dal numero di diesis o bemolli', () {
    expect(
      PdfMetadataService.fromTextAndName('3 diesis', 'x.pdf').keySignature,
      'La maggiore',
    );
    expect(
      PdfMetadataService.fromTextAndName('Armatura: 3♯', 'x.pdf').keySignature,
      'La maggiore',
    );
    expect(
      PdfMetadataService.fromTextAndName('2 bemolli', 'x.pdf').keySignature,
      'Si♭ maggiore',
    );
    expect(
      PdfMetadataService.fromTextAndName('4 flats', 'x.pdf').keySignature,
      'La♭ maggiore',
    );
    expect(
      PdfMetadataService.fromTextAndName(
        '3 diesis\nFa# minore',
        'x.pdf',
      ).keySignature,
      'Fa♯ minore',
    );
  });

  test('senza testo usa nome file per titolo e autore', () {
    final result = PdfMetadataService.fromTextAndName(
      '',
      'Notturno - Chopin.pdf',
    );

    expect(result.title, 'Notturno');
    expect(result.author, 'Chopin');
    expect(result.bpm, isNull);
    expect(result.timeSignature, isNull);
  });

  test('metro e tempo anche nel nome file', () {
    final result = PdfMetadataService.fromTextAndName(
      '',
      'Marcia - 3-4 - 120 bpm.pdf',
    );

    expect(result.timeSignature, '3/4');
    expect(result.bpm, 120);
  });

  test('non scambia un anno per un metro', () {
    expect(
      PdfMetadataService.fromTextAndName(
        'FrancyPages 2026/2027',
        'x.pdf',
      ).timeSignature,
      isNull,
    );
  });

  test('senza indicazioni non inventa tempo né tonalità', () {
    final result = PdfMetadataService.fromTextAndName(
      'Spartito senza indicazioni',
      'brano.pdf',
    );

    expect(result.bpm, isNull);
    expect(result.timeSignature, isNull);
    expect(result.keySignature, isNull);
    expect(result.hasScoreData, isFalse);
  });
}
