import 'dart:async';

import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../services/library_service.dart';
import '../services/settings_service.dart';

enum _ProfileAction { rename, delete }

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.library});

  final LibraryService? library;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  LibraryService get _library => widget.library ?? LibraryService.instance;

  List<Profile> _profiles = const [];
  Map<String, int> _counts = const {};
  bool _isLoading = true;
  String? _error;

  bool _horizontalSwipe = false;
  bool _swipeEnabled = true;
  bool _tapZones = false;
  bool _autoDetect = true;
  bool _metronomeSound = true;
  bool _metronomeAccent = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final profiles = await _library.loadProfiles();
      final counts = <String, int>{};
      for (final profile in profiles) {
        counts[profile.id] = (await _library.loadPieces(profile.id)).length;
      }

      final horizontal = await SettingsService.loadHorizontalSwipe();
      final swipeEnabled = await SettingsService.loadSwipeEnabled();
      final tapZones = await SettingsService.loadTapZones();
      final autoDetect = await SettingsService.loadAutoDetect();
      final metroSound = await SettingsService.loadMetronomeSound();
      final metroAccent = await SettingsService.loadMetronomeAccent();

      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _counts = counts;
        _horizontalSwipe = horizontal;
        _swipeEnabled = swipeEnabled;
        _tapZones = tapZones;
        _autoDetect = autoDetect;
        _metronomeSound = metroSound;
        _metronomeAccent = metroAccent;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = error is LibraryException
            ? error.message
            : 'Si è verificato un errore: $error';
      });
    }
  }

  void _showError(Object error) {
    final message = error is LibraryException
        ? error.message
        : 'Si è verificato un errore: $error';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
  }

  Future<String?> _promptName({
    required String title,
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nome profilo'),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _addProfile() async {
    final name = await _promptName(title: 'Nuovo profilo');
    if (name == null || !mounted) return;
    try {
      await _library.addProfile(name);
      await _load();
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _renameProfile(Profile profile) async {
    final name = await _promptName(
      title: 'Rinomina profilo',
      initial: profile.name,
    );
    if (name == null || !mounted) return;
    try {
      await _library.renameProfile(profile, name);
      await _load();
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _deleteProfile(Profile profile) async {
    final count = _counts[profile.id] ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elimina profilo'),
        content: Text(
          count == 0
              ? 'Vuoi eliminare il profilo "${profile.name}"?'
              : 'Vuoi eliminare il profilo "${profile.name}" e i suoi $count brani?\nI PDF verranno rimossi dal dispositivo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _library.deleteProfile(profile);
      await _load();
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  void _setHorizontalSwipe(bool horizontal) {
    setState(() => _horizontalSwipe = horizontal);
    unawaited(SettingsService.saveHorizontalSwipe(horizontal));
  }

  void _setSwipeEnabled(bool enabled) {
    setState(() => _swipeEnabled = enabled);
    unawaited(SettingsService.saveSwipeEnabled(enabled));
  }

  void _setTapZones(bool enabled) {
    setState(() => _tapZones = enabled);
    unawaited(SettingsService.saveTapZones(enabled));
  }

  void _setAutoDetect(bool enabled) {
    setState(() => _autoDetect = enabled);
    unawaited(SettingsService.saveAutoDetect(enabled));
  }

  void _setMetronomeSound(bool enabled) {
    setState(() => _metronomeSound = enabled);
    unawaited(SettingsService.saveMetronomeSound(enabled));
  }

  void _setMetronomeAccent(bool enabled) {
    setState(() => _metronomeAccent = enabled);
    unawaited(SettingsService.saveMetronomeAccent(enabled));
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _buildProfiles() {
    final children = <Widget>[];
    for (var index = 0; index < _profiles.length; index++) {
      final profile = _profiles[index];
      if (index > 0) children.add(const Divider(height: 1));
      children.add(
        ListTile(
          leading: CircleAvatar(
            backgroundColor: profile.color,
            foregroundColor: Colors.white,
            child: Text(
              profile.name.isEmpty
                  ? '?'
                  : profile.name.substring(0, 1).toUpperCase(),
            ),
          ),
          title: Text(profile.name),
          subtitle: Text('${_counts[profile.id] ?? 0} brani'),
          trailing: PopupMenuButton<_ProfileAction>(
            tooltip: 'Opzioni profilo',
            onSelected: (action) {
              switch (action) {
                case _ProfileAction.rename:
                  _renameProfile(profile);
                case _ProfileAction.delete:
                  _deleteProfile(profile);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _ProfileAction.rename,
                child: Text('Rinomina'),
              ),
              PopupMenuItem(
                value: _ProfileAction.delete,
                child: Text('Elimina'),
              ),
            ],
          ),
        ),
      );
    }
    if (children.isNotEmpty) children.add(const Divider(height: 1));
    children.add(
      ListTile(
        leading: const Icon(Icons.add),
        title: const Text('Nuovo profilo'),
        onTap: _addProfile,
      ),
    );
    return _card(children);
  }

  Widget _buildGestures() {
    return _card([
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Direzione di scorrimento',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 10),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Verticale'),
                  icon: Icon(Icons.swap_vert),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Orizzontale'),
                  icon: Icon(Icons.swap_horiz),
                ),
              ],
              selected: {_horizontalSwipe},
              onSelectionChanged: (selection) =>
                  _setHorizontalSwipe(selection.first),
            ),
          ],
        ),
      ),
      const Divider(height: 1),
      SwitchListTile(
        title: const Text('Scorrimento a swipe'),
        subtitle: const Text('Cambia pagina trascinando lo spartito.'),
        value: _swipeEnabled,
        onChanged: _setSwipeEnabled,
      ),
      const Divider(height: 1),
      SwitchListTile(
        title: const Text('Cambio pagina ai lati'),
        subtitle: const Text(
          'Tocca il bordo sinistro o destro per la pagina precedente o successiva.',
        ),
        value: _tapZones,
        onChanged: _setTapZones,
      ),
    ]);
  }

  Widget _buildMetronome() {
    return _card([
      SwitchListTile(
        title: const Text('Suono del metronomo'),
        subtitle: const Text(
          'Se disattivato restano il battito visivo e il feedback sul primo tempo.',
        ),
        value: _metronomeSound,
        onChanged: _setMetronomeSound,
      ),
      const Divider(height: 1),
      SwitchListTile(
        title: const Text('Accentua il primo battito'),
        subtitle: const Text(
          'Click più acuto e feedback all\'inizio di ogni battuta.',
        ),
        value: _metronomeAccent,
        onChanged: _setMetronomeAccent,
      ),
    ]);
  }

  Widget _buildLibrarySettings() {
    return _card([
      SwitchListTile(
        title: const Text('Riconosci i dati dallo spartito'),
        subtitle: const Text(
          'All\'importazione leggo titolo, autore, tonalità, tempo e metro dal PDF. '
          'Se manca il tempo uso 120 BPM e 4/4.',
        ),
        value: _autoDetect,
        onChanged: _setAutoDetect,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 56),
                    const SizedBox(height: 16),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Riprova'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _sectionTitle('PROFILI'),
                _buildProfiles(),
                _sectionTitle('GESTI NEL LETTORE'),
                _buildGestures(),
                _sectionTitle('METRONOMO'),
                _buildMetronome(),
                _sectionTitle('LIBRERIA'),
                _buildLibrarySettings(),
                _sectionTitle('INFORMAZIONI'),
                _card([
                  const ListTile(
                    leading: Icon(Icons.picture_as_pdf_outlined),
                    title: Text('FrancyPages'),
                    subtitle: Text(
                      'Versione 1.0.0\nLibreria personale di spartiti con lettore e metronomo.',
                    ),
                    isThreeLine: true,
                  ),
                ]),
              ],
            ),
    );
  }
}
