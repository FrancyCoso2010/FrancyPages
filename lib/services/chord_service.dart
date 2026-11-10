import 'package:flutter/material.dart';

/// Un accordo trovato nello spartito e la sua posizione normalizzata (0..1).
class ChordMark {
  const ChordMark({required this.chord, required this.bounds});

  final String chord;
  final Rect bounds;
}

/// Riconosce gli accordi scritti nel testo del PDF e li trasporta di semitoni.
///
/// Il servizio è puro e testabile: il lettore gli passa i frammenti di testo
/// con i loro rettangoli già normalizzati rispetto alla pagina.
class ChordService {
  ChordService._();

  static const Map<String, int> _pitchClasses = {
    'C': 0,
    'C#': 1,
    'Db': 1,
    'D': 2,
    'D#': 3,
    'Eb': 3,
    'E': 4,
    'F': 5,
    'F#': 6,
    'Gb': 6,
    'G': 7,
    'G#': 8,
    'Ab': 8,
    'A': 9,
    'A#': 10,
    'Bb': 10,
    'B': 11,
  };

  static const Map<String, int> _italianPitches = {
    'Do': 0,
    'Re': 2,
    'Mi': 4,
    'Fa': 5,
    'Sol': 7,
    'La': 9,
    'Si': 11,
  };

  static const Map<String, String> _italianNotes = {
    'do': 'Do',
    're': 'Re',
    'mi': 'Mi',
    'fa': 'Fa',
    'sol': 'Sol',
    'la': 'La',
    'si': 'Si',
  };

  static const List<String> _sharpNames = [
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];

  static const List<String> _flatNames = [
    'C',
    'Db',
    'D',
    'Eb',
    'E',
    'F',
    'Gb',
    'G',
    'Ab',
    'A',
    'Bb',
    'B',
  ];

  static const List<String> _italianSharpNames = [
    'Do',
    'Do#',
    'Re',
    'Re#',
    'Mi',
    'Fa',
    'Fa#',
    'Sol',
    'Sol#',
    'La',
    'La#',
    'Si',
  ];

  static const List<String> _italianFlatNames = [
    'Do',
    'Reb',
    'Re',
    'Mib',
    'Mi',
    'Fa',
    'Solb',
    'Sol',
    'Lab',
    'La',
    'Sib',
    'Si',
  ];

  static final RegExp _rootPattern = RegExp(
    r'^((?:Do|Re|Mi|Fa|Sol|La|Si|[A-G])(?:[#b])?)(.*)$',
    caseSensitive: false,
  );
  static final RegExp _notePattern = RegExp(
    r'^((?:Do|Re|Mi|Fa|Sol|La|Si|[A-G]))([#b]?)$',
    caseSensitive: false,
  );
  static final RegExp _qualityPattern = RegExp(
    r'^(?:(?:maj|min|m|M|dim|aug|sus|add|no|alt|hd|°|ø|Δ|[+-])?'
    r'[0-9]*(?:[#b][0-9]+)*'
    r'(?:(?:sus|add|maj|min|no)[0-9]*)*'
    r'[+-]?)$',
  );
  static final RegExp _tokenPattern = RegExp(
    r'(?:^|[^A-Za-z0-9])'
    r'((?:Do|Re|Mi|Fa|Sol|La|Si|[A-G])(?:[#b♯♭])?'
    r'[A-Za-z0-9#b♯♭°øΔ/+\-]*)(?![A-Za-z0-9])',
    caseSensitive: false,
  );

  static String normalize(String raw) =>
      raw.replaceAll('♯', '#').replaceAll('♭', 'b').trim();

  /// Vero se [raw] è una scrittura di accordo plausibile.
  static bool isChord(String raw) => _split(raw) != null;

  /// Trasporta [chord] di [semitones] semitoni.
  ///
  /// Con [preferFlats] usa i bemolli (utile per tonalità come Fa o Si♭).
  /// Mantiene la notazione originale: italiana (`Fa#-`) o inglese (`F#m`).
  static String? transpose(
    String chord,
    int semitones, {
    bool preferFlats = false,
  }) {
    final parsed = _split(chord);
    if (parsed == null) return null;
    final rootPitch = _pitch(parsed.root);
    if (rootPitch == null) return null;

    final names = parsed.italian
        ? (preferFlats ? _italianFlatNames : _italianSharpNames)
        : (preferFlats ? _flatNames : _sharpNames);
    final root = names[_wrap(rootPitch + semitones)];
    final parsedBass = parsed.bass;
    final bass = parsedBass == null ? null : _pitch(parsedBass);
    if (parsedBass != null && bass == null) return null;

    var bassName = bass == null ? '' : names[_wrap(bass + semitones)];
    if (parsed.bassLower) bassName = bassName.toLowerCase();

    return '$root${parsed.quality}'
        '${bassName.isEmpty ? '' : '/$bassName'}';
  }

  /// Sceglie i bemolli per le tonalità che li usano (es. Fa, Si♭, Re minore).
  static bool preferFlatsForKey(String keySignature) {
    final normalized = normalize(keySignature).toLowerCase().trim();
    if (normalized.isEmpty) return false;
    if (normalized.contains('bemolle') ||
        normalized.contains('bemolli') ||
        normalized.contains('♭')) {
      return true;
    }

    final token = normalized.split(RegExp(r'\s+')).first;
    if (token.contains('b')) return true;

    const flatMajor = {
      'fa',
      'sib',
      'mib',
      'lab',
      'reb',
      'solb',
      'dob',
      'f',
      'bb',
      'eb',
      'ab',
      'db',
      'gb',
      'cb',
    };
    const flatMinor = {
      're',
      'sol',
      'do',
      'fa',
      'sib',
      'mib',
      'lab',
      'd',
      'g',
      'c',
      'f',
      'bb',
      'eb',
      'ab',
    };

    if (flatMajor.contains(token)) return true;
    if (normalized.contains('minore') || normalized.contains('minor')) {
      return flatMinor.contains(token);
    }
    return false;
  }

  /// Trova gli accordi dentro una riga di testo (es. "Intro: C Am7 | F#m7b5").
  ///
  /// Restituisce anche gli indici dei caratteri, così il lettore può ritagliare
  /// il rettangolo esatto del singolo accordo invece di usare tutta la riga.
  static List<({String chord, int start, int end})> findChordsInText(
    String text,
  ) {
    final candidates = <({String chord, int start, int end})>[];
    for (final match in _tokenPattern.allMatches(text)) {
      final value = match.group(1)!;
      final chord = normalize(value);
      if (!isChord(chord)) continue;
      candidates.add((
        chord: chord,
        start: match.end - value.length,
        end: match.end,
      ));
    }

    // In una riga di testo normale una parola come "la" o "mi" non è un
    // accordo. Accettiamo una nota nuda da sola o un accordo con qualità
    // (Fa#-, Si-9, Am7...) anche quando è dentro una riga più lunga.
    if (candidates.length == 1) {
      final token = candidates.single;
      final raw = text.substring(token.start, token.end).trim();
      if (text.trim() != raw && !_isDecorated(raw)) {
        return const <({String chord, int start, int end})>[];
      }
    }
    return candidates;
  }

  /// Estrae gli accordi dai frammenti di testo con i loro rettangoli normalizzati.
  static List<ChordMark> detectFromSpans(
    Iterable<({String text, Rect bounds})> spans,
  ) {
    final marks = <ChordMark>[];
    final seen = <String>{};
    for (final span in spans) {
      final chord = normalize(span.text);
      if (!isChord(chord)) continue;
      final bounds = span.bounds;
      if (bounds.width <= 0 || bounds.height <= 0) continue;
      final key =
          '$chord@${bounds.left.toStringAsFixed(3)}:'
          '${bounds.top.toStringAsFixed(3)}';
      if (!seen.add(key)) continue;
      marks.add(ChordMark(chord: chord, bounds: bounds));
    }
    return marks;
  }

  static bool _isDecorated(String raw) {
    final parsed = _split(raw);
    if (parsed == null) return false;
    if (parsed.quality.isNotEmpty || parsed.bass != null) return true;
    return parsed.root.contains('#') || parsed.root.contains('b');
  }

  static ({
    String root,
    String quality,
    String? bass,
    bool italian,
    bool bassLower,
  })?
  _split(String raw) {
    final value = normalize(raw);
    if (value.isEmpty || value.length > 16) return null;
    if (value.contains(RegExp(r'\s'))) return null;

    final rootMatch = _rootPattern.firstMatch(value);
    if (rootMatch == null) return null;
    final rawRoot = rootMatch.group(1)!;
    final root = _canonicalNote(rawRoot);
    if (root == null) return null;
    final rootLetter = rawRoot.replaceAll(RegExp(r'[#b]$'), '');
    final italian = _italianNotes.containsKey(rootLetter.toLowerCase());

    var rest = rootMatch.group(2)!;
    if (rest == '6/9') {
      return (
        root: root,
        quality: '6/9',
        bass: null,
        italian: italian,
        bassLower: false,
      );
    }

    String? bass;
    var bassLower = false;
    final slash = rest.lastIndexOf('/');
    if (slash != -1) {
      final candidate = rest.substring(slash + 1);
      final canonicalBass = _canonicalNote(candidate);
      if (canonicalBass == null) return null;
      bass = canonicalBass;
      bassLower =
          candidate == candidate.toLowerCase() &&
          candidate != candidate.toUpperCase();
      rest = rest.substring(0, slash);
    }
    if (rest.contains('/')) return null;
    if (rest.isNotEmpty && !_qualityPattern.hasMatch(rest)) return null;
    return (
      root: root,
      quality: rest,
      bass: bass,
      italian: italian,
      bassLower: bassLower,
    );
  }

  static String? _canonicalNote(String raw) {
    final value = normalize(raw);
    final match = _notePattern.firstMatch(value);
    if (match == null) return null;
    final letter = match.group(1)!;
    final accidental = match.group(2)!;
    final canonical =
        _italianNotes[letter.toLowerCase()] ?? letter.toUpperCase();
    return '$canonical$accidental';
  }

  static int? _pitch(String note) {
    final canonical = _canonicalNote(note);
    if (canonical == null) return null;
    final match = _notePattern.firstMatch(canonical);
    if (match == null) return null;
    final letter = match.group(1)!;
    final accidental = match.group(2)!;
    final base = _italianPitches[letter] ?? _pitchClasses[letter];
    if (base == null) return null;
    if (accidental == '#') return _wrap(base + 1);
    if (accidental == 'b') return _wrap(base - 1);
    return base;
  }

  static int _wrap(int value) => ((value % 12) + 12) % 12;
}
