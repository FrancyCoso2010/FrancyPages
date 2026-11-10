import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/piece.dart';
import '../models/profile.dart';

/// Errore applicativo con un messaggio già pronto per l'utente.
class LibraryException implements Exception {
  const LibraryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PickedPdf {
  const PickedPdf({required this.path, required this.name});

  final String path;
  final String name;
}

class _Library {
  const _Library(this.profiles, this.pieces);

  final List<Profile> profiles;
  final List<Piece> pieces;
}

/// Persistenza di profili e brani.
///
/// La libreria vive nelle preferenze condivise; i PDF restano file nella
/// cartella privata dell'app. Le operazioni di scrittura sono serializzate per
/// non perdere aggiornamenti quando più azioni si sovrappongono.
class LibraryService {
  LibraryService();

  static final LibraryService instance = LibraryService();

  static const String _profilesKey = 'library_profiles_v1';
  static const String _piecesKey = 'library_pieces_v1';
  static const String _legacyFilesKey = 'files';
  static const String _folderName = 'FrancyPages';
  static final RegExp _invalidChars = RegExp(r'[\\/:*?"<>|\x00-\x1F]');

  Future<void> _tail = Future<void>.value();

  Future<T> _locked<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  // --- Lettura e scrittura ----------------------------------------------

  Future<_Library> _readLibrary() async {
    final prefs = await SharedPreferences.getInstance();
    var profiles = _decodeProfiles(prefs.getString(_profilesKey));
    var pieces = _decodePieces(prefs.getString(_piecesKey));
    var dirty = false;

    if (profiles.isEmpty) {
      profiles = [Profile.defaultProfile()];
      dirty = true;
    }

    if (prefs.getString(_piecesKey) == null) {
      pieces = await _migrateLegacyFiles(
        prefs.getString(_legacyFilesKey),
        profiles.first.id,
      );
      dirty = true;
      await prefs.remove(_legacyFilesKey);
    }

    final validIds = profiles.map((profile) => profile.id).toSet();
    final fallbackId = profiles.first.id;
    final normalized = <Piece>[];
    for (final piece in pieces) {
      if (validIds.contains(piece.profileId)) {
        normalized.add(piece);
      } else {
        normalized.add(piece.copyWith(profileId: fallbackId));
        dirty = true;
      }
    }

    if (dirty) {
      await _write(prefs, profiles, normalized);
    }
    return _Library(profiles, normalized);
  }

  Future<void> _write(
    SharedPreferences prefs,
    List<Profile> profiles,
    List<Piece> pieces,
  ) async {
    await prefs.setString(
      _profilesKey,
      jsonEncode(profiles.map((profile) => profile.toJson()).toList()),
    );
    await prefs.setString(
      _piecesKey,
      jsonEncode(pieces.map((piece) => piece.toJson()).toList()),
    );
  }

  static List<Profile> _decodeProfiles(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final result = <Profile>[];
      final seen = <String>{};
      for (final entry in decoded) {
        if (entry is! Map) continue;
        try {
          final profile = Profile.fromJson(Map<String, dynamic>.from(entry));
          if (seen.add(profile.id)) result.add(profile);
        } on FormatException {
          // Profilo corrotto: verrà ignorato.
        }
      }
      return result;
    } on FormatException {
      return [];
    }
  }

  static List<Piece> _decodePieces(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final result = <Piece>[];
      final seen = <String>{};
      for (final entry in decoded) {
        if (entry is! Map) continue;
        try {
          final piece = Piece.fromJson(Map<String, dynamic>.from(entry));
          if (seen.add(piece.id)) result.add(piece);
        } on FormatException {
          // Brano corrotto: verrà ignorato.
        }
      }
      return result;
    } on FormatException {
      return [];
    }
  }

  /// Converte l'elenco dei vecchi PDF in brani del profilo predefinito,
  /// conservando data di aggiunta e ultima pagina letta.
  Future<List<Piece>> _migrateLegacyFiles(String? raw, String profileId) async {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final result = <Piece>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final map = Map<String, dynamic>.from(entry);
        final rawName = map['name'];
        final path = map['path'];
        if (rawName is! String ||
            rawName.trim().isEmpty ||
            path is! String ||
            path.isEmpty) {
          continue;
        }
        var title = _stripPdfExtension(rawName);
        if (title.isEmpty) title = 'Brano';
        var size = 0;
        try {
          size = await File(path).length();
        } on FileSystemException {
          size = 0;
        }
        final rawDate = map['addedAt'];
        final rawPage = map['lastPage'];
        result.add(
          Piece(
            id: Piece.newId(),
            profileId: profileId,
            title: title,
            filePath: path,
            addedAt:
                (rawDate is String ? DateTime.tryParse(rawDate) : null) ??
                DateTime.now(),
            lastPage: rawPage is int && rawPage > 0 ? rawPage : 0,
            sizeBytes: size,
          ),
        );
      }
      return result;
    } on FormatException {
      return [];
    }
  }

  // --- Profili -----------------------------------------------------------

  Future<List<Profile>> loadProfiles() {
    return _locked(() async {
      final data = await _readLibrary();
      return List<Profile>.unmodifiable(data.profiles);
    });
  }

  Future<Profile> addProfile(String rawName) {
    return _locked(() async {
      final data = await _readLibrary();
      final name = rawName.trim();
      if (name.isEmpty) {
        throw const LibraryException('Inserisci un nome per il profilo.');
      }
      if (data.profiles.any(
        (profile) => profile.name.toLowerCase() == name.toLowerCase(),
      )) {
        throw const LibraryException('Esiste già un profilo con questo nome.');
      }

      final profile = Profile(
        id: Piece.newId(),
        name: name,
        colorValue: Profile.colorForIndex(data.profiles.length),
        createdAt: DateTime.now(),
      );
      final prefs = await SharedPreferences.getInstance();
      await _write(prefs, [...data.profiles, profile], data.pieces);
      return profile;
    });
  }

  Future<Profile> renameProfile(Profile profile, String rawName) {
    return _locked(() async {
      final data = await _readLibrary();
      final index = data.profiles.indexWhere((item) => item.id == profile.id);
      if (index == -1) {
        throw const LibraryException('Profilo non trovato.');
      }
      final name = rawName.trim();
      if (name.isEmpty) {
        throw const LibraryException('Inserisci un nome per il profilo.');
      }
      if (data.profiles.any(
        (item) =>
            item.id != profile.id &&
            item.name.toLowerCase() == name.toLowerCase(),
      )) {
        throw const LibraryException('Esiste già un profilo con questo nome.');
      }

      final profiles = List<Profile>.of(data.profiles);
      final renamed = profiles[index].copyWith(name: name);
      profiles[index] = renamed;
      final prefs = await SharedPreferences.getInstance();
      await _write(prefs, profiles, data.pieces);
      return renamed;
    });
  }

  Future<void> deleteProfile(Profile profile) {
    return _locked(() async {
      final data = await _readLibrary();
      if (data.profiles.length <= 1) {
        throw const LibraryException(
          'Non puoi eliminare l\'unico profilo disponibile.',
        );
      }
      if (!data.profiles.any((item) => item.id == profile.id)) {
        throw const LibraryException('Profilo non trovato.');
      }

      final removed = data.pieces
          .where((piece) => piece.profileId == profile.id)
          .toList();
      final profiles = data.profiles
          .where((item) => item.id != profile.id)
          .toList();
      final pieces = data.pieces
          .where((piece) => piece.profileId != profile.id)
          .toList();
      final prefs = await SharedPreferences.getInstance();
      await _write(prefs, profiles, pieces);

      for (final piece in removed) {
        await _deleteFileQuietly(piece.filePath);
      }
    });
  }

  // --- Brani -------------------------------------------------------------

  Future<List<Piece>> loadPieces(String profileId) {
    return _locked(() async {
      final data = await _readLibrary();
      final pieces = data.pieces
          .where((piece) => piece.profileId == profileId)
          .toList();
      pieces.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      return pieces;
    });
  }

  Future<Piece> addPiece(Piece piece) {
    return _locked(() async {
      final data = await _readLibrary();
      if (!data.profiles.any((profile) => profile.id == piece.profileId)) {
        throw const LibraryException('Profilo non trovato.');
      }
      final prefs = await SharedPreferences.getInstance();
      await _write(prefs, data.profiles, [...data.pieces, piece]);
      return piece;
    });
  }

  Future<Piece> updatePiece(Piece piece) {
    return _locked(() async {
      final data = await _readLibrary();
      final index = data.pieces.indexWhere((item) => item.id == piece.id);
      if (index == -1) {
        throw const LibraryException('Brano non trovato.');
      }
      if (!data.profiles.any((profile) => profile.id == piece.profileId)) {
        throw const LibraryException('Profilo non trovato.');
      }
      final pieces = List<Piece>.of(data.pieces);
      pieces[index] = piece;
      final prefs = await SharedPreferences.getInstance();
      await _write(prefs, data.profiles, pieces);
      return piece;
    });
  }

  Future<void> deletePiece(Piece piece) {
    return _locked(() async {
      final data = await _readLibrary();
      final pieces = data.pieces.where((item) => item.id != piece.id).toList();
      if (pieces.length != data.pieces.length) {
        final prefs = await SharedPreferences.getInstance();
        await _write(prefs, data.profiles, pieces);
      }
      await _deleteFileQuietly(piece.filePath);
    });
  }

  Future<void> updateLastPage(String pieceId, int page) {
    if (page < 1) return Future<void>.value();
    return _locked(() async {
      final data = await _readLibrary();
      final index = data.pieces.indexWhere((item) => item.id == pieceId);
      if (index == -1) return;
      final piece = data.pieces[index];
      if (piece.lastPage == page) return;

      final pieces = List<Piece>.of(data.pieces);
      pieces[index] = piece.copyWith(lastPage: page);
      final prefs = await SharedPreferences.getInstance();
      await _write(prefs, data.profiles, pieces);
    });
  }

  Future<void> _deleteFileQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // File già assente: non è un errore per la libreria.
    }
  }

  // --- File PDF ----------------------------------------------------------

  Future<Directory> appDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}$_folderName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static String _baseName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    return index == -1 ? normalized : normalized.substring(index + 1);
  }

  static String _stripPdfExtension(String name) {
    if (name.toLowerCase().endsWith('.pdf')) {
      return name.substring(0, name.length - 4).trim();
    }
    return name.trim();
  }

  /// Rimuove cartelle, estensione e caratteri non validi dal nome file.
  static String _sanitizeFileName(String raw) {
    var name = _baseName(raw).trim();
    name = name.replaceAll(_invalidChars, '_');
    name = _stripPdfExtension(name);
    return name.replaceAll(RegExp(r'^[\s.]+|[\s.]+$'), '');
  }

  Future<String> _uniqueFileName(Directory dir, String base) async {
    final safeBase = base.isEmpty ? 'brano' : base;
    var name = '$safeBase.pdf';
    var counter = 1;
    while (await File('${dir.path}${Platform.pathSeparator}$name').exists()) {
      name = '$safeBase ($counter).pdf';
      counter++;
    }
    return name;
  }

  /// Copia un PDF scelto dall'utente nella libreria privata dell'app.
  Future<File> storePdf({
    required String sourcePath,
    required String preferredName,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const LibraryException('Il file selezionato non esiste più.');
    }
    final dir = await appDirectory();
    final base = _sanitizeFileName(preferredName);
    final name = await _uniqueFileName(dir, base);
    final destination = File('${dir.path}${Platform.pathSeparator}$name');
    try {
      await source.copy(destination.path);
    } on FileSystemException {
      throw const LibraryException(
        'Non è stato possibile copiare il PDF nella libreria.',
      );
    }
    return destination;
  }

  /// Apre il selettore di sistema e restituisce il PDF scelto.
  static Future<PickedPdf?> pickPdf() async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        dialogTitle: 'Scegli lo spartito',
      );
      if (picked == null) return null;
      final path = picked.path;
      if (path == null) {
        throw const LibraryException('Il file selezionato non è accessibile.');
      }
      return PickedPdf(path: path, name: picked.name);
    } catch (error) {
      if (error is LibraryException) rethrow;
      throw LibraryException(
        'Impossibile aprire il selettore dei file: $error',
      );
    }
  }
}
