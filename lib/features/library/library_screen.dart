import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../shared/staggered_item.dart';
import '../../core/services/account_service.dart';
import '../../core/services/navigation_service.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/models/models.dart';
import '../../core/models/account_models.dart';
import '../../core/services/addon_service.dart';
import '../../core/services/download_manager_service.dart';
import '../../core/models/addon_models.dart';
import '../shared/track_list_tile.dart';
import '../shared/offline_banner.dart';
import '../downloads/downloads_screen.dart';
import '../auth/auth_screen.dart';
import '../shared/batch_download_dialog.dart';
import '../album/album_detail_screen.dart';
import '../artist/artist_detail_screen.dart';
import '../../core/utils/app_toast.dart';
import '../../core/services/jiosaavn_addon_handler.dart';

const String _kAddonId = JioSaavnAddonHandler.addonId;

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<UserPlaylist> _playlists = [];
  bool _loadingPlaylists = false;

  UserPlaylist? _selectedPlaylist;
  List<Track>? _playlistTracks;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AccountService>().addListener(_onAccountChanged);
        _loadPlaylists();
      }
    });
  }

  @override
  void dispose() {
    try {
      context.read<AccountService>().removeListener(_onAccountChanged);
    } catch (_) {}
    super.dispose();
  }

  void _onAccountChanged() {
    if (!mounted) return;
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    final account = context.read<AccountService>();
    if (!account.isLoggedIn) {
      if (mounted) {
        setState(() {
          _playlists = [];
          _loadingPlaylists = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _loadingPlaylists = true);
    final playlists = await account.getPlaylists();
    if (!mounted) return;
    setState(() {
      _playlists = playlists;
      _loadingPlaylists = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      children: [
        const OfflineBanner(),
        Expanded(
          child: _selectedPlaylist != null
              ? _buildPlaylistDetail()
              : DefaultTabController(
                  length: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(AppTheme.space6, AppTheme.space7, AppTheme.space6, AppTheme.space4),
                        child: Text(
                          'Tu biblioteca',
                          style: text.displayMedium?.copyWith(
                            fontFamily: AppTheme.displayFont,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      TabBar(
                        indicatorColor: AppTheme.accent,
                        labelColor: AppTheme.accent,
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        labelStyle: TextStyle(
                            fontFamily: AppTheme.displayFont,
                            fontWeight: FontWeight.w600,
                            fontSize: 14),
                        unselectedLabelStyle: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                            color: AppTheme.textMuted),
                        unselectedLabelColor: AppTheme.textMuted,
                        indicatorSize: TabBarIndicatorSize.label,
                        dividerColor: Colors.transparent,
                        tabs: const [
                          Tab(text: 'Playlists'),
                          Tab(text: 'Canciones'),
                          Tab(text: 'Álbumes'),
                          Tab(text: 'Artistas'),
                          Tab(text: 'Descargas'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildPlaylists(),
                            _buildLikedSongs(),
                            _buildAlbums(),
                            _buildArtists(),
                            const DownloadsScreen(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  // ========== LIKED SONGS ==========

  Widget _buildLikedSongs() {
    final account = context.watch<AccountService>();

    if (!account.isLoggedIn) {
      return _centeredMessage(
        icon: Icons.favorite_rounded,
        text: 'Inicia sesión para ver tus canciones favoritas',
        actionLabel: 'Iniciar sesión',
        onAction: () => _openAuth(),
      );
    }

    final tracks =
        account.favoriteTracks.map((f) => trackFromStored(f.data)).toList();

    if (tracks.isEmpty) {
      return _centeredMessage(
        icon: Icons.favorite_rounded,
        text: 'Aún no tienes canciones favoritas.\nToca el corazón en cualquier canción para guardarla.',
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppTheme.space6, AppTheme.space4, AppTheme.space6, 0),
          child: Row(
            children: [
              Text(
                '${tracks.length} canciones',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () =>
                    BatchDownloadDialog.show(context, List.of(tracks)),
                icon: const Icon(Icons.download_rounded, size: 20),
                label: const Text('Descargar todo'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(AppTheme.space6),
            itemCount: tracks.length,
            itemBuilder: (context, index) => StaggeredItem(
              index: index,
              child: TrackListTile(
                track: tracks[index],
                tracks: tracks,
                index: index,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ========== ALBUMS ==========

  Widget _buildAlbums() {
    final account = context.watch<AccountService>();
    if (!account.isLoggedIn) {
      return _centeredMessage(
        icon: Icons.album_rounded,
        text: 'Inicia sesión para ver tus álbumes favoritos',
        actionLabel: 'Iniciar sesión',
        onAction: () => _openAuth(),
      );
    }
    final albums = account.favoriteAlbums;
    if (albums.isEmpty) {
      return _centeredMessage(
        icon: Icons.album_rounded,
        text: 'Aún no tienes álbumes favoritos.',
      );
    }
    return _FavGrid(
      items: albums,
      onTap: (row) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AlbumDetailScreen(
          id: row.itemId,
          addonId: _kAddonId,
          initialTitle: _titleOf(row.data, row.itemId),
          initialArtwork: coverUrlFromUuid(_coverOf(row.data)),
        ),
      )),
    );
  }

  // ========== ARTISTS ==========

  Widget _buildArtists() {
    final account = context.watch<AccountService>();
    if (!account.isLoggedIn) {
      return _centeredMessage(
        icon: Icons.person_rounded,
        text: 'Inicia sesión para ver tus artistas favoritos',
        actionLabel: 'Iniciar sesión',
        onAction: () => _openAuth(),
      );
    }
    final artists = account.favoriteArtists;
    if (artists.isEmpty) {
      return _centeredMessage(
        icon: Icons.person_rounded,
        text: 'Aún no tienes artistas favoritos.',
      );
    }
    return _FavGrid(
      items: artists,
      onTap: (row) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ArtistDetailScreen(
          id: row.itemId,
          addonId: _kAddonId,
          initialTitle: _titleOf(row.data, row.itemId),
          initialArtwork: coverUrlFromUuid(_coverOf(row.data)),
        ),
      )),
    );
  }

  // ========== PLAYLISTS ==========

  Widget _buildPlaylists() {
    final account = context.watch<AccountService>();
    final cs = Theme.of(context).colorScheme;

    if (!account.isLoggedIn) {
      return _centeredMessage(
        icon: Icons.queue_music_rounded,
        text: 'Inicia sesión para ver tus playlists',
        actionLabel: 'Iniciar sesión',
        onAction: () => _openAuth(),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AppTheme.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showCreatePlaylistDialog(),
                  icon: Icon(Icons.add, color: AppTheme.surface),
                  label: Text('NUEVA PLAYLIST',
                      style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          color: AppTheme.surface,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: AppTheme.surface,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.space4,
                      vertical: AppTheme.space3,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusDefault),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space4),
          Expanded(
            child: _loadingPlaylists
                ? Center(
                    child:
                        CircularProgressIndicator(color: AppTheme.accent))
                : _playlists.isEmpty
                    ? _centeredMessage(
                        icon: Icons.queue_music_rounded,
                        text: 'Aún no tienes playlists.\nCrea una para empezar.',
                      )
                    : ListView.builder(
                        itemCount: _playlists.length,
                        itemBuilder: (context, index) => StaggeredItem(
                          index: index,
                          child: _buildPlaylistItem(_playlists[index]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistItem(UserPlaylist playlist) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.space3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusDefault),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusDefault),
          onTap: () => _openPlaylist(playlist),
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.space3),
            child: Row(
              children: [
                Container(
                  width: AppTheme.space6,
                  height: AppTheme.space6,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  ),
                  child: Icon(Icons.queue_music_rounded,
                      color: AppTheme.accent),
                ),
                const SizedBox(width: AppTheme.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.name,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (playlist.description.isNotEmpty)
                        Text(
                          playlist.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelMedium,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: AppTheme.danger.withValues(alpha: 0.6), size: 20),
                  onPressed: () => _confirmDeletePlaylist(playlist),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ========== PLAYLIST DETAIL ==========

  Widget _buildPlaylistDetail() {
    final player = context.read<AudioPlayerService>();
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final playlist = _selectedPlaylist!;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                color: cs.onSurface,
                onPressed: _closePlaylist,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      style: text.displaySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Playlist',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (_playlistTracks != null && _playlistTracks!.isNotEmpty) ...[
                IconButton(
                  tooltip: 'Descargar playlist',
                  icon: Icon(
                    Icons.download_rounded,
                    size: 28,
                    color: _playlistFullyDownloaded
                        ? Colors.greenAccent
                        : cs.onSurface,
                  ),
                  onPressed: () => BatchDownloadDialog.show(
                      context, List.of(_playlistTracks!)),
                ),
                IconButton(
                  icon: const Icon(Icons.play_circle_fill),
                  iconSize: 50,
                  color: cs.primary,
                  onPressed: () => player.playAll(_playlistTracks!),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _playlistTracks == null
                ? Center(
                    child:
                        CircularProgressIndicator(color: cs.primary))
                : _playlistTracks!.isEmpty
                    ? _centeredMessage(
                        icon: Icons.music_off_rounded,
                        text: 'Aún no hay canciones en esta playlist.',
                      )
                    : ListView.builder(
                        itemCount: _playlistTracks!.length,
                        itemBuilder: (context, index) {
                          final track = _playlistTracks![index];
                          return StaggeredItem(
                            index: index,
                            child: TrackListTile(
                              track: track,
                              tracks: _playlistTracks!,
                              index: index,
                              onRemove: () => _removeTrackFromPlaylist(track),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPlaylist(UserPlaylist playlist) async {
    setState(() {
      _selectedPlaylist = playlist;
      _playlistTracks = null;
    });
    context.read<NavigationService>().setBackHandler(_closePlaylist);

    final result =
        await context.read<AccountService>().getPlaylistDetail(playlist.id);
    if (!mounted) return;
    setState(() {
      if (result != null) {
        _selectedPlaylist = result.$1;
        _playlistTracks = result.$2;
      } else {
        _playlistTracks = [];
      }
    });
  }

  void _closePlaylist() {
    if (!mounted) return;
    setState(() {
      _selectedPlaylist = null;
      _playlistTracks = null;
    });
    try {
      context.read<NavigationService>().clearBackHandler();
    } catch (_) {}
    _loadPlaylists();
  }

  /// True when every track of the open playlist is already on disk.
  bool get _playlistFullyDownloaded {
    final tracks = _playlistTracks;
    if (tracks == null || tracks.isEmpty) return false;
    final dm = context.read<DownloadManagerService>();
    return tracks.every((t) => dm.isDownloaded(t.id));
  }

  Future<void> _removeTrackFromPlaylist(Track track) async {
    final ok = await context
        .read<AccountService>()
        .removeTrackFromPlaylist(_selectedPlaylist!.id, track.id);
    if (ok && mounted) {
      setState(() {
        _playlistTracks!.removeWhere((t) => t.id == track.id);
      });
      AppToast.show(context, 'Se eliminó "${track.title}" de la playlist');
    }
  }

  // ========== DIALOGS ==========

  Future<void> _showCreatePlaylistDialog() async {
    final account = context.read<AccountService>();
    if (!account.isLoggedIn) {
      await _openAuth();
      return;
    }

    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final dcs = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
        title: Row(
          children: [
            Icon(Icons.add_box, color: dcs.primary),
            const SizedBox(width: 10),
            const Text('Nueva playlist'),
          ],
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nombre de la playlist',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Crear'),
          ),
        ],
        );
      },
    );

    if (name != null && name.isNotEmpty) {
      final created = await account.createPlaylist(name);
      if (mounted) {
        AppToast.show(
          context,
          created != null
              ? 'Playlist "${created.name}" creada'
              : 'No se pudo crear la playlist',
          isError: created == null,
        );
        _loadPlaylists();
      }
    }
  }

  Future<void> _confirmDeletePlaylist(UserPlaylist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Eliminar playlist?'),
        content: Text(
            '¿Seguro que quieres eliminar "${playlist.name}"? No se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final ok = await context.read<AccountService>().deletePlaylist(playlist.id);
      if (mounted) {
        AppToast.show(
          context,
          ok ? 'Playlist eliminada' : 'No se pudo eliminar la playlist',
          isError: !ok,
        );
        _loadPlaylists();
      }
    }
  }

  // ========== HELPERS ==========

  Future<void> _openAuth() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
    );
  }

  String _coverOf(Map<String, dynamic> data) {
    final d = data;
    final cover = d['cover'] ??
        d['album']?['cover'] ??
        d['image'] ??
        d['picture'] ??
        d['images']?['LARGE']?['url'] ??
        d['images']?['SMALL']?['url'];
    return cover?.toString() ?? '';
  }

  String _titleOf(Map<String, dynamic> data, String fallback) {
    final title = data['title'] ?? data['name'];
    return title?.toString() ?? fallback;
  }

  Widget _centeredMessage({
    required IconData icon,
    required String text,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: AppTheme.textMuted),
          const SizedBox(height: AppTheme.space5),
          Text(
            text,
            textAlign: TextAlign.center,
            style: textTheme.bodyLarge?.copyWith(
              color: AppTheme.textMuted,
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: AppTheme.space4),
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: AppTheme.surface,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.space4,
                  vertical: AppTheme.space3,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusDefault),
                ),
              ),
              child: Text(actionLabel,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontWeight: FontWeight.w600,
                  )),
            ),
          ],
        ],
      ),
    );
  }
}

class _FavGrid extends StatelessWidget {
  final List<FavoriteRow> items;
  final void Function(FavoriteRow) onTap;

  const _FavGrid({
    required this.items,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final crossCount = w > 1200 ? 5 : w > 900 ? 4 : w > 600 ? 3 : 2;
        final aspect = w > 900 ? 0.85 : w > 600 ? 0.8 : 0.75;
        return GridView.builder(
          padding: const EdgeInsets.all(AppTheme.space6),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossCount,
            mainAxisSpacing: AppTheme.space4,
            crossAxisSpacing: AppTheme.space4,
            childAspectRatio: aspect,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final row = items[index];
            final data = row.data;
            final title = data['title'] ?? data['name'] ?? row.itemId;
            final subtitle = data['artist']?['name'] ??
                (data['artists'] is List && (data['artists'] as List).isNotEmpty
                    ? (data['artists'] as List).first['name']
                    : null) ??
                data['description'] ??
                '';
            return StaggeredItem(
              index: index,
              child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onTap(row),
                borderRadius: BorderRadius.circular(AppTheme.radiusDefault),
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppTheme.radiusDefault),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(AppTheme.radiusDefault)),
                              child: _FavCover(
                                row: row,
                                addonService: context.read<AddonService>(),
                              ),
                            ),
                            // Download button for favourite albums — fetches
                            // the album detail and batch-downloads its tracks.
                            if (row.itemType == 'album')
                              Positioned(
                                top: 6,
                                right: 6,
                                child: _FavAlbumDownloadButton(row: row),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(AppTheme.space3),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title?.toString() ?? row.itemId,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleSmall?.copyWith(
                                fontFamily: AppTheme.bodyFont,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            if (subtitle != null && subtitle.toString().isNotEmpty)
                              Text(
                                subtitle.toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.labelMedium,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            );
          },
        );
      },
    );
  }
}

/// Small circular button overlaid on favourite album covers. Fetches the
/// album detail (with tracks) and opens the batch download dialog.
class _FavAlbumDownloadButton extends StatefulWidget {
  final FavoriteRow row;

  const _FavAlbumDownloadButton({required this.row});

  @override
  State<_FavAlbumDownloadButton> createState() =>
      _FavAlbumDownloadButtonState();
}

class _FavAlbumDownloadButtonState extends State<_FavAlbumDownloadButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final dm = context.watch<DownloadManagerService>();
    final cs = Theme.of(context).colorScheme;

    if (_busy) {
      return Container(
        width: 32,
        height: 32,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          shape: BoxShape.circle,
        ),
        child: const CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return FutureBuilder<AddonAlbum?>(
      future: context
          .read<AddonService>()
          .getAlbumDetail(widget.row.itemId, addonId: _kAddonId),
      builder: (context, snapshot) {
        final tracks = snapshot.data?.tracks
                ?.map((t) => trackFromAddonTrack(t))
                .toList() ??
            const <Track>[];
        final downloadedCount = tracks.where((t) => dm.isDownloaded(t.id)).length;
        final allDownloaded =
            tracks.isNotEmpty && downloadedCount == tracks.length;

        return InkWell(
          onTap: tracks.isEmpty || _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    await BatchDownloadDialog.show(context, tracks);
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              shape: BoxShape.circle,
            ),
            child: allDownloaded
                ? const Icon(Icons.download_done_rounded,
                    color: Colors.greenAccent, size: 18)
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      if (downloadedCount > 0 && tracks.isNotEmpty)
                        SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            value: downloadedCount / tracks.length,
                            strokeWidth: 2,
                            color: AppTheme.accent,
                          ),
                        ),
                      Icon(
                        Icons.download_rounded,
                        size: 18,
                        color: downloadedCount > 0
                            ? AppTheme.accent
                            : Colors.white,
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _FavCover extends StatefulWidget {
  final FavoriteRow row;
  final AddonService addonService;

  const _FavCover({
    required this.row,
    required this.addonService,
  });

  @override
  State<_FavCover> createState() => _FavCoverState();
}

class _FavCoverState extends State<_FavCover> {
  String? _url;

  @override
  void initState() {
    super.initState();
    final initial = _initialCover();
    if (initial != null) {
      _url = initial;
    } else {
      _fetchFallback();
    }
  }

  String? _initialCover() {
    final data = widget.row.data;
    final images = data['images'];
    final imageUrl = images is Map
        ? (images['LARGE']?['url'] ??
            images['MEDIUM']?['url'] ??
            images['SMALL']?['url'])
        : null;
    final cover = data['cover'] ??
        data['album']?['cover'] ??
        data['picture'] ??
        data['image'] ??
        data['pictures'] ??
        imageUrl;
    if ((cover ?? '').isEmpty) return null;
    if (widget.row.itemType == 'artist') {
      final c = coverUrlFromUuid(cover!, size: 750);
      return c.isNotEmpty ? c : null;
    }
    final c = coverUrlFromUuid(cover!);
    return c.isNotEmpty ? c : null;
  }

  Future<void> _fetchFallback() async {
    final type = widget.row.itemType;
    if (type != 'artist') return;
    final addonId = widget.row.data['addonId']?.toString() ?? _kAddonId;
    String? artwork;
    try {
      final a = await widget.addonService
          .getArtistDetail(widget.row.itemId, addonId: addonId);
      artwork = a?.artworkURL;
    } catch (e) {
      print('[FavCover] fallback fetch failed: $e');
    }
    if (artwork != null && artwork.isNotEmpty && mounted) {
      setState(() => _url = artwork);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_url == null || _url!.isEmpty) {
      return _placeholder(context);
    }
    return Image.network(
      _url!,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _placeholder(context),
    );
  }

  Widget _placeholder(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHigh,
      child: Center(
        child: Icon(Icons.gradient_rounded, size: 40, color: cs.outline),
      ),
    );
  }
}
