import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
import '../shared/staggered_item.dart';
import '../../core/services/addon_service.dart';
import '../../core/models/models.dart';
import '../../core/models/addon_models.dart';
import '../shared/track_list_tile.dart';
import '../shared/offline_banner.dart';
import '../import/playlist_import_dialog.dart';
import '../../core/services/history_service.dart';
import '../shared/addon_detail_screen.dart';
import '../artist/artist_detail_screen.dart';
import '../album/album_detail_screen.dart';

/// Search Screen — Hostinger Design System
/// Searches the catalog and displays unified results
class SearchScreen extends StatefulWidget {
  final Function(int)? onNavigate;
  const SearchScreen({super.key, this.onNavigate});

  @override
  State<SearchScreen> createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  AddonSearchResult? _results;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void focusSearch() {
    _focusNode.requestFocus();
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) return;

    context.read<HistoryService>().addSearch(query);

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final addonService = context.read<AddonService>();
      final results = await addonService.search(query);

      setState(() {
        _results = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Track _mapToAddonTrack(AddonTrack at) => trackFromAddonTrack(at);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      children: [
        const OfflineBanner(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.space6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header — Hostinger style
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded),
                          color: AppTheme.textPrimary,
                          onPressed: () => widget.onNavigate?.call(0),
                        ),
                        const SizedBox(width: AppTheme.space2),
                        Text(
                          'Buscar',
                          style: text.displayMedium?.copyWith(
                            fontFamily: AppTheme.displayFont,
                          ),
                        ),
                      ],
                    ),
                    // Hostinger pill button
                    ElevatedButton.icon(
                      onPressed: () => PlaylistImportDialog.show(context),
                      icon: const Icon(Icons.playlist_add_rounded,
                          size: 18, color: AppTheme.surface),
                      label: Text(
                        'IMPORTAR',
                        style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.surface,
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
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusDefault),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: AppTheme.space4),

                // Hostinger pill search input
                TextField(
                  controller: _searchController,
                  focusNode: _focusNode,
                  autofocus: true,
                  style: TextStyle(
                    fontFamily: AppTheme.bodyFont,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Busca canciones, álbumes, artistas...',
                    hintStyle: TextStyle(
                      fontFamily: AppTheme.bodyFont,
                      color: AppTheme.textMuted,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: AppTheme.textMuted,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close_rounded,
                                color: AppTheme.textMuted),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _results = null;
                              });
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AppTheme.surface,
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusDefault),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusDefault),
                      borderSide: BorderSide(
                        color: AppTheme.border.withValues(alpha: 0.1),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusDefault),
                      borderSide: const BorderSide(
                        color: AppTheme.accent,
                        width: 2,
                      ),
                    ),
                  ),
                  onSubmitted: _search,
                  onChanged: (value) => setState(() {}),
                ),

                const SizedBox(height: AppTheme.space6),

                Expanded(
                  child: _buildResults(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResults() {
    if (_isLoading) {
      return Center(
          child: CircularProgressIndicator(color: AppTheme.accent));
    }

    final addonService = context.watch<AddonService>();
    if (addonService.activeAddonId == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(AppTheme.radiusDefault),
              ),
              child: Icon(Icons.extension_off_rounded,
                  size: 48, color: AppTheme.textMuted),
            ),
            const SizedBox(height: AppTheme.space4),
            Text(
              'No hay proveedor de búsqueda activo',
              style: TextStyle(
                fontFamily: AppTheme.displayFont,
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppTheme.space2),
            Text(
              'Selecciona o instala un complemento para buscar.',
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                color: AppTheme.textMuted,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Text(
          'Error: $_error',
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            color: AppTheme.danger,
          ),
        ),
      );
    }

    if (_results == null) {
      final history = context.watch<HistoryService>();
      final recents = history.recentSearches;

      if (recents.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radiusDefault),
                ),
                child: Icon(Icons.search_rounded,
                    size: 48, color: AppTheme.textMuted),
              ),
              const SizedBox(height: AppTheme.space4),
              Text(
                'Busca tu música favorita',
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  color: AppTheme.textMuted,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        );
      } else {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppTheme.space2),
              child: Text(
                'Búsquedas recientes',
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: recents.length,
                itemBuilder: (context, index) {
                  final term = recents[index];
                  return StaggeredItem(
                    index: index,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.history_rounded,
                          color: AppTheme.textMuted),
                      title: Text(
                        term,
                        style: TextStyle(
                          fontFamily: AppTheme.bodyFont,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      onTap: () {
                        _searchController.text = term;
                        _search(term);
                      },
                      trailing: IconButton(
                        icon: Icon(Icons.north_west,
                            size: 16, color: AppTheme.textMuted),
                        onPressed: () {
                          _searchController.text = term;
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      }
    }

    if (_results!.isEmpty) {
      return Center(
        child: Text(
          'No se encontraron resultados',
          style: TextStyle(
            fontFamily: AppTheme.bodyFont,
            color: AppTheme.textMuted,
          ),
        ),
      );
    }

    // Map AddonTrack to Track for the player queue
    final allMappedTracks =
        _results!.tracks.map((t) => _mapToAddonTrack(t)).toList();

    // Split tracks into Top 3 and More
    final topTracks = allMappedTracks.take(3).toList();
    final moreTracks = allMappedTracks.length > 3
        ? allMappedTracks.sublist(3)
        : <Track>[];

    return CustomScrollView(
      slivers: [
        // 1. Top Results
        if (topTracks.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.space3),
              child: Text(
                'Resultados destacados',
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                return StaggeredItem(
                  index: index,
                  child: TrackListTile(
                    track: topTracks[index],
                    tracks: allMappedTracks,
                    index: index,
                  ),
                );
              },
              childCount: topTracks.length,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppTheme.space6)),
        ],

        // 2. Artists — Hostinger style
        if (_results!.artists.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.space4),
              child: Text(
                'Artistas',
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 165,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _results!.artists.length,
                itemBuilder: (context, index) {
                  final artist = _results!.artists[index];
                  return StaggeredItem(
                    index: index,
                    child: _HostingerArtistCard(artist: artist),
                  );
                },
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppTheme.space6)),
        ],

        // 3. Albums — Hostinger style
        if (_results!.albums.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.space4),
              child: Text(
                'Álbumes',
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 225,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _results!.albums.length,
                itemBuilder: (context, index) {
                  final album = _results!.albums[index];
                  return StaggeredItem(
                    index: index,
                    child: _HostingerAlbumCard(album: album),
                  );
                },
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppTheme.space6)),
        ],

        // 4. Playlists — Hostinger style
        if (_results!.playlists.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.space4),
              child: Text(
                'Playlists',
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 225,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _results!.playlists.length,
                itemBuilder: (context, index) {
                  final playlist = _results!.playlists[index];
                  return StaggeredItem(
                    index: index,
                    child: _HostingerPlaylistCard(playlist: playlist),
                  );
                },
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppTheme.space6)),
        ],

        // 5. More Tracks
        if (moreTracks.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.space3),
              child: Text(
                'Más canciones',
                style: TextStyle(
                  fontFamily: AppTheme.displayFont,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                return StaggeredItem(
                  index: index + 3,
                  child: TrackListTile(
                    track: moreTracks[index],
                    tracks: allMappedTracks,
                    index: index + 3,
                  ),
                );
              },
              childCount: moreTracks.length,
            ),
          ),
        ],
      ],
    );
  }
}

/// Hostinger Album Card
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
            builder: (context) => AlbumDetailScreen(
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
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(AppTheme.radiusDefault),
                    boxShadow: AppTheme.shadowMedium,
                  ),
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(AppTheme.radiusDefault),
                    child: album.artworkURL != null
                        ? CachedNetworkImage(
                            imageUrl: album.artworkURL!,
                            fit: BoxFit.cover,
                            memCacheWidth: 360,
                            memCacheHeight: 360,
                            placeholder: (_, __) => Container(
                              color: AppTheme.surface,
                              child: Icon(Icons.album_rounded,
                                  size: 40, color: AppTheme.textMuted),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: AppTheme.surface,
                              child: Icon(Icons.album_rounded,
                                  size: 40, color: AppTheme.textMuted),
                            ),
                          )
                        : Container(
                            color: AppTheme.surface,
                            child: Icon(Icons.album_rounded,
                                size: 40, color: AppTheme.textMuted),
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

/// Hostinger Artist Card
class _HostingerArtistCard extends StatelessWidget {
  final AddonArtist artist;

  const _HostingerArtistCard({required this.artist});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ArtistDetailScreen(
              id: artist.id,
              addonId: artist.addonId,
              initialTitle: artist.name,
              initialArtwork: artist.artworkURL,
            ),
          ),
        );
      },
      child: Container(
        width: 130,
        margin: const EdgeInsets.only(right: AppTheme.space3),
        child: Column(
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: AppTheme.surface,
                shape: BoxShape.circle,
                boxShadow: AppTheme.shadowMedium,
              ),
              child: ClipOval(
                child: artist.artworkURL != null
                    ? CachedNetworkImage(
                        imageUrl: artist.artworkURL!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: AppTheme.surface3,
                          child: Icon(Icons.person_rounded,
                              size: 36, color: AppTheme.textMuted),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: AppTheme.surface3,
                          child: Icon(Icons.person_rounded,
                              size: 36, color: AppTheme.textMuted),
                        ),
                      )
                    : Container(
                        color: AppTheme.surface3,
                        child: Icon(Icons.person_rounded,
                            size: 36, color: AppTheme.textMuted),
                      ),
              ),
            ),
            const SizedBox(height: AppTheme.space2),
            Text(
              artist.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTheme.bodyFont,
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
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

/// Hostinger Playlist Card
class _HostingerPlaylistCard extends StatelessWidget {
  final AddonPlaylist playlist;

  const _HostingerPlaylistCard({required this.playlist});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AddonDetailScreen(
              id: playlist.id,
              type: AddonDetailType.playlist,
              addonId: playlist.addonId,
              initialTitle: playlist.title,
              initialArtwork: playlist.artworkURL,
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
            Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.circular(AppTheme.radiusDefault),
                boxShadow: AppTheme.shadowMedium,
              ),
              child: ClipRRect(
                borderRadius:
                    BorderRadius.circular(AppTheme.radiusDefault),
                child: playlist.artworkURL != null
                    ? CachedNetworkImage(
                        imageUrl: playlist.artworkURL!,
                        fit: BoxFit.cover,
                        memCacheWidth: 360,
                        memCacheHeight: 360,
                        placeholder: (_, __) => Container(
                          color: AppTheme.surface,
                          child: Icon(Icons.queue_music_rounded,
                              size: 40, color: AppTheme.textMuted),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: AppTheme.surface,
                          child: Icon(Icons.queue_music_rounded,
                              size: 40, color: AppTheme.textMuted),
                        ),
                      )
                    : Container(
                        color: AppTheme.surface,
                        child: Icon(Icons.queue_music_rounded,
                            size: 40, color: AppTheme.textMuted),
                      ),
              ),
            ),
            const SizedBox(height: AppTheme.space2),
            Text(
              playlist.title,
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
              playlist.creator ?? 'Playlist',
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
