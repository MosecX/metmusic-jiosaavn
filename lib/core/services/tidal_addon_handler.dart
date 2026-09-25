import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../models/addon_models.dart';
import 'user_addon_handler.dart';
import 'settings_service.dart';

/// Built-in "Tidal HiFi" addon that proxies the MetMusic private backend.
///
/// The backend (https://<project>.functions.supabase.co/api) exposes an
/// Eclipse-Music-compatible catalog: /search, /tracks/:id, /albums/:id,
/// /artists/:id, /playlists/:id, /mixes/:id, /lyrics/:id, /recommendations/:id,
/// /stream/:id and /manifest/:id. All image URLs are already final Tidal CDN
/// URLs, so no UUID→URL conversion is needed here.
const _defaultBackendBase =
    'https://hzloipljzbnammznxfnz.functions.supabase.co/api';

class TidalAddonHandler extends UserAddonHandler {
  final SettingsService _settings;
  final Dio _dio;

  TidalAddonHandler({required SettingsService settingsService})
      : _settings = settingsService,
        _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          headers: {'Accept': 'application/json'},
        ));

  String get _base {
    final b = _settings.tidalApiBase;
    return b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  }

  @override
  Widget? buildAddonPageWidget(BuildContext context) {
    return TidalApiConfigWidget(
      settings: _settings,
      onChanged: (newBase) {
        if (newBase != _settings.tidalApiBase) {
          _settings.setTidalApiBase(newBase);
        }
      },
    );
  }

  @override
  AddonManifest get manifest => AddonManifest(
        id: 'com.tidal.hifi',
        name: 'MetMusic (Backend)',
        version: '2.0.0',
        description:
            'Catálogo Tidal lossless/Hi-Res a través del backend privado de MetMusic. Búsqueda, streaming y exploración de álbumes, artistas y playlists.',
        icon: null,
        resources: [
          AddonResource.search,
          AddonResource.stream,
          AddonResource.catalog,
        ],
        types: ['track', 'album', 'artist', 'playlist'],
        contentType: AddonContentType.music,
        addonType: AddonType.user,
        baseUrl: null,
        installedAt: DateTime(2024, 1, 1),
        isBuiltIn: true,
      );

  // ========== SEARCH ==========

  @override
  Future<AddonSearchResult?> search(String query) async {
    try {
      final res = await _dio.get('$_base/search', queryParameters: {
        'q': query,
        'limit': 24,
        'offset': 0,
      });
      final data = res.data is Map ? Map<String, dynamic>.from(res.data) : {};
      final tracks = _mapTracks(data['tracks']);
      final albums = _mapAlbums(data['albums']);
      final artists = _mapArtists(data['artists']);
      final playlists = _mapPlaylists(data['playlists']);
      return AddonSearchResult(
        tracks: tracks,
        albums: albums,
        artists: artists,
        playlists: playlists,
      );
    } catch (e) {
      print('[MetMusic] search error: $e');
      return null;
    }
  }

  @override
  Future<List<AddonAlbum>> searchAlbums(String query, {int limit = 10}) async {
    try {
      final res = await _dio.get('$_base/search', queryParameters: {
        'q': query,
        'limit': limit,
        'offset': 0,
      });
      final data = res.data is Map ? Map<String, dynamic>.from(res.data) : {};
      return _mapAlbums(data['albums']);
    } catch (e) {
      print('[MetMusic] searchAlbums error: $e');
      return [];
    }
  }

  // ========== STREAM ==========

  @override
  Future<AddonStreamResult?> getStreamResult(String trackId,
      {bool atmos = false}) async {
    if (atmos) {
      final atm = await _probeStream(trackId, atmos: true);
      if (atm != null) return atm;
    }
    return _probeStream(trackId, atmos: false);
  }

  Future<AddonStreamResult?> _probeStream(String trackId,
      {bool atmos = false}) async {
    try {
      final res = await _dio.get('$_base/stream/$trackId', queryParameters: {
        if (atmos) 'atmos': '1',
        if (!atmos) 'quality': _settings.playbackQuality,
      });
      final data = res.data is Map ? Map<String, dynamic>.from(res.data) : {};
      final urls = data['urls'] is List
          ? List<String>.from(data['urls'].map((e) => e.toString()))
          : <String>[];
      final manifest = data['manifest'] is Map
          ? Map<String, dynamic>.from(data['manifest'])
          : null;
      final manifestUrl = manifest?['url']?.toString();

      if (atmos && manifestUrl != null && manifestUrl.isNotEmpty) {
        return AddonStreamResult(
          url: manifestUrl,
          format: 'dash',
          quality: 'DOLBY_ATMOS',
        );
      }
      if (urls.isNotEmpty) {
        final url = urls.first;
        return AddonStreamResult(
          url: url,
          format: _formatForUrl(url),
          quality: data['quality']?.toString(),
        );
      }
      if (manifestUrl != null && manifestUrl.isNotEmpty) {
        return AddonStreamResult(
          url: manifestUrl,
          format: 'dash',
          quality: data['quality']?.toString(),
        );
      }
    } catch (e) {
      print('[MetMusic] stream probe error ($trackId, atmos=$atmos): $e');
    }
    return null;
  }

  @override
  Future<String?> getStreamInfo(String trackId) async {
    final r = await _probeStream(trackId, atmos: false);
    return r?.quality;
  }

  @override
  Future<String?> getTrackAudioQuality(String trackId) async {
    try {
      final res = await _dio.get('$_base/tracks/$trackId');
      final data = res.data is Map ? Map<String, dynamic>.from(res.data) : {};
      final q = data['audioQuality']?.toString();
      if (q != null && q.isNotEmpty) return q;
    } catch (e) {
      print('[MetMusic] getTrackAudioQuality error: $e');
    }
    return null;
  }

  String _formatForUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.flac')) return 'flac';
    if (lower.contains('.aac') || lower.contains('.m4a')) return 'aac';
    if (lower.contains('.mp4')) return 'mp4';
    return 'mp4';
  }

  /// Normalize a provider quality string to the app's canonical form.
  /// The backend emits "HIRES_LOSSLESS" (no underscore) but the model, badge
  /// and stream format checks expect "HI_RES_LOSSLESS". This also covers the
  /// other Tidal tiers (LOSSLESS / HIGH / LOW).
  String _normQuality(String? q) {
    if (q == null || q.isEmpty) return '';
    final u = q.toUpperCase().replaceAll('_', '');
    if (u.contains('HIRES')) return 'HI_RES_LOSSLESS';
    if (u.contains('LOSSLESS')) return 'LOSSLESS';
    if (u.contains('HIGH')) return 'HIGH';
    if (u.contains('LOW')) return 'LOW';
    return q;
  }

  // ========== CATALOG ==========

  @override
  Future<AddonAlbum?> getAlbumDetail(String albumId, {int limit = 300}) async {
    try {
      final res = await _dio.get('$_base/albums/$albumId', queryParameters: {
        'limit': limit,
        'offset': 0,
      });
      final data = res.data is Map ? Map<String, dynamic>.from(res.data) : {};
      final tracks = _mapTracks(data['tracks']);
      return AddonAlbum(
        id: albumId,
        title: data['title']?.toString() ?? 'Unknown Album',
        artist: _artistName(data['artist']),
        artworkURL: _asUrl(data['cover']),
        trackCount: data['numberOfTracks'] ?? tracks.length,
        year: data['releaseDate']?.toString().split('-').first,
        type: data['type']?.toString(),
        audioModes: _atmosModes(data['isAtmos']),
        audioQuality: _normQuality(data['audioQuality']?.toString()),
        tracks: tracks,
        addonId: manifest.id,
      );
    } catch (e) {
      print('[MetMusic] getAlbumDetail error: $e');
      return null;
    }
  }

  @override
  Future<AddonArtist?> getArtistDetail(String artistId) async {
    try {
      final metaRes = await _dio.get('$_base/artists/$artistId');
      final meta = metaRes.data is Map
          ? Map<String, dynamic>.from(metaRes.data)
          : {};
      final name = meta['name']?.toString() ?? 'Artist';
      final picture = _asUrl(meta['picture']);

      final albums = _mapAlbums(meta['albums']);
      final topTracks = _mapTracks(meta['tracks']);
      topTracks.sort((a, b) => (b.popularity ?? 0) - (a.popularity ?? 0));
      final limitedTopTracks =
          topTracks.length > 20 ? topTracks.sublist(0, 20) : topTracks;

      String? artistMixId;
      try {
        final mixesRes = await _dio.get('$_base/artists/$artistId/mixes');
        final mixesData =
            mixesRes.data is Map ? Map<String, dynamic>.from(mixesRes.data) : {};
        final mixes = mixesData['mixes'] is List
            ? List<dynamic>.from(mixesData['mixes'])
            : <dynamic>[];
        if (mixes.isNotEmpty) {
          final first = mixes.first is Map
              ? Map<String, dynamic>.from(mixes.first)
              : <String, dynamic>{};
          artistMixId = first['id']?.toString();
        }
      } catch (e) {
        print('[MetMusic] artist mixes error: $e');
      }

      return AddonArtist(
        id: artistId,
        name: name,
        artworkURL: picture,
        artistMixId: artistMixId,
        topTracks: limitedTopTracks,
        albums: albums,
        addonId: manifest.id,
      );
    } catch (e) {
      print('[MetMusic] getArtistDetail error: $e');
      return null;
    }
  }

  @override
  Future<AddonMix?> getMixDetail(String mixId) async {
    try {
      final res = await _dio.get('$_base/mixes/$mixId');
      final data = res.data is Map ? Map<String, dynamic>.from(res.data) : {};
      final mix = data['mix'] is Map
          ? Map<String, dynamic>.from(data['mix'])
          : <String, dynamic>{};
      final tracks = _mapTracks(data['tracks']);
      return AddonMix(
        id: mixId,
        title: mix['title']?.toString() ?? 'Mix',
        subtitle: mix['subTitle']?.toString(),
        description: mix['description']?.toString(),
        artworkURL: _asUrl(mix['picture']),
        tracks: tracks,
        addonId: manifest.id,
      );
    } catch (e) {
      print('[MetMusic] getMixDetail error: $e');
      return null;
    }
  }

  @override
  Future<AddonPlaylist?> getPlaylistDetail(String playlistId) async {
    try {
      final res = await _dio.get('$_base/playlists/$playlistId', queryParameters: {
        'limit': 300,
        'offset': 0,
      });
      final data = res.data is Map ? Map<String, dynamic>.from(res.data) : {};
      final tracks = _mapTracks(data['tracks']);
      final owner = data['owner'] is Map
          ? Map<String, dynamic>.from(data['owner'])
          : null;
      return AddonPlaylist(
        id: data['id']?.toString() ?? playlistId,
        title: data['title']?.toString() ?? 'Unknown Playlist',
        description: data['description']?.toString(),
        artworkURL: _asUrl(data['picture']),
        creator: owner?['name']?.toString(),
        trackCount: data['numberOfTracks'] ?? tracks.length,
        tracks: tracks,
        addonId: manifest.id,
      );
    } catch (e) {
      print('[MetMusic] getPlaylistDetail error: $e');
      return null;
    }
  }

  // ========== RECOMMENDATIONS / HEALTH ==========

  @override
  Future<List<AddonTrack>> getRecommendations(String seedTrackId,
      {int limit = 24}) async {
    try {
      final res = await _dio.get('$_base/recommendations/$seedTrackId',
          queryParameters: {'limit': limit});
      final data = res.data;
      final List<dynamic> items;
      if (data is List) {
        items = data;
      } else if (data is Map) {
        final m = Map<String, dynamic>.from(data);
        items = (m['data']?['items'] ?? m['items'] ?? []) as List<dynamic>;
      } else {
        items = [];
      }
      return items
          .map((e) => _trackToAddon(e is Map ? Map<String, dynamic>.from(e) : {}))
          .where((t) => t.id.isNotEmpty)
          .toList();
    } catch (e) {
      print('[MetMusic] getRecommendations error: $e');
      return [];
    }
  }

  @override
  Future<ApiHealthStatus?> checkHealth() async {
    final stopwatch = Stopwatch()..start();
    try {
      final res = await _dio.get('$_base/health',
          options: Options(receiveTimeout: const Duration(seconds: 6)));
      stopwatch.stop();
      if (res.statusCode == 200) {
        final body = res.data is Map ? Map<String, dynamic>.from(res.data) : {};
        return ApiHealthStatus(
          online: true,
          version: body['version']?.toString(),
          latencyMs: stopwatch.elapsedMilliseconds,
        );
      }
      return ApiHealthStatus(
        online: false,
        error: 'HTTP ${res.statusCode}',
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e) {
      stopwatch.stop();
      return ApiHealthStatus(
        online: false,
        error: e is DioException && e.response != null
            ? 'HTTP ${e.response?.statusCode}'
            : null,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  // ========== MAPPERS ==========

  List<AddonTrack> _mapTracks(dynamic list) {
    if (list is! List) return [];
    return list
        .map((e) => _trackToAddon(e is Map ? Map<String, dynamic>.from(e) : {}))
        .where((t) => t.id.isNotEmpty)
        .toList();
  }

  List<AddonAlbum> _mapAlbums(dynamic list) {
    if (list is! List) return [];
    return list
        .map((e) => _albumToAddon(e is Map ? Map<String, dynamic>.from(e) : {}))
        .toList();
  }

  List<AddonArtist> _mapArtists(dynamic list) {
    if (list is! List) return [];
    return list
        .map((e) => _artistToAddon(e is Map ? Map<String, dynamic>.from(e) : {}))
        .toList();
  }

  List<AddonPlaylist> _mapPlaylists(dynamic list) {
    if (list is! List) return [];
    return list
        .map((e) => _playlistToAddon(e is Map ? Map<String, dynamic>.from(e) : {}))
        .toList();
  }

  AddonTrack _trackToAddon(Map<String, dynamic> m) {
    final id = m['id']?.toString() ?? '';
    final title = m['title']?.toString() ?? 'Unknown Title';

    final artists = m['artists'] is List
        ? List<dynamic>.from(m['artists'])
        : <dynamic>[];
    final primaryArtist = artists.isNotEmpty
        ? Map<String, dynamic>.from(artists.first)
        : <String, dynamic>{};
    final artistName = _artistNames(primaryArtist, artists);

    final album = m['album'] is Map
        ? Map<String, dynamic>.from(m['album'])
        : <String, dynamic>{};
    final cover = _asUrl(m['cover'] ?? album['cover']);

    final artistId = primaryArtist['id']?.toString();
    final albumId = album['id']?.toString();
    // Backend returns "HIRES_LOSSLESS" (no underscore) while the app/UI expect
    // the canonical "HI_RES_LOSSLESS". Normalize up-front so isHiRes, the badge
    // and the stream format all resolve correctly.
    final quality = _normQuality(m['audioQuality']?.toString());
    final isAtmos = m['isAtmos'] == true;

    // Preserve Atmos flag so Track.isAtmos (which reads rawData['audioModes'])
    // resolves correctly downstream.
    final rawData = Map<String, dynamic>.from(m);
    if (isAtmos) rawData['audioModes'] = ['ATMOS'];
    if (quality.isNotEmpty) rawData['audioQuality'] = quality;

    return AddonTrack(
      id: id,
      title: title,
      artist: artistName,
      album: album['title']?.toString(),
      duration: m['duration'] is int
          ? m['duration']
          : int.tryParse(m['duration']?.toString() ?? ''),
      artworkURL: cover,
      isrc: m['isrc']?.toString(),
      format: quality.toUpperCase().contains('HI_RES') ? 'flac' : 'mp4',
      quality: quality.isEmpty ? null : quality,
      streamURL: null,
      artistId: artistId,
      albumId: albumId,
      popularity: m['popularity'] is int
          ? m['popularity']
          : int.tryParse(m['popularity']?.toString() ?? ''),
      rawData: rawData,
      addonId: manifest.id,
    );
  }

  AddonAlbum _albumToAddon(Map<String, dynamic> m) {
    final id = m['id']?.toString() ?? '';
    final title = m['title']?.toString() ?? 'Unknown Album';
    return AddonAlbum(
      id: id,
      title: title,
      artist: _artistName(m['artist']),
      artworkURL: _asUrl(m['cover']),
      trackCount: m['numberOfTracks'],
      year: m['releaseDate']?.toString().split('-').first,
      type: m['type']?.toString(),
      audioModes: _atmosModes(m['isAtmos']),
      audioQuality: _normQuality(m['audioQuality']?.toString()),
      addonId: manifest.id,
    );
  }

  AddonArtist _artistToAddon(Map<String, dynamic> m) {
    final id = m['id']?.toString() ?? '';
    final name = m['name']?.toString() ?? 'Unknown Artist';
    return AddonArtist(
      id: id,
      name: name,
      artworkURL: _asUrl(m['picture']),
      addonId: manifest.id,
    );
  }

  AddonPlaylist _playlistToAddon(Map<String, dynamic> m) {
    final id = m['id']?.toString() ?? '';
    final title = m['title']?.toString() ?? 'Unknown Playlist';
    final owner = m['owner'] is Map ? Map<String, dynamic>.from(m['owner']) : null;
    return AddonPlaylist(
      id: id,
      title: title,
      description: m['description']?.toString(),
      artworkURL: _asUrl(m['picture']),
      creator: owner?['name']?.toString(),
      trackCount: m['numberOfTracks'],
      addonId: manifest.id,
    );
  }

  String _artistNames(Map<String, dynamic> primary, List<dynamic> others) {
    final names = <String>[];
    if (primary['name'] != null) names.add(primary['name'].toString());
    for (final a in others) {
      if (a is Map && a['name'] != null) {
        final name = a['name'].toString();
        if (!names.contains(name)) names.add(name);
      }
    }
    return names.isEmpty ? 'Unknown Artist' : names.join(', ');
  }

  String _artistName(dynamic artist) {
    if (artist is! Map) return 'Unknown Artist';
    return artist['name']?.toString() ?? 'Unknown Artist';
  }

  /// Backend returns fully-qualified Tidal CDN URLs (e.g.
  /// https://resources.tidal.com/images/.../1080x1080.jpg). Pass through.
  String? _asUrl(dynamic value) {
    if (value == null) return null;
    final s = value.toString();
    return s.isEmpty ? null : s;
  }

  List<String>? _atmosModes(dynamic isAtmos) {
    if (isAtmos == true) return ['ATMOS'];
    return null;
  }
}

class TidalApiConfigWidget extends StatefulWidget {
  final SettingsService settings;
  final ValueChanged<String> onChanged;

  const TidalApiConfigWidget({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  @override
  State<TidalApiConfigWidget> createState() => _TidalApiConfigWidgetState();
}

class _TidalApiConfigWidgetState extends State<TidalApiConfigWidget> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.settings.tidalApiBase);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) {
      widget.onChanged(value);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('API base URL updated'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white10
            : Colors.black12,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MetMusic API base URL',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              isDense: true,
              hintText: _defaultBackendBase,
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}
