import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
import '../shared/staggered_item.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/addon_service.dart';
import '../../core/services/local_library_service.dart';
import '../../core/services/account_service.dart';
import '../../core/models/models.dart';
import '../../core/models/addon_models.dart';
import '../../core/services/history_service.dart';
import '../../core/services/download_manager_service.dart';
import '../../core/utils/app_toast.dart';
import '../import/playlist_import_dialog.dart';
import '../album/album_detail_screen.dart';
import '../shared/offline_banner.dart';

const _seedTrackIds = [
  '426214797', '426651227', '436445459', '426178440', '424801149', '422281860',
  '380058874', '424468149', '437775283', '436206991', '415829263', '429540378',
  '422096216', '300692914', '1550546', '409386866',
];

const _genres = [
  ('Electronic', 'electronic'),
  ('Hip-Hop', 'hip hop'),
  ('Rock', 'rock'),
];

/// Home Screen — Hostinger Design System
/// Hero featured album, recommendations and genre album sections
class HomeScreen extends StatefulWidget {
  final Function(int)? onNavigate;

  const HomeScreen({super.key, this.onNavigate});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  List<Track> _recommended = [];
  AddonAlbum? _heroAlbum;
  List<Track> _heroTracks = [];
  final Map<String, List<AddonAlbum>> _genreAlbums = {
    for (final g in _genres) g.$2: [],
  };
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadHome());
  }

  Future<void> _loadHome() async {
    setState(() => _loading = true);
    final addonService = context.read<AddonService>();
    final history = context.read<HistoryService>();

    final seed = _pickSeed(history);

    // Performance: recommendations and all genre searches run concurrently
    // instead of sequentially (each is an independent network call), cutting
    // first-paint wait to the slowest single request.
    final results = await Future.wait<dynamic>([
      addonService.getRecommendations(seed, limit: 24),
      ..._genres.map((g) => addonService.searchAlbums(g.$2, limit: 10)),
    ]);
    if (!mounted) return;

    final recs = results[0] as List<Track>;
    final genreResults = <String, List<AddonAlbum>>{};
    for (var i = 0; i < _genres.length; i++) {
      genreResults[_genres[i].$2] = results[i + 1] as List<AddonAlbum>;
    }

    // Hero album detail loads in parallel with the first paint: the hero is
    // appended asynchronously so recommendations render without waiting.
    AddonAlbum? heroAlbum;
    final heroTracks = <Track>[];
    if (recs.isNotEmpty) {
      final hero = recs[Random().nextInt(recs.length)];
      if (hero.albumId != null) {
        final album = await addonService.getAlbumDetail(
          hero.albumId!,
          addonId: hero.addonId,
        );
        if (album != null && (album.tracks?.isNotEmpty ?? false)) {
          heroAlbum = album;
          heroTracks.addAll(album.tracks!.map(trackFromAddonTrack));
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _recommended = recs;
      _heroAlbum = heroAlbum;
      _heroTracks = heroTracks;
      _genreAlbums
        ..clear()
        ..addAll(genreResults);
      _loading = false;
    });
  }

  String _pickSeed(HistoryService history) {
    final recent = history.recentlyPlayed;
    if (recent.isNotEmpty) {
      final id = recent.first.addonTrackId ?? recent.first.id;
      if (id.isNotEmpty) return id;
    }
    return _seedTrackIds[Random().nextInt(_seedTrackIds.length)];
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Column(
      children: [
        const OfflineBanner(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadHome,
            color: AppTheme.accent,
            child: _buildHomeContent(),
          ),
        ),
      ],
    );
  }

  Widget _buildHomeContent() {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final history = context.watch<HistoryService>();
    final playHistory = history.recentlyPlayed;
    final account = context.watch<AccountService>();

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppTheme.space6,
        AppTheme.space2,
        AppTheme.space6,
        AppTheme.space6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppTheme.space2),

          // Hostinger Typography — Display heading
          Text(
            'Descubre música',
            style: text.displayMedium?.copyWith(
              fontFamily: AppTheme.displayFont,
              letterSpacing: -0.5,
            ),
          ),

          Text(
            account.isLoggedIn
                ? 'Hola, @${account.user!.username}'
                : 'Bienvenido a MetMusic - JioSaavn',
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              color: AppTheme.textMuted,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: AppTheme.space7),
          _buildHostingerSearchBar(history.recentSearches),
          const SizedBox(height: AppTheme.space6),

          if (_loading)
            Padding(
              padding: const EdgeInsets.only(top: 60),
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.accent),
              ),
            )
          else ...[
            if (_heroAlbum != null && _heroTracks.isNotEmpty) ...[
              _buildHostingerHero(_heroAlbum!, _heroTracks),
              const SizedBox(height: AppTheme.space7),
            ],

            if (_recommended.isNotEmpty) ...[
              Text(
                'Recomendado para ti',
                style: text.headlineMedium?.copyWith(
                  fontFamily: AppTheme.displayFont,
                ),
              ),
              const SizedBox(height: AppTheme.space4),
              SizedBox(
                height: 240,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _recommended.length > 14 ? 14 : _recommended.length,
                  itemBuilder: (context, index) {
                    return StaggeredItem(
                      index: index,
                      child: _HostingerTrackCard(
                        track: _recommended[index],
                        width: 176,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppTheme.space7),
            ],

            for (final genre in _genres) ...[
              if ((_genreAlbums[genre.$2] ?? []).isNotEmpty) ...[
                Text(
                  genre.$1,
                  style: text.headlineMedium?.copyWith(
                    fontFamily: AppTheme.displayFont,
                  ),
                ),
                const SizedBox(height: AppTheme.space4),
                SizedBox(
                  height: 225,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _genreAlbums[genre.$2]!.length,
                    itemBuilder: (context, index) => StaggeredItem(
                      index: index,
                      child: _HostingerAlbumCard(
                        album: _genreAlbums[genre.$2]![index],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.space7),
              ],
            ],
          ],

          if (playHistory.isNotEmpty) ...[
            Text(
              'Reproducido recientemente',
              style: text.headlineMedium?.copyWith(
                fontFamily: AppTheme.displayFont,
              ),
            ),
            const SizedBox(height: AppTheme.space4),
            SizedBox(
              height: 240,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: playHistory.length,
                itemBuilder: (context, index) {
                  return StaggeredItem(
                    index: index,
                    child: _HostingerTrackCard(
                      track: playHistory[index],
                      width: 176,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppTheme.space7),
          ],

          // Hostinger Quick Actions
          Text(
            'Acciones rápidas',
            style: text.headlineMedium?.copyWith(
              fontFamily: AppTheme.displayFont,
            ),
          ),
          const SizedBox(height: AppTheme.space4),
          Wrap(
            spacing: AppTheme.space3,
            runSpacing: AppTheme.space3,
            children: [
              StaggeredItem(
                index: 0,
                stagger: true,
                child: _HostingerQuickActionCard(
                  icon: Icons.library_music_rounded,
                  label: 'Tu biblioteca',
                  onTap: () => widget.onNavigate?.call(1),
                ),
              ),
              StaggeredItem(
                index: 1,
                stagger: true,
                child: _HostingerQuickActionCard(
                  icon: Icons.download_rounded,
                  label: 'Importar playlist',
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => const PlaylistImportDialog(),
                    );
                  },
                ),
              ),
            ],
          ),

          if (!_loading &&
              _recommended.isEmpty &&
              _heroAlbum == null &&
              playHistory.isEmpty) ...[
            const SizedBox(height: AppTheme.space9),
            Center(
              child: Column(
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(AppTheme.radiusDefault),
                    ),
                    child: Icon(
                      Icons.music_note_rounded,
                      size: 48,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: AppTheme.space4),
                  Text(
                    '¡Empieza a reproducir música!',
                    style: text.headlineSmall?.copyWith(
                      fontFamily: AppTheme.displayFont,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Hostinger Hero Card — gradient background with pill elements
  Widget _buildHostingerHero(AddonAlbum album, List<Track> tracks) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final player = context.read<AudioPlayerService>();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusDefault),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.surface,
            AppTheme.surface3,
          ],
        ),
        boxShadow: AppTheme.shadowStrong,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.space4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Album Art with rounded corners
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              child: CachedNetworkImage(
                imageUrl: album.artworkURL ?? '',
                width: 120,
                height: 120,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  width: 120,
                  height: 120,
                  color: AppTheme.surface3,
                  child: Icon(
                    Icons.album_rounded,
                    size: 40,
                    color: AppTheme.textMuted,
                  ),
                ),
                errorWidget: (_, __, ___) => Container(
                  width: 120,
                  height: 120,
                  color: AppTheme.surface3,
                  child: Icon(
                    Icons.album_rounded,
                    size: 40,
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppTheme.space4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hostinger badge style
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.space2,
                      vertical: AppTheme.space1,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                      border: Border.all(
                        color: AppTheme.accent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      'ÁLBUM DESTACADO',
                      style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.accent,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTheme.space2),
                  Text(
                    album.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleLarge?.copyWith(
                      fontFamily: AppTheme.displayFont,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: AppTheme.space1),
                  Text(
                    album.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      color: AppTheme.textMuted,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: AppTheme.space4),
                  Row(
                    children: [
                      // Hostinger primary button
                      ElevatedButton.icon(
                        onPressed: () async {
                          await player.playAll(tracks);
                        },
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: Text(
                          'REPRODUCIR',
                          style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
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
                      const SizedBox(width: AppTheme.space2),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AlbumDetailScreen(
                                id: album.id,
                                addonId: album.addonId,
                                initialTitle: album.title,
                                initialArtwork: album.artworkURL,
                              ),
                            ),
                          );
                        },
                        child: Text(
                          'Abrir álbum',
                          style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            color: AppTheme.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hostinger Search Bar — pill-shaped input
  Widget _buildHostingerSearchBar(List<String> searchHistory) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          readOnly: true,
          onTap: () {
            widget.onNavigate?.call(3);
          },
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            color: AppTheme.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: 'Busca canciones...',
            prefixIcon: Icon(
              Icons.search_rounded,
              color: AppTheme.textMuted,
            ),
            filled: true,
            fillColor: AppTheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusDefault),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusDefault),
              borderSide: BorderSide(
                color: AppTheme.border.withValues(alpha: 0.1),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusDefault),
              borderSide: const BorderSide(
                color: AppTheme.accent,
                width: 2,
              ),
            ),
          ),
        ),

        if (searchHistory.isNotEmpty) ...[
          const SizedBox(height: AppTheme.space4),
          Padding(
            padding: const EdgeInsets.only(left: AppTheme.space1),
            child: Text(
              'Búsquedas recientes',
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMuted,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: AppTheme.space3),
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: searchHistory.length > 8 ? 8 : searchHistory.length,
              itemBuilder: (context, index) {
                final query = searchHistory[index];
                return StaggeredItem(
                  index: index,
                  child: GestureDetector(
                    onTap: () => widget.onNavigate?.call(3),
                    child: Container(
                      margin: const EdgeInsets.only(right: AppTheme.space2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.space4,
                        vertical: AppTheme.space2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                        border: Border.all(
                          color: AppTheme.border.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          query,
                          style: TextStyle(
                            fontFamily: AppTheme.bodyFont,
                            fontSize: 13,
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

/// Hostinger Album Card — rounded corners, subtle shadow
class _HostingerAlbumCard extends StatelessWidget {
  final AddonAlbum album;

  const _HostingerAlbumCard({required this.album});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AlbumDetailScreen(
              id: album.id,
              addonId: album.addonId,
              initialTitle: album.title,
              initialArtwork: album.artworkURL,
            ),
          ),
        );
      },
      child: Container(
        width: 180,
        margin: const EdgeInsets.only(right: AppTheme.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Album Art — Hostinger style
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTheme.radiusDefault),
                    boxShadow: AppTheme.shadowMedium,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusDefault),                    child: CachedNetworkImage(
                      imageUrl: album.artworkURL ?? '',
                      width: 180,
                      height: 180,
                      fit: BoxFit.cover,
                      memCacheWidth: 360,
                      memCacheHeight: 360,
                      fadeInDuration: const Duration(milliseconds: 150),
                      placeholder: (_, __) => Container(
                        width: 180,
                        height: 180,
                        color: AppTheme.surface3,
                        child: Icon(
                          Icons.album_rounded,
                          size: 40,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        width: 180,
                        height: 180,
                        color: AppTheme.surface3,
                        child: Icon(
                          Icons.album_rounded,
                          size: 40,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.space2),
            Text(
              album.title,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              album.artist,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                color: AppTheme.textMuted,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Hostinger Track Card — modern rounded card
class _HostingerTrackCard extends StatelessWidget {
  final Track track;
  final double? width;

  const _HostingerTrackCard({
    required this.track,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final player = context.read<AudioPlayerService>();

    return GestureDetector(
      onTap: () => player.playSingleTrack(track),
      child: Container(
        width: width ?? 150,
        margin: const EdgeInsets.only(right: AppTheme.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Track Art — Hostinger style
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusDefault),
                boxShadow: AppTheme.shadowMedium,
              ),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusDefault),
                    child: CachedNetworkImage(
                      imageUrl: track.displayImage,
                      width: width ?? 176,
                      height: width ?? 176,
                      fit: BoxFit.cover,
                      memCacheWidth: 352,
                      memCacheHeight: 352,
                      fadeInDuration: const Duration(milliseconds: 150),
                      placeholder: (_, __) => Container(
                        width: width ?? 176,
                        height: width ?? 176,
                        color: AppTheme.surface3,
                        child: Icon(
                          Icons.music_note_rounded,
                          size: 40,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        width: width ?? 176,
                        height: width ?? 176,
                        color: AppTheme.surface3,
                        child: Icon(
                          Icons.music_note_rounded,
                          size: 40,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                  ),
                  // More options button
                  Positioned(
                    top: AppTheme.space1,
                    right: AppTheme.space1,
                    child: Material(
                      color: Colors.transparent,
                      child: PopupMenuButton<String>(
                        icon: Container(
                          padding: const EdgeInsets.all(AppTheme.space1),
                          decoration: BoxDecoration(
                            color: AppTheme.surface.withValues(alpha: 0.7),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.more_vert,
                            size: 16,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        onSelected: (value) => _handleMenuAction(context, value),
                        itemBuilder: (context) => [
                          _buildMenuItem(Icons.queue_music_rounded, 'Añadir a la cola'),
                          _buildMenuItem(Icons.playlist_play_rounded, 'Reproducir siguiente'),
                          _buildMenuItem(Icons.library_add_rounded, 'Añadir a biblioteca'),
                          _buildMenuItem(Icons.download_rounded, 'Descargar'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.space2),
            Text(
              track.title,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              track.artist,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                color: AppTheme.textMuted,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildMenuItem(IconData icon, String label) {
    return PopupMenuItem<String>(
      value: label,
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.textMuted),
          const SizedBox(width: AppTheme.space2),
          Text(
            label,
            style: TextStyle(
              fontFamily: AppTheme.bodyFont,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  void _handleMenuAction(BuildContext context, String action) {
    final player = context.read<AudioPlayerService>();

    switch (action) {
      case 'Añadir a la cola':
        player.addToQueue(track);
        AppToast.show(context, 'Añadido a la cola');
        break;
      case 'Reproducir siguiente':
        player.playNext(track);
        AppToast.show(context, 'Reproducirá a continuación');
        break;
      case 'Añadir a biblioteca':
        _showLibraryPicker(context, track);
        break;
      case 'Descargar':
        final addonService = context.read<AddonService>();
        final downloadManager = context.read<DownloadManagerService>();
        addonService
            .getStreamUrl(track.addonTrackId ?? track.id, addonId: track.addonId)
            .then((url) {
          if (url != null && context.mounted) {
            downloadManager.downloadTrack(track: track, streamUrl: url);
            AppToast.show(context, 'Descarga iniciada');
          } else if (context.mounted) {
            AppToast.show(context, 'No se pudo obtener la URL de descarga',
                isError: true);
          }
        });
        break;
    }
  }

  void _showLibraryPicker(BuildContext context, Track track) async {
    final cs = Theme.of(context).colorScheme;
    final addonService = context.read<AddonService>();
    final localService = context.read<LocalLibraryService>();

    final cloudLibraries = await addonService.getLibraries();
    final localLibraries = localService.getLibraries();

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusDefault),
        ),
      ),
      builder: (bContext) {
        if (cloudLibraries.isEmpty && localLibraries.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(AppTheme.space4),
            child: Center(
              child: Text(
                'No se encontraron bibliotecas. ¡Crea una primero!',
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  color: AppTheme.textMuted,
                ),
              ),
            ),
          );
        }

        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: AppTheme.space4),
          children: [
            if (localLibraries.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.space4,
                  vertical: AppTheme.space2,
                ),
                child: Text(
                  'BIBLIOTECAS LOCALES',
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              ...localLibraries.map((lib) => ListTile(
                    leading: Icon(Icons.folder_rounded, color: AppTheme.accent),
                    title: Text(
                      lib.name,
                      style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(bContext);
                      final success =
                          await localService.addTrackToLibrary(lib.id, track);
                      if (context.mounted) {
                        AppToast.show(
                          context,
                          success ? 'Añadido a ${lib.name}' : 'No se pudo añadir',
                          isError: !success,
                        );
                      }
                    },
                  )),
            ],
            if (cloudLibraries.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.space4,
                  vertical: AppTheme.space2,
                ),
                child: Text(
                  'BIBLIOTECAS EN LA NUBE',
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              ...cloudLibraries.map((lib) => ListTile(
                    leading: Icon(Icons.cloud_rounded, color: AppTheme.accent),
                    title: Text(
                      lib.name,
                      style: TextStyle(
                        fontFamily: AppTheme.bodyFont,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(bContext);
                      final success =
                          await addonService.addTracksToLibrary(lib.id, [track]);
                      if (context.mounted) {
                        AppToast.show(
                          context,
                          success ? 'Añadido a ${lib.name}' : 'No se pudo añadir',
                          isError: !success,
                        );
                      }
                    },
                  )),
            ],
          ],
        );
      },
    );
  }
}

/// Hostinger Quick Action Card — pill-shaped action buttons
class _HostingerQuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HostingerQuickActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.space4,
          vertical: AppTheme.space3,
        ),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusDefault),
          border: Border.all(
            color: AppTheme.border.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.accent, size: 20),
            const SizedBox(width: AppTheme.space2),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
