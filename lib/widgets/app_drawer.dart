import 'package:flutter/material.dart';

enum AppSection { brani, dettagli }

/// Menu laterale comune alle sezioni della libreria.
class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    required this.section,
    this.profileName,
    this.onOpenBrani,
    this.onOpenDettagli,
    this.onOpenSettings,
  });

  final AppSection section;
  final String? profileName;
  final VoidCallback? onOpenBrani;
  final VoidCallback? onOpenDettagli;
  final VoidCallback? onOpenSettings;

  void _closeAndAct(BuildContext context, VoidCallback? action) {
    Navigator.pop(context);
    if (action != null) action();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.library_music,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FrancyPages',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          profileName ?? 'La tua libreria di spartiti',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ListTile(
              selected: section == AppSection.brani,
              selectedTileColor: colorScheme.secondaryContainer,
              leading: Icon(
                Icons.library_music_outlined,
                color: section == AppSection.brani ? colorScheme.primary : null,
              ),
              title: const Text('Brani'),
              subtitle: const Text('La libreria e la ricerca'),
              onTap: () => _closeAndAct(
                context,
                section == AppSection.brani ? null : onOpenBrani,
              ),
            ),
            ListTile(
              selected: section == AppSection.dettagli,
              selectedTileColor: colorScheme.secondaryContainer,
              leading: Icon(
                Icons.queue_music,
                color: section == AppSection.dettagli
                    ? colorScheme.primary
                    : null,
              ),
              title: const Text('Dettagli brani'),
              subtitle: const Text('Titolo, autore, tonalità e tempo'),
              onTap: () => _closeAndAct(
                context,
                section == AppSection.dettagli ? null : onOpenDettagli,
              ),
            ),
            const Spacer(),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Impostazioni'),
              onTap: () => _closeAndAct(context, onOpenSettings),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Text(
                'Versione 1.0.0',
                style: TextStyle(fontSize: 11, color: colorScheme.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
