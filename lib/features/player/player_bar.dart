import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/account_service.dart';
import '../../core/models/models.dart';
import '../lyrics/lyrics_screen.dart';
import '../queue/queue_screen.dart';
import '../artist/artist_detail_screen.dart';
import '../../core/utils/app_toast.dart';

/// Player Bar - bottom player controls matching original exactly
class PlayerBar extends StatefulWidget {
  const PlayerBar({super.key});

  @override
  State<PlayerBar> createState() => _PlayerBarState();
}

class _PlayerBarState extends State<PlayerBar> {
  OverlayEntry? _lyricsOverlay;
  OverlayEntry? _expandedOverlay;

  void _toggleLyrics(BuildContext context) {
    if (_lyricsOverlay != null) {
      _removeLyricsOverlay();
    } else {
      _showLyricsOverlay(context);
    }
  }

  void _removeLyricsOverlay() {
    _lyricsOverlay?.remove();
    _lyricsOverlay = null;
  }

  void _showLyricsOverlay(BuildContext context) {
    final settings = context.read<SettingsService>();
    final useVisualizer = settings.lyricsMode == 'visualizer';

    if (useVisualizer) {
      _expandedOverlay?.remove();
      final overlay = Overlay.of(context);
      _expandedOverlay = OverlayEntry(
        builder: (ctx) => _FullVisualizerOverlay(
          onClose: () {
            _expandedOverlay?.remove();
            _expandedOverlay = null;
          },
        ),
      );
      overlay.insert(_expandedOverlay!);
      return;
    }

    final overlay = Overlay.of(context);
    final cs = Theme.of(context).colorScheme;
    _lyricsOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: 0,
        left: 0,
        right: 0,
        bottom: 72,
        child: Material(
          color: cs.surface.withValues(alpha: 0.9),
          child: const LyricsList(),
        ),
      ),
    );

    overlay.insert(_lyricsOverlay!);
  }

  void _showExpandedPlayer(BuildContext context, AudioPlayerService player, Track track) {
    _expandedOverlay?.remove();
    final overlay = Overlay.of(context);
    _expandedOverlay = OverlayEntry(
      builder: (ctx) => _ExpandedDesktopPlayer(
        player: player,
        track: track,
        onClose: () {
          _expandedOverlay?.remove();
          _expandedOverlay = null;
        },
      ),
    );
    overlay.insert(_expandedOverlay!);
  }

  @override
  void dispose() {
    _removeLyricsOverlay();
    _expandedOverlay?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerService>();
    final cs = Theme.of(context).colorScheme;
    final track = player.currentTrack;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;

    if (track == null) {
      return const SizedBox.shrink();
    }

    return Container(
      height: isMobile ? 60 : 72,
      decoration: BoxDecoration(
        color: cs.surfaceContainer.withValues(alpha: 0.95),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: isMobile
          ? _MobilePlayerBar(track: track, player: player)
          : _DesktopPlayerBar(
              track: track,
              player: player,
              onLyricsTap: () => _toggleLyrics(context),
              onTrackTap: () => _showExpandedPlayer(context, player, track),
            ),
    );
  }
}

class _DesktopPlayerBar extends StatelessWidget {
  final Track track;
  final AudioPlayerService player;
  final VoidCallback onLyricsTap;
  final VoidCallback onTrackTap;

  const _DesktopPlayerBar({
    required this.track,
    required this.player,
    required this.onLyricsTap,
    required this.onTrackTap,
  });

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textColor = cs.onSurface;
    final secondaryColor = cs.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: Row(
        children: [
          SizedBox(
            width: 260,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: onTrackTap,
                  child: _TrackArt(
                      imageUrl: track.displayImage,
                      isDownloaded: false,
                      size: 46),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        style: TextStyle(
                            color: textColor, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      GestureDetector(
                        onTap: track.artistId != null
                            ? () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ArtistDetailScreen(
                                      id: track.artistId!,
                                      addonId: track.addonId ?? '',
                                      initialTitle: track.artist,
                                    ),
                                  ),
                                );
                              }
                            : null,
                        child: Text(
                          track.artist,
                          style: TextStyle(
                            color: secondaryColor,
                            fontSize: 12,
                            decoration: track.artistId != null
                                ? TextDecoration.underline
                                : null,
                            decorationColor: secondaryColor.withValues(alpha: 0.3),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (track.isHiRes)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            track.audioQuality!.displayText,
                            style: const TextStyle(
                                color: Colors.black,
                                fontSize: 9,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ),
                Consumer<AccountService>(
                  builder: (context, account, child) {
                    final isFav = account.isFavorite(
                        'track', track.addonTrackId ?? track.id);
                    return IconButton(
                      icon:
                          Icon(isFav ? Icons.favorite : Icons.favorite_border),
                      color: isFav ? cs.primary : secondaryColor,
                      iconSize: 22,
                      onPressed: () => _toggleFavorite(context, account, track),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      constraints: const BoxConstraints(),
                    );
                  },
                ),
              ],
            ),
          ),

          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.shuffle),
                        iconSize: 20,
                        color: player.shuffleEnabled
                            ? cs.primary
                            : secondaryColor,
                        onPressed: player.toggleShuffle,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 15),
                      IconButton(
                        icon: const Icon(Icons.skip_previous),
                        iconSize: 28,
                        color: textColor,
                        onPressed: player.previousTrack,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 15),
                      InkWell(
                        onTap: player.togglePlayPause,
                        borderRadius: BorderRadius.circular(30),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                              color: cs.primary,
                              shape: BoxShape.circle),
                          child: player.isLoadingTrack
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.black),
                                  ),
                                )
                              : Icon(
                                  player.isPlaying
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                  color: Colors.black,
                                  size: 20,
                                ),
                        ),
                      ),
                      const SizedBox(width: 15),
                      IconButton(
                        icon: const Icon(Icons.skip_next),
                        iconSize: 28,
                        color: textColor,
                        onPressed: player.nextTrack,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 15),
                      IconButton(
                        icon: Icon(
                          player.loopMode == LoopMode.one
                              ? Icons.repeat_one
                              : Icons.repeat,
                        ),
                        iconSize: 20,
                        color: player.loopMode != LoopMode.off
                            ? cs.primary
                            : secondaryColor,
                        onPressed: player.toggleLoop,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text(
                        _formatDuration(player.position),
                        style: TextStyle(color: secondaryColor, fontSize: 11),
                      ),
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6.0),
                                  child: LinearProgressIndicator(
                                    value: player.bufferedSliderValue / 1000,
                                    backgroundColor: cs.surfaceContainerHigh,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      cs.onSurface.withValues(alpha: 0.3),
                                    ),
                                    minHeight: 4,
                                  ),
                                ),
                              ),
                            ),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: cs.primary,
                                inactiveTrackColor: Colors.transparent,
                                trackHeight: 2,
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 14),
                              ),
                              child: Slider(
                                value: player.sliderValue.toDouble(),
                                min: 0,
                                max: 1000,
                                onChanged: (value) =>
                                    player.seekToSlider(value.toInt()),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _formatDuration(player.duration),
                        style: TextStyle(color: secondaryColor, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          SizedBox(
            width: 260,
            child: Padding(
              padding: const EdgeInsets.only(right: 20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.lyrics_outlined),
                    color: secondaryColor,
                    onPressed: onLyricsTap,
                    iconSize: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.queue_music),
                    color: secondaryColor,
                    onPressed: () => _showQueue(context),
                    iconSize: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                  ),
                  _VolumeButton(player: player, secondaryColor: secondaryColor),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showQueue(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const QueueScreen(),
    );
  }

  Future<void> _toggleFavorite(
      BuildContext context, AccountService account, Track track) async {
    if (!account.isLoggedIn) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inicia sesión para dar me gusta')),
        );
      }
      return;
    }
    await account.toggleFavorite(
      type: 'track',
      itemId: track.addonTrackId ?? track.id,
      data: storedTrackFromTrack(track),
    );
  }
}

class _VolumeButton extends StatefulWidget {
  final AudioPlayerService player;
  final Color secondaryColor;

  const _VolumeButton({required this.player, required this.secondaryColor});

  @override
  State<_VolumeButton> createState() => _VolumeButtonState();
}

class _VolumeButtonState extends State<_VolumeButton> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  void _toggleVolumeSlider() {
    if (_overlayEntry != null) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showOverlay() {
    final overlay = Overlay.of(context);

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: 160,
        height: 50,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(-60, -60), // Position above and slightly left
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(10),
            color: Theme.of(context).cardColor,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 8),
                const Icon(Icons.volume_down, size: 20),
                Expanded(
                  child: StatefulBuilder(builder: (context, setState) {
                    return SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 6),
                        trackHeight: 2,
                      ),
                      child: Slider(
                        value: widget.player.volume,
                        onChanged: (value) {
                          widget.player.setVolume(value);
                          setState(() {});
                        },
                      ),
                    );
                  }),
                ),
                const Icon(Icons.volume_up, size: 20),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: IconButton(
        icon:
            Icon(widget.player.volume > 0 ? Icons.volume_up : Icons.volume_off),
        iconSize: 20,
        color: widget.secondaryColor,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        constraints: const BoxConstraints(),
        visualDensity: VisualDensity.compact,
        onPressed: _toggleVolumeSlider,
      ),
    );
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }
}

class _MobilePlayerBar extends StatelessWidget {
  final Track track;
  final AudioPlayerService player;

  const _MobilePlayerBar({
    required this.track,
    required this.player,
  });

  @override
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textColor = cs.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LinearProgressIndicator(
          value: player.sliderValue / 1000,
          backgroundColor: Colors.transparent,
          valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
          minHeight: 2,
        ),
        GestureDetector(
          onTap: () => _showExpandedPlayer(context),
          onVerticalDragEnd: (details) {
            if (details.primaryVelocity! < -300) {
              _showExpandedPlayer(context);
            } else if (details.primaryVelocity! > 300) {
              player.clearQueue();
            }
          },
          child: Container(
            color: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              children: [
                _TrackArt(
                    imageUrl: track.displayImage,
                    size: 44,
                    isDownloaded: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(track.title,
                          style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(track.artist,
                          style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 11),
                          maxLines: 1),
                    ],
                  ),
                ),
                Consumer<AccountService>(
                  builder: (context, account, child) {
                    final isFav = account.isFavorite(
                        'track', track.addonTrackId ?? track.id);
                    return IconButton(
                      icon:
                          Icon(isFav ? Icons.favorite : Icons.favorite_border),
                      color: isFav
                          ? cs.primary
                          : cs.onSurfaceVariant,
                      iconSize: 20,
                      onPressed: () {
                        if (!account.isLoggedIn) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Inicia sesión para dar me gusta')),
                          );
                          return;
                        }
                        account.toggleFavorite(
                          type: 'track',
                          itemId: track.addonTrackId ?? track.id,
                          data: storedTrackFromTrack(track),
                        );
                      },
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      constraints: const BoxConstraints(),
                    );
                  },
                ),
                InkWell(
                    onTap: player.togglePlayPause,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                            color: cs.primary,
                            shape: BoxShape.circle),
                        child: player.isLoadingTrack
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.black),
                                ),
                              )
                            : Icon(
                                player.isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                                color: Colors.black,
                                size: 22))),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  color: textColor,
                  onPressed: player.nextTrack,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showExpandedPlayer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _ExpandedMobilePlayer(player: player, track: track),
    );
  }
}

class _ExpandedMobilePlayer extends StatefulWidget {
  final AudioPlayerService player;
  final Track track;

  const _ExpandedMobilePlayer({
    required this.player,
    required this.track,
  });

  @override
  State<_ExpandedMobilePlayer> createState() => _ExpandedMobilePlayerState();
}

class _ExpandedMobilePlayerState extends State<_ExpandedMobilePlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _scale = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.repeat(reverse: true, period: const Duration(seconds: 20));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildBlurredBackground(Track track) {
    final imageUrl = track.displayImage;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (imageUrl.isNotEmpty)
          AnimatedBuilder(
            animation: _scale,
            builder: (context, child) => Transform.scale(
              scale: _scale.value,
              child: child,
            ),
            child: SizedBox.expand(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 45, sigmaY: 45),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),
          )
        else
          Container(
            color: Theme.of(context).colorScheme.surface,
          ),
        Container(color: Colors.black.withValues(alpha: 0.62)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textColor = cs.onSurface;
    final secondaryColor = cs.onSurfaceVariant;

    return DraggableScrollableSheet(
      initialChildSize: 1.0,
      minChildSize: 0.0,
      maxChildSize: 1.0,
      snap: true,
      builder: (context, scrollController) {
        final screenHeight = MediaQuery.of(context).size.height;
        final isSmallScreen = screenHeight < 700;

        // Dynamic sizes
        final artSize = isSmallScreen ? screenHeight * 0.3 : 300.0;
        final titleFontSize = isSmallScreen ? 20.0 : 26.0;
        final artistFontSize = isSmallScreen ? 14.0 : 18.0;
        final sectionSpacing = isSmallScreen ? 15.0 : 30.0;

        return Consumer<AudioPlayerService>(builder: (context, player, _) {
          // The sheet remains open while the queue advances, so always read
          // the live track instead of the one that opened the sheet.
          final track = player.currentTrack ?? widget.track;
          return Stack(
            fit: StackFit.expand,
            children: [
              _buildBlurredBackground(track),
              Container(
                decoration: const BoxDecoration(
                  color: Colors.transparent,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: screenHeight,
                ),
                child: Padding(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 34,
                    left: 24,
                    right: 24,
                    bottom: MediaQuery.of(context).padding.bottom + 20,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Drag handle
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: cs.outline,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      // Tapping the cover opens lyrics; it replaces the old
                      // dedicated lyrics button and keeps the player cleaner.
                      GestureDetector(
                        onTap: () => showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => const LyricsScreen(),
                        ),
                        child: SizedBox(
                          height: artSize,
                          child: Center(
                            child: Stack(
                              alignment: Alignment.bottomRight,
                              children: [
                                _TrackArt(
                                  imageUrl: track.displayImage,
                                  size: artSize - 20,
                                  isDownloaded: false,
                                ),
                                Container(
                                  margin: const EdgeInsets.all(10),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white38, width: 1),
                                  ),
                                  child: const Icon(Icons.lyrics_outlined,
                                      color: Colors.white, size: 22),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: sectionSpacing),

                      // Info
                      Column(
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              track.title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: textColor,
                                  fontSize: titleFontSize,
                                  fontWeight: FontWeight.bold),
                              maxLines: 2,
                            ),
                          ),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: track.artistId != null
                                ? () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ArtistDetailScreen(
                                          id: track.artistId!,
                                          addonId: track.addonId ?? '',
                                          initialTitle: track.artist,
                                        ),
                                      ),
                                    );
                                  }
                                : null,
                            child: Text(track.artist,
                                style: TextStyle(
                                  color: secondaryColor,
                                  fontSize: artistFontSize,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1),
                          ),
                        ],
                      ),
                      SizedBox(height: sectionSpacing),

                      // Progress
                      Column(
                        children: [
                          Stack(
                            children: [
                              // Buffered Indicator
                              Positioned.fill(
                                child: Align(
                                  alignment: Alignment.center,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal:
                                            24.0), // Slider internal padding default is around 24
                                    child: LinearProgressIndicator(
                                      value: player.bufferedSliderValue / 1000,
                                      backgroundColor: cs.surfaceContainerHigh,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        cs.onSurface.withValues(alpha: 0.3),
                                      ),
                                      minHeight: 4,
                                    ),
                                  ),
                                ),
                              ),
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  inactiveTrackColor: Colors.transparent,
                                ),
                                child: Slider(
                                  value: player.sliderValue.toDouble(),
                                  min: 0,
                                  max: 1000,
                                  activeColor: cs.primary,
                                  onChanged: (v) =>
                                      player.seekToSlider(v.toInt()),
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_formatDuration(player.position),
                                    style: TextStyle(
                                        color: secondaryColor, fontSize: 12)),
                                Text(_formatDuration(player.duration),
                                    style: TextStyle(
                                        color: secondaryColor, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Controls with Loop/Shuffle
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.shuffle),
                            iconSize: 28, // Added size
                            color: player.shuffleEnabled
                                ? cs.primary
                                : secondaryColor,
                            onPressed: player.toggleShuffle,
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_previous,
                                size: 42), // Increased
                            color: textColor,
                            onPressed: player.previousTrack,
                          ),
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              boxShadow: player.isPlaying
                                  ? AppTheme.glowShadow(AppTheme.sky, 0.3)
                                  : const [],
                            ),
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              onPressed: player.togglePlayPause,
                              iconSize: 38,
                              color: Colors.black,
                              icon: player.isLoadingTrack
                                  ? const SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                Colors.black),
                                      ),
                                    )
                                  : Icon(player.isPlaying
                                      ? Icons.pause
                                      : Icons.play_arrow),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_next,
                                size: 42), // Increased
                            color: textColor,
                            onPressed: player.nextTrack,
                          ),
                          IconButton(
                            icon: Icon(player.loopMode == LoopMode.one
                                ? Icons.repeat_one
                                : Icons.repeat),
                            iconSize: 28, // Added size
                            color: player.loopMode != LoopMode.off
                                ? cs.primary
                                : secondaryColor,
                            onPressed: player.toggleLoop,
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Acciones inferiores: favorito, añadir a playlist y cola.
                      // Botones pequeños y sutiles para no recargar la vista.
                      Consumer<AccountService>(
                        builder: (context, account, _) {
                          final isFav = account.isFavorite(
                              'track', track.addonTrackId ?? track.id);
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _SubtleIconButton(
                                icon: isFav
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                active: isFav,
                                onPressed: () {
                                  if (!account.isLoggedIn) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content:
                                              Text('Log in to like songs')),
                                    );
                                    return;
                                  }
                                  account.toggleFavorite(
                                    type: 'track',
                                    itemId: track.addonTrackId ?? track.id,
                                    data: storedTrackFromTrack(track),
                                  );
                                },
                              ),
                              _SubtleIconButton(
                                icon: Icons.playlist_add,
                                onPressed: () =>
                                    _showAddToPlaylist(context, track),
                              ),
                              _SubtleIconButton(
                                icon: Icons.queue_music,
                                onPressed: () => showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (_) => const QueueScreen(),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
        });
      },
    );
  }
}

class _TrackArt extends StatelessWidget {
  final String imageUrl;
  final double size;
  final bool isDownloaded;

  const _TrackArt({
    required this.imageUrl,
    this.size = 55,
    required this.isDownloaded,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: cs.surfaceContainer,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: imageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: cs.surfaceContainer),
                    errorWidget: (_, __, ___) =>
                        const Icon(Icons.music_note, color: Colors.white30),
                  )
                : const Icon(Icons.music_note, color: Colors.white30),
          ),
        ),
        if (isDownloaded)
          Positioned(
            right: 2,
            bottom: 2,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.check, size: 12, color: Colors.black),
            ),
          ),
      ],
    );
  }
}

/// Small, minimalist icon button used in the expanded player's bottom row
/// (favorite / add-to-playlist / queue). Keeps the player from feeling
/// top-heavy and cluttered.
class _SubtleIconButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onPressed;

  const _SubtleIconButton({
    required this.icon,
    this.active = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(icon),
      iconSize: 22,
      splashRadius: 20,
      color: active ? cs.primary : cs.onSurfaceVariant,
      onPressed: onPressed,
    );
  }
}

/// Bottom-sheet to add the given track to an existing playlist or a new one.
Future<void> _showAddToPlaylist(BuildContext context, Track track) async {
  final account = context.read<AccountService>();
  final cs = Theme.of(context).colorScheme;
  if (!account.isLoggedIn) {
    if (context.mounted) {
      AppToast.show(context, 'Inicia sesión para añadir a playlists');
    }
    return;
  }

  final playlists = await account.getPlaylists();
  if (!context.mounted) return;

  showModalBottomSheet(
    context: context,
    builder: (_) => SafeArea(
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Añadir a playlist',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            ListTile(
              leading: Icon(Icons.add_circle_outline,
                  color: cs.primary),
              title: const Text('Nueva playlist'),
              onTap: () async {
                Navigator.pop(context);
                final controller = TextEditingController();
                final name = await showDialog<String>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Nueva playlist'),
                    content: TextField(
                      controller: controller,
                      autofocus: true,
                      decoration:
                          const InputDecoration(hintText: 'Nombre de la playlist'),
                    ),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancelar')),
                      TextButton(
                          onPressed: () =>
                              Navigator.pop(ctx, controller.text.trim()),
                          child: const Text('Crear')),
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
                      AppToast.show(context, 'Se añadió "${track.title}" a $name');
                    }
                  }
                }
              },
            ),
            if (playlists.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Aún no tienes playlists.'),
              )
            else
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: playlists.length,
                  itemBuilder: (context, index) {
                    final pl = playlists[index];
                    return ListTile(
                      leading: const Icon(Icons.queue_music),
                      title: Text(pl.name),
                      onTap: () async {
                        Navigator.pop(context);
                        await context
                            .read<AccountService>()
                            .addTrackToPlaylist(pl.id, track);
                        if (context.mounted) {
                          AppToast.show(context,
                              'Se añadió "${track.title}" a ${pl.name}');
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

class _ExpandedDesktopPlayer extends StatefulWidget {
  final AudioPlayerService player;
  final Track track;
  final VoidCallback onClose;

  const _ExpandedDesktopPlayer({
    required this.player,
    required this.track,
    required this.onClose,
  });

  @override
  State<_ExpandedDesktopPlayer> createState() => _ExpandedDesktopPlayerState();
}

class _ExpandedDesktopPlayerState extends State<_ExpandedDesktopPlayer>
    with SingleTickerProviderStateMixin {
  final FocusNode _focusNode = FocusNode();
  late final AnimationController _anim;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.92, end: 1.0).animate(
        CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onClose,
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Material(
              color: Colors.black87,
              child: Stack(
                children: [
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 12,
                    right: 16,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 28),
                      onPressed: widget.onClose,
                    ),
                  ),
                  Center(
                    child: _ExpandedMobilePlayer(
                      player: widget.player,
                      track: widget.track,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FullVisualizerOverlay extends StatefulWidget {
  final VoidCallback onClose;
  const _FullVisualizerOverlay({required this.onClose});

  @override
  State<_FullVisualizerOverlay> createState() => _FullVisualizerOverlayState();
}

class _FullVisualizerOverlayState extends State<_FullVisualizerOverlay>
    with SingleTickerProviderStateMixin {
  final FocusNode _focusNode = FocusNode();
  late final AnimationController _anim;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _anim.forward();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onClose,
        child: FadeTransition(
          opacity: _fade,
          child: Material(
            color: Colors.black,
            child: Stack(
              children: [
                const VisualizerLyrics(),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  right: 16,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: widget.onClose,
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}