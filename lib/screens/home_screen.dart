import 'dart:async';

import 'package:flutter/material.dart';

import '../models/piece.dart';
import '../models/profile.dart';
import '../services/library_service.dart';
import '../services/settings_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/meta_chip.dart';
import 'pdf_viewer_screen.dart';
import 'piece_details_screen.dart';
import 'settings_screen.dart';

const String _manageProfilesValue = '__manage_profiles__';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.library});

  /// Libreria iniettabile per i test; di norma [LibraryService.instance].
  final LibraryService? library;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  LibraryService get _library => widget.library ?? LibraryService.instance;

  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<String> _query = ValueNotifier<String>('');

  List<Profile> _profiles = const [];
  List<Piece> _pieces = const [];
  String? _activeProfileId;
  bool _isLoading = true;
  String? _loadError;
  SortMode _sortMode = SortMode.recent;
  int _loadRequest = 0;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _restoreSortMode();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _query.dispose();
    super.dispose();
  }

  Profile? get _activeProfile {
    for (final profile in _profiles) {
      if (profile.id == _activeProfileId) return profile;
    }
    return _profiles.isEmpty ? null : _profiles.first;
  }

  Future<void> _restoreSortMode() async {
    final mode = await SettingsService.loadSortMode();
    if (!mounted || mode == _sortMode) return;
    setState(() => _sortMode = mode);
  }

  Future<void> _changeSortMode(SortMode mode) async {
    if (mode == _sortMode) return;
    setState(() => _sortMode = mode);
    await SettingsService.saveSortMode(mode);
  }

  List<Piece> _visiblePieces(String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _pieces
        : _pieces
              .where(
                (piece) =>
                    piece.title.toLowerCase().contains(query) ||
                    piece.author.toLowerCase().contains(query) ||
                    piece.keySignature.toLowerCase().contains(query),
              )
              .toList(growable: false);

    final sorted = List<Piece>.of(filtered);
    if (_sortMode == SortMode.name) {
      sorted.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    } else {
      sorted.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    }
    return sorted;
  }

  Future<void> _loadAll({bool showSpinner = true}) async {
    final request = ++_loadRequest;
    if (showSpinner) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
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
      if (!mounted || request != _loadRequest) return;
      if (stored != active.id) {
        unawaited(SettingsService.saveActiveProfileId(active.id));
      }
      setState(() {
        _profiles = profiles;
        _activeProfileId = active.id;
        _pieces = pieces;
        _isLoading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted || request != _loadRequest) return;
      final message = _messageFor(error);
      if (_pieces.isEmpty) {
        setState(() {
          _loadError = message;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        _showMessage(message, isError: true);
      }
    }
  }

  Future<void> _selectProfile(String id) async {
    if (id == _activeProfileId) return;
    setState(() {
      _activeProfileId = id;
      _pieces = const [];
      _isLoading = true;
      _loadError = null;
    });
    unawaited(SettingsService.saveActiveProfileId(id));
    try {
      final pieces = await _library.loadPieces(id);
      if (!mounted || _activeProfileId != id) return;
      setState(() {
        _pieces = pieces;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted || _activeProfileId != id) return;
      setState(() {
        _isLoading = false;
        _loadError = _messageFor(error);
      });
    }
  }

  static String _messageFor(Object error) {
    if (error is LibraryException) return error.message;
    return 'Si è verificato un errore: $error';
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

  Future<void> _openPiece(Piece piece) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(
          piece: piece,
          onPageChanged: (page) => _updateLastPage(piece.id, page),
        ),
      ),
    );
  }

  void _updateLastPage(String pieceId, int page) {
    if (!mounted || page < 1) return;
    final index = _pieces.indexWhere((piece) => piece.id == pieceId);
    if (index == -1 || _pieces[index].lastPage == page) return;
    setState(() {
      final updated = List<Piece>.of(_pieces);
      updated[index] = updated[index].copyWith(lastPage: page);
      _pieces = updated;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _query.value = '';
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SettingsScreen(library: _library)),
    );
    if (mounted) await _loadAll(showSpinner: false);
  }

  Future<void> _openDetails() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PieceDetailsScreen(library: _library)),
    );
    if (mounted) await _loadAll(showSpinner: false);
  }

  Widget _buildSearchField() {
    return _SearchField(
      controller: _searchController,
      count: _pieces.length,
      onChanged: (value) => _query.value = value,
      onClear: _clearSearch,
    );
  }

  Widget _buildListArea() {
    return ValueListenableBuilder<String>(
      valueListenable: _query,
      builder: (context, query, _) {
        final visible = _visiblePieces(query);
        return _buildList(visible, query);
      },
    );
  }

  Widget _buildList(List<Piece> visible, String query) {
    final accent =
        _activeProfile?.color ?? Theme.of(context).colorScheme.primary;
    return RefreshIndicator(
      onRefresh: () => _loadAll(showSpinner: false),
      child: visible.isEmpty
          ? CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(
                    isSearching: query.trim().isNotEmpty,
                    profileName: _activeProfile?.name ?? 'questo profilo',
                    onClearSearch: _clearSearch,
                    onOpenDetails: _openDetails,
                  ),
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 28),
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final piece = visible[index];
                return _PieceTile(
                  key: ValueKey(piece.id),
                  piece: piece,
                  accentColor: accent,
                  onTap: () => _openPiece(piece),
                );
              },
            ),
    );
  }

  Widget _buildContent() {
    if (_isLoading && _pieces.isEmpty) {
      return const _LoadingState();
    }
    if (_loadError != null && _pieces.isEmpty) {
      return _ErrorState(message: _loadError!, onRetry: _loadAll);
    }

    return Column(
      children: [
        if (_pieces.isNotEmpty) _buildSearchField(),
        Expanded(child: _buildListArea()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = _activeProfile;
    return Scaffold(
      drawer: AppDrawer(
        section: AppSection.brani,
        profileName: profile?.name,
        onOpenDettagli: _openDetails,
        onOpenSettings: _openSettings,
      ),
      appBar: AppBar(
        titleSpacing: 0,
        title: _profiles.isEmpty
            ? const Text('FrancyPages')
            : _ProfileSelector(
                profiles: _profiles,
                selected: profile,
                onSelected: _selectProfile,
                onManage: _openSettings,
              ),
        actions: [
          PopupMenuButton<SortMode>(
            icon: const Icon(Icons.sort),
            tooltip: 'Ordina',
            initialValue: _sortMode,
            onSelected: _changeSortMode,
            itemBuilder: (context) => [
              for (final mode in SortMode.values)
                CheckedPopupMenuItem<SortMode>(
                  value: mode,
                  checked: mode == _sortMode,
                  child: Text(mode.label),
                ),
            ],
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (currentChild, previousChildren) => Stack(
          fit: StackFit.expand,
          children: [...previousChildren, ?currentChild],
        ),
        child: KeyedSubtree(
          key: ValueKey('home-$_isLoading-${_loadError != null}'),
          child: _buildContent(),
        ),
      ),
    );
  }
}

class _ProfileSelector extends StatelessWidget {
  const _ProfileSelector({
    required this.profiles,
    required this.selected,
    required this.onSelected,
    required this.onManage,
  });

  final List<Profile> profiles;
  final Profile? selected;
  final ValueChanged<String> onSelected;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Cambia profilo',
      onSelected: (value) {
        if (value == _manageProfilesValue) {
          onManage();
        } else {
          onSelected(value);
        }
      },
      itemBuilder: (context) => [
        for (final profile in profiles)
          CheckedPopupMenuItem<String>(
            value: profile.id,
            checked: profile.id == selected?.id,
            child: Row(
              children: [
                Icon(Icons.folder_outlined, color: profile.color, size: 18),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: _manageProfilesValue,
          child: Row(
            children: [
              Icon(Icons.settings_outlined, size: 18),
              SizedBox(width: 10),
              Text('Gestisci profili'),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                selected?.name ?? 'FrancyPages',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

class _PieceTile extends StatelessWidget {
  const _PieceTile({
    super.key,
    required this.piece,
    required this.accentColor,
    required this.onTap,
  });

  final Piece piece;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        accentColor.withValues(alpha: 0.24),
                        accentColor.withValues(alpha: 0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    Icons.picture_as_pdf_outlined,
                    color: accentColor,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        piece.title,
                        key: ValueKey('piece-title:${piece.id}'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
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
                          if (piece.keySignature.trim().isNotEmpty)
                            MetaChip(label: piece.keySignature.trim()),
                          MetaChip(label: '${piece.bpm} BPM'),
                          MetaChip(label: piece.timeSignature),
                          if (piece.lastPage > 1)
                            MetaChip(label: 'pag. ${piece.lastPage}'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Icon(
                    Icons.chevron_right,
                    size: 22,
                    color: colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.count,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final int count;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          return TextField(
            controller: controller,
            onChanged: onChanged,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            textInputAction: TextInputAction.search,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: 'Cerca tra $count brani',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: value.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Cancella ricerca',
                      onPressed: onClear,
                    ),
            ),
          );
        },
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.isSearching,
    required this.profileName,
    required this.onClearSearch,
    required this.onOpenDetails,
  });

  final bool isSearching;
  final String profileName;
  final VoidCallback onClearSearch;
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSearching ? Icons.search_off : Icons.library_music_outlined,
              size: 64,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              isSearching
                  ? 'Nessun brano corrisponde alla ricerca.'
                  : 'Nessun brano in "$profileName".\nAggiungi i brani da Dettagli brani.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.outline),
            ),
            if (isSearching) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: onClearSearch,
                child: const Text('Cancella ricerca'),
              ),
            ] else ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onOpenDetails,
                icon: const Icon(Icons.queue_music),
                label: const Text('Vai a Dettagli brani'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Riprova'),
            ),
          ],
        ),
      ),
    );
  }
}
