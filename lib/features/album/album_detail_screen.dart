import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/addon_service.dart';
import '../../core/services/account_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/models/models.dart';
import '../shared/staggered_item.dart';
import '../../core/models/addon_models.dart';
import '../../core/utils/app_toast.dart';
import '../shared/track_list_tile.dart';
import '../shared/offline_banner.dart';
import '../shared/batch_download_dialog.dart';
import '../../core/services/download_manager_service.dart';
import '../shared/player_shell.dart';

class AlbumDetailScreen extends StatefulWidget {
  final String id;
  final String addonId;
  final String initialTitle;
  final String? initialArtwork;

  const AlbumDetailScreen({
    super.key,
    required this.id,
    required this.addonId,
    required this.initialTitle,
    this.initialArtwork,
  });

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  AddonAlbum? _album;
  bool _loading = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      setState(() {
        _scrollOffset = _scrollController.offset;
      });
    });
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final album = await context
          .read<AddonService>()
          .getAlbumDetail(widget.id, addonId: widget.addonId);
      if (!mounted) return;
      setState(() {
        _album = album;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final isDark = settings.isDarkMode;
    final cs = Theme.of(context).colorScheme;
    final account = context.watch<AccountService>();

    return PlayerShell(
      child: Scaffold(
        backgroundColor: AppTheme.pageBackground,
        body: Column(
          children: [
            const OfflineBanner(),
            Expanded(child: _buildBody(cs, account, isDark)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme cs, AccountService account, bool isDark) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: cs.primary),
      );
    }
    if (_error != null || _album == null) {
      return Center(
        child: Text(
          'Error: $_error',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }

    final album = _album!;
    final tracks = album.tracks?.map((t) => trackFromAddonTrack(t)).toList() ?? [];
    final isFav = account.isFavorite('album', album.id);
    final artworkUrl = album.artworkURL ?? widget.initialArtwork;
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        Positioned(
          top: -_scrollOffset * 0.3,
          left: 0,
          right: 0,
          height: 420,
          child: _BlurAura(imageUrl: artworkUrl, isDark: isDark),
        ),

        CustomScrollView(
          controller: _scrollController,
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 80)),

            SliverToBoxAdapter(
              child: Column(
                children: [
                  const SizedBox(height: 24),

                  _AlbumCover(
                    artworkUrl: artworkUrl,
                    tracks: tracks,
                  ),

                  const SizedBox(height: 28),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      album.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    album.artist,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),

                  const SizedBox(height: 24),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: Icon(
                            isFav ? Icons.favorite : Icons.favorite_border,
                            color: isFav
                                ? cs.primary
                                : cs.onSurfaceVariant,
                            size: 28,
                          ),
                          onPressed: () => _toggleAlbumFavorite(album, tracks),
                        ),
                        _AlbumDownloadButton(tracks: tracks),
                        IconButton(
                          icon: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.accent,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.play_arrow_rounded,
                                color: AppTheme.surface, size: 28),
                          ),
                          onPressed: () async {
                            final player = context.read<AudioPlayerService>();
                            await player.playAll(tracks);
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),

            if (tracks.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => StaggeredItem(
                      index: index,
                      child: TrackListTile(
                        track: tracks[index],
                        tracks: tracks,
                        index: index,
                      ),
                    ),
                    childCount: tracks.length,
                  ),
                ),
              )
            else
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                    child: Text('Sin canciones',
                        style: TextStyle(color: AppTheme.textMuted)),
                  ),
                ),
              ),
          ],
        ),

        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _GradientBlurBar(
            title: album.title,
            onBack: () => Navigator.maybePop(context),
          ),
        ),
      ],
    );
  }

  Future<void> _toggleAlbumFavorite(AddonAlbum album, List<Track> tracks) async {
    final account = context.read<AccountService>();
    if (!account.isLoggedIn) {
      if (context.mounted) AppToast.show(context, 'Inicia sesión para guardar álbumes');
      return;
    }
    final ok = await account.toggleFavorite(
      type: 'album',
      itemId: album.id,
      data: {
        'id': int.tryParse(album.id),
        'title': album.title,
        'type': album.type,
        'releaseDate': album.year?.toString(),
        'cover': coverUuidFromUrl(album.artworkURL ?? widget.initialArtwork),
        'artist': {'id': null, 'name': album.artist},
        'audioQuality': tracks.isNotEmpty ? _qualityOf(tracks.first) : 'LOSSLESS',
        'audioModes': _audioModesOf(tracks),
      },
    );
    if (context.mounted) {
      AppToast.show(
        context,
        ok ? 'Guardado en la biblioteca' : 'No se pudo actualizar',
        isError: !ok,
      );
    }
  }
}

class _BlurAura extends StatelessWidget {
  final String? imageUrl;
  final bool isDark;

  const _BlurAura({required this.imageUrl, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return const SizedBox.expand();
    }
    return OverflowBox(
      maxHeight: 500,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
        child: Transform.scale(
          scale: 1.4,
          child: CachedNetworkImage(
            imageUrl: imageUrl!,
            fit: BoxFit.cover,
            color: (isDark ? Colors.black : Colors.white).withOpacity(0.6),
            colorBlendMode: BlendMode.darken,
          ),
        ),
      ),
    );
  }
}

/// Download action next to the favourite button: shows aggregate state
/// across the album (partial ring / green check) and opens the batch dialog.
class _AlbumDownloadButton extends StatelessWidget {
  final List<Track> tracks;

  const _AlbumDownloadButton({required this.tracks});

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) return const SizedBox.shrink();
    final dm = context.watch<DownloadManagerService>();
    final cs = Theme.of(context).colorScheme;

    final downloaded = tracks.where((t) => dm.isDownloaded(t.id)).length;
    final downloading = tracks.any((t) => dm.isDownloading(t.id));
    final allDownloaded = downloaded == tracks.length;

    return IconButton(
      tooltip: 'Descargar álbum',
      icon: allDownloaded
          ? const Icon(Icons.download_done_rounded,
              color: Colors.greenAccent, size: 28)
          : Stack(
              alignment: Alignment.center,
              children: [
                if (downloading || downloaded > 0)
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      value: downloaded / tracks.length,
                      strokeWidth: 2,
                      color: AppTheme.accent,
                    ),
                  ),
                Icon(
                  Icons.download_rounded,
                  size: 26,
                  color: downloaded > 0 || downloading
                      ? AppTheme.accent
                      : cs.onSurfaceVariant,
                ),
              ],
            ),
      onPressed: () => BatchDownloadDialog.show(context, List.of(tracks)),
    );
  }
}

class _AlbumCover extends StatelessWidget {
  final String? artworkUrl;
  final List<Track> tracks;

  const _AlbumCover({
    required this.artworkUrl,
    required this.tracks,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SizedBox(
        width: 260,
        height: 260,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: 8,
              left: 16,
              right: 16,
              bottom: -8,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: cs.shadow.withOpacity(0.5),
                      blurRadius: 40,
                      spreadRadius: -4,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: artworkUrl != null
                    ? CachedNetworkImage(
                        imageUrl: artworkUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            const Icon(Icons.album, size: 64, color: Colors.white30),
                      )
                    : Container(
                        color: cs.surfaceContainerHigh,
                        child: const Icon(Icons.album, size: 64, color: Colors.white30),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _qualityOf(Track track) {
  final aq = track.audioQuality;
  if (aq != null) return aq.isHiRes ? 'HI_RES_LOSSLESS' : 'LOSSLESS';
  return 'LOSSLESS';
}

List<String>? _audioModesOf(List<Track> tracks) {
  for (final t in tracks) {
    final raw = t.rawData;
    if (raw is! Map) continue;
    final audioModes = (raw as Map)['audioModes'];
    if (audioModes is List) {
      return List<String>.from(audioModes);
    }
  }
  return null;
}

class _GradientBlurBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const _GradientBlurBar({
    required this.title,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final topPadding = MediaQuery.of(context).padding.top;
    final totalHeight = topPadding + kToolbarHeight + 8;

    return ClipRect(
      child: SizedBox(
        height: totalHeight,
        child: Stack(
          children: [
            Positioned.fill(
              child: Column(
                children: [
                  const Spacer(),
                  ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                      child: SizedBox(height: totalHeight * 0.2),
                    ),
                  ),
                  ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: SizedBox(height: totalHeight * 0.2),
                    ),
                  ),
                  ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: SizedBox(height: totalHeight * 0.2),
                    ),
                  ),
                  ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                      child: SizedBox(height: totalHeight * 0.2),
                    ),
                  ),
                  ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
                      child: SizedBox(height: totalHeight * 0.15),
                    ),
                  ),
                ],
              ),
            ),

            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.transparent,
                      Colors.white.withOpacity(0.08),
                      Colors.white.withOpacity(0.25),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),

            Positioned(
              top: topPadding,
              left: 4,
              right: 4,
              height: kToolbarHeight,
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded,
                        color: cs.onSurface, size: 20),
                    onPressed: onBack,
                  ),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
