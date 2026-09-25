import 'package:dio/dio.dart';

import '../models/addon_models.dart';
import 'jiosaavn_service.dart';
import 'user_addon_handler.dart';

/// Built-in JioSaavn addon handler — the single catalog + streaming provider.
///
/// Talks to the public JioSaavn API proxy (rthmx / ODSkyler spec):
///
/// * `/api/songs|albums|artists|playlists?q=` → search
/// * `/api/album?token=` · `/api/artist?token=` · `/api/playlist?token=` → detail
/// * `/api/song?token=` → song detail (fallback stream resolution)
///
/// Playback resolves the JioSaavn `encrypted_media_url` through
/// [JioSaavnService] into a permanent AAC/MP4 CDN URL (upgraded to 320 kbps).
/// Tracks are inherently JioSaavn, so there is no cross-matching/fallback.
class JioSaavnAddonHandler extends UserAddonHandler {
  JioSaavnAddonHandler({required JioSaavnService jioSaavnService})
      : _jioSaavn = jioSaavnService {
    _base = JioSaavnService.apiBase;
  }

  /// Stable addon id used everywhere in the app (track.user id prefix, stream
  /// routing, favorites, libraries).
  static const String addonId = 'com.jiosaavn';

  static const String _quality = 'HIGH';

  final JioSaavnService _jioSaavn;
  late final String _base;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
    headers: {
      'Accept': 'application/json',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/126.0.0.0 Safari/537.36',
    },
  ));

  /// token → song cache. Populated while mapping search/detail rows so that
  /// advancing the queue at track end resolves its stream with zero extra
  /// HTTP round-trips to the API (the [JioSaavnService] stream cache handles
  /// the CDN bitrate probing TTL).
  final Map<String, JioSaavnSong> _songByToken = {};

  @override
  AddonManifest get manifest => AddonManifest(
        id: addonId,
        name: 'JioSaavn',
        version: '1.0.0',
        description: 'Catálogo completo de JioSaavn: canciones, álbumes, '
            'artistas y playlists con streaming hasta 320 kbps.',
        resources: const [
          AddonResource.search,
          AddonResource.stream,
          AddonResource.catalog,
        ],
        types: const ['track', 'album', 'artist', 'playlist'],
        contentType: AddonContentType.music,
        addonType: AddonType.user,
        installedAt: DateTime.now(),
        isBuiltIn: true,
      );

  // ========== Search ==========

  @override
  Future<AddonSearchResult?> search(String query) async {
    final queryCleaned = query.trim();
    if (queryCleaned.isEmpty) return AddonSearchResult();

    final results = await Future.wait<dynamic>([
      _searchSongs(queryCleaned),
      _searchAlbumsRaw(queryCleaned),
      _searchArtistsRaw(queryCleaned),
      _searchPlaylistsRaw(queryCleaned),
    ]);

    return AddonSearchResult(
      tracks: results[0] as List<AddonTrack>,
      albums: results[1] as List<AddonAlbum>,
      artists: results[2] as List<AddonArtist>,
      playlists: results[3] as List<AddonPlaylist>,
    );
  }

  @override
  Future<List<AddonAlbum>> searchAlbums(String query, {int limit = 10}) async {
    try {
      return (await _searchAlbumsRaw(query)).take(limit).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<AddonTrack>> _searchSongs(String query) async {
    try {
      return _songsFromResults(await _getJson('/songs', {'q': query}));
    } catch (_) {
      return [];
    }
  }

  Future<List<AddonAlbum>> _searchAlbumsRaw(String query) async {
    try {
      return _albumsFromResults(await _getJson('/albums', {'q': query}));
    } catch (_) {
      return [];
    }
  }

  Future<List<AddonArtist>> _searchArtistsRaw(String query) async {
    try {
      final data = await _getJson('/artists', {'q': query});
      final results = _asList(data['results']);
      return results.map(_artistFromRow).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<AddonPlaylist>> _searchPlaylistsRaw(String query) async {
    try {
      final data = await _getJson('/playlists', {'q': query});
      final results = _asList(data['results']);
      return results.map((r) => _playlistFromRow(r, withTracks: false)).toList();
    } catch (_) {
      return [];
    }
  }

  // ========== Catalog Detail ==========

  @override
  Future<AddonAlbum?> getAlbumDetail(String albumToken) async {
    try {
      final data = await _getJson('/album', {'token': albumToken});
      final songs = _asList(data['songs']).map(_songFromRow).toList();
      return AddonAlbum(
        id: data['token']?.toString() ?? albumToken,
        title: data['title']?.toString() ?? 'Unknown Album',
        artist: _subtitleArtist(data['subtitle']),
        artworkURL: jioSaavnImage(data['image']),
        trackCount: int.tryParse(data['song_count']?.toString() ?? ''),
        year: data['year']?.toString(),
        audioQuality: _quality,
        tracks: songs,
        addonId: addonId,
      );
    } catch (e) {
      print('[JioSaavn] getAlbumDetail failed: $e');
      return null;
    }
  }

  @override
  Future<AddonArtist?> getArtistDetail(String artistToken) async {
    try {
      final data = await _getJson('/artist', {'token': artistToken});
      final topTracks = _asList(data['topSongs']).map(_songFromRow).toList();
      final albums =
          _asList(data['topAlbums']).map(_albumFromRow).toList();
      return AddonArtist(
        id: artistToken,
        name: data['name']?.toString() ?? 'Unknown Artist',
        artworkURL: jioSaavnImage(data['image']),
        topTracks: topTracks,
        albums: albums,
        addonId: addonId,
      );
    } catch (e) {
      print('[JioSaavn] getArtistDetail failed: $e');
      return null;
    }
  }

  @override
  Future<AddonPlaylist?> getPlaylistDetail(String playlistToken) async {
    try {
      final data = await _getJson('/playlist', {'token': playlistToken});
      final songs = _asList(data['list']).map(_songFromRow).toList();
      return AddonPlaylist(
        id: data['token']?.toString() ?? playlistToken,
        title: data['title']?.toString() ?? 'Unknown Playlist',
        description: data['header_desc']?.toString(),
        artworkURL: jioSaavnImage(data['image']),
        creator: _subtitleArtist(data['subtitle']),
        trackCount: int.tryParse(data['list_count']?.toString() ?? ''),
        tracks: songs,
        addonId: addonId,
      );
    } catch (e) {
      print('[JioSaavn] getPlaylistDetail failed: $e');
      return null;
    }
  }

  // ========== Stream ==========

  @override
  Future<AddonStreamResult?> getStreamResult(String trackId) async {
    // 1. Instant path: the song is already in the token cache (built while
    //    mapping search/detail rows) and carries an encrypted media URL.
    var song = _songByToken[trackId];

    // 2. Fetch by token when unknown (e.g. downloaded/queued tracks built by
    //    another context) or when the cached copy can't be played.
    if (song == null || song.encryptedMediaUrl.isEmpty) {
      try {
        final fresh = await _jioSaavn.songByToken(trackId);
        if (fresh == null) return null;
        _songByToken[trackId] = fresh;
        song = fresh;
      } catch (e) {
        print('[JioSaavn] getStreamResult fetch failed for $trackId: $e');
        return null;
      }
    }
    if (song.encryptedMediaUrl.isEmpty) return null;

    // 3. Resolve the permanent CDN URL (320 → 160 → 96 → 48 → 12 kbps),
    //    retrying once with a fresh probe if an already-cached URL expired.
    var stream = await _jioSaavn.resolveStream(song);
    if (stream == null) {
      stream = await _jioSaavn.resolveStream(song, forceFresh: true);
    }
    if (stream == null) return null;

    return AddonStreamResult(
      url: stream.url,
      format: stream.mimeType,
      quality: _quality,
    );
  }

  // ========== Health ==========

  @override
  Future<ApiHealthStatus?> checkHealth() async {
    final stopwatch = Stopwatch()..start();
    try {
      // The API root returns raw JavaScript (unquoted keys:
      // `status: "active"`), not JSON — parsing it as a Map throws
      // "type 'String' is not a subtype". Read the body as text and match
      // the fields with a tolerant regex instead.
      final res = await _dio.get<String>(
        _base,
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      stopwatch.stop();
      final body = res.data ?? '';
      final status = RegExp(r'status\s*:\s*"([^"]+)"').firstMatch(body)?.group(1);
      final name = RegExp(r'name\s*:\s*"([^"]+)"').firstMatch(body)?.group(1);
      final online = status == 'active' || body.contains('"status":"active"');
      return ApiHealthStatus(
        online: online,
        version: name,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e) {
      stopwatch.stop();
      return ApiHealthStatus(
        online: false,
        error: e.toString(),
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  // ========== Row Mappers ==========

  AddonTrack _songFromRow(Map<String, dynamic> raw) {
    final song = JioSaavnService.fromRawMap(raw);
    if (song != null) _songByToken[song.token] = song;
    return AddonTrack(
      id: raw['token']?.toString() ?? '',
      title: raw['title']?.toString() ?? 'Unknown Title',
      artist: song?.artist ?? 'Unknown Artist',
      album: song?.album,
      duration: song?.durationSeconds,
      artworkURL: jioSaavnImage(raw['image']),
      quality: _quality,
      artistId: null,
      albumId: (raw['more_info'] is Map)
          ? raw['more_info']['album_id']?.toString()
          : null,
      addonId: addonId,
      rawData: raw,
    );
  }

  AddonAlbum _albumFromRow(Map<String, dynamic> raw) {
    return AddonAlbum(
      id: raw['token']?.toString() ?? raw['id']?.toString() ?? '',
      title: raw['title']?.toString() ?? 'Unknown Album',
      artist: _subtitleArtist(raw['subtitle']),
      artworkURL: jioSaavnImage(raw['image']),
      trackCount: int.tryParse(raw['song_count']?.toString() ?? ''),
      year: raw['year']?.toString(),
      type: raw['type']?.toString(),
      audioQuality: _quality,
      addonId: addonId,
    );
  }

  AddonArtist _artistFromRow(Map<String, dynamic> raw) {
    return AddonArtist(
      id: raw['token']?.toString() ?? raw['id']?.toString() ?? '',
      name: raw['name']?.toString() ?? 'Unknown Artist',
      artworkURL: jioSaavnImage(raw['image']),
      addonId: addonId,
    );
  }

  AddonPlaylist _playlistFromRow(Map<String, dynamic> raw,
      {bool withTracks = false}) {
    return AddonPlaylist(
      id: raw['token']?.toString() ?? raw['id']?.toString() ?? '',
      title: raw['title']?.toString() ?? 'Unknown Playlist',
      description: raw['header_desc']?.toString(),
      artworkURL: jioSaavnImage(raw['image']),
      creator: _subtitleArtist(raw['subtitle']),
      trackCount: int.tryParse(RegExp(r'\d+')
              .firstMatch(raw['subtitle']?.toString() ?? '')
              ?.group(0) ??
          ''),
      addonId: addonId,
    );
  }

  // ========== HTTP Helpers ==========

  Future<Map<String, dynamic>> _getJson(String path, Map<String, dynamic> params,
      {bool probe = false}) async {
    final res = await _dio.get(
      probe ? _base : '$_base$path',
      queryParameters: params,
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  List<Map<String, dynamic>> _asList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  List<AddonTrack> _songsFromResults(Map<String, dynamic> data) {
    return _asList(data['results']).map(_songFromRow).toList();
  }

  List<AddonAlbum> _albumsFromResults(Map<String, dynamic> data) {
    return _asList(data['results']).map(_albumFromRow).toList();
  }

  /// "MANANA" → "MANANA"; "QMIIR - MANANA" → "QMIIR".
  String _subtitleArtist(dynamic subtitle) {
    final s = subtitle?.toString().trim() ?? '';
    if (s.isEmpty) return 'Varios artistas';
    final sep = s.indexOf(' - ');
    return sep > 0 ? s.substring(0, sep).trim() : s;
  }
}