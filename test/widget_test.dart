import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:francy_pages/main.dart';
import 'package:francy_pages/models/piece.dart';
import 'package:francy_pages/models/profile.dart';
import 'package:francy_pages/screens/home_screen.dart';
import 'package:francy_pages/services/library_service.dart';
import 'package:francy_pages/services/settings_service.dart';

Piece _piece({
  required String id,
  required String profileId,
  required String title,
  String author = 'Autore',
  String key = 'Do maggiore',
  int bpm = 120,
  String meter = '4/4',
  DateTime? addedAt,
  int lastPage = 0,
  int bytes = 1536,
}) {
  return Piece(
    id: id,
    profileId: profileId,
    title: title,
    author: author,
    keySignature: key,
    bpm: bpm,
    timeSignature: meter,
    filePath: '/tmp/$id.pdf',
    addedAt: addedAt ?? DateTime(2026, 1, 2),
    lastPage: lastPage,
    sizeBytes: bytes,
  );
}

Future<LibraryService> _seed(
  List<Piece> Function(String profileId) build,
) async {
  final library = LibraryService();
  final profiles = await library.loadProfiles();
  for (final piece in build(profiles.first.id)) {
    await library.addPiece(piece);
  }
  return library;
}

Widget _app(LibraryService library) {
  return FrancyPagesApp(home: HomeScreen(library: library));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('mostra il profilo attivo e lo stato vuoto', (
    WidgetTester tester,
  ) async {
    final library = await _seed((_) => []);
    await tester.pumpWidget(_app(library));
    await tester.pumpAndSettle();

    expect(find.text('Personale'), findsOneWidget);
    expect(find.textContaining('Nessun brano in'), findsOneWidget);
    expect(find.text('Aggiungi brano'), findsNothing);
    expect(find.text('Vai a Dettagli brani'), findsOneWidget);
  });

  testWidgets('elenca i brani con autore, tonalità, tempo e metro', (
    WidgetTester tester,
  ) async {
    final library = await _seed(
      (profileId) => [
        _piece(
          id: 'p1',
          profileId: profileId,
          title: 'Notturno',
          author: 'Chopin',
          key: 'Do minore',
          bpm: 72,
          meter: '3/4',
          lastPage: 4,
        ),
      ],
    );
    await tester.pumpWidget(_app(library));
    await tester.pumpAndSettle();

    expect(find.text('Notturno'), findsOneWidget);
    expect(find.text('Chopin'), findsOneWidget);
    expect(find.textContaining('72 BPM'), findsOneWidget);
    expect(find.textContaining('3/4'), findsOneWidget);
    expect(find.textContaining('pag. 4'), findsOneWidget);
  });

  testWidgets('la ricerca filtra per titolo, autore e tonalità', (
    WidgetTester tester,
  ) async {
    final library = await _seed(
      (profileId) => [
        _piece(
          id: 'p1',
          profileId: profileId,
          title: 'Notturno',
          author: 'Chopin',
        ),
        _piece(
          id: 'p2',
          profileId: profileId,
          title: 'Scala di Do',
          author: 'Mozart',
        ),
      ],
    );
    await tester.pumpWidget(_app(library));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'chopin');
    await tester.pumpAndSettle();

    expect(find.text('Notturno'), findsOneWidget);
    expect(find.text('Scala di Do'), findsNothing);

    await tester.enterText(find.byType(TextField), 'mozart');
    await tester.pumpAndSettle();

    expect(find.text('Scala di Do'), findsOneWidget);
    expect(find.text('Notturno'), findsNothing);

    await tester.enterText(find.byType(TextField), 'nessuno');
    await tester.pumpAndSettle();

    expect(find.textContaining('Nessun brano corrisponde'), findsOneWidget);
  });

  testWidgets('il menu Ordina riordina l\'elenco per nome', (
    WidgetTester tester,
  ) async {
    final library = await _seed(
      (profileId) => [
        _piece(
          id: 'p1',
          profileId: profileId,
          title: 'Zeta',
          addedAt: DateTime(2026, 3, 1),
        ),
        _piece(
          id: 'p2',
          profileId: profileId,
          title: 'Alfa',
          addedAt: DateTime(2026, 2, 1),
        ),
      ],
    );
    await tester.pumpWidget(_app(library));
    await tester.pumpAndSettle();

    List<String> titles() => tester
        .widgetList<Text>(
          find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'piece-title:',
                ),
          ),
        )
        .map((text) => text.data!)
        .toList();

    expect(titles(), ['Zeta', 'Alfa']);

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: find.text('Nome (A-Z)'),
        matching: find.byType(CheckedPopupMenuItem<SortMode>),
      ),
    );
    await tester.pumpAndSettle();

    expect(titles(), ['Alfa', 'Zeta']);
  });

  testWidgets('in Brani non si aggiungono, modificano o eliminano brani', (
    WidgetTester tester,
  ) async {
    final library = await _seed(
      (profileId) => [_piece(id: 'p1', profileId: profileId, title: 'Scala')],
    );
    await tester.pumpWidget(_app(library));
    await tester.pumpAndSettle();

    expect(find.text('Scala'), findsOneWidget);
    expect(find.byType(Dismissible), findsNothing);
    expect(find.byTooltip('Opzioni'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('Aggiungi brano'), findsNothing);
  });

  testWidgets('mostra l\'errore di caricamento e permette di riprovare', (
    WidgetTester tester,
  ) async {
    final library = _FailingLibrary();
    await tester.pumpWidget(_app(library));
    await tester.pumpAndSettle();

    expect(find.textContaining('Archivio non disponibile'), findsOneWidget);

    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Nessun brano in'), findsOneWidget);
  });

  testWidgets('Dettagli brani mostra solo il profilo attivo', (
    WidgetTester tester,
  ) async {
    final library = LibraryService();
    final profiles = await library.loadProfiles();
    final church = await library.addProfile('Chiesa');
    await library.addPiece(
      _piece(id: 'personale', profileId: profiles.first.id, title: 'Mio brano'),
    );
    await library.addPiece(
      _piece(id: 'chiesa', profileId: church.id, title: 'Inno chiesa'),
    );
    await tester.pumpWidget(_app(library));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dettagli brani'));
    await tester.pumpAndSettle();

    expect(find.text('Mio brano'), findsOneWidget);
    expect(find.text('Inno chiesa'), findsNothing);
    expect(find.textContaining('in Personale'), findsOneWidget);
  });

  testWidgets('apre l\'editor dei dettagli da Dettagli brani', (
    WidgetTester tester,
  ) async {
    final library = await _seed(
      (profileId) => [_piece(id: 'p1', profileId: profileId, title: 'Scala')],
    );
    await tester.pumpWidget(_app(library));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dettagli brani'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scala'));
    await tester.pumpAndSettle();

    expect(find.text('Dettagli brano'), findsOneWidget);
    expect(find.byTooltip('Salva'), findsOneWidget);
    expect(find.text('Tonalità'), findsOneWidget);
  });

  testWidgets('il menu laterale apre i dettagli di tutti i brani', (
    WidgetTester tester,
  ) async {
    final library = await _seed(
      (profileId) => [
        _piece(id: 'p1', profileId: profileId, title: 'Notturno'),
      ],
    );
    await tester.pumpWidget(_app(library));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(find.text('Brani'), findsOneWidget);
    expect(find.text('Dettagli brani'), findsOneWidget);

    await tester.tap(find.text('Dettagli brani'));
    await tester.pumpAndSettle();

    expect(find.text('Dettagli brani'), findsOneWidget);
    expect(find.text('Notturno'), findsOneWidget);
    expect(find.textContaining('Do maggiore'), findsOneWidget);
  });

  testWidgets('apre le impostazioni', (WidgetTester tester) async {
    final library = await _seed((_) => []);
    await tester.pumpWidget(_app(library));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Impostazioni'));
    await tester.pumpAndSettle();

    expect(find.text('Impostazioni'), findsOneWidget);
    expect(find.text('PROFILI'), findsOneWidget);
    expect(find.text('GESTI NEL LETTORE'), findsOneWidget);
  });

  testWidgets('cambia profilo e mostra i brani del profilo scelto', (
    WidgetTester tester,
  ) async {
    final library = LibraryService();
    final profiles = await library.loadProfiles();
    final church = await library.addProfile('Chiesa');
    await library.addPiece(
      _piece(
        id: 'c1',
        profileId: church.id,
        title: 'Inno',
        author: 'Autore',
        key: 'Sol maggiore',
      ),
    );
    await tester.pumpWidget(_app(library));
    await tester.pumpAndSettle();

    expect(find.text('Personale'), findsOneWidget);
    expect(find.text('Inno'), findsNothing);
    expect(profiles, hasLength(1));
    expect(await library.loadProfiles(), hasLength(2));

    await tester.tap(find.byTooltip('Cambia profilo'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: find.text('Chiesa'),
        matching: find.byType(CheckedPopupMenuItem<String>),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Inno'), findsOneWidget);
  });
}

class _FailingLibrary extends LibraryService {
  int _failures = 1;

  @override
  Future<List<Profile>> loadProfiles() {
    if (_failures > 0) {
      _failures--;
      throw const LibraryException('Archivio non disponibile');
    }
    return super.loadProfiles();
  }
}
