import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/piece.dart';
import '../services/chord_service.dart';
import '../services/library_service.dart';
import '../services/metronome_controller.dart';
import '../services/settings_service.dart';

enum _ViewerAction { goToPage, toggleDirection, retry }

class PdfViewerScreen extends StatefulWidget {
  const PdfViewerScreen({super.key, required this.piece, this.onPageChanged});

  final Piece piece;

  /// Chiamato con la pagina corrente (1-based) a ogni cambio pagina.
  final ValueChanged<int>? onPageChanged;

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen>
    with WidgetsBindingObserver {
  final PdfViewerController _controller = PdfViewerController();
  final ValueNotifier<int> _pageNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _transpose = ValueNotifier<int>(0);
  final ValueNotifier<bool> _showChords = ValueNotifier<bool>(true);
  final ValueNotifier<String?> _pdfError = ValueNotifier<String?>(null);

  Timer? _saveTimer;
  late final MetronomeController _metronome;

  Map<int, List<ChordMark>> _chords = const {};
  int _pages = 0;
  int _currentPage = 0;
  bool _isReady = false;
  bool _prefsLoaded = false;
  bool _horizontalSwipe = false;
  bool _swipeEnabled = true;
  bool _tapZones = false;
  int _viewerToken = 0;
  int _analysisToken = 0;
  bool _preferFlats = false;
  Timer? _snapTimer;
  double _fitScale = 1;
  bool _snapping = false;

  int get _initialPageNumber => (_currentPage < 0 ? 0 : _currentPage) + 1;

  int get _totalChords =>
      _chords.values.fold<int>(0, (total, marks) => total + marks.length);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentPage = widget.piece.lastPage > 0 ? widget.piece.lastPage - 1 : 0;
    _pageNotifier.value = _currentPage;
    _preferFlats = ChordService.preferFlatsForKey(widget.piece.keySignature);
    _metronome = MetronomeController(
      bpm: widget.piece.bpm,
      beatsPerBar: widget.piece.beatsPerBar,
    );
    _loadPreferences();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _snapTimer?.cancel();
    _persistPage();
    _metronome.dispose();
    _pageNotifier.dispose();
    _transpose.dispose();
    _showChords.dispose();
    _pdfError.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _saveTimer?.cancel();
      _persistPage();
    }
  }

  Future<void> _loadPreferences() async {
    final horizontal = await SettingsService.loadHorizontalSwipe();
    final tapZones = await SettingsService.loadTapZones();
    final swipeEnabled = await SettingsService.loadSwipeEnabled();
    final sound = await SettingsService.loadMetronomeSound();
    final accent = await SettingsService.loadMetronomeAccent();
    if (!mounted) return;
    setState(() {
      _horizontalSwipe = horizontal;
      _tapZones = tapZones;
      _swipeEnabled = swipeEnabled;
      _prefsLoaded = true;
    });
    unawaited(_metronome.setSoundEnabled(sound));
    unawaited(_metronome.setAccentFirst(accent));
  }

  void _persistPage() {
    if (!_isReady || _pages == 0) return;
    unawaited(
      LibraryService.instance.updateLastPage(widget.piece.id, _currentPage + 1),
    );
  }

  void _schedulePersist() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _persistPage);
  }

  Future<void> _goToPage(int index) async {
    if (!_isReady || _pages == 0) return;
    final target = index.clamp(0, _pages - 1);
    if (target == _currentPage) return;
    await _controller.goToPage(pageNumber: target + 1);
    if (!mounted) return;
    _currentPage = target;
    _pageNotifier.value = target;
    widget.onPageChanged?.call(target + 1);
    _schedulePersist();
  }

  Future<void> _promptForPage() async {
    final page = await showDialog<int>(
      context: context,
      builder: (_) => _GoToPageDialog(pageCount: _pages),
    );
    if (page == null) return;
    await _goToPage(page - 1);
  }

  void _retry() {
    _snapTimer?.cancel();
    _snapping = false;
    _analysisToken++;
    setState(() {
      _pdfError.value = null;
      _isReady = false;
      _pages = 0;
      _chords = const {};
      _currentPage = widget.piece.lastPage > 0 ? widget.piece.lastPage - 1 : 0;
      _pageNotifier.value = _currentPage;
      _viewerToken++;
    });
  }

  void _toggleSwipeDirection() {
    final horizontal = !_horizontalSwipe;
    _snapTimer?.cancel();
    _snapping = false;
    _analysisToken++;
    setState(() {
      _horizontalSwipe = horizontal;
      _isReady = false;
      _viewerToken++;
    });
    unawaited(SettingsService.saveHorizontalSwipe(horizontal));
  }

  Future<void> _openMetronome() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) =>
          _MetronomeSheet(controller: _metronome, piece: widget.piece),
    );
  }

  Future<void> _openTranspose() async {
    var semitones = _transpose.value;
    var showChords = _showChords.value;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) {
          void update(int value) {
            final clamped = value.clamp(-11, 11);
            _transpose.value = clamped;
            setSheet(() => semitones = clamped);
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      'Accordi',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${semitones > 0 ? '+' : ''}$semitones semitoni',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _totalChords == 0
                      ? 'Nessun accordo riconosciuto in questo spartito.'
                      : '$_totalChords accordi riconosciuti sotto il rigo.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.filledTonal(
                      onPressed: () => update(semitones - 1),
                      icon: const Icon(Icons.remove),
                      tooltip: 'Un semitono indietro',
                    ),
                    SizedBox(
                      width: 90,
                      child: Text(
                        '${semitones > 0 ? '+' : ''}$semitones',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton.filled(
                      onPressed: () => update(semitones + 1),
                      icon: const Icon(Icons.add),
                      tooltip: 'Un semitono avanti',
                    ),
                  ],
                ),
                Slider(
                  value: semitones.toDouble(),
                  min: -11,
                  max: 11,
                  divisions: 22,
                  label: '${semitones > 0 ? '+' : ''}$semitones',
                  onChanged: (value) => update(value.round()),
                ),
                Wrap(
                  spacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final value in [-5, -2, -1, 0, 1, 2, 5])
                      ChoiceChip(
                        label: Text(value > 0 ? '+$value' : '$value'),
                        selected: semitones == value,
                        onSelected: (_) => update(value),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mostra gli accordi trasposti'),
                  subtitle: const Text(
                    'I riquadri compaiono sopra gli accordi originali.',
                  ),
                  value: showChords,
                  onChanged: (value) {
                    _showChords.value = value;
                    setSheet(() => showChords = value);
                  },
                ),
                TextButton.icon(
                  onPressed: () {
                    update(0);
                    _showChords.value = true;
                    setSheet(() => showChords = true);
                  },
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Riporta tutto all\'originale'),
                ),
                const SizedBox(height: 4),
                Text(
                  'Se il PDF è una scansione senza testo, gli accordi non sono leggibili: '
                  'in quel caso il riquadro non compare.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  PdfPageLayout _layoutHorizontal(List<PdfPage> pages, PdfViewerParams params) {
    const margin = 8.0;
    const gap = 16.0;
    if (pages.isEmpty) {
      return PdfPageLayout(pageLayouts: const [], documentSize: Size.zero);
    }
    final rects = <Rect>[];
    var x = margin;
    var maxHeight = 0.0;
    for (final page in pages) {
      rects.add(Rect.fromLTWH(x, margin, page.width, page.height));
      x += page.width + gap;
      maxHeight = math.max(maxHeight, page.height);
    }
    return PdfPageLayout(
      pageLayouts: rects,
      documentSize: Size(x - gap + margin, maxHeight + margin * 2),
    );
  }

  void _onViewerReady(PdfDocument document, PdfViewerController controller) {
    if (!mounted) return;
    final pages = document.pages.length;
    final page = pages == 0 ? 0 : _currentPage.clamp(0, pages - 1);
    _pdfError.value = null;
    setState(() {
      _pages = pages;
      _currentPage = page;
      _isReady = true;
    });
    _pageNotifier.value = page;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scale = _controller.value.getMaxScaleOnAxis();
      if (scale > 0) _fitScale = scale;
    });
    unawaited(_analyzeChords(document));
  }

  Future<void> _analyzeChords(PdfDocument document) async {
    final generation = ++_analysisToken;
    final pages = document.pages.take(40).toList(growable: false);
    if (pages.isEmpty) return;

    // Analizza prima la pagina aperta, poi quelle vicine: gli accordi
    // compaiono subito invece di aspettare la scansione di tutto il PDF.
    final start = _currentPage.clamp(0, pages.length - 1);
    final ordered = <PdfPage>[];
    for (var distance = 0; distance < pages.length; distance++) {
      final forward = start + distance;
      if (forward < pages.length) ordered.add(pages[forward]);
      final backward = start - distance;
      if (distance > 0 && backward >= 0) ordered.add(pages[backward]);
    }

    final result = <int, List<ChordMark>>{};
    for (final page in ordered) {
      if (!mounted || generation != _analysisToken) return;
      try {
        final text = await page.loadStructuredText();
        if (page.width <= 0 || page.height <= 0) continue;
        final marks = <ChordMark>[];
        final seen = <String>{};
        for (final line in _buildTextLines(text.fragments)) {
          for (final found in ChordService.findChordsInText(line.value)) {
            final bounds = _normalizedCharBounds(
              line.rects,
              found.start,
              found.end,
              page,
            );
            if (bounds == null) continue;
            final key =
                '${found.chord}@${bounds.left.toStringAsFixed(3)}:'
                '${bounds.top.toStringAsFixed(3)}';
            if (!seen.add(key)) continue;
            marks.add(ChordMark(chord: found.chord, bounds: bounds));
          }
        }
        if (marks.isEmpty) continue;
        result[page.pageNumber] = marks;
        if (!mounted || generation != _analysisToken) return;
        setState(() {
          _chords = Map<int, List<ChordMark>>.unmodifiable(
            Map<int, List<ChordMark>>.of(result),
          );
        });
      } catch (_) {
        // Una pagina senza testo estraibile non deve bloccare il lettore.
      }
    }
  }

  /// pdfrx divide spesso un accordo in frammenti (`Fa#`, `-`, `6`).
  /// Li ricompone in righe visive ignorando i ritorni a capo artificiali.
  List<_PdfTextLine> _buildTextLines(List<PdfPageTextFragment> fragments) {
    final lines = <_PdfTextLine>[];
    _PdfTextLine? current;
    for (final fragment in fragments) {
      if (fragment.text.trim().isEmpty) continue;
      if (current == null || !current.sameLine(fragment.bounds)) {
        current = _PdfTextLine(fragment.bounds);
        lines.add(current);
      }
      current.add(fragment);
    }
    return lines;
  }

  /// Ritaglia il rettangolo del singolo accordo usando i rettangoli dei suoi
  /// caratteri, così il riquadro copre anche qualità e basso.
  Rect? _normalizedCharBounds(
    List<PdfRect> rects,
    int start,
    int end,
    PdfPage page,
  ) {
    if (start < 0 || end <= start || end > rects.length) return null;

    var left = double.infinity;
    var top = double.negativeInfinity;
    var right = double.negativeInfinity;
    var bottom = double.infinity;
    for (var index = start; index < end; index++) {
      final rect = rects[index];
      left = math.min(left, rect.left);
      right = math.max(right, rect.right);
      top = math.max(top, rect.top);
      bottom = math.min(bottom, rect.bottom);
    }

    if (!left.isFinite ||
        !right.isFinite ||
        !top.isFinite ||
        !bottom.isFinite ||
        right <= left ||
        top <= bottom) {
      return null;
    }

    return Rect.fromLTWH(
      left / page.width,
      (page.height - top) / page.height,
      (right - left) / page.width,
      (top - bottom) / page.height,
    );
  }

  void _onPageChanged(int? pageNumber) {
    if (!mounted || pageNumber == null) return;
    final page = _pages == 0
        ? pageNumber - 1
        : (pageNumber - 1).clamp(0, _pages - 1);
    _currentPage = page;
    _pageNotifier.value = page;
    widget.onPageChanged?.call(page + 1);
    _schedulePersist();
  }

  void _scheduleSnap() {
    if (!_swipeEnabled) return;
    _snapTimer?.cancel();
    _snapTimer = Timer(const Duration(milliseconds: 220), () {
      unawaited(_snapToNearestPage());
    });
  }

  /// Aggancia la pagina al bordo quando lo scorrimento si ferma.
  /// Non interviene mentre l'utente sta ingrandendo lo spartito.
  Future<void> _snapToNearestPage() async {
    if (!mounted || !_isReady || _snapping || _pages == 0) return;
    final scale = _controller.value.getMaxScaleOnAxis();
    if (scale > 0 && scale > _fitScale * 1.06) return;
    _snapping = true;
    try {
      await _controller.goToPage(
        pageNumber: _currentPage + 1,
        anchor: _horizontalSwipe
            ? PdfPageAnchor.centerLeft
            : PdfPageAnchor.topCenter,
        duration: const Duration(milliseconds: 180),
      );
    } catch (_) {
      // Lo snap non deve mai bloccare la lettura.
    } finally {
      _snapping = false;
    }
  }

  List<Widget> _buildPageOverlays(
    BuildContext context,
    Rect pageRect,
    PdfPage page,
  ) {
    final marks = _chords[page.pageNumber];
    if (marks == null || marks.isEmpty || pageRect.isEmpty) {
      return const [];
    }
    final colorScheme = Theme.of(context).colorScheme;
    return [
      Positioned.fill(
        child: IgnorePointer(
          child: ValueListenableBuilder<int>(
            valueListenable: _transpose,
            builder: (context, semitones, _) {
              return ValueListenableBuilder<bool>(
                valueListenable: _showChords,
                builder: (context, show, _) {
                  if (!show) return const SizedBox.shrink();
                  final chips = <Widget>[];
                  for (final mark in marks) {
                    final label = ChordService.transpose(
                      mark.chord,
                      semitones,
                      preferFlats: _preferFlats,
                    );
                    if (label == null) continue;
                    final rect = Rect.fromLTWH(
                      mark.bounds.left * pageRect.width,
                      mark.bounds.top * pageRect.height,
                      mark.bounds.width * pageRect.width,
                      mark.bounds.height * pageRect.height,
                    );
                    // Il riquadro deve coprire l'accordo originale, non
                    // flottare sopra: usa la sua larghezza/altezza come base.
                    final width = math
                        .max(rect.width + 4, label.length * 6.8 + 10)
                        .clamp(26.0, 140.0)
                        .toDouble();
                    final height = math
                        .max(rect.height + 3, 16.0)
                        .clamp(16.0, 28.0)
                        .toDouble();
                    final left = (rect.center.dx - width / 2)
                        .clamp(0.0, math.max(0.0, pageRect.width - width))
                        .toDouble();
                    final top = (rect.center.dy - height / 2)
                        .clamp(0.0, math.max(0.0, pageRect.height - height))
                        .toDouble();
                    chips.add(
                      Positioned(
                        left: left,
                        top: top,
                        width: width,
                        height: height,
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            // Bianco pieno: copre il vecchio accordo e rende
                            // leggibile quello trasposto anche sui PDF scuri.
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: colorScheme.primary.withValues(alpha: 0.8),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.shadow.withValues(
                                  alpha: 0.18,
                                ),
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              label,
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 10,
                                height: 1,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                  return Stack(children: chips);
                },
              );
            },
          ),
        ),
      ),
    ];
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.broken_image_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Impossibile aprire il PDF.\n$message',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh),
              label: const Text('Riprova'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTapZone({
    required String label,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onTap == null
          ? null
          : () {
              unawaited(HapticFeedback.selectionClick());
              onTap();
            },
      child: Semantics(
        button: onTap != null,
        label: label,
        child: Center(
          child: Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.primary
                .withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (!_prefsLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: PdfViewer.file(
              widget.piece.filePath,
              key: ValueKey('pdf-$_viewerToken-$_horizontalSwipe'),
              controller: _controller,
              initialPageNumber: _initialPageNumber,
              params: PdfViewerParams(
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerLowest,
                margin: 12,
                pageDropShadow: null,
                pageAnchor: _horizontalSwipe
                    ? PdfPageAnchor.centerLeft
                    : PdfPageAnchor.topCenter,
                sizeDelegateProvider: const PdfViewerSizeDelegateProviderLegacy(
                  useAlternativeFitScaleAsMinScale: true,
                ),
                textSelectionParams: const PdfTextSelectionParams(
                  enabled: false,
                ),
                panEnabled: _swipeEnabled,
                layoutPages: _horizontalSwipe ? _layoutHorizontal : null,
                onViewerReady: _onViewerReady,
                onPageChanged: _onPageChanged,
                onInteractionStart: (_) => _snapTimer?.cancel(),
                onInteractionEnd: (_) => _scheduleSnap(),
                pageOverlaysBuilder: _buildPageOverlays,
                loadingBannerBuilder: (_, _, _) => const SizedBox.shrink(),
                errorBannerBuilder: (context, error, stackTrace, documentRef) {
                  return _buildError('$error');
                },
              ),
            ),
          ),
        ),
        if (!_isReady) const Center(child: CircularProgressIndicator()),
        if (_tapZones && _isReady) ...[
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 64,
            child: _buildTapZone(
              label: 'Pagina precedente',
              icon: Icons.chevron_left,
              onTap: _currentPage > 0
                  ? () => _goToPage(_currentPage - 1)
                  : null,
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 64,
            child: _buildTapZone(
              label: 'Pagina successiva',
              icon: Icons.chevron_right,
              onTap: _currentPage < _pages - 1
                  ? () => _goToPage(_currentPage + 1)
                  : null,
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final subtitle = [
      if (widget.piece.author.trim().isNotEmpty) widget.piece.author.trim(),
      if (widget.piece.keySignature.trim().isNotEmpty)
        widget.piece.keySignature.trim(),
      '${widget.piece.bpm} BPM',
      widget.piece.timeSignature,
    ].join(' • ');

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        toolbarHeight: 68,
        titleSpacing: 0,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.piece.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 1),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          ValueListenableBuilder<int>(
            valueListenable: _pageNotifier,
            builder: (context, page, _) {
              final total = _pages;
              return TextButton(
                onPressed: total > 0 ? _promptForPage : null,
                child: Text(total > 0 ? '${page + 1}/$total' : '–/–'),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.music_note),
            tooltip: 'Accordi e trasposizione',
            onPressed: _openTranspose,
          ),
          AnimatedBuilder(
            animation: _metronome,
            builder: (context, _) => IconButton(
              icon: Icon(
                Icons.av_timer,
                color: _metronome.isPlaying ? colorScheme.primary : null,
              ),
              tooltip: 'Metronomo',
              onPressed: _openMetronome,
            ),
          ),
          PopupMenuButton<_ViewerAction>(
            tooltip: 'Altre opzioni',
            onSelected: (action) {
              switch (action) {
                case _ViewerAction.goToPage:
                  _promptForPage();
                case _ViewerAction.toggleDirection:
                  _toggleSwipeDirection();
                case _ViewerAction.retry:
                  _retry();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _ViewerAction.goToPage,
                child: Text('Vai a pagina'),
              ),
              PopupMenuItem(
                value: _ViewerAction.toggleDirection,
                child: Text(
                  _horizontalSwipe
                      ? 'Passa allo scorrimento verticale'
                      : 'Passa allo scorrimento orizzontale',
                ),
              ),
              const PopupMenuItem(
                value: _ViewerAction.retry,
                child: Text('Ricarica PDF'),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: ValueListenableBuilder<int>(
            valueListenable: _pageNotifier,
            builder: (context, page, _) {
              final progress = _pages > 0
                  ? ((page + 1) / _pages).clamp(0.0, 1.0)
                  : 0.0;
              return LinearProgressIndicator(value: progress, minHeight: 3);
            },
          ),
        ),
      ),
      body: _buildBody(),
    );
  }
}

class _MetronomeSheet extends StatefulWidget {
  const _MetronomeSheet({required this.controller, required this.piece});

  final MetronomeController controller;
  final Piece piece;

  @override
  State<_MetronomeSheet> createState() => _MetronomeSheetState();
}

class _MetronomeSheetState extends State<_MetronomeSheet> {
  static const List<String> _meters = ['2/4', '3/4', '4/4', '6/8'];

  double? _draftBpm;

  MetronomeController get _controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final beats = _controller.beatsPerBar;
        final selectedMeter = _meters.firstWhere(
          (meter) => int.parse(meter.split('/').first) == beats,
          orElse: () => '$beats/4',
        );
        final bpm = (_draftBpm ?? _controller.bpm.toDouble()).clamp(
          MetronomeController.minBpm.toDouble(),
          MetronomeController.maxBpm.toDouble(),
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text(
                    'Metronomo',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text(
                    'Brano: ${widget.piece.bpm} BPM • ${widget.piece.timeSignature}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var index = 0; index < beats; index++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 90),
                      width: 14,
                      height: 14,
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            _controller.isPlaying &&
                                _controller.currentBeat == index
                            ? colorScheme.primary
                            : colorScheme.surfaceContainerHighest,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '${bpm.round()}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'BPM',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
              Slider(
                value: bpm,
                min: MetronomeController.minBpm.toDouble(),
                max: MetronomeController.maxBpm.toDouble(),
                divisions:
                    MetronomeController.maxBpm - MetronomeController.minBpm,
                label: '${bpm.round()} BPM',
                onChanged: (value) => setState(() => _draftBpm = value),
                onChangeEnd: (value) async {
                  await _controller.setBpm(value.round());
                  if (mounted) setState(() => _draftBpm = null);
                },
              ),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () => _controller.setBpm(_controller.bpm - 1),
                    child: const Text('−1'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _controller.setBpm(_controller.bpm + 1),
                    child: const Text('+1'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () => _controller.toggle(),
                    icon: Icon(
                      _controller.isPlaying ? Icons.stop : Icons.play_arrow,
                    ),
                    label: Text(_controller.isPlaying ? 'Stop' : 'Avvia'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Metro',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final meter in _meters)
                    ChoiceChip(
                      label: Text(meter),
                      selected: selectedMeter == meter,
                      onSelected: (_) => _controller.setBeatsPerBar(
                        int.parse(meter.split('/').first),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Accentua il primo battito'),
                value: _controller.accentFirst,
                onChanged: (value) {
                  _controller.setAccentFirst(value);
                  unawaited(SettingsService.saveMetronomeAccent(value));
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Suono'),
                subtitle:
                    _controller.audioUnavailable && _controller.soundEnabled
                    ? const Text(
                        'Audio non disponibile: uso il click di sistema',
                      )
                    : null,
                value: _controller.soundEnabled,
                onChanged: (value) {
                  _controller.setSoundEnabled(value);
                  unawaited(SettingsService.saveMetronomeSound(value));
                },
              ),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () {
                  _controller.setBpm(widget.piece.bpm);
                  _controller.setBeatsPerBar(widget.piece.beatsPerBar);
                },
                icon: const Icon(Icons.refresh),
                label: Text(
                  'Torna a ${widget.piece.bpm} BPM • ${widget.piece.timeSignature}',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GoToPageDialog extends StatefulWidget {
  const _GoToPageDialog({required this.pageCount});

  final int pageCount;

  @override
  State<_GoToPageDialog> createState() => _GoToPageDialogState();
}

class _GoToPageDialogState extends State<_GoToPageDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final page = int.tryParse(_controller.text.trim());
    if (page == null || page < 1 || page > widget.pageCount) {
      setState(() {
        _errorText = 'Inserisci un numero tra 1 e ${widget.pageCount}';
      });
      return;
    }
    Navigator.of(context).pop(page);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Vai a pagina'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.go,
        onSubmitted: (_) => _submit(),
        onChanged: (_) {
          if (_errorText != null) setState(() => _errorText = null);
        },
        decoration: InputDecoration(
          labelText: 'Pagina (1-${widget.pageCount})',
          errorText: _errorText,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Vai')),
      ],
    );
  }
}

/// Riga visiva ricostruita dai frammenti di pdfrx.
class _PdfTextLine {
  _PdfTextLine(PdfRect bounds) : top = bounds.top, bottom = bounds.bottom;

  final StringBuffer _text = StringBuffer();
  final List<PdfRect> rects = [];
  double top;
  double bottom;
  double? _lastRight;

  String get value => _text.toString();

  bool sameLine(PdfRect bounds) {
    final overlap = math.min(top, bounds.top) - math.max(bottom, bounds.bottom);
    final minHeight = math.min(top - bottom, bounds.height);
    final centerDistance =
        (((top + bottom) / 2) - ((bounds.top + bounds.bottom) / 2)).abs();
    return (minHeight > 0 && overlap >= minHeight * 0.35) ||
        centerDistance <= math.max(3.0, (top - bottom) * 0.9);
  }

  void add(PdfPageTextFragment fragment) {
    final value = fragment.text;
    if (_lastRight != null &&
        fragment.bounds.left - _lastRight! > 1.0 &&
        !_canJoinChordPart(_text.toString(), value.trimLeft())) {
      _text.write(' ');
      rects.add(PdfRect(_lastRight!, top, _lastRight!, bottom));
    }
    for (var index = 0; index < value.length; index++) {
      final char = value[index];
      if (char == '\n' || char == '\r') continue;
      _text.write(char);
      rects.add(
        index < fragment.charRects.length
            ? fragment.charRects[index]
            : fragment.bounds,
      );
    }
    _lastRight = fragment.bounds.right;
    top = math.max(top, fragment.bounds.top);
    bottom = math.min(bottom, fragment.bounds.bottom);
  }

  static final RegExp _chordPartPattern = RegExp(
    r'^(?:[-+0-9/#°øΔ]|(?:maj|min|sus|add|dim|aug|alt|hd)|[mM](?=[0-9]))',
  );

  /// Evita di separare `Fa#-` da `6` o `7+` quando il PDF li spezza.
  bool _canJoinChordPart(String previous, String next) {
    if (!_endsWithChord(previous) || next.isEmpty) return false;
    return _chordPartPattern.hasMatch(next);
  }

  bool _endsWithChord(String value) {
    final trimmed = value.trimRight();
    if (trimmed.isEmpty) return false;
    final lastWord = trimmed.split(RegExp(r'\s+')).last;
    return ChordService.isChord(lastWord);
  }
}
