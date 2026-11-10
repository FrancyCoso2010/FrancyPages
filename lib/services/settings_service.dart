import 'package:shared_preferences/shared_preferences.dart';

/// Criteri di ordinamento dell'elenco dei brani.
enum SortMode {
  recent('Più recenti'),
  name('Nome (A-Z)');

  const SortMode(this.label);

  final String label;
}

/// Preferenze dell'interfaccia.
///
/// Se lo storage non è disponibile (test, piattaforme senza plugin) si usano
/// i valori predefiniti: una preferenza non deve mai bloccare l'app.
class SettingsService {
  SettingsService._();

  static const String _sortKey = 'sortMode';
  static const String _horizontalSwipeKey = 'horizontalSwipe';
  static const String _tapZonesKey = 'tapZones';
  static const String _swipeEnabledKey = 'swipeEnabled';
  static const String _autoDetectKey = 'autoDetectMetadata';
  static const String _metronomeSoundKey = 'metronomeSound';
  static const String _metronomeAccentKey = 'metronomeAccent';
  static const String _activeProfileKey = 'activeProfileId';

  static Future<T> _read<T>(
    T Function(SharedPreferences prefs) read,
    T fallback,
  ) async {
    try {
      return read(await SharedPreferences.getInstance());
    } catch (_) {
      return fallback;
    }
  }

  static Future<void> _write(
    Future<void> Function(SharedPreferences prefs) write,
  ) async {
    try {
      await write(await SharedPreferences.getInstance());
    } catch (_) {
      return;
    }
  }

  // --- Ordinamento -------------------------------------------------------

  static Future<SortMode> loadSortMode() => _read(
    (prefs) => prefs.getString(_sortKey) == SortMode.name.name
        ? SortMode.name
        : SortMode.recent,
    SortMode.recent,
  );

  static Future<void> saveSortMode(SortMode mode) =>
      _write((prefs) => prefs.setString(_sortKey, mode.name));

  // --- Profilo attivo ----------------------------------------------------

  static Future<String?> loadActiveProfileId() =>
      _read((prefs) => prefs.getString(_activeProfileKey), null);

  static Future<void> saveActiveProfileId(String id) =>
      _write((prefs) => prefs.setString(_activeProfileKey, id));

  // --- Gesti nel lettore -------------------------------------------------

  static Future<bool> loadHorizontalSwipe() =>
      _read((prefs) => prefs.getBool(_horizontalSwipeKey) ?? false, false);

  static Future<void> saveHorizontalSwipe(bool horizontal) =>
      _write((prefs) => prefs.setBool(_horizontalSwipeKey, horizontal));

  static Future<bool> loadTapZones() =>
      _read((prefs) => prefs.getBool(_tapZonesKey) ?? false, false);

  static Future<void> saveTapZones(bool enabled) =>
      _write((prefs) => prefs.setBool(_tapZonesKey, enabled));

  static Future<bool> loadSwipeEnabled() =>
      _read((prefs) => prefs.getBool(_swipeEnabledKey) ?? true, true);

  static Future<void> saveSwipeEnabled(bool enabled) =>
      _write((prefs) => prefs.setBool(_swipeEnabledKey, enabled));

  // --- Lettura dei dati dai PDF -----------------------------------------

  static Future<bool> loadAutoDetect() =>
      _read((prefs) => prefs.getBool(_autoDetectKey) ?? true, true);

  static Future<void> saveAutoDetect(bool enabled) =>
      _write((prefs) => prefs.setBool(_autoDetectKey, enabled));

  // --- Metronomo ---------------------------------------------------------

  static Future<bool> loadMetronomeSound() =>
      _read((prefs) => prefs.getBool(_metronomeSoundKey) ?? true, true);

  static Future<void> saveMetronomeSound(bool enabled) =>
      _write((prefs) => prefs.setBool(_metronomeSoundKey, enabled));

  static Future<bool> loadMetronomeAccent() =>
      _read((prefs) => prefs.getBool(_metronomeAccentKey) ?? true, true);

  static Future<void> saveMetronomeAccent(bool enabled) =>
      _write((prefs) => prefs.setBool(_metronomeAccentKey, enabled));
}
