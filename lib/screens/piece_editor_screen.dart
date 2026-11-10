import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/piece.dart';
import '../models/profile.dart';
import '../services/library_service.dart';
import '../services/pdf_metadata_service.dart';

const List<String> _meterOptions = [
  '2/2',
  '2/4',
  '3/4',
  '4/4',
  '5/4',
  '6/8',
  '7/8',
  '9/8',
  '12/8',
];

class PieceEditorScreen extends StatefulWidget {
  const PieceEditorScreen({
    super.key,
    required this.library,
    required this.profiles,
    required this.profileId,
    this.piece,
    this.sourcePdfPath,
    this.sourceFileName,
    this.detected,
  });

  final LibraryService library;
  final List<Profile> profiles;
  final String profileId;
  final Piece? piece;
  final String? sourcePdfPath;
  final String? sourceFileName;
  final DetectedMetadata? detected;

  @override
  State<PieceEditorScreen> createState() => _PieceEditorScreenState();
}

class _PieceEditorScreenState extends State<PieceEditorScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _title;
  late final TextEditingController _author;
  late final TextEditingController _key;
  late final TextEditingController _bpm;
  late String _meter;
  late String _profileId;
  late final List<String> _meters;

  bool _saving = false;

  bool get _isNew => widget.piece == null;

  @override
  void initState() {
    super.initState();
    final piece = widget.piece;
    final detected = widget.detected;
    final fallbackTitle = _stripPdf(widget.sourceFileName ?? '');

    _title = TextEditingController(
      text: piece?.title ?? detected?.title ?? fallbackTitle,
    );
    _author = TextEditingController(
      text: piece?.author ?? detected?.author ?? '',
    );
    _key = TextEditingController(
      text: piece?.keySignature ?? detected?.keySignature ?? '',
    );
    _bpm = TextEditingController(text: '${piece?.bpm ?? detected?.bpm ?? 120}');
    _meter = piece?.timeSignature ?? detected?.timeSignature ?? '4/4';
    _profileId = piece?.profileId ?? widget.profileId;
    _meters = _meterOptions.contains(_meter)
        ? _meterOptions
        : [_meter, ..._meterOptions];

    final profileExists = widget.profiles.any(
      (profile) => profile.id == _profileId,
    );
    if (!profileExists && widget.profiles.isNotEmpty) {
      _profileId = widget.profiles.first.id;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _key.dispose();
    _bpm.dispose();
    super.dispose();
  }

  static String _stripPdf(String name) {
    if (name.toLowerCase().endsWith('.pdf')) {
      return name.substring(0, name.length - 4).trim();
    }
    return name.trim();
  }

  String? _validateTitle(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Inserisci il titolo del brano';
    }
    return null;
  }

  String? _validateBpm(String? value) {
    final bpm = int.tryParse(value?.trim() ?? '');
    if (bpm == null || bpm < 30 || bpm > 300) {
      return 'Valore tra 30 e 300';
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    File? copiedFile;
    try {
      final title = _title.text.trim();
      final author = _author.text.trim();
      final key = _key.text.trim();
      final bpm = int.parse(_bpm.text.trim());

      if (_isNew) {
        final source = widget.sourcePdfPath;
        if (source == null) {
          throw const LibraryException('Nessun PDF selezionato.');
        }
        copiedFile = await widget.library.storePdf(
          sourcePath: source,
          preferredName: title,
        );
        final piece = Piece(
          id: Piece.newId(),
          profileId: _profileId,
          title: title,
          author: author,
          keySignature: key,
          bpm: bpm,
          timeSignature: _meter,
          filePath: copiedFile.path,
          addedAt: DateTime.now(),
          sizeBytes: await copiedFile.length(),
        );
        await widget.library.addPiece(piece);
      } else {
        final updated = widget.piece!.copyWith(
          profileId: _profileId,
          title: title,
          author: author,
          keySignature: key,
          bpm: bpm,
          timeSignature: _meter,
        );
        await widget.library.updatePiece(updated);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (copiedFile != null) {
        try {
          if (await copiedFile.exists()) await copiedFile.delete();
        } on FileSystemException {
          // Copia orfana: ignorare.
        }
      }
      if (!mounted) return;
      setState(() => _saving = false);
      _showError(error);
    }
  }

  Future<void> _delete() async {
    final piece = widget.piece;
    if (piece == null || _saving) return;

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

    setState(() => _saving = true);
    try {
      await widget.library.deletePiece(piece);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError(error);
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

  Widget _buildDetectionBanner() {
    if (!_isNew) return const SizedBox.shrink();
    final detected = widget.detected;
    final colorScheme = Theme.of(context).colorScheme;
    final found =
        detected != null &&
        (detected.hasScoreData || (detected.author?.isNotEmpty ?? false));
    final message = found
        ? 'Ho letto i dati dallo spartito: controlla titolo, autore, tonalità, tempo e metro prima di salvare.'
        : 'Nessuna indicazione trovata nello spartito: imposto 120 BPM e 4/4. Puoi modificarli qui.';

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            found ? Icons.auto_awesome : Icons.info_outline,
            color: colorScheme.onSecondaryContainer,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: colorScheme.onSecondaryContainer,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final name = widget.piece == null
        ? (widget.sourceFileName ?? 'PDF selezionato')
        : widget.piece!.filePath.split(Platform.pathSeparator).last;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.picture_as_pdf, color: colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  _isNew
                      ? 'Il PDF verrà copiato nella libreria al salvataggio.'
                      : widget.piece!.sizeLabel,
                  style: TextStyle(fontSize: 12, color: colorScheme.outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Nuovo brano' : 'Dettagli brano'),
        actions: [
          if (!_isNew)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Elimina brano',
              onPressed: _saving ? null : _delete,
            ),
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'Salva',
              onPressed: _save,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            _buildDetectionBanner(),
            TextFormField(
              controller: _title,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Titolo',
                hintText: 'Nome del brano',
              ),
              validator: _validateTitle,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _author,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Autore / compositore',
                hintText: 'Facoltativo',
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _bpm,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Tempo',
                      suffixText: 'BPM',
                    ),
                    validator: _validateBpm,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    initialValue: _meter,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Metro'),
                    items: [
                      for (final meter in _meters)
                        DropdownMenuItem(value: meter, child: Text(meter)),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _meter = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _key,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Tonalità',
                hintText: 'Es. Do maggiore, La minore',
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _profileId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Profilo'),
              items: [
                for (final profile in widget.profiles)
                  DropdownMenuItem(
                    value: profile.id,
                    child: Row(
                      children: [
                        Icon(
                          Icons.folder_outlined,
                          size: 18,
                          color: profile.color,
                        ),
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
              ],
              onChanged: (value) {
                if (value != null) setState(() => _profileId = value);
              },
            ),
            const SizedBox(height: 20),
            _buildFileCard(),
            const SizedBox(height: 14),
            Text(
              'Il metronomo del lettore parte da questo tempo e da questo metro.',
              style: TextStyle(fontSize: 12, color: colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
