import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/addon_service.dart';
import '../../core/services/account_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/audio_player_service.dart';
import '../shared/staggered_item.dart';
import '../../core/models/addon_models.dart';
import '../../core/utils/app_toast.dart';
import '../shared/track_list_tile.dart';
import '../shared/offline_banner.dart';
import '../shared/player_shell.dart';
import '../album/album_detail_screen.dart';
import '../shared/quality_badge.dart';

class ArtistDetailScreen extends StatefulWidget {
  final String id;
  final String addonId;
  final String initialTitle;
  final String? initialArtwork;

  const ArtistDetailScreen({
    super.key,
    required this.id,
    required this.addonId,
    required this.initialTitle,
    this.initialArtwork,
  });

  @override
  State<ArtistDetailScreen> createState() => _ArtistDetailScreenState();
}

class _ArtistDetailScreenState extends State<ArtistDetailScreen> {
  AddonArtist? _artist;
  bool _loading = true;
  String? _error;
  final Map<String, AddonAlbum> _albumDetails = {};
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
      final artist = await context
          .read<AddonService>()
          .getArtistDetail(widget.id, addonId: widget.addonId);
      if (!mounted) return;
      setState(() {
        _artist = artist;
        _loading = false;
      });
      if (artist != null) _enrichAlbums(artist);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _enrichAlbums(AddonArtist artist) async {
    final albums = artist.albums ?? [];
    if (albums.isEmpty) return;
    final service = context.read<AddonService>();
    final results = await Future.wait(
      albums.map((a) => service.getAlbumDetail(a.id,
          addonId: a.addonId, limit: 1)),
    );
    if (!mounted) return;
    final updated = <String, AddonAlbum>{};
    for (int i = 0; i < albums.length; i++) {
      final r = results[i];
      if (r != null) updated[r.id] = r;
    }
    if (updated.isNotEmpty) {
      setState(() {
        _albumDetails.addAll(updated);
      });
    }
  }

  AddonAlbum _albumFor(AddonAlbum a) => _albumDetails[a.id] ?? a;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final isDark = settings.isDarkMode;
    final cs = Theme.of(context).colorScheme;

    return PlayerShell(
      child: Scaffold(
        backgroundColor: AppTheme.pageBackground,
        body: Column(
          children: [
            const OfflineBanner(),
            Expanded(child: _buildBody(cs, isDark)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme cs, bool isDark) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: cs.primary),
      );
    }
    if (_error != null || _artist == null) {
      return Center(
        child: Text(
          'Error: $_error',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }

    final artist = _artist!;
    final topTracks =
        artist.topTracks?.map((t) => trackFromAddonTrack(t)).toList() ?? [];
    final albums = artist.albums ?? [];
    final artworkUrl = artist.artworkURL ?? widget.initialArtwork;

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

                  _ArtistCover(
                    artworkUrl: artworkUrl,
                  ),

                  const SizedBox(height: 28),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      artist.name,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _FavoriteButton(
                          isFav: context
                              .watch<AccountService>()
                              .isFavorite('artist', artist.id),
                          onPressed: () => _toggleArtistFavorite(artist),
                        ),
                        if (topTracks.isNotEmpty)
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
                              await player.playAll(topTracks);
                            },
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),

            if (topTracks.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                  child: Text(
                    'Canciones populares',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => StaggeredItem(
                      index: index,
                      child: TrackListTile(
                        track: topTracks[index],
                        tracks: topTracks,
                        index: index,
                      ),
                    ),
                    childCount: topTracks.length,
                  ),
                ),
              ),
            ],

            if (albums.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
                  child: Text(
                    'Álbumes (${albums.length})',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 160,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.72,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => StaggeredItem(
                      index: index,
                      child: _AlbumGridCard(
                        album: _albumFor(albums[index]),
                      ),
                    ),
                    childCount: albums.length,
                  ),
                ),
              ),
            ],
          ],
        ),

        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _GradientBlurBar(
            title: artist.name,
            onBack: () => Navigator.maybePop(context),
          ),
        ),
      ],
    );
  }

  Future<void> _toggleArtistFavorite(AddonArtist artist) async {
    final account = context.read<AccountService>();
    if (!account.isLoggedIn) {
      if (context.mounted) AppToast.show(context, 'Inicia sesión para guardar artistas');
      return;
    }
    final ok = await account.toggleFavorite(
      type: 'artist',
      itemId: artist.id,
      data: {
        'id': int.tryParse(artist.id),
        'name': artist.name,
        'picture': coverUuidFromUrl(artist.artworkURL),
        'image': artist.artworkURL,
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

class _FavoriteButton extends StatelessWidget {
  final bool isFav;
  final VoidCallback onPressed;

  const _FavoriteButton({
    required this.isFav,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(
        isFav ? Icons.favorite : Icons.favorite_border,
        color: isFav
            ? cs.primary
            : cs.onSurfaceVariant,
        size: 28,
      ),
      onPressed: onPressed,
    );
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

class _ArtistCover extends StatelessWidget {
  final String? artworkUrl;

  const _ArtistCover({required this.artworkUrl});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SizedBox(
        width: 220,
        height: 220,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: 6,
              left: 12,
              right: 12,
              bottom: -6,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: cs.shadow.withOpacity(0.6),
                      blurRadius: 36,
                      spreadRadius: -2,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: ClipOval(
                child: artworkUrl != null
                    ? CachedNetworkImage(
                        imageUrl: artworkUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            const Icon(Icons.person, size: 56, color: Colors.white30),
                      )
                    : Container(
                        color: cs.surfaceContainerHigh,
                        child: const Icon(Icons.person, size: 56, color: Colors.white30),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumGridCard extends StatelessWidget {
  final AddonAlbum album;

  const _AlbumGridCard({required this.album});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final badge = albumBadgeQuality(album);
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AlbumDetailScreen(
              id: album.id,
              addonId: album.addonId,
              initialTitle: album.title,
              initialArtwork: album.artworkURL,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: album.artworkURL != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: CachedNetworkImage(
                            imageUrl: album.artworkURL!,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) =>
                                const Icon(Icons.album, size: 32),
                          ),
                        )
                      : const Icon(Icons.album, size: 32),
                ),
                if (badge != null)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: QualityBadge.fromQuality(quality: badge),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            album.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            album.year ?? '',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
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
