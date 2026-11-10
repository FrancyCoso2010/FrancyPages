import 'package:flutter/material.dart';

/// Un profilo è una libreria separata di brani (chiesa, band, personale…).
class Profile {
  const Profile({
    required this.id,
    required this.name,
    required this.colorValue,
    this.createdAt,
  });

  final String id;
  final String name;
  final int colorValue;
  final DateTime? createdAt;

  static const List<int> palette = [
    0xFF5B4B8A,
    0xFF2E6F5E,
    0xFF8A4B3D,
    0xFF3D5A8A,
    0xFF7A3D6E,
    0xFF8A6B2E,
  ];

  static Profile defaultProfile() {
    return Profile(
      id: 'default',
      name: 'Personale',
      colorValue: palette.first,
      createdAt: DateTime.now(),
    );
  }

  static int colorForIndex(int index) => palette[index % palette.length];

  Color get color => Color(colorValue);

  Profile copyWith({String? name, int? colorValue}) {
    return Profile(
      id: id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': colorValue,
    'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
  };

  factory Profile.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! String || id.isEmpty || name is! String || name.trim().isEmpty) {
      throw const FormatException('Profilo non valido');
    }
    final rawColor = json['color'];
    final rawDate = json['createdAt'];
    return Profile(
      id: id,
      name: name.trim(),
      colorValue: rawColor is int ? rawColor : palette.first,
      createdAt: rawDate is String ? DateTime.tryParse(rawDate) : null,
    );
  }
}
