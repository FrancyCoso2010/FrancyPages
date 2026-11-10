import 'dart:async';

import 'package:flutter/material.dart';

import '../models/piece.dart';
import '../models/profile.dart';
import '../services/library_service.dart';
import '../services/pdf_metadata_service.dart';
import '../services/settings_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/meta_chip.dart';
import 'piece_editor_screen.dart';
import 'settings_screen.dart';

enum _DetailAction { edit, delete }

class PieceDetailsScreen extends StatefulWidget {
  const PieceDetailsScreen({super.key, this.library});

  final LibraryService? library;

  @override
  State<PieceDetailsScreen> createState() => _PieceDetailsScreenState();
}

class _PieceDetailsScreenState extends State<PieceDetailsScreen> {
  LibraryService get _library => widget.library ?? LibraryService.instance;

  List<Profile> _profiles = const [];
  List<Piece> _pieces = const [];
  Map<String, Profile> _profilesById = const {};
  String? _activeProfileId;
  bool _isLoading = true;
  bool _isBusy = false;
  String? _error;
  bool _analysisDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final profiles = await _library.loadProfiles();
      if (profiles.isEmpty) {
        throw const LibraryException('Nessun profilo disponibile.');
      }
      final stored = await SettingsService.loadActiveProfileId();
      final active = profiles.firstWhere(
        (profile) => profile.id == stored,
        orElse: () => profiles.first,
      );
      final pieces = await _library.loadPieces(active.id);
      pieces.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _profilesById = {for (final profile in profiles) profile.id: profile};
        _activeProfileId = active.id;
        _pieces = pieces;
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

  void _showMessage(String message, {bool isError = false}) {
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? theme.colorScheme.error : null,
        ),
      );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SettingsScreen(library: _library)),
    );
    if (mounted) await _load();
  }

  Future<void> _addPiece() async {
    if (_isBusy) return;
    if (_profiles.isEmpty) {
      _showMessage('Nessun profilo disponibile.', isError: true);
      return;
    }
    final profile = _profiles.firstWhere(
      (item) => item.id == _activeProfileId,
      orElse: () => _profiles.first,
    );

    PickedPdf? picked;
    try {
      picked = await LibraryService.pickPdf();
    } catch (error) {
      if (mounted) {
        _showMessage(
          error is LibraryException ? error.message : '$error',
          isError: true,
        );
      }
      return;
    }
    if (picked == null || !mounted) return;

    setState(() => _isBusy = true);
    DetectedMetadata? detected;
    final autoDetect = await SettingsService.loadAutoDetect();
    if (autoDetect && mounted) {
      _showAnalysisDialog();
      try {
        detected = await PdfMetadataService.detect(
          path: picked.path,
          fileName: picked.name,
        );
      } catch (_) {
        detected = null;
      } finally {
        _dismissAnalysisDialog();
      }
    }
    if (!mounted) return;
    setState(() => _isBusy = false);

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PieceEditorScreen(
          library: _library,
          profiles: _profiles,
          profileId: profile.id,
          sourcePdfPath: picked!.path,
          sourceFileName: picked.name,
          detected: detected,
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  void _showAnalysisDialog() {
    if (_analysisDialogOpen) return;
    _analysisDialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DetailsAnalysisDialog(),
    );
  }

  void _dismissAnalysisDialog() {
    if (!_analysisDialogOpen || !mounted) return;
    _analysisDialogOpen = false;
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _openEditor(Piece piece) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PieceEditorScreen(
          library: _library,
          profiles: _profiles,
          profileId: piece.profileId,
          piece: piece,
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _delete(Piece piece) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elimina brano'),
        content: Text('Vuoi eliminare definitivamente "${piece.title}"?'),
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
      await _library.deletePiece(piece);
      if (!mounted) return;
      _showMessage('Brano eliminato');
      await _load();
    } catch (error) {
      if (mounted) {
        _showMessage(
          error is LibraryException ? error.message : '$error',
          isError: true,
        );
      }
    }
  }

  Future<void> _showOptions(Piece piece) async {
    final action = await showModalBottomSheet<_DetailAction>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  piece.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text('${piece.authorLabel} • ${piece.keyLabel}'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Modifica dettagli'),
                onTap: () => Navigator.pop(context, _DetailAction.edit),
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: colorScheme.error),
                title: Text(
                  'Elimina',
                  style: TextStyle(color: colorScheme.error),
                ),
                onTap: () => Navigator.pop(context, _DetailAction.delete),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _DetailAction.edit:
        await _openEditor(piece);
      case _DetailAction.delete:
        await _delete(piece);
    }
  }

  Widget _buildEmpty() {
    final colorScheme = Theme.of(context).colorScheme;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.queue_music, size: 64, color: colorScheme.outline),
                  const SizedBox(height: 16),
                  Text(
                    'Nessun brano in "${_profilesById[_activeProfileId]?.name ?? 'questo profilo'}".\nAggiungi uno spartito per compilare titolo, autore, tonalità e tempo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colorScheme.outline),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _isBusy ? null : _addPiece,
                    icon: const Icon(Icons.add),
                    label: const Text('Aggiungi brano'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildList() {
    if (_pieces.isEmpty) return _buildEmpty();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 100),
        itemCount: _pieces.length,
        itemBuilder: (context, index) {
          final piece = _pieces[index];
          return _DetailTile(
            key: ValueKey(piece.id),
            piece: piece,
            profile: _profilesById[piece.profileId],
            onTap: () => _openEditor(piece),
            onOptions: () => _showOptions(piece),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: AppDrawer(
        section: AppSection.dettagli,
        profileName: _profilesById[_activeProfileId]?.name ?? 'Profilo attivo',
        onOpenBrani: () => Navigator.of(context).pop(),
        onOpenSettings: _openSettings,
      ),
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Dettagli brani'),
            Text(
              '${_pieces.length} brani in ${_profilesById[_activeProfileId]?.name ?? 'questo profilo'}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Aggiorna',
            onPressed: _isLoading ? null : _load,
          ),
        ],
      ),
      body: _isLoading && _pieces.isEmpty
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
          : _buildList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isBusy || _profiles.isEmpty ? null : _addPiece,
        icon: _isBusy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: Text(_isBusy ? 'Analisi…' : 'Aggiungi brano'),
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({
    super.key,
    required this.piece,
    required this.profile,
    required this.onTap,
    required this.onOptions,
  });

  final Piece piece;
  final Profile? profile;
  final VoidCallback onTap;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = profile?.color ?? colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.music_note, color: accent, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        piece.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        piece.authorLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          MetaChip(label: piece.keyLabel),
                          MetaChip(label: '${piece.bpm} BPM'),
                          MetaChip(label: piece.timeSignature),
                          if (profile != null)
                            MetaChip(label: profile!.name, color: accent),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'Opzioni dettagli',
                  onPressed: onOptions,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailsAnalysisDialog extends StatelessWidget {
  const _DetailsAnalysisDialog();

  @override
  Widget build(BuildContext context) {
    return const AlertDialog(
      content: SizedBox(
        width: 280,
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: 20),
            Expanded(
              child: Text(
                'Analisi dello spartito…\nCerco titolo, autore, tonalità, tempo e accordi.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
