import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/import_service.dart';
import '../../core/services/addon_service.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/models/models.dart';
import '../../core/services/local_library_service.dart';

class ImportItem {
  final String id;
  final String title;
  final String subtitle;

  ImportItem({required this.id, required this.title, required this.subtitle});
}

/// Playlist Import Dialog - import playlist tracks to library
class PlaylistImportDialog extends StatefulWidget {
  const PlaylistImportDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PlaylistImportDialog(),
    );
  }

  @override
  State<PlaylistImportDialog> createState() => _PlaylistImportDialogState();
}

class _PlaylistImportDialogState extends State<PlaylistImportDialog> {
  // State mgmt
  int _step = 0; // 0: File import, 1: Select Tracks, 2: Select Library, 3: Importing
  List<ImportItem> _playlistItems = [];
  Map<String, bool> _selectedItems = {};
  bool _isLoading = false;
  String? _error;
  String? _importLibraryId;

  Future<void> _pickCsvFile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      final file = result.files.first;
      final name = (file.name).toLowerCase();
      if (!name.endsWith('.csv') && !name.endsWith('.txt')) {
        throw Exception('Selecciona un archivo .csv o .txt de Spotify / YouTube Music.');
      }

      final bytes = file.bytes;
      if (bytes == null) throw Exception('No se pudo leer el archivo.');

      final content = utf8.decode(bytes);
      final items = _parsePlaylistFile(content);

      if (items.isEmpty) {
        throw Exception(
            'No se encontraron canciones. Usa un CSV de Spotify o YouTube Music.');
      }

      setState(() {
        _playlistItems = items;
        _selectedItems = {for (var i in items) i.id: true};
        _isLoading = false;
        _step = 1;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception:', '').trim();
        _isLoading = false;
      });
    }
  }

  List<ImportItem> _parsePlaylistFile(String content) {
    final lines = content.split(RegExp(r'\r?\n'));
    final nonEmpty = lines.where((l) => l.trim().isNotEmpty).toList();
    if (nonEmpty.isEmpty) return [];

    final header = _parseCsvLine(nonEmpty.first);
    int titleIdx = -1;
    int artistIdx = -1;
    for (var i = 0; i < header.length; i++) {
      final h = header[i].toLowerCase().trim();
      if (titleIdx == -1 && (h == 'track' || h == 'title')) titleIdx = i;
      if (artistIdx == -1 &&
          (h == 'artist' || h == 'channel title' || h == 'channel')) {
        artistIdx = i;
      }
    }

    final dataLines =
        (titleIdx != -1 || artistIdx != -1) ? nonEmpty.skip(1) : nonEmpty;
    final items = <ImportItem>[];

    for (final line in dataLines) {
      final cols = _parseCsvLine(line);
      if (cols.isEmpty) continue;

      String title;
      String artist;
      if (titleIdx != -1 && artistIdx != -1) {
        title = cols[titleIdx];
        artist = cols[artistIdx];
      } else if (cols.length >= 2) {
        title = cols[0];
        artist = cols[1];
      } else {
        final split = cols[0].split(RegExp(r'\s+[-–—]\s+'));
        if (split.length >= 2) {
          title = split[0];
          artist = split.sublist(1).join(' - ');
        } else {
          title = cols[0];
          artist = '';
        }
      }

      title = title.trim();
      artist = artist.trim();
      if (title.isEmpty) continue;

      items.add(ImportItem(
        id: '${items.length}_$title',
        title: title,
        subtitle: artist,
      ));
    }

    return items;
  }

  List<String> _parseCsvLine(String line) {
    final result = <String>[];
    final sb = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            sb.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          sb.write(c);
        }
      } else {
        if (c == '"') {
          inQuotes = true;
        } else if (c == ',') {
          result.add(sb.toString());
          sb.clear();
        } else {
          sb.write(c);
        }
      }
    }
    result.add(sb.toString());
    return result.map((s) => s.trim()).toList();
  }

  Future<void> _importToNewPlaylist() async {
    final selectedCount = _selectedItems.values.where((e) => e).length;
    if (selectedCount == 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No hay canciones seleccionadas')));
      return;
    }

    final localLibraryService = context.read<LocalLibraryService>();
    final newLib =
        await localLibraryService.createLibrary('Playlist importada');
    _importLibraryId = newLib.id;
    _startImport(newLib.id);
  }

  void _startImport(String libraryId) {
    final selectedTracks =
        _playlistItems.where((i) => _selectedItems[i.id] == true).toList();

    setState(() {
      _step = 3;
    });

    final addonService = context.read<AddonService>();
    final importService = context.read<ImportService>();
    final localLibraryService = context.read<LocalLibraryService>();

    importService.startImport(
      addonService: addonService,
      localLibraryService: localLibraryService,
      libraryId: libraryId,
      tracks: selectedTracks,
    );
  }

  Future<void> _playImportedPlaylist() async {
    final libraryId = _importLibraryId;
    if (libraryId == null) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final localLibraryService = context.read<LocalLibraryService>();
    final addonService = context.read<AddonService>();
    List<Track> tracks;
    if (libraryId.startsWith('local_')) {
      tracks = localLibraryService.getLibraryTracks(libraryId);
    } else {
      tracks = await addonService.getLibraryTracks(libraryId);
    }
    if (mounted) Navigator.pop(context);
    if (tracks.isNotEmpty) {
      final player = context.read<AudioPlayerService>();
      player.playAll(tracks);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final isDark = settings.isDarkMode;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.playlist_play, color: AppTheme.accent),
          SizedBox(width: 10),
           Text('Importar playlist'),
        ],
      ),
      content: SizedBox(
        width: 600,
        height: 400,
        child: _buildContent(isDark),
      ),
      actions: _buildActions(),
    );
  }

  Widget _buildContent(bool isDark) {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.accent));
    }

    switch (_step) {
      case 0: // File import
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.playlist_add, size: 56, color: AppTheme.accent),
            const SizedBox(height: 16),
            const Text(
              'Importa una playlist desde un archivo CSV exportado de Spotify o YouTube Music.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.upload_file),
                label: const Text('Seleccionar archivo CSV'),
                onPressed: _isLoading ? null : _pickCsvFile,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        );

      case 1: // Track Selection
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Encontradas ${_playlistItems.length} canciones'),
                TextButton(
                  onPressed: () {
                    setState(() {
                      final allSelected = _selectedItems.values.every((e) => e);
                      _selectedItems.updateAll((key, val) => !allSelected);
                    });
                  },
                  child: const Text('Seleccionar todas'),
                )
              ],
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _playlistItems.length,
                itemBuilder: (context, index) {
                  final item = _playlistItems[index];
                  return CheckboxListTile(
                    value: _selectedItems[item.id] ?? false,
                    onChanged: (val) =>
                        setState(() => _selectedItems[item.id] = val ?? false),
                    title: Text(item.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(item.subtitle,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    activeColor: AppTheme.accent,
                  );
                },
              ),
            ),
          ],
        );

      case 2: // Library Selection
        return FutureBuilder<List<MusicLibrary>>(
          future: context.read<AddonService>().getLibraries(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            
            final cloudLibs = snapshot.data ?? [];
            final localLibs = context.read<LocalLibraryService>().getLibraries();
            
            if (cloudLibs.isEmpty && localLibs.isEmpty) {
              return const Center(child: Text('No se encontraron bibliotecas.'));
            }

            return Column(
              children: [
                const Text('Selecciona la biblioteca donde importar:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView(
                    children: [
                      if (localLibs.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                           child: Text('BIBLIOTECAS LOCALES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                        ),
                        ...localLibs.map((lib) => ListTile(
                              leading: const Icon(Icons.folder, color: AppTheme.accent),
                              title: Text(lib.name),
                              onTap: () => _startImport(lib.id),
                              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                            )),
                      ],
                      if (cloudLibs.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                           child: Text('BIBLIOTECAS EN LA NUBE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                        ),
                        ...cloudLibs.map((lib) => ListTile(
                              leading: const Icon(Icons.cloud, color: AppTheme.accent),
                              title: Text(lib.name),
                              onTap: () => _startImport(lib.id),
                              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                            )),
                      ],
                      const Divider(),
                      ListTile(
                        leading: const Icon(Icons.add_circle_outline, color: AppTheme.accent),
                         title: const Text('Crear nueva biblioteca local'),
                        onTap: () async {
                          final nameController = TextEditingController();
                          final name = await showDialog<String>(
                            context: context,
                            builder: (context) => AlertDialog(
                               title: const Text('Nombre de la nueva biblioteca'),
                              content: TextField(controller: nameController, autofocus: true),
                              actions: [
                                 TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                                 TextButton(onPressed: () => Navigator.pop(context, nameController.text), child: const Text('Crear')),
                              ],
                            ),
                          );
                          if (name != null && name.isNotEmpty) {
                             final newLib = await context.read<LocalLibraryService>().createLibrary(name);
                             _startImport(newLib.id);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );

      case 3: // Importing Progress
        return Consumer<ImportService>(
          builder: (context, importService, _) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Importando canciones...',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                LinearProgressIndicator(
                  value: importService.progress,
                  backgroundColor: Colors.grey[800],
                  color: AppTheme.accent,
                  minHeight: 10,
                ),
                const SizedBox(height: 10),
                Text(
                  importService.statusMessage == 'Done!'
                      ? '${importService.importedCount} / ${importService.totalTracks} canciones agregadas'
                      : '${importService.importedCount} agregadas · ${importService.totalTracks - importService.importedCount} faltan',
                ),
                const SizedBox(height: 20),
                if (importService.statusMessage == 'Done!') ...[
                  const Icon(Icons.check_circle, color: AppTheme.accent, size: 48),
                  const SizedBox(height: 10),
                  const Text('¡Importación completada!', style: TextStyle(fontWeight: FontWeight.bold)),
                ] else
                  Text(importService.statusMessage,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
              ],
            );
          },
        );

      default:
        return const SizedBox.shrink();
    }
  }

  List<Widget> _buildActions() {
      if (_step == 3) {
        final importService = context.watch<ImportService>();
        if (importService.statusMessage == 'Done!') {
          return [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
            ElevatedButton(
              onPressed: _playImportedPlaylist,
              child: const Text('Reproducir'),
            ),
          ];
        }
        return [
          TextButton(
            onPressed: () {
              importService.stopImport();
            },
            child: const Text('Detener', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              importService.setBackground(true);
              Navigator.pop(context); // Hide dialog
            },
            child: const Text('Ejecutar en segundo plano'),
          ),
        ];
      }

    return [
      if (_step > 0)
        TextButton(
          onPressed: () => setState(() => _step--),
          child: const Text('Atrás'),
        )
      else
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      if (_step == 1)
        ElevatedButton(
          onPressed: _importToNewPlaylist,
          child: const Text('Crear playlist'),
        ),
    ];
  }
}
