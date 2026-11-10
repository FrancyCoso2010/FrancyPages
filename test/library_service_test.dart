import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:francy_pages/models/piece.dart';
import 'package:francy_pages/services/library_service.dart';

const MethodChannel _pathProviderChannel = MethodChannel(
  'plugins.flutter.io/path_provider',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late LibraryService library;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('francy_pages_library');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
          return root.path;
        });
    library = LibraryService();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('crea il profilo predefinito e gestisce i brani', () async {
    final profiles = await library.loadProfiles();
    expect(profiles, hasLength(1));
    expect(profiles.single.name, 'Personale');

    final piece = Piece(
      id: Piece.newId(),
      profileId: profiles.single.id,
      title: 'Notturno',
      filePath: '/tmp/notturno.pdf',
      addedAt: DateTime(2026, 3, 1),
      author: 'Chopin',
      keySignature: 'Do minore',
      bpm: 72,
      timeSignature: '3/4',
    );
    await library.addPiece(piece);

    final pieces = await library.loadPieces(profiles.single.id);
    expect(pieces.single.title, 'Notturno');
    expect(pieces.single.beatsPerBar, 3);
    expect(pieces.single.copyWith().author, 'Chopin');

    await library.updateLastPage(piece.id, 4);
    expect((await library.loadPieces(profiles.single.id)).single.lastPage, 4);

    await library.updatePiece(pieces.single.copyWith(title: 'Notturno op. 9'));
    expect(
      (await library.loadPieces(profiles.single.id)).single.title,
      'Notturno op. 9',
    );

    await library.deletePiece(pieces.single);
    expect(await library.loadPieces(profiles.single.id), isEmpty);
  });

  test('profili: aggiunta, rinomina, duplicati e ultimo profilo', () async {
    await library.loadProfiles();

    final band = await library.addProfile('Band');
    expect(band.name, 'Band');

    await expectLater(
      library.addProfile('band'),
      throwsA(isA<LibraryException>()),
    );

    final renamed = await library.renameProfile(band, 'Band di scuola');
    expect(renamed.name, 'Band di scuola');

    await library.deleteProfile(renamed);
    final remaining = await library.loadProfiles();
    expect(remaining, hasLength(1));

    await expectLater(
      library.deleteProfile(remaining.single),
      throwsA(isA<LibraryException>()),
    );
  });

  test('deleteProfile elimina brani e file PDF del profilo', () async {
    final profiles = await library.loadProfiles();
    final band = await library.addProfile('Band');
    final appDir = await library.appDirectory();
    final file = File('${appDir.path}/Brano.pdf');
    await file.writeAsBytes([1, 2, 3]);

    await library.addPiece(
      Piece(
        id: Piece.newId(),
        profileId: band.id,
        title: 'Brano',
        filePath: file.path,
        addedAt: DateTime.now(),
        sizeBytes: 3,
      ),
    );

    await library.deleteProfile(band);

    expect(file.existsSync(), isFalse);
    expect(await library.loadPieces(band.id), isEmpty);
    expect((await library.loadProfiles()).single.id, profiles.single.id);
  });

  test('migra i vecchi PDF in brani del profilo predefinito', () async {
    final appDir = Directory('${root.path}/FrancyPages');
    await appDir.create(recursive: true);
    final file = File('${appDir.path}/Scala.pdf');
    await file.writeAsBytes([1, 2, 3, 4]);

    SharedPreferences.setMockInitialValues({
      'files': jsonEncode([
        {
          'name': 'Scala.pdf',
          'path': file.path,
          'addedAt': DateTime(2026, 2, 3).toIso8601String(),
          'lastPage': 2,
        },
      ]),
    });

    final profiles = await library.loadProfiles();
    final pieces = await library.loadPieces(profiles.single.id);

    expect(pieces, hasLength(1));
    expect(pieces.single.title, 'Scala');
    expect(pieces.single.lastPage, 2);
    expect(pieces.single.sizeBytes, 4);
    expect((await SharedPreferences.getInstance()).getString('files'), isNull);
  });

  test('storePdf copia il file con un nome unico nella libreria', () async {
    final source = File('${root.path}/originale.pdf');
    await source.writeAsBytes([1, 2, 3]);

    final first = await library.storePdf(
      sourcePath: source.path,
      preferredName: 'Scala',
    );
    final second = await library.storePdf(
      sourcePath: source.path,
      preferredName: 'Scala',
    );

    expect(first.path, endsWith('Scala.pdf'));
    expect(second.path, endsWith('Scala (1).pdf'));
    expect(await first.length(), 3);
    expect(await second.length(), 3);
  });
}
