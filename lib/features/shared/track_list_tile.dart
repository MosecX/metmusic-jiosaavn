import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:reicon_flutter/reicon_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/addon_service.dart';
import '../../core/services/account_service.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/download_manager_service.dart';
import '../../core/models/models.dart';
import '../../core/services/jiosaavn_addon_handler.dart';
import '../../core/utils/app_toast.dart';
import '../album/album_detail_screen.dart';
import '../artist/artist_detail_screen.dart';

class TrackListTile extends StatelessWidget {
  final Track track;
  final List<Track> tracks;
  final int index;
  final VoidCallback? onRemove;

  /// Square cover size for list rows — large enough to read the artwork
  /// (was 32px, too small to feel professional on phones).
  static const double _coverSize = 56;

  const TrackListTile({
    super.key,
    required this.track,
    required this.tracks,
    required this.index,
    this.onRemove,
    this.removeLabel = 'Remove',
  });

  final String removeLabel;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerService>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final text = theme.textTheme;

    final isCurrentTrack = player.currentTrack?.id == track.id;
    final isPlaying = isCurrentTrack && player.isPlaying;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppTheme.space1),
      decoration: BoxDecoration(
        color: isCurrentTrack
            ? AppTheme.accent.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusDefault),
        border: isCurrentTrack
            ? Border.all(color: AppTheme.accent.withValues(alpha: 0.3), width: 1)
            : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppTheme.space3, vertical: AppTheme.space1),
        leading: Stack(
          children: [
            _buildLeading(context),
            if (player.loadingTrackId == track.id)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.scrim.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(cs.onSurface),
                      ),
                    ),
                  ),
                ),
              )
            else if (isPlaying)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.scrim.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: _MusicVisualizer(color: cs.onSurface, size: 24),
                  ),
                ),
              ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleMedium?.copyWith(
                  fontWeight: isCurrentTrack ? FontWeight.w700 : FontWeight.w600,
                  color: isCurrentTrack ? AppTheme.accent : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _DownloadStateIcon(track: track),
          ],
        ),
        subtitle: Text(
          track.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.bodySmall?.copyWith(
            color: isCurrentTrack
                ? AppTheme.accent.withValues(alpha: 0.7)
                : AppTheme.textMuted,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildFavoriteButton(context),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert,
                  color: AppTheme.textMuted, size: 20),
              onSelected: (value) => _handleMenuAction(context, value),
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'play_next', child: Text('Reproducir siguiente')),
                const PopupMenuItem(value: 'add_queue', child: Text('Añadir a la cola')),
                const PopupMenuItem(value: 'add_playlist', child: Text('Añadir a playlist')),
                PopupMenuItem(
                  value: _isFavorite(context) ? 'unlike' : 'like',
                  child: Text(_isFavorite(context) ? 'Quitar de favoritos' : 'Favorito'),
                ),
                const PopupMenuItem(value: 'download', child: Text('Descargar')),
                const PopupMenuDivider(),
                if (_albumId != null)
                  const PopupMenuItem(
                    value: 'go_album',
                    child: Text('Ir al álbum')),
                if (_artistId != null)
                  const PopupMenuItem(
                    value: 'go_artist',
                    child: Text('Ir al artista')),
                if (onRemove != null)
                  PopupMenuItem(
                    value: 'remove',
                    child: Text(removeLabel,
                        style: TextStyle(color: cs.error)),
                  ),
              ],
            ),
          ],
        ),
        onTap: () {
          if (isCurrentTrack) {
            player.togglePlayPause();
          } else if (tracks.isNotEmpty) {
            player.playAll(tracks, startIndex: index);
          } else {
            player.playSingleTrack(track);
          }
        },
      ),
    );
  }

  bool _isFavorite(BuildContext context) {
    final account = context.read<AccountService>();
    return account.isFavorite('track', _favKey(track));
  }

  Widget _buildLeading(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: _coverSize,
      height: _coverSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        color: cs.surfaceContainerHigh,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        child: track.albumCover != null && track.albumCover!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: track.albumCover!,
                fit: BoxFit.cover,
                memCacheWidth: 112,
                memCacheHeight: 112,
                fadeInDuration: const Duration(milliseconds: 150),
                errorWidget: (_, __, ___) =>
                    Icon(Icons.music_note, color: cs.onSurfaceVariant, size: 28),
              )
            : Icon(Icons.music_note, color: cs.onSurfaceVariant, size: 28),
      ),
    );
  }

  Widget _buildFavoriteButton(BuildContext context) {
    final account = context.watch<AccountService>();
    final cs = Theme.of(context).colorScheme;
    final isFav = account.isFavorite('track', _favKey(track));
    return IconButton(
      icon: Icon(
        isFav ? Icons.favorite : Icons.favorite_border,
        color: isFav ? AppTheme.accent : AppTheme.textMuted,
        size: 20,
      ),
      onPressed: () => _toggleFavorite(context, track),
      tooltip: isFav ? 'Unlike' : 'Like',
    );
  }

  String _favKey(Track t) => t.addonTrackId ?? t.id;

  Future<void> _toggleFavorite(BuildContext context, Track track) async {
    final account = context.read<AccountService>();
    if (!account.isLoggedIn) {
      if (context.mounted) {
        AppToast.show(context, 'Inicia sesión para guardar canciones');
      }
      return;
    }
    final key = _favKey(track);
    final wasFav = account.isFavorite('track', key);
    final ok = await account.toggleFavorite(
      type: 'track',
      itemId: key,
      data: storedTrackFromTrack(track),
    );
    if (context.mounted) {
      AppToast.show(
        context,
        !ok
            ? 'No se pudo actualizar'
            : (wasFav ? 'Quitado de favoritos' : 'Añadido a favoritos'),
        isError: !ok,
      );
    }
  }

  void _handleMenuAction(BuildContext context, String action) {
    final player = context.read<AudioPlayerService>();

    switch (action) {
      case 'add_queue':
        player.addToQueue(track);
        AppToast.show(context, 'Se añadió "${track.title}" a la cola');
        break;
      case 'play_next':
        player.playNext(track);
        AppToast.show(context, 'Sonará "${track.title}" a continuación');
        break;
      case 'like':
      case 'unlike':
        _toggleFavorite(context, track);
        break;
      case 'download':
        _downloadTrack(context);
        break;
      case 'add_playlist':
        _showPlaylistPicker(context);
        break;
      case 'go_album':
        if (_albumId != null) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => AlbumDetailScreen(
              id: _albumId!,
              addonId: track.addonId ?? JioSaavnAddonHandler.addonId,
              initialTitle: track.albumTitle ?? '',
              initialArtwork: track.albumCover,
            ),
          ));
        }
        break;
      case 'go_artist':
        if (_artistId != null) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ArtistDetailScreen(
              id: _artistId!,
              addonId: track.addonId ?? JioSaavnAddonHandler.addonId,
              initialTitle: track.artist,
            ),
          ));
        }
        break;
      case 'remove':
        onRemove?.call();
        break;
    }
  }

  /// Album token from the raw JioSaavn row (more_info.album_id), falling back
  /// to the mapped Track field.
  String? get _albumId {
    final raw = track.rawData;
    if (raw != null) {
      final more = raw['more_info'];
      if (more is Map) {
        final id = more['album_id']?.toString();
        if (id != null && id.isNotEmpty) return id;
      }
    }
    final id = track.albumId;
    return (id != null && id.isNotEmpty) ? id : null;
  }

  /// Artist token from the raw JioSaavn row (more_info.artists.primary),
  /// falling back to the mapped Track field.
  String? get _artistId {
    final raw = track.rawData;
    if (raw != null) {
      final more = raw['more_info'];
      if (more is Map) {
        final artists = more['artists'];
        if (artists is Map) {
          final primary = artists['primary'];
          if (primary is List && primary.isNotEmpty && primary.first is Map) {
            final map = Map<String, dynamic>.from(primary.first as Map);
            final token =
                (map['token'] ?? map['artist_token'] ?? map['id'])?.toString();
            if (token != null && token.isNotEmpty) return token;
          }
        }
      }
    }
    final id = track.artistId;
    return (id != null && id.isNotEmpty) ? id : null;
  }

  Future<void> _downloadTrack(BuildContext context) async {
    final downloadManager = context.read<DownloadManagerService>();
    final addonService = context.read<AddonService>();
    if (downloadManager.isDownloaded(track.id)) {
      AppToast.show(context, 'Ya está descargada');
      return;
    }
    final url = await addonService.getStreamUrl(
        track.addonTrackId ?? track.id,
        addonId: track.addonId);
    if (url != null && context.mounted) {
      await downloadManager.downloadTrack(track: track, streamUrl: url);
      if (context.mounted) AppToast.show(context, 'Descargando "${track.title}"');
    } else if (context.mounted) {
      AppToast.show(context, 'No se pudo obtener el enlace de descarga',
          isError: true);
    }
  }

  Future<void> _showPlaylistPicker(BuildContext context) async {
    final account = context.read<AccountService>();
    if (!account.isLoggedIn) {
      if (context.mounted) {
        AppToast.show(context, 'Inicia sesión para añadir a playlists');
      }
      return;
    }

    final playlists = await account.getPlaylists();
    if (!context.mounted) return;
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusDefault),
        ),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.space6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Añadir a playlist',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontFamily: AppTheme.displayFont,
                      )),
              const SizedBox(height: AppTheme.space4),
              ListTile(
                leading: Icon(Icons.add_circle_outline, color: AppTheme.accent),
                title: const Text('Nueva playlist'),
                onTap: () async {
                  Navigator.pop(context);
                  final nameController = TextEditingController();
                  final name = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Nueva playlist'),
                      content: TextField(
                        controller: nameController,
                        autofocus: true,
                        decoration:
                            const InputDecoration(hintText: 'Nombre de la playlist'),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancelar'),
                        ),
                        TextButton(
                          onPressed: () =>
                              Navigator.pop(ctx, nameController.text.trim()),
                          child: const Text('Crear'),
                        ),
                      ],
                    ),
                  );
                  if (name != null && name.isNotEmpty) {
                    final pl = await context
                        .read<AccountService>()
                        .createPlaylist(name);
                    if (pl != null) {
                      await context
                          .read<AccountService>()
                          .addTrackToPlaylist(pl.id, track);
                      if (context.mounted) {
                        AppToast.show(
                            context, 'Se añadió "${track.title}" a $name');
                      }
                    }
                  }
                },
              ),
              if (playlists.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(AppTheme.space4),
                  child: Text('Aún no tienes playlists.'),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final pl = playlists[index];
                      return ListTile(
                        leading: Icon(Icons.queue_music, color: AppTheme.accent),
                        title: Text(pl.name),
                        onTap: () async {
                          final ok =
                              await account.addTrackToPlaylist(pl.id, track);
                          if (context.mounted) {
                            Navigator.pop(context);
                            AppToast.show(
                              context,
                              ok
                                  ? 'Se añadió "${track.title}" a ${pl.name}'
                                  : 'No se pudo añadir',
                              isError: !ok,
                            );
                          }
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small trailing indicator next to the title: a green check when the track
/// is already downloaded, a progress ring while it's downloading, nothing
/// otherwise.
class _DownloadStateIcon extends StatelessWidget {
  final Track track;

  const _DownloadStateIcon({required this.track});

  @override
  Widget build(BuildContext context) {
    final dm = context.watch<DownloadManagerService>();

    if (dm.isDownloading(track.id)) {
      final progress = dm.getProgress(track.id) ?? 0;
      return SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          value: progress > 0 ? progress / 100 : null,
          strokeWidth: 2,
          color: AppTheme.accent,
        ),
      );
    }
    if (dm.isDownloaded(track.id)) {
      return const Icon(Icons.download_done_rounded,
          color: Colors.greenAccent, size: 18);
    }
    return const SizedBox.shrink();
  }
}

class _MusicVisualizer extends StatefulWidget {
  final Color color;
  final double size;

  const _MusicVisualizer({required this.color, required this.size});

  @override
  State<_MusicVisualizer> createState() => _MusicVisualizerState();
}

class _MusicVisualizerState extends State<_MusicVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  static const List<double> _waveData = [
    0.5, 0.7, 0.9, 1.0, 0.9, 0.7, 0.5, 0.3, 0.1, 0.0, 0.1, 0.3
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.size,
      width: widget.size * 1.2,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(4, (index) {
              final byteOffset = (index * 3);
              final tableIndex = ((_controller.value * _waveData.length).floor() +
                      byteOffset) %
                  _waveData.length;
              final double waveVal = _waveData[tableIndex];
              final double baseFactor = 0.2 + (index % 3) * 0.1;
              final double heightFactor =
                  (baseFactor + waveVal * 0.7).clamp(0.2, 1.0);

              return Container(
                width: widget.size / 5,
                height: widget.size * heightFactor,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.7 + (waveVal * 0.3)),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
