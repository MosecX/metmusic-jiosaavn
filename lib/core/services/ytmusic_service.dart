import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// YouTube Music playback service — InnerTube pipeline (no extra deps).
///
/// Integration model follows BStream-Music's self-contained Dart InnerTube
/// approach:
///
///   1. Bootstrap  — GET https://music.youtube.com/ to extract the live
///      INNERTUBE_API_KEY / client version / VISITOR_DATA (WEB_REMIX, 67).
///   2. Search     — POST /youtubei/v1/search with the "Songs" filter to get
///      only official song rows (MUSIC_VIDEO_TYPE_ATV) with videoIds.
///   3. Resolve    — POST /youtubei/v1/player with tokenless device clients
///      (VISIONOS → ANDROID) whose responses carry *direct, pre-signed*
///      googlevideo audio URLs (no cipher deciphering, no PO tokens needed).
///   4. Match      — ISRC matching: the Tidal track's ISRC (from /info?id=)
///      is used as the search query when available, and candidates are
///      additionally compared against metadata so the same recording plays.
///
/// Only playback is routed through YouTube Music; browsing stays on the
/// Tidal catalog.

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

/// A song row returned by the YouTube Music catalog search.
@immutable
class YtMusicSong {
  final String videoId;
  final String title;
  final String artist;
  final String? album;
  final int? durationSeconds;
  final String? thumbnailUrl;
  final bool isExplicit;
  final int? views;
  final bool isOfficialSong; // MUSIC_VIDEO_TYPE_ATV (song) vs OMV (video)

  const YtMusicSong({
    required this.videoId,
    required this.title,
    required this.artist,
    this.album,
    this.durationSeconds,
    this.thumbnailUrl,
    this.isExplicit = false,
    this.views,
    this.isOfficialSong = false,
  });
}

/// A resolved, playable audio stream for a videoId.
@immutable
class YtMusicStream {
  final String videoId;
  final String url;
  final int? bitrate;
  final String? mimeType;
  final int? contentLength;
  final Duration? expiresIn;

  const YtMusicStream({
    required this.videoId,
    required this.url,
    this.bitrate,
    this.mimeType,
    this.contentLength,
    this.expiresIn,
  });
}

/// Result of resolving a Tidal track into a YouTube Music videoId.
@immutable
class YtMusicMatch {
  final YtMusicSong song;
  final String method; // 'isrc' | 'metadata'

  const YtMusicMatch({required this.song, required this.method});
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

class YtMusicService {
  static const String _musicOrigin = 'https://music.youtube.com';
  static const String _searchEndpoint =
      '$_musicOrigin/youtubei/v1/search?prettyPrint=false';
  static const String _bootstrapUri = '$_musicOrigin/';
  static const String _desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/140.0.0.0 Safari/537.36';

  /// WEB_REMIX search filter — "Songs" tab only (official song catalog rows).
  static const String _songsFilter = 'EgWKAQIIAWoMEA4QChADEAQQCRAF';

  /// Tokenless device clients (BStream ladder subset). These clients return
  /// direct pre-signed googlevideo URLs — no player JS deciphering and no
  /// PO token binding. Verified against live responses.
  static const List<Map<String, Object?>> _playerClients = [
    {
      'key': 'visionos',
      'clientName': 'VISIONOS',
      'clientVersion': '1.02',
      'host': _musicOrigin,
      'userAgent':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) '
          'Version/26.0 Safari/605.1.15',
      'extra': {
        'deviceMake': 'Apple',
        'deviceModel': 'RealityDevice17,1',
        'osName': 'visionOS',
        'osVersion': '26.5.23O471',
      },
    },
    {
      'key': 'android',
      'clientName': 'ANDROID',
      'clientVersion': '21.26.364',
      'host': 'https://www.youtube.com',
      'userAgent':
          'com.google.android.youtube/21.26.364 (Linux; U; Android 11) gzip',
      'extra': {'osName': 'Android', 'osVersion': '11'},
    },
  ];

  static final YtMusicService _instance = YtMusicService._();
  factory YtMusicService() => _instance;
  YtMusicService._();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
  ));

  /// Auth-free DASH manifest extractor. Used to resolve direct pre-signed
  /// googlevideo audio URLs (androidSdkless/ios clients) when the InnerTube
  /// player ladder returns LOGIN_REQUIRED ("Sign in to confirm you're not a
  /// bot").
  final YoutubeExplode _yt = YoutubeExplode();

  // Bootstrapped WEB_REMIX configuration (refreshed lazily on 401/403/400).
  String? _apiKey;
  String? _clientVersion;
  String? _visitorData;
  DateTime? _bootstrappedAt;
  Future<bool>? _bootstrapFuture;

  // Caches — results are stable for a given query/track.
  final Map<String, List<YtMusicSong>> _searchCache = {};
  final Map<String, YtMusicMatch?> _matchCache = {};
  final Map<String, YtMusicStream> _streamCache = {};
  final Map<String, DateTime> _streamCacheTs = {};

  int get cacheSize => _searchCache.length + _matchCache.length;

  void clearCaches() {
    _searchCache.clear();
    _matchCache.clear();
    _streamCache.clear();
    _streamCacheTs.clear();
  }

  // ─────────────────────────────────────────────
  // 1. Bootstrap
  // ─────────────────────────────────────────────

  Future<bool> _ensureBootstrapped({bool force = false}) async {
    if (!force &&
        _apiKey != null &&
        _clientVersion != null &&
        _visitorData != null &&
        _bootstrappedAt != null &&
        DateTime.now().difference(_bootstrappedAt!) <
            const Duration(hours: 12)) {
      return true;
    }
    // Collapse concurrent bootstrap attempts into one request.
    return _bootstrapFuture ??= _bootstrap().whenComplete(
        () => Future.microtask(() => _bootstrapFuture = null));
  }

  Future<bool> _bootstrap() async {
    try {
      final res = await _dio.get(
        _bootstrapUri,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'Accept': 'text/html,application/xhtml+xml',
            'User-Agent': _desktopUserAgent,
            'Accept-Language': 'es-419,es;q=0.9,en;q=0.8',
          },
        ),
      );
      final html = res.data?.toString() ?? '';
      _apiKey = _extractConfig(html, 'INNERTUBE_API_KEY');
      _clientVersion = _extractConfig(html, 'INNERTUBE_CLIENT_VERSION');
      _visitorData = _extractConfig(html, 'VISITOR_DATA');
      if (_apiKey != null &&
          _clientVersion != null &&
          _visitorData != null) {
        _bootstrappedAt = DateTime.now();
        debugPrint('[YtMusic] Bootstrapped (v$_clientVersion)');
        return true;
      }
      debugPrint('[YtMusic] Bootstrap incomplete — missing config keys');
      return false;
    } catch (e) {
      debugPrint('[YtMusic] Bootstrap failed: $e');
      return false;
    }
  }

  /// Extract a `"KEY":"VALUE"` string pair from the ytcfg embedded in HTML.
  static String? _extractConfig(String html, String key) {
    final m = RegExp('"$key"\\s*:\\s*"((?:\\\\.|[^"\\\\])*)"').firstMatch(html);
    if (m == null) return null;
    try {
      final decoded = jsonDecode('"${m.group(1)}"');
      return decoded is String && decoded.isNotEmpty ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _webRemixContext() => {
        'client': {
          'clientName': 'WEB_REMIX',
          'clientVersion': _clientVersion,
          'hl': 'es-419',
          'gl': 'US',
          'visitorData': _visitorData,
        },
      };

  Map<String, String> _webRemixHeaders() => {
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=UTF-8',
        'Origin': _musicOrigin,
        'Referer': '$_musicOrigin/',
        'User-Agent': _desktopUserAgent,
        'X-YouTube-Client-Name': '67',
        'X-YouTube-Client-Version': _clientVersion ?? '',
        'X-Goog-Visitor-Id': _visitorData ?? '',
      };

  // ─────────────────────────────────────────────
  // 2. Catalog search (Songs filter)
  // ─────────────────────────────────────────────

  /// Search official songs. [useSongsFilter] narrows to the Songs tab
  /// (ATV rows only); when false, the general search is scanned which also
  /// surfaces videos/cards.
  Future<List<YtMusicSong>> searchSongs(String query,
      {bool useSongsFilter = false, bool useCache = true}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final cacheKey = '${useSongsFilter ? 'F' : 'A'}:$q';
    if (useCache && _searchCache.containsKey(cacheKey)) {
      return _searchCache[cacheKey]!;
    }

    if (!await _ensureBootstrapped()) return const [];

    final body = {
      'context': _webRemixContext(),
      'query': q,
      if (useSongsFilter) 'params': _songsFilter,
    };

    try {
      var res = await _dio.post(
        '$_searchEndpoint&key=$_apiKey',
        options: Options(headers: _webRemixHeaders()),
        data: body,
      );
      if (_needsFreshConfig(res.statusCode)) {
        if (!await _ensureBootstrapped(force: true)) return const [];
        res = await _dio.post(
          '$_searchEndpoint&key=$_apiKey',
          options: Options(headers: _webRemixHeaders()),
          data: body,
        );
      }
      final songs = _parseSearchResponse(res.data);
      if (useCache) _cachePut(cacheKey, songs);
      return songs;
    } catch (e) {
      debugPrint('[YtMusic] search error: $e');
      return const [];
    }
  }

  static bool _needsFreshConfig(int? status) =>
      status == 400 || status == 401 || status == 403;

  void _cachePut(String key, List<YtMusicSong> songs) {
    // Bounded cache (single-flight per query; bounded list below).
    if (_searchCache.length > 128) _searchCache.remove(_searchCache.keys.first);
    _searchCache[key] = songs;
  }

  /// Flatten the InnerTube search payload into [YtMusicSong]s.
  ///
  /// Handles the two observed layouts:
  ///   • Songs-filter: tab → sectionListRenderer → musicShelfRenderer list.
  ///   • General: tab → itemSectionRenderer wrappers with
  ///     musicResponsiveListItemRenderer rows + top musicCardShelfRenderer.
  List<YtMusicSong> _parseSearchResponse(dynamic data) {
    final results = <YtMusicSong>[];
    try {
      final tabs = _dig(data, ['contents', 'tabbedSearchResultsRenderer', 'tabs'])
          as List?;
      if (tabs == null || tabs.isEmpty) return results;
      final content =
          _dig(tabs.first, ['tabRenderer', 'content']) as Map?;
      final sections =
          _dig(content, ['sectionListRenderer', 'contents']) as List?;
      if (sections == null) return results;

      for (final section in sections) {
        // Layout A: direct musicShelfRenderer.
        final shelf = _dig(section, ['musicShelfRenderer']) as Map?;
        if (shelf != null) {
          _parseShelfItems(shelf['contents'], results);
          continue;
        }
        // Layout B: itemSectionRenderer wrappers.
        final innerList =
            _dig(section, ['itemSectionRenderer', 'contents']) as List?;
        if (innerList != null) {
          for (final inner in innerList) {
            final row = _dig(inner, ['musicResponsiveListItemRenderer']) as Map?;
            if (row != null) {
              final song = _parseResponsiveRow(row);
              if (song != null) results.add(song);
              continue;
            }
            final cardShelf =
                _dig(inner, ['musicCardShelfRenderer']) as Map?;
            if (cardShelf != null) {
              final song = _parseCardShelf(cardShelf);
              if (song != null) results.add(song);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[YtMusic] parse search error: $e');
    }
    return results;
  }

  void _parseShelfItems(dynamic items, List<YtMusicSong> out) {
    if (items is! List) return;
    for (final item in items) {
      final row = _dig(item, ['musicResponsiveListItemRenderer']) as Map?;
      if (row == null) continue;
      final song = _parseResponsiveRow(row);
      if (song != null) out.add(song);
    }
  }

  YtMusicSong? _parseResponsiveRow(Map row) {
    final videoId = row['playlistItemData']?['videoId']?.toString();
    // Fallback: videoId from navigationEndpoint watch links.
    String? fallbackId;
    if (videoId == null) {
      fallbackId = _findVideoId(row);
      if (fallbackId == null) return null;
    }
    final id = videoId ?? fallbackId!;

    final columns = row['flexColumns'] as List? ?? const [];
    String title = '';
    String subtitle = '';
    if (columns.isNotEmpty) {
      title = _flexText(columns.first);
    }
    if (columns.length > 1) {
      subtitle = _flexText(columns[1]);
    }

    // Title/subtitle fallback from overlay metadata for card-style rows.
    if (title.isEmpty) {
      title = _dig(row, ['overlay', 'musicItemThumbnailOverlayRenderer']) != null
          ? _findTitleText(row) ?? ''
          : _findTitleText(row) ?? '';
    }

    final rawJson = jsonEncode(row);
    final isOfficialSong = rawJson.contains('MUSIC_VIDEO_TYPE_ATV') ||
        rawJson.contains('MUSIC_PAGE_TYPE_TRACK') ||
        rawJson.contains('MUSIC_PAGE_TYPE_ALBUM');

    final explicit = rawJson.contains('"MUSIC_EXPLICIT_BADGE"') ||
        subtitle.toLowerCase().contains('explícita');

    int? duration = _parseDuration(subtitle);
    int? views = _parseViews(subtitle);
    String? thumbnail = _parseThumbnail(row);

    // "Canción" rows: "title|Canción| • |artist" — album from subtitle after artist.
    final parts = subtitle.split('•');
    String? album;
    if (parts.length >= 3) {
      final candidate = parts.last.trim();
      if (!_isNoiseSubtitle(candidate)) album = candidate;
    }

    return YtMusicSong(
      videoId: id,
      title: title,
      artist: _artistFromSubtitle(subtitle),
      album: album,
      durationSeconds: duration,
      thumbnailUrl: thumbnail,
      isExplicit: explicit,
      views: views,
      isOfficialSong: isOfficialSong,
    );
  }

  YtMusicSong? _parseCardShelf(Map card) {
    final titleRuns = _dig(card, ['title', 'runs']) as List?;
    final watch = titleRuns != null && titleRuns.isNotEmpty
        ? _dig(titleRuns.first, ['navigationEndpoint', 'watchEndpoint']) as Map?
        : null;
    final videoId = watch?['videoId']?.toString();
    if (videoId == null) return null;

    final title = titleRuns?.first['text']?.toString() ?? '';
    final subtitleRuns = _dig(card, ['subtitle', 'runs']) as List? ?? const [];
    final subtitle =
        subtitleRuns.map((r) => r['text']?.toString() ?? '').join();
    final rawJson = jsonEncode(card);
    return YtMusicSong(
      videoId: videoId,
      title: title,
      artist: _artistFromSubtitle(subtitle),
      durationSeconds: _parseDuration(subtitle),
      views: _parseViews(subtitle),
      thumbnailUrl: _parseThumbnail(card),
      isOfficialSong: rawJson.contains('MUSIC_VIDEO_TYPE_ATV') ||
          rawJson.contains('MUSIC_VIDEO_TYPE_OMV') == false,
    );
  }

  // ─────────────────────────────────────────────
  // 3. ISRC / metadata matching
  // ─────────────────────────────────────────────

  /// Resolve a Tidal track (title + artist + optional ISRC) to a YouTube
  /// Music videoId. Strategy mirrors BStream's catalog-first mindset:
  ///
  ///  1. ISRC query — when available, searching by ISRC returns an exact
  ///     catalog identity when YouTube knows the recording.
  ///  2. Metadata query — "artist title" with official-song preference and
  ///     duration sanity checks.
  Future<YtMusicMatch?> findMatch({
    required String title,
    required String artist,
    String? isrc,
    int? durationSeconds,
    bool useCache = true,
  }) async {
    final cacheKey = '$isrc|$artist|$title|${durationSeconds ?? ''}';
    if (useCache && _matchCache.containsKey(cacheKey)) {
      return _matchCache[cacheKey];
    }

    // 1. ISRC-first search (exact catalog match).
    if (isrc != null && isrc.trim().isNotEmpty) {
      final isrcSongs = await searchSongs(isrc.trim(), useCache: useCache);
      final isrcHit = _bestMatch(
        candidates: isrcSongs,
        title: title,
        artist: artist,
        durationSeconds: durationSeconds,
      );
      if (isrcHit != null) {
        final m = YtMusicMatch(song: isrcHit, method: 'isrc');
        if (useCache) _matchCache[cacheKey] = m;
        return m;
      }
    }

    // 2. Metadata search: "artist title" then plain "title".
    for (final query in [
      '$artist $title',
      title,
    ]) {
      final songs = await searchSongs(query, useCache: useCache);
      final hit = _bestMatch(
        candidates: songs,
        title: title,
        artist: artist,
        durationSeconds: durationSeconds,
      );
      if (hit != null) {
        final m = YtMusicMatch(song: hit, method: 'metadata');
        if (useCache) _matchCache[cacheKey] = m;
        return m;
      }
    }

    if (useCache) _matchCache[cacheKey] = null;
    return null;
  }

  /// Score candidate songs against the Tidal metadata and return the best.
  YtMusicSong? _bestMatch({
    required List<YtMusicSong> candidates,
    required String title,
    required String artist,
    int? durationSeconds,
  }) {
    YtMusicSong? best;
    int bestScore = 0;

    final normTitle = _normalize(title);
    final normArtist = _normalize(artist);
    final primaryArtistRaw =
        artist.split(RegExp(r',| y | & | feat| ft')).first.trim();
    final primaryArtist = _normalize(
        primaryArtistRaw.isEmpty ? artist : primaryArtistRaw);

    for (final song in candidates) {
      int score = 0;
      final sTitle = _normalize(song.title);
      final sArtist = _normalize(song.artist);

      // Title similarity (exact / containment / word overlap).
      if (sTitle == normTitle) {
        score += 50;
      } else if (sTitle.contains(normTitle) || normTitle.contains(sTitle)) {
        score += 30;
      } else {
        final overlap = _wordOverlap(normTitle, sTitle);
        if (overlap >= 0.8) {
          score += 25;
        } else if (overlap >= 0.5) {
          score += 10;
        }
      }

      // Artist similarity.
      if (sArtist == normArtist) {
        score += 40;
      } else if (sArtist.contains(normArtist) ||
          normArtist.contains(sArtist)) {
        score += 25;
      } else if (sArtist.contains(primaryArtist)) {
        score += 20;
      } else {
        final overlap = _wordOverlap(primaryArtist, sArtist);
        if (overlap >= 0.5) score += 12;
      }

      // Official catalog song strongly preferred (ATV rows).
      if (song.isOfficialSong) score += 20;

      // Duration sanity (±3s exact, ±8s near).
      if (durationSeconds != null && song.durationSeconds != null) {
        final diff = (song.durationSeconds! - durationSeconds).abs();
        if (diff <= 3) {
          score += 25;
        } else if (diff <= 8) {
          score += 15;
        } else if (diff <= 20) {
          score += 5;
        } else if (diff > 45) {
          score -= 15;
        }
      }

      // Avoid obvious remix/live/cover mismatches unless query says so.
      final lowerTitle = song.title.toLowerCase();
      for (final marker in ['remix', 'live', 'cover', 'sped up', 'slowed']) {
        if (lowerTitle.contains(marker) && !normTitle.contains(marker)) {
          score -= 20;
        }
      }

      if (score > bestScore) {
        bestScore = score;
        best = song;
      }
    }

    // Require a confident match.
    return bestScore >= 45 ? best : null;
  }

  // ─────────────────────────────────────────────
  // 4. Stream resolution (player ladder)
  // ─────────────────────────────────────────────

  /// Resolve a playable direct audio URL for a videoId.
  ///
  /// Primary path: DASH manifest extracted with the auth-free device clients
  /// (androidSdkless → ios) from `youtube_explode_dart`. These return direct
  /// pre-signed googlevideo audio URLs with no PO token / JS deciphering and
  /// no "Sign in to confirm you're not a bot" wall.
  ///
  /// Fallback path: legacy tokenless InnerTube ladder (VISIONOS then ANDROID),
  /// kept for the edge cases the manifest path cannot cover.
  ///
  /// Short TTL cache for gapless queue advance.
  Future<YtMusicStream?> resolveStream(String videoId,
      {bool forceFresh = false}) async {
    if (videoId.isEmpty) return null;

    if (!forceFresh && _streamCache.containsKey(videoId)) {
      final ts = _streamCacheTs[videoId]!;
      if (DateTime.now().difference(ts) < const Duration(minutes: 20)) {
        return _streamCache[videoId];
      }
      _streamCache.remove(videoId);
      _streamCacheTs.remove(videoId);
    }

    final manifest = await _resolveFromManifest(videoId);
    if (manifest != null) return _cacheStream(videoId, manifest);

    // Fallback: legacy tokenless ladder (may be behind LOGIN_REQUIRED).
    for (final client in _playerClients) {
      try {
        final stream = await _requestPlayerForClient(client, videoId);
        if (stream != null) return _cacheStream(videoId, stream);
      } catch (e) {
        debugPrint('[YtMusic] player ${client['key']} failed for $videoId: $e');
      }
    }
    return null;
  }

  YtMusicStream _cacheStream(String videoId, YtMusicStream stream) {
    if (_streamCache.length > 64) {
      _streamCache.remove(_streamCache.keys.first);
      _streamCacheTs.remove(_streamCache.keys.first);
    }
    _streamCache[videoId] = stream;
    _streamCacheTs[videoId] = DateTime.now();
    return stream;
  }

  Future<YtMusicStream?> _resolveFromManifest(String videoId) async {
    try {
      final manifest = await _yt.videos.streams
          .getManifest(
            videoId,
            ytClients: [
              YoutubeApiClient.androidSdkless,
              YoutubeApiClient.ios,
            ],
          )
          .timeout(const Duration(seconds: 20));
      return _pickBestAudio(manifest);
    } catch (e) {
      debugPrint('[YtMusic] manifest resolve failed for $videoId: $e');
      return null;
    }
  }

  /// Pick the best audio-only stream: prefer a non-throttled format, then the
  /// highest bitrate (opus/webm wins ties over aac/m4a).
  static YtMusicStream? _pickBestAudio(StreamManifest manifest) {
    YtMusicStream? best;
    int bestScore = -1;
    for (final audio in manifest.audioOnly) {
      final url = audio.url.toString();
      if (url.isEmpty) continue;
      final bitrate = audio.bitrate.bitsPerSecond;
      final container = audio.container.name.toLowerCase();
      final audioCodec = audio.audioCodec.toLowerCase();

      int score = bitrate;
      if (!audio.isThrottled) score += 20000;
      if (audioCodec.contains('opus')) score += 10000;
      if (container.contains('webm')) score += 5000;

      if (score > bestScore) {
        bestScore = score;
        best = YtMusicStream(
          videoId: audio.videoId.toString(),
          url: url,
          bitrate: bitrate,
          mimeType: 'audio/$container',
          contentLength: audio.size.totalBytes,
        );
      }
    }
    return best;
  }

  Future<YtMusicStream?> _requestPlayerForClient(
      Map<String, Object?> client, String videoId) async {
    final host = client['host'] as String;
    final endpoint = '$host/youtubei/v1/player?prettyPrint=false';
    final body = {
      'context': {
        'client': {
          'clientName': client['clientName'],
          'clientVersion': client['clientVersion'],
          ...?client['extra'] as Map<String, Object?>?,
          'hl': 'en',
          'gl': 'US',
        },
      },
      'videoId': videoId,
      'contentCheckOk': true,
      'racyCheckOk': true,
    };

    final res = await _dio.post(
      endpoint,
      options: Options(headers: {
        'Content-Type': 'application/json',
        'Accept': '*/*',
        'User-Agent': client['userAgent'],
      }),
      data: body,
    );

    final data = res.data;
    if (data is! Map) return null;

    final playability = _dig(data, ['playabilityStatus', 'status'])?.toString();
    if (playability != null && playability.toUpperCase() != 'OK') {
      debugPrint(
          '[YtMusic] $videoId unplayable on ${client['key']}: $playability');
      return null;
    }

    final formats = _dig(data, ['streamingData', 'adaptiveFormats']) as List?;
    if (formats == null || formats.isEmpty) return null;

    // Pick the highest-bitrate audio-only format (opus > aac tiebreak).
    Map? best;
    int bestScore = -1;
    for (final f in formats) {
      if (f is! Map) continue;
      final mime = f['mimeType']?.toString() ?? '';
      if (!mime.toLowerCase().startsWith('audio/')) continue;
      final url = f['url'];
      if (url == null || url.toString().isEmpty) continue;
      final bitrate = (f['bitrate'] as num?)?.toInt() ?? 0;
      int score = bitrate;
      if (mime.contains('opus')) score += 10000; // prefer opus at equal rate
      if (score > bestScore) {
        bestScore = score;
        best = f;
      }
    }
    if (best == null) return null;

    final url = best['url'].toString();
    final expiresIn =
        (_dig(data, ['streamingData', 'expiresInSeconds']) as num?)?.toInt();
    return YtMusicStream(
      videoId: videoId,
      url: url,
      bitrate: (best['bitrate'] as num?)?.toInt(),
      mimeType: best['mimeType']?.toString(),
      contentLength: int.tryParse(best['contentLength']?.toString() ?? ''),
      expiresIn: expiresIn != null ? Duration(seconds: expiresIn) : null,
    );
  }

  /// Convenience: match + resolve in one call.
  Future<YtMusicStream?> resolveForTrack({
    required String title,
    required String artist,
    String? isrc,
    int? durationSeconds,
  }) async {
    final match = await findMatch(
      title: title,
      artist: artist,
      isrc: isrc,
      durationSeconds: durationSeconds,
    );
    if (match == null) return null;
    return resolveStream(match.song.videoId);
  }

  // ─────────────────────────────────────────────
  // Parsing helpers
  // ─────────────────────────────────────────────

  /// Safely walk a nested path of map keys/lists.
  static dynamic _dig(dynamic node, List<String> path) {
    dynamic cur = node;
    for (final key in path) {
      if (cur is! Map) return null;
      cur = cur[key];
    }
    return cur;
  }

  static String _flexText(dynamic flexColumn) {
    final runs =
        _dig(flexColumn, ['musicResponsiveListItemFlexColumnRenderer', 'text', 'runs'])
            as List?;
    if (runs == null) return '';
    return runs.map((r) => r['text']?.toString() ?? '').join();
  }

  static String? _findVideoId(Map row) {
    String? found;
    void walk(dynamic node) {
      if (found != null || node is! Map) return;
      final watch = node['watchEndpoint'];
      if (watch is Map && watch['videoId'] != null) {
        found = watch['videoId'].toString();
        return;
      }
      for (final v in node.values) {
        if (found != null) return;
        if (v is Map) walk(v);
        if (v is List) for (final e in v) walk(e);
      }
    }

    walk(row);
    return found;
  }

  static String? _findTitleText(Map row) {
    String? found;
    void walk(dynamic node) {
      if (found != null || node is! Map) return;
      final runs = node['runs'];
      if (runs is List && runs.isNotEmpty && runs.first is Map) {
        final t = runs.first['text']?.toString();
        if (t != null && t.isNotEmpty) {
          found = t;
          return;
        }
      }
      for (final v in node.values) {
        if (found != null) return;
        if (v is Map) walk(v);
        if (v is List) for (final e in v) walk(e);
      }
    }

    walk(row);
    return found;
  }

  static String? _parseThumbnail(Map row) {
    final thumbs = _dig(
        row, ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails'])
        as List?;
    if (thumbs == null || thumbs.isEmpty) return null;
    // Prefer the largest square-ish thumbnail (YT uses w544-h544 for songs).
    String? bestUrl;
    int bestArea = -1;
    for (final t in thumbs) {
      if (t is! Map) continue;
      final url = t['url']?.toString();
      if (url == null || !url.startsWith('http')) continue;
      final w = (t['width'] as num?)?.toInt() ?? 0;
      final h = (t['height'] as num?)?.toInt() ?? 0;
      final area = w * h;
      if (area > bestArea) {
        bestArea = area;
        bestUrl = url;
      }
    }
    // Normalize to 544px cover.
    if (bestUrl != null && bestUrl.contains('w120-h120')) {
      bestUrl = bestUrl.replaceFirst('w120-h120', 'w544-h544');
    }
    return bestUrl;
  }

  static int? _parseDuration(String subtitle) {
    final m = RegExp(r'(\d+):(\d{2})(?::(\d{2}))?').firstMatch(subtitle);
    if (m == null) return null;
    if (m.group(3) != null) {
      return int.parse(m.group(1)!) * 3600 +
          int.parse(m.group(2)!) * 60 +
          int.parse(m.group(3)!);
    }
    return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
  }

  static int? _parseViews(String subtitle) {
    final m =
        RegExp(r'([\d.,]+)\s*(mil|millones|M|K|mil millones)?').firstMatch(subtitle);
    if (m == null) return null;
    final rawNum = double.tryParse(m.group(1)!.replaceAll(RegExp(r'[.,]'), ''));
    if (rawNum == null) return null;
    final unit = m.group(2)?.toLowerCase() ?? '';
    if (unit == 'mil' || unit == 'k') return (rawNum * 1000).round();
    if (unit.contains('millon') || unit == 'm') return (rawNum * 1000000).round();
    return rawNum.round();
  }

  static String _artistFromSubtitle(String subtitle) {
    final parts = subtitle.split('•');
    final artistPart = parts.length >= 2 ? parts[1] : subtitle;
    return artistPart
        .replaceAll(RegExp(r'^(Canción|Video|Single|EP|Álbum)\s*'), '')
        .trim();
  }

  static bool _isNoiseSubtitle(String s) {
    final lower = s.toLowerCase();
    return lower.contains('reproducciones') ||
        lower.contains('vistas') ||
        lower.contains('suscrip') ||
        lower.contains('usuarios') ||
        RegExp(r'^\d+:\d{2}$').hasMatch(s.trim()) ||
        s.trim().isEmpty;
  }

  /// Normalization for fuzzy comparison: lowercase, strip accents, remove
  /// feat/official/lyrics decorations and punctuation.
  static String _normalize(String s) {
    var out = s.toLowerCase();
    const withDiacritics = 'áéíóúüñ';
    const without = 'aeioun';
    for (int i = 0; i < withDiacritics.length; i++) {
      out = out.replaceAll(withDiacritics[i], without[i]);
    }
    out = out
        .replaceAll(RegExp(r'\((feat|ft)\.?[^)]*\)'), '')
        .replaceAll(RegExp(r'\[(feat|ft)\.?[^\]]*\]'), '')
        .replaceAll(RegExp(r'\((official|video|audio|lyrics?|visualizer)[^)]*\)'),
            '')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return out;
  }

  static double _wordOverlap(String a, String b) {
    final setA = a.split(' ').where((w) => w.length > 1).toSet();
    final setB = b.split(' ').where((w) => w.length > 1).toSet();
    if (setA.isEmpty || setB.isEmpty) return 0;
    final inter = setA.intersection(setB).length;
    return inter / (setA.length < setB.length ? setA.length : setB.length);
  }
}
