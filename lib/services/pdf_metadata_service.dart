import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:pdfrx/pdfrx.dart';

/// Dati letti dallo spartito durante l'importazione.
class DetectedMetadata {
  const DetectedMetadata({
    this.title,
    this.author,
    this.keySignature,
    this.bpm,
    this.timeSignature,
  });

  final String? title;
  final String? author;
  final String? keySignature;
  final int? bpm;
  final String? timeSignature;

  bool get hasScoreData =>
      keySignature != null || bpm != null || timeSignature != null;
}

typedef PdfTextReader = Future<String> Function(String path);

/// Riconosce titolo, autore, tonalità, tempo e metro dallo spartito.
///
/// Il testo del PDF viene estratto con PDFium (pdfrx); se il PDF è scansionato
/// e non contiene testo, si usano le informazioni del documento e il nome del
/// file. Tutto è best-effort: i campi restano sempre modificabili.
class PdfMetadataService {
  PdfMetadataService._();

  static const int _maxTextChars = 60000;

  static Future<DetectedMetadata> detect({
    required String path,
    required String fileName,
    PdfTextReader? readText,
    bool usePdfText = true,
  }) async {
    var text = '';
    if (usePdfText) {
      try {
        text = await (readText ?? _readPdfText)(path);
      } catch (_) {
        text = '';
      }
    }
    final info = await _readDocumentInfo(path);
    return fromSources(
      text: text,
      fileName: fileName,
      infoTitle: info.title,
      infoAuthor: info.author,
    );
  }

  /// Variante pura, usata anche dai test.
  static DetectedMetadata fromTextAndName(String text, String fileName) {
    return fromSources(text: text, fileName: fileName);
  }

  static DetectedMetadata fromSources({
    required String text,
    required String fileName,
    String? infoTitle,
    String? infoAuthor,
  }) {
    final clean = _prepare(text);
    final stem = _fileStem(fileName);
    final fileParts = _splitFileName(stem);

    final bpm =
        _findBpm(clean) ??
        _findBpm(stem, allowLooseEquals: true) ??
        _tempoWord(clean) ??
        _tempoWord(stem);
    final timeSignature =
        _findMeter(clean) ??
        _findMeter(stem, allowHyphen: true) ??
        _findMeter(clean, allowHyphen: true);
    final keySignature =
        _findKey(clean) ??
        _findKeyFromSignature(clean) ??
        _findKey(stem) ??
        _findKeyFromSignature(stem);
    final title =
        _cleanTitle(infoTitle) ??
        _titleFromText(clean) ??
        _cleanTitle(fileParts.title);
    final author =
        _cleanAuthor(infoAuthor) ??
        _authorFromText(clean) ??
        _cleanAuthor(fileParts.author);

    return DetectedMetadata(
      title: title,
      author: author,
      keySignature: keySignature,
      bpm: bpm,
      timeSignature: timeSignature,
    );
  }

  // --- Estrazione del testo ---------------------------------------------

  static Future<String> _readPdfText(String path) async {
    final document = await PdfDocument.openFile(path);
    try {
      final buffer = StringBuffer();
      final pageCount = math.min(document.pages.length, 3);
      for (var index = 0; index < pageCount; index++) {
        final pageText = await document.pages[index].loadText();
        if (pageText == null) continue;
        buffer.writeln(pageText.fullText);
      }
      return buffer.toString();
    } finally {
      await document.dispose();
    }
  }

  static Future<({String? title, String? author})> _readDocumentInfo(
    String path,
  ) async {
    try {
      final file = File(path);
      final length = await file.length();
      if (length > 25 * 1024 * 1024) {
        return (title: null, author: null);
      }
      final bytes = await file.readAsBytes();
      final raw = latin1.decode(bytes, allowInvalid: true);
      return (
        title: _pdfInfoValue(raw, 'Title'),
        author: _pdfInfoValue(raw, 'Author'),
      );
    } catch (_) {
      return (title: null, author: null);
    }
  }

  static String? _pdfInfoValue(String raw, String key) {
    final pattern = RegExp(
      '/$key\\s*(\\(((?:\\\\.|[^\\\\)])*)\\)|<([0-9A-Fa-f\\s]+)>)',
    );
    final match = pattern.firstMatch(raw);
    if (match == null) return null;

    final literal = match.group(2);
    final hex = match.group(3);
    final value = literal != null
        ? _unescapePdfLiteral(literal)
        : _decodeHexString(hex ?? '');
    final clean = value.replaceAll(RegExp(r'[\x00-\x1F]'), ' ').trim();
    if (clean.isEmpty || clean.length > 200) return null;
    return clean;
  }

  static String _unescapePdfLiteral(String input) {
    final units = <int>[];
    for (var i = 0; i < input.length; i++) {
      final code = input.codeUnitAt(i);
      if (code != 0x5C) {
        units.add(code);
        continue;
      }
      i++;
      if (i >= input.length) break;
      final escaped = input.codeUnitAt(i);
      switch (escaped) {
        case 0x6E:
          units.add(10);
        case 0x72:
          units.add(13);
        case 0x74:
          units.add(9);
        case 0x62:
          units.add(8);
        case 0x66:
          units.add(12);
        case 0x0D:
          if (i + 1 < input.length && input.codeUnitAt(i + 1) == 0x0A) i++;
        case 0x0A:
          break;
        default:
          if (escaped >= 0x30 && escaped <= 0x37) {
            var value = escaped - 0x30;
            var digits = 1;
            while (digits < 3 && i + 1 < input.length) {
              final next = input.codeUnitAt(i + 1);
              if (next < 0x30 || next > 0x37) break;
              i++;
              value = value * 8 + (next - 0x30);
              digits++;
            }
            units.add(value & 0xFF);
          } else {
            units.add(escaped);
          }
      }
    }
    return _decodeUnits(units);
  }

  static String _decodeHexString(String input) {
    final hex = input.replaceAll(RegExp(r'\s+'), '');
    if (hex.isEmpty) return '';
    final padded = hex.length.isOdd ? '${hex}0' : hex;
    final units = <int>[];
    for (var i = 0; i < padded.length; i += 2) {
      units.add(int.parse(padded.substring(i, i + 2), radix: 16));
    }
    return _decodeUnits(units);
  }

  static String _decodeUnits(List<int> units) {
    if (units.length >= 2 && units[0] == 0xFE && units[1] == 0xFF) {
      final codes = <int>[];
      for (var i = 2; i + 1 < units.length; i += 2) {
        codes.add((units[i] << 8) | units[i + 1]);
      }
      return String.fromCharCodes(codes);
    }
    return String.fromCharCodes(units);
  }

  // --- Normalizzazione ---------------------------------------------------

  static String _prepare(String text) {
    var clean = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    clean = clean.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), ' ');
    clean = clean.replaceAll(RegExp(r'[ \t]+'), ' ');
    if (clean.length > _maxTextChars) {
      clean = clean.substring(0, _maxTextChars);
    }
    return clean;
  }

  static String _fileStem(String fileName) {
    var name = fileName.replaceAll('\\', '/');
    final index = name.lastIndexOf('/');
    if (index != -1) name = name.substring(index + 1);
    if (name.toLowerCase().endsWith('.pdf')) {
      name = name.substring(0, name.length - 4);
    }
    return name.trim();
  }

  static ({String title, String? author}) _splitFileName(String stem) {
    final cleaned = stem
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final parts = cleaned
        .split(RegExp(r'\s+[-–—]\s+|\s*\|\s*'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return (title: cleaned, author: null);
    return (title: parts.first, author: parts.length > 1 ? parts[1] : null);
  }

  // --- Tempo -------------------------------------------------------------

  static int? _findBpm(String source, {bool allowLooseEquals = false}) {
    final head = source.length > 4000 ? source.substring(0, 4000) : source;
    final patterns = <RegExp>[
      RegExp(
        r'(?:bpm|m\.?\s*m\.?|metronomo)\s*[:=]?\s*(\d{2,3})',
        caseSensitive: false,
      ),
      RegExp(r'(\d{2,3})\s*(?:bpm)', caseSensitive: false),
      RegExp(r'[♩♪qQ]\s*[=:]\s*(\d{2,3})'),
    ];
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(head)) {
        final value = int.tryParse(match.group(1)!);
        if (value != null && value >= 30 && value <= 300) return value;
      }
    }
    if (allowLooseEquals) {
      final loose = RegExp(r'=\s*(\d{2,3})(?!\d)');
      for (final match in loose.allMatches(head)) {
        final value = int.tryParse(match.group(1)!);
        if (value != null && value >= 40 && value <= 260) return value;
      }
    }
    return null;
  }

  static const Map<String, int> _tempoWords = {
    'grave': 45,
    'largo': 50,
    'lento': 56,
    'larghetto': 60,
    'adagio': 66,
    'andante': 84,
    'andantino': 92,
    'moderato': 100,
    'allegretto': 112,
    'allegro': 132,
    'vivace': 152,
    'presto': 176,
    'prestissimo': 200,
  };

  static int? _tempoWord(String source) {
    final head = source.length > 2000 ? source.substring(0, 2000) : source;
    final lower = head.toLowerCase();
    for (final entry in _tempoWords.entries) {
      if (RegExp('\\b${entry.key}\\b').hasMatch(lower)) {
        return entry.value;
      }
    }
    return null;
  }

  // --- Metro -------------------------------------------------------------

  static final RegExp _meterSlash = RegExp(
    r'(?<![\d/])(\d{1,2})\s*/\s*(\d{1,2})(?![\d/])',
  );
  static final RegExp _meterHyphen = RegExp(
    r'(?<![\d-])(\d{1,2})\s*[-–]\s*(\d{1,2})(?![\d-])',
  );

  static String? _findMeter(String source, {bool allowHyphen = false}) {
    final normalized = source.replaceAll('⁄', '/').replaceAll('∕', '/');

    String? search(RegExp pattern) {
      for (final match in pattern.allMatches(normalized)) {
        final beats = int.tryParse(match.group(1)!);
        final unit = int.tryParse(match.group(2)!);
        if (beats != null &&
            unit != null &&
            beats >= 1 &&
            beats <= 16 &&
            (unit == 2 || unit == 4 || unit == 8 || unit == 16)) {
          return '$beats/$unit';
        }
      }
      return null;
    }

    final slash = search(_meterSlash);
    if (slash != null) return slash;
    if (allowHyphen) {
      final hyphen = search(_meterHyphen);
      if (hyphen != null) return hyphen;
    }

    final lower = normalized.toLowerCase();
    if (lower.contains('common time') || lower.contains('tempo comune')) {
      return '4/4';
    }
    if (lower.contains('cut time') || lower.contains('alla breve')) {
      return '2/2';
    }
    return null;
  }

  // --- Tonalità ----------------------------------------------------------

  static final RegExp _italianKey = RegExp(
    r'\b(do|re|mi|fa|sol|la|si)\s*(#|b|♯|♭)?\s*(maggiore|magg|minore|min)\b',
    caseSensitive: false,
  );
  static final RegExp _englishKey = RegExp(
    r'\b([A-G])\s*(#|b|♯|♭)?\s*(major|minor|maj|min)\b',
    caseSensitive: false,
  );

  static const Map<String, String> _notesFromEnglish = {
    'c': 'Do',
    'd': 'Re',
    'e': 'Mi',
    'f': 'Fa',
    'g': 'Sol',
    'a': 'La',
    'b': 'Si',
  };

  static String? _findKey(String source) {
    final head = source.length > 3000 ? source.substring(0, 3000) : source;
    final normalized = head.replaceAll('♯', '#').replaceAll('♭', 'b');

    final italian = _italianKey.firstMatch(normalized);
    if (italian != null) {
      final note = italian.group(1)!.toLowerCase();
      final mode = italian.group(3)!.toLowerCase().startsWith('magg')
          ? 'maggiore'
          : 'minore';
      return '${note[0].toUpperCase()}${note.substring(1)}'
          '${_accidental(italian.group(2))} $mode';
    }

    final english = _englishKey.firstMatch(normalized);
    if (english != null) {
      final note = _notesFromEnglish[english.group(1)!.toLowerCase()]!;
      final mode = english.group(3)!.toLowerCase().startsWith('maj')
          ? 'maggiore'
          : 'minore';
      return '$note${_accidental(english.group(2))} $mode';
    }
    return null;
  }

  // Armature: 1..7 diesis o bemolli. L'ordine è quello delle quinte.
  static const List<String> _sharpMajorKeys = [
    'Do',
    'Sol',
    'Re',
    'La',
    'Mi',
    'Si',
    'Fa♯',
    'Do♯',
  ];
  static const List<String> _sharpMinorKeys = [
    'La',
    'Mi',
    'Si',
    'Fa♯',
    'Do♯',
    'Sol♯',
    'Re♯',
    'La♯',
  ];
  static const List<String> _flatMajorKeys = [
    'Do',
    'Fa',
    'Si♭',
    'Mi♭',
    'La♭',
    'Re♭',
    'Sol♭',
    'Do♭',
  ];
  static const List<String> _flatMinorKeys = [
    'La',
    'Re',
    'Sol',
    'Do',
    'Fa',
    'Si♭',
    'Mi♭',
    'La♭',
  ];

  static final RegExp _sharpCount = RegExp(
    r'(?<![\d/])([1-7])\s*(?:♯|#|diesis|sharp(?:s)?)(?![#♯\w])',
    caseSensitive: false,
  );
  static final RegExp _flatCount = RegExp(
    r'(?<![\d/])([1-7])\s*(?:♭|bemolle|bemolli|flat(?:s)?)(?![♭\w])',
    caseSensitive: false,
  );

  /// Ricava la tonalità dall'armatura: ad esempio 3 diesis = La maggiore
  /// oppure Fa♯ minore. In assenza di indicazioni di modo sceglie il maggiore.
  static String? _findKeyFromSignature(String source) {
    final head = source.length > 4000 ? source.substring(0, 4000) : source;
    if (head.trim().isEmpty) return null;

    var sharps =
        int.tryParse(_sharpCount.firstMatch(head)?.group(1) ?? '') ?? 0;
    var flats = int.tryParse(_flatCount.firstMatch(head)?.group(1) ?? '') ?? 0;

    if (sharps == 0) {
      final run = RegExp(r'[♯#]{2,7}').firstMatch(head);
      if (run != null) sharps = run.group(0)!.length;
    }
    if (flats == 0) {
      final run = RegExp(r'[♭]{2,7}').firstMatch(head);
      if (run != null) flats = run.group(0)!.length;
    }
    if (sharps < 1 && flats < 1) return null;

    final minor = RegExp(
      r'\b(minore|minor)\b',
      caseSensitive: false,
    ).hasMatch(head);
    final keys = sharps > 0
        ? (minor ? _sharpMinorKeys : _sharpMajorKeys)
        : (minor ? _flatMinorKeys : _flatMajorKeys);
    final count = sharps > 0 ? sharps : flats;
    if (count < 1 || count >= keys.length) return null;
    return '${keys[count]} ${minor ? 'minore' : 'maggiore'}';
  }

  static String _accidental(String? raw) {
    if (raw == null) return '';
    if (raw == '#' || raw == '♯') return '♯';
    return '♭';
  }

  // --- Titolo e autore ---------------------------------------------------

  static final RegExp _meterLine = RegExp(r'^\d{1,2}\s*[/⁄]\s*\d{1,2}$');
  static final RegExp _tempoLine = RegExp(
    r'^[♩♪qQ]?\s*[=:]\s*\d{2,3}(\s*bpm)?$',
    caseSensitive: false,
  );
  static final RegExp _bpmLine = RegExp(
    r'^(?:bpm|m\.?\s*m\.?)\s*[:=]?\s*\d{2,3}$',
    caseSensitive: false,
  );

  static const Set<String> _instrumentWords = {
    'pianoforte',
    'piano',
    'voce',
    'voci',
    'soprano',
    'contralto',
    'tenore',
    'basso',
    'coro',
    'chitarra',
    'flauto',
    'violino',
    'viola',
    'violoncello',
    'tromba',
    'sax',
    'sassofono',
    'batteria',
    'organo',
    'tastiera',
    'archi',
    'ottavino',
    'clarinetto',
    'fagotto',
  };

  static String? _titleFromText(String text) {
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .take(20);
    for (final line in lines) {
      if (_isNoiseLine(line)) continue;
      final withoutLabel = line
          .replaceFirst(
            RegExp(r'^(titolo|title)\s*[:\-–]\s*', caseSensitive: false),
            '',
          )
          .trim();
      if (_looksLikeTitle(withoutLabel)) {
        return _truncate(withoutLabel, 120);
      }
    }
    return null;
  }

  static bool _isNoiseLine(String line) {
    if (line.length > 120) return false;
    if (_meterLine.hasMatch(line) || _tempoLine.hasMatch(line)) return true;
    if (_bpmLine.hasMatch(line)) return true;
    if (RegExp(r'^(pagina|page)\s*\d+', caseSensitive: false).hasMatch(line)) {
      return true;
    }
    if (RegExp(r'^\d+(\s*/\s*\d+)?$').hasMatch(line)) return true;
    if (_findKey(line) != null) return true;
    return false;
  }

  static bool _looksLikeTitle(String value) {
    final trimmed = value.trim();
    if (trimmed.length < 2 || trimmed.length > 120) return false;
    if (!RegExp(r'[A-Za-zÀ-ÿ]').hasMatch(trimmed)) return false;
    if (_meterLine.hasMatch(trimmed) || _tempoLine.hasMatch(trimmed)) {
      return false;
    }
    if (_bpmLine.hasMatch(trimmed)) return false;
    if (RegExp(r'^[\d\s.,]+$').hasMatch(trimmed)) return false;
    return true;
  }

  static String? _cleanTitle(String? raw) {
    if (raw == null) return null;
    var value = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    value = value.replaceFirst(
      RegExp(r'^(titolo|title)\s*[:\-–]\s*', caseSensitive: false),
      '',
    );
    if (!_looksLikeTitle(value)) return null;
    return _truncate(value, 120);
  }

  static String? _authorFromText(String text) {
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    final pattern = RegExp(
      r'^(?:autore|composer|compositore|musica(?:\s+di)?|music\s+by|di|by)\s*[:\-–]?\s+(.+)$',
      caseSensitive: false,
    );
    for (final line in lines) {
      if (line.length > 90) continue;
      final match = pattern.firstMatch(line);
      if (match == null) continue;
      final author = _cleanAuthor(match.group(1));
      if (author != null) return author;
    }
    return null;
  }

  static String? _cleanAuthor(String? raw) {
    if (raw == null) return null;
    var value = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    value = value.replaceFirst(
      RegExp(
        r'^(?:di|by|autore|composer|compositore)\s*[:\-–]?\s*',
        caseSensitive: false,
      ),
      '',
    );
    if (value.length < 2 || value.length > 80) return null;
    if (!RegExp(r'[A-Za-zÀ-ÿ]').hasMatch(value)) return null;
    if (RegExp(r'^[\d\s.,]+$').hasMatch(value)) return null;
    if (_findMeter(value) != null || _findKey(value) != null) return null;
    if (_instrumentWords.contains(value.toLowerCase())) return null;
    return value;
  }

  static String _truncate(String value, int max) =>
      value.length <= max ? value : '${value.substring(0, max - 1)}…';
}
