import 'dart:math';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/audio_player_service.dart';
import '../../core/services/settings_service.dart';

/// Lyrics screen with two selectable presentation modes:
///  - 'standard'   : clean, left-aligned synchronized lyrics (unchanged).
///  - 'visualizer' : animated backdrop + glowing, detailed line animations,
///                    with full landscape support for an immersive view.
/// Blur sigma (in px) for a lyric line given its distance (in lines) from the
/// currently playing line. The active line is sharp; neighbours get a soft
/// blur that ramps up with distance, so lines "emerge from" and "fade into" a
/// blur as they approach / leave the active one. Capped to stay cheap.
double _lineBlur(int distance, {double intensity = 1.0}) {
  if (distance <= 0) return 0;
  return (2.0 + (distance - 1) * 1.4).clamp(0.0, 8.0) * intensity;
}

class LyricsScreen extends StatelessWidget {
  const LyricsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final track = context.watch<AudioPlayerService>().currentTrack;
    final artwork = track?.displayImage ?? '';
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 1,
      minChildSize: .4,
      maxChildSize: 1,
      snap: true,
      snapSizes: const [.7, 1],
      builder: (context, scrollController) {
        if (settings.lyricsMode == 'visualizer') {
          return VisualizerLyrics(scrollController: scrollController);
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            if (artwork.isNotEmpty)
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 42, sigmaY: 42),
                child: Transform.scale(
                  scale: 1.15,
                  child: CachedNetworkImage(imageUrl: artwork, fit: BoxFit.cover),
                ),
              ),
            ColoredBox(color: cs.scrim.withOpacity(0.8)),
            LyricsList(scrollController: scrollController),
          ],
        );
      },
    );
  }
}

class LyricsList extends StatefulWidget {
  final ScrollController? scrollController;
  const LyricsList({this.scrollController, super.key});

  @override
  State<LyricsList> createState() => _LyricsListState();
}

class _LyricsListState extends State<LyricsList> {
  late final ScrollController _scrollController;
  final List<GlobalKey> _itemKeys = [];
  int _previousLyric = -1;
  double _estimatedItemHeight = 60;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ScrollController();
  }

  @override
  void dispose() {
    if (widget.scrollController == null) _scrollController.dispose();
    super.dispose();
  }

  void _scrollToActive(AudioPlayerService player) {
    if (player.currentLyricIndex == _previousLyric) return;
    _previousLyric = player.currentLyricIndex;
    final index = player.currentLyricIndex;
    if (index < 0 || index >= _itemKeys.length) return;
    _scrollToIndex(index, 0);
  }

  void _scrollToIndex(int index, int attempt) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final itemContext = _itemKeys[index].currentContext;
      if (itemContext != null) {
        final itemBox = itemContext.findRenderObject() as RenderBox?;
        final scrollBox = _scrollController.position.context.storageContext
            .findRenderObject() as RenderBox?;
        if (itemBox != null && scrollBox != null) {
          if (_estimatedItemHeight == 60 && itemBox.size.height > 0) {
            _estimatedItemHeight = itemBox.size.height;
          }
          final itemOffset = itemBox.localToGlobal(Offset.zero).dy -
              scrollBox.localToGlobal(Offset.zero).dy +
              _scrollController.offset;
          final target = itemOffset -
              (_scrollController.position.viewportDimension / 2) +
              (itemBox.size.height / 2);
          _scrollController.animateTo(
            target.clamp(0.0, _scrollController.position.maxScrollExtent),
            duration: const Duration(milliseconds: 550),
            curve: Curves.easeInOutCubic,
          );
          return;
        }
      }
      if (attempt >= 40) return;
      final maxExtent = _scrollController.position.maxScrollExtent;
      final estimated = (index * _estimatedItemHeight) -
          (_scrollController.position.viewportDimension / 2) +
          (_estimatedItemHeight / 2);
      _scrollController.jumpTo(estimated.clamp(0.0, maxExtent));
      _scrollToIndex(index, attempt + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerService>();
    final cs = Theme.of(context).colorScheme;
    final lyrics = player.lyrics;
    while (_itemKeys.length < lyrics.length) {
      _itemKeys.add(GlobalKey());
    }
    _scrollToActive(player);

    if (player.isFetchingLyrics) {
      return Center(child: CircularProgressIndicator(color: cs.onSurface));
    }
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                28, MediaQuery.of(context).padding.top + 22, 20, 26),
            child: Row(children: [
              Container(width: 36, height: 4, decoration: BoxDecoration(color: cs.outline, borderRadius: BorderRadius.circular(8))),
              const SizedBox(width: 14),
              Text('Letra', style: TextStyle(color: cs.onSurface, fontSize: 25, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
        if (lyrics.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('No hay letra disponible.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16))),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
                28, 0, 24, MediaQuery.of(context).padding.bottom + 100),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final lyric = lyrics[index];
                final active = index == player.currentLyricIndex;
                final passed = !active &&
                    player.currentLyricIndex >= 0 &&
                    index < player.currentLyricIndex;
                final sigma = _lineBlur((index - player.currentLyricIndex).abs(),
                    intensity: 0.4);
                return GestureDetector(
                  key: _itemKeys[index],
                  onTap: () => player.seekToLyric(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOutCubic,
                    margin: EdgeInsets.symmetric(
                      vertical: active ? 7 : 5,
                      horizontal: 0,
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    child: ImageFiltered(
                      imageFilter:
                          ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOutCubic,
                        style: TextStyle(
                          color: active
                              ? cs.onSurface
                              : (passed ? cs.outline : cs.onSurfaceVariant),
                          fontSize: active ? 24 : 23,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                          height: 1.34,
                          shadows: active
                              ? [
                                  Shadow(
                                    blurRadius: 14,
                                    color: cs.onSurface.withOpacity(0.22),
                                  ),
                                  Shadow(
                                    blurRadius: 26,
                                    color: cs.onSurface.withOpacity(0.14),
                                  ),
                                ]
                              : null,
                        ),
                        child: Text(lyric.text, textAlign: TextAlign.left),
                      ),
                    ),
                  ),
                );
              }, childCount: lyrics.length),
            ),
          ),
      ],
    );
  }
}

/// Immersive "Visualizer" lyrics mode: a slow animated backdrop (blurred
/// artwork + drifting glowing orbs) behind synchronized lines that glow and
/// scale in as they become active. Layout adapts to landscape orientation.
class VisualizerLyrics extends StatefulWidget {
  final ScrollController? scrollController;
  const VisualizerLyrics({this.scrollController});

  @override
  State<VisualizerLyrics> createState() => VisualizerLyricsState();
}

class VisualizerLyricsState extends State<VisualizerLyrics>
    with SingleTickerProviderStateMixin {
  late final ScrollController _scrollController;
  final List<GlobalKey> _itemKeys = [];
  int _previousLyric = -1;
  double _estimatedItemHeight = 80;
  late final AnimationController _bg;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ScrollController();
    _bg = AnimationController(vsync: this, duration: const Duration(seconds: 12))
      ..repeat();
  }

  @override
  void dispose() {
    if (widget.scrollController == null) _scrollController.dispose();
    _bg.dispose();
    super.dispose();
  }

  void _scrollToActive(AudioPlayerService player) {
    if (player.currentLyricIndex == _previousLyric) return;
    _previousLyric = player.currentLyricIndex;
    final index = player.currentLyricIndex;
    if (index < 0 || index >= _itemKeys.length) return;
    _scrollToIndex(index, 0);
  }

  void _scrollToIndex(int index, int attempt) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final itemContext = _itemKeys[index].currentContext;
      if (itemContext != null) {
        final itemBox = itemContext.findRenderObject() as RenderBox?;
        final scrollBox = _scrollController.position.context.storageContext
            .findRenderObject() as RenderBox?;
        if (itemBox != null && scrollBox != null) {
          if (_estimatedItemHeight == 80 && itemBox.size.height > 0) {
            _estimatedItemHeight = itemBox.size.height;
          }
          final itemOffset = itemBox.localToGlobal(Offset.zero).dy -
              scrollBox.localToGlobal(Offset.zero).dy +
              _scrollController.offset;
          final target = itemOffset -
              (_scrollController.position.viewportDimension / 2) +
              (itemBox.size.height / 2);
          _scrollController.animateTo(
            target.clamp(0.0, _scrollController.position.maxScrollExtent),
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeInOutCubic,
          );
          return;
        }
      }
      if (attempt >= 40) return;
      final maxExtent = _scrollController.position.maxScrollExtent;
      final estimated = (index * _estimatedItemHeight) -
          (_scrollController.position.viewportDimension / 2) +
          (_estimatedItemHeight / 2);
      _scrollController.jumpTo(estimated.clamp(0.0, maxExtent));
      _scrollToIndex(index, attempt + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerService>();
    final cs = Theme.of(context).colorScheme;
    final track = player.currentTrack;
    final artwork = track?.displayImage ?? '';
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final lyrics = player.lyrics;
    while (_itemKeys.length < lyrics.length) {
      _itemKeys.add(GlobalKey());
    }
    _scrollToActive(player);

    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: [
        _VisualizerBackdrop(artwork: artwork, controller: _bg),
        ColoredBox(color: cs.scrim.withOpacity(0.6)),
        if (player.isFetchingLyrics)
          Center(child: CircularProgressIndicator(color: cs.onSurface))
        else if (lyrics.isEmpty)
          Center(
            child: Text('No hay letra disponible.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16)),
          )
        else
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    landscape ? 40 : 28,
                    MediaQuery.of(context).padding.top +
                        (landscape ? 28 : 22),
                    landscape ? 40 : 20,
                    landscape ? 30 : 26,
                  ),
                  child: Row(
                    mainAxisAlignment: landscape
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: cs.outline,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text('Letra',
                          style: TextStyle(
                              color: cs.onSurface,
                              fontSize: 25,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  landscape ? 48 : 24,
                  0,
                  landscape ? 48 : 24,
                  MediaQuery.of(context).padding.bottom + 120,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final lyric = lyrics[index];
                    final active = index == player.currentLyricIndex;
                    final passed = !active &&
                        player.currentLyricIndex >= 0 &&
                        index < player.currentLyricIndex;
                    return _VisualizerLine(
                      key: _itemKeys[index],
                      text: lyric.text,
                      active: active,
                      passed: passed,
                      landscape: landscape,
                      blur: _lineBlur((index - player.currentLyricIndex).abs()),
                      onTap: () => player.seekToLyric(index),
                    );
                  }, childCount: lyrics.length),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// Animated backdrop: a single blurred copy of the album cover that drifts,
/// scales (Ken-Burns) and rotates with large, clearly visible motion so it
/// reads as a living visualizer. The blur is rasterized ONCE and cached; only
/// the cheap GPU transforms animate each frame, so it stays light on phones.
class _VisualizerBackdrop extends StatelessWidget {
  final String artwork;
  final AnimationController controller;
  const _VisualizerBackdrop(
      {required this.artwork, required this.controller});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = controller.value;
        final a = 2 * pi * t;
        final scaleX = 3.0 + 0.8 * sin(a);
        final scaleY = 2.9 + 0.8 * sin(a * 1.3 + 0.8);
        final dx = size.width * 0.45 * sin(a);
        final dy = size.height * 0.40 * cos(a * 0.73);
        final angle = 0.20 * sin(a * 0.7);
        return Transform.translate(
          offset: Offset(dx, dy),
          child: Transform.rotate(
            angle: angle,
            child: Transform.scale(
              scaleX: scaleX,
              scaleY: scaleY,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: artwork.isNotEmpty
                    ? CachedNetworkImage(imageUrl: artwork, fit: BoxFit.cover)
                    : Container(color: cs.scrim),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A single synchronized line for the Visualizer mode. When active it scales
/// up, brightens to pure white, gains letter-spacing and a cyan/white glow;
/// inactive lines stay dim and small. All transitions are animated.
class _VisualizerLine extends StatelessWidget {
  final String text;
  final bool active;
  final bool passed;
  final bool landscape;
  final double blur;
  final VoidCallback onTap;

  const _VisualizerLine({
    required super.key,
    required this.text,
    required this.active,
    required this.passed,
    required this.landscape,
    required this.blur,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeSize = landscape ? 33.0 : 27.0;
    final inactiveSize = landscape ? 28.0 : 23.0;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        margin: EdgeInsets.symmetric(
          vertical: active ? 9 : 6,
          horizontal: 0,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          textAlign: landscape ? TextAlign.center : TextAlign.left,
          style: TextStyle(
            color: active
                ? cs.onSurface
                : (passed ? cs.outline : cs.onSurfaceVariant),
            fontSize: active ? activeSize : inactiveSize,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            letterSpacing: active ? 0.2 : 0.0,
            height: 1.36,
            shadows: active
                ? [
                    Shadow(
                        blurRadius: 14,
                        color: cs.onSurface.withOpacity(0.22)),
                    Shadow(
                        blurRadius: 26,
                        color: cs.primary.withOpacity(0.18)),
                  ]
                : null,
          ),
          child: Text(text),
        ),
        ),
      ),
    );
  }
}
