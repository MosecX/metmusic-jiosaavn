import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/addon_service.dart';
import '../../core/services/account_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/models/addon_models.dart';
import '../shared/staggered_item.dart';
import '../../core/utils/app_toast.dart';
import '../shared/track_list_tile.dart';
import '../shared/offline_banner.dart';
import '../shared/player_shell.dart';

class MixScreen extends StatefulWidget {
  final String id;
  final String addonId;
  final String initialTitle;
  final String? initialArtwork;

  const MixScreen({
    super.key,
    required this.id,
    required this.addonId,
    required this.initialTitle,
    this.initialArtwork,
  });

  @override
  State<MixScreen> createState() => _MixScreenState();
}

class _MixScreenState extends State<MixScreen> {
  AddonMix? _mix;
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
      final mix = await context
          .read<AddonService>()
          .getMixDetail(widget.id, addonId: widget.addonId);
      if (!mounted) return;
      setState(() {
        _mix = mix;
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
    if (_error != null || _mix == null) {
      return Center(
        child: Text(
          'Error: $_error',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }

    final mix = _mix!;
    final tracks = mix.tracks?.map((t) => trackFromAddonTrack(t)).toList() ?? [];
    final artworkUrl = mix.artworkURL ?? widget.initialArtwork;
    final isFav = context
        .watch<AccountService>()
        .isFavorite('mix', _favId);

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

                  _MixCover(
                    artworkUrl: artworkUrl,
                  ),

                  const SizedBox(height: 28),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.auto_awesome,
                          color: Color(0xFFFACC15), size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          mix.title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),

                  if (mix.subtitle != null && mix.subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      mix.subtitle!,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                  ],

                  if (mix.description != null && mix.description!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        mix.description!,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],

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
                          onPressed: () => _toggleMixFavorite(mix),
                        ),
                        if (tracks.isNotEmpty)
                          IconButton(
                            icon: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.accent,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.play_arrow_rounded,
                                  color: Colors.black, size: 28),
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
            title: mix.title,
            onBack: () => Navigator.maybePop(context),
          ),
        ),
      ],
    );
  }

  String get _favId =>
      (_mix?.id.isNotEmpty ?? false) ? _mix!.id : widget.id;

  Future<void> _toggleMixFavorite(AddonMix mix) async {
    final account = context.read<AccountService>();
    if (!account.isLoggedIn) {
      if (context.mounted) {
        AppToast.show(context, 'Inicia sesión para guardar mixes');
      }
      return;
    }
    final ok = await account.toggleFavorite(
      type: 'mix',
      itemId: _favId,
      data: {
        'id': mix.id,
        'title': mix.title,
        'subtitle': mix.subtitle,
        'description': mix.description,
        'type': 'MIX',
        'addonId': widget.addonId,
        'images': {
          'LARGE': {'url': mix.artworkURL},
          'MEDIUM': {'url': mix.artworkURL},
          'SMALL': {'url': mix.artworkURL},
        },
        'picture': coverUuidFromUrl(mix.artworkURL),
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

class _MixCover extends StatelessWidget {
  final String? artworkUrl;

  const _MixCover({required this.artworkUrl});

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
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: artworkUrl != null
                    ? CachedNetworkImage(
                        imageUrl: artworkUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            const Icon(Icons.auto_awesome, size: 56, color: Colors.white30),
                      )
                    : Container(
                        color: cs.surfaceContainerHigh,
                        child: const Icon(Icons.auto_awesome, size: 56, color: Colors.white30),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
