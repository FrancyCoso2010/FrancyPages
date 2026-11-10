import 'dart:math';

/// Un brano della libreria: il PDF più i dati che lo descrivono.
class Piece {
  const Piece({
    required this.id,
    required this.profileId,
    required this.title,
    required this.filePath,
    required this.addedAt,
    this.author = '',
    this.keySignature = '',
    this.bpm = 120,
    this.timeSignature = '4/4',
    this.lastPage = 0,
    this.sizeBytes = 0,
  });

  final String id;
  final String profileId;
  final String title;
  final String author;
  final String keySignature;

  /// Battiti al minuto usati dal metronomo. 120 quando lo spartito non lo indica.
  final int bpm;

  /// Indicazione metrica, ad esempio `4/4` o `6/8`.
  final String timeSignature;
  final String filePath;
  final DateTime addedAt;

  /// Ultima pagina letta (1-based). 0 significa "mai aperto".
  final int lastPage;
  final int sizeBytes;

  static String newId() {
    final random = Random();
    final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final salt = random.nextInt(1 << 30).toRadixString(36);
    return '$time-$salt';
  }

  /// Numero di battiti per battuta ricavato dal metro.
  int get beatsPerBar {
    final numerator = int.tryParse(timeSignature.split('/').first);
    if (numerator == null || numerator < 1 || numerator > 16) return 4;
    return numerator;
  }

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String get authorLabel =>
      author.trim().isEmpty ? 'Autore non indicato' : author.trim();

  String get keyLabel =>
      keySignature.trim().isEmpty ? 'Tonalità n.d.' : keySignature.trim();

  Piece copyWith({
    String? profileId,
    String? title,
    String? author,
    String? keySignature,
    int? bpm,
    String? timeSignature,
    String? filePath,
    DateTime? addedAt,
    int? lastPage,
    int? sizeBytes,
  }) {
    return Piece(
      id: id,
      profileId: profileId ?? this.profileId,
      title: title ?? this.title,
      author: author ?? this.author,
      keySignature: keySignature ?? this.keySignature,
      bpm: bpm ?? this.bpm,
      timeSignature: timeSignature ?? this.timeSignature,
      filePath: filePath ?? this.filePath,
      addedAt: addedAt ?? this.addedAt,
      lastPage: lastPage ?? this.lastPage,
      sizeBytes: sizeBytes ?? this.sizeBytes,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'profileId': profileId,
    'title': title,
    'author': author,
    'keySignature': keySignature,
    'bpm': bpm,
    'timeSignature': timeSignature,
    'filePath': filePath,
    'addedAt': addedAt.toIso8601String(),
    'lastPage': lastPage,
    'sizeBytes': sizeBytes,
  };

  factory Piece.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final profileId = json['profileId'];
    final title = json['title'];
    final filePath = json['filePath'];
    if (id is! String ||
        id.isEmpty ||
        profileId is! String ||
        profileId.isEmpty ||
        title is! String ||
        title.trim().isEmpty ||
        filePath is! String ||
        filePath.isEmpty) {
      throw const FormatException('Brano non valido');
    }

    final rawBpm = json['bpm'];
    final rawMeter = json['timeSignature'];
    final rawDate = json['addedAt'];
    final rawLastPage = json['lastPage'];
    final rawSize = json['sizeBytes'];

    return Piece(
      id: id,
      profileId: profileId,
      title: title.trim(),
      author: json['author'] is String ? (json['author'] as String).trim() : '',
      keySignature: json['keySignature'] is String
          ? (json['keySignature'] as String).trim()
          : '',
      bpm: rawBpm is int && rawBpm >= 30 && rawBpm <= 300 ? rawBpm : 120,
      timeSignature: rawMeter is String && _meterPattern.hasMatch(rawMeter)
          ? rawMeter
          : '4/4',
      filePath: filePath,
      addedAt:
          (rawDate is String ? DateTime.tryParse(rawDate) : null) ??
          DateTime.now(),
      lastPage: rawLastPage is int && rawLastPage > 0 ? rawLastPage : 0,
      sizeBytes: rawSize is int && rawSize > 0 ? rawSize : 0,
    );
  }

  static final RegExp _meterPattern = RegExp(r'^\d{1,2}/\d{1,2}$');
}
