import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'des_ecb.dart';

/// Upgrades a JioSaavn CDN image URL to the given square size. The API returns
/// 150x150 (or 50x50) thumbnails; the CDN also hosts 500x500 and 50x50
/// renditions of the same asset, so the size token can be rewritten safely.
/// Falls back to the original URL when it doesn't match the expected pattern.
String jioSaavnImage(String? url, {int size = 500}) {
  final u = url?.toString() ?? '';
  if (u.isEmpty) return u;
  // NOTE: the $ anchor must stay unescaped inside this raw string —
  // \$ would match a literal dollar sign and never match real URLs.
  final scaled =
      u.replaceFirst(RegExp(r'\d+x\d+(?=\.jpg$)'), '${size}x$size');
  return scaled;
}

/// A song row returned by the JioSaavn songs search.
@immutable
class JioSaavnSong {
  final String token;
  final String title;
  final String artist;
  final String? album;
  final int? durationSeconds;
  final String? thumbnailUrl;
  final String encryptedMediaUrl;

  const JioSaavnSong({
    required this.token,
    required this.title,
    required this.artist,
    this.album,
    this.durationSeconds,
    this.thumbnailUrl,
    required this.encryptedMediaUrl,
  });
}

/// A resolved, playable audio stream (permanent AAC/MP4 URL).
@immutable
class JioSaavnStream {
  final String token;
  final String url;
  final int? bitrate;
  final String? mimeType;

  const JioSaavnStream({
    required this.token,
    required this.url,
    this.bitrate,
    this.mimeType,
  });
}

/// Result of resolving a Tidal track into a JioSaavn song token.
@immutable
class JioSaavnMatch {
  final JioSaavnSong song;
  final String method; // 'metadata'

  const JioSaavnMatch({required this.song, required this.method});
}

/// Resolves JioSaavn songs into permanent media URLs.
///
/// Search runs against the public JioSaavn API (`/api/songs?q=`), the audio
/// URL is recovered from `encrypted_media_url` (DES-ECB, key 38346591 — see
/// [DesEcb]) and the bitrate is upgraded to the best available (320 → 160 →
/// 96).
class JioSaavnService {
  static const String _base = String.fromEnvironment(
    'JIO_SAVNN_API_BASE',
    defaultValue: 'https://rthmx.vercel.app/api',
  );

  /// Mirror deployment with the same ODSkyler spec. Used automatically when
  /// the primary base fails (timeouts, 5xx, connection errors) so downloads
  /// and playback keep working during primary outages.
  static const String _fallbackBase =
      'https://jiosaavn-api-lyart-eight.vercel.app/api';

  /// Public accessor so other services (e.g. [JioSaavnAddonHandler]) can hit
  /// the same API base for catalog/detail endpoints.
  static String get apiBase => _base;

  /// Ordered list of bases: primary first, then the mirror.
  static List<String> get _bases => [_base, _fallbackBase];

  static const List<int> _qualities = [320, 160, 96, 48, 12];

  static const String _desKey = '38346591';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'Accept': 'application/json',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/126.0.0.0 Safari/537.36',
    },
  ));

  final Map<String, JioSaavnMatch?> _matchCache = {};
  final Map<String, JioSaavnStream> _streamCache = {};
  final Map<String, int> _streamCacheTs = {};

  /// Normalizes text for loose comparison (accents, case and punctuation),
  /// keeping letters AND digits so numeric titles like "11:11" keep meaning.
  static String _normalize(String s) {
    final buf = StringBuffer();
    for (final unit in s.toLowerCase().codeUnits) {
      if ((unit >= 0x30 && unit <= 0x39) || (unit >= 0x61 && unit <= 0x7a)) {
        buf.writeCharCode(unit);
      }
    }
    return buf.toString();
  }

  /// Latin-1 (y europeas) minúsculas acentuadas → base, para comparar
  /// "Maná" contra "Mana" o "Despechá" contra "Despecha".
  static const Map<int, String> _accentBase = {
    0xe0: 'a', 0xe1: 'a', 0xe2: 'a', 0xe3: 'a', 0xe4: 'a', 0xe5: 'a',
    0xe7: 'c',
    0xe8: 'e', 0xe9: 'e', 0xea: 'e', 0xeb: 'e',
    0xec: 'i', 0xed: 'i', 0xee: 'i', 0xef: 'i',
    0xf1: 'n',
    0xf2: 'o', 0xf3: 'o', 0xf4: 'o', 0xf5: 'o', 0xf6: 'o',
    0xf9: 'u', 0xfa: 'u', 0xfb: 'u', 0xfc: 'u',
    0xff: 'y',
  };

  static String _stripAccents(String s) {
    final buf = StringBuffer();
    for (final unit in s.toLowerCase().codeUnits) {
      final base = _accentBase[unit];
      if (base != null) {
        buf.write(base);
      } else {
        buf.writeCharCode(unit);
      }
    }
    return buf.toString();
  }

  /// True when [needle] appears as a whole word (token) inside [hay],
  /// ignoring accents/case. "roa" matches "Roa - ..." but NOT "Guava Road
  /// Dub" (donde solo aparece como substring).
  static bool _containsWord(String hay, String needle) {
    if (hay.isEmpty || needle.isEmpty) return false;
    final h = _stripAccents(hay);
    final n = _stripAccents(needle);
    if (!RegExp('[a-z0-9]').hasMatch(n)) return false;
    final escaped = RegExp.escape(n);
    return RegExp('(^|[^a-z0-9])$escaped([^a-z0-9]|\$)').hasMatch(h);
  }

  static final RegExp _featParen = RegExp(
    r'\s*\(\s*(?:feat\.?|ft\.?|featuring)\b[^)]*\)',
    caseSensitive: false,
  );
  static final RegExp _featDangling = RegExp(
    r'\s+(?:feat\.?|ft\.?|featuring)\b[^()]*$',
    caseSensitive: false,
  );

  /// Returns [title] without the "(feat. X)"/"(ft. X)"/"(featuring X)" part.
  ///
  /// Los paréntesis en la consulta rompen la búsqueda del API (0 resultados),
  /// y JioSaavn suele nombrar la pista sin el "(feat. X)".
  static String _coreTitle(String title) {
    final t = title.replaceAll(_featParen, '').trim();
    final t2 = t.replaceAll(_featDangling, '').trim();
    return t2.isEmpty ? t : t2;
  }

  /// Builds a [JioSaavnSong] from a raw JioSaavn JSON row, covering the two
  /// shapes the rthmx API returns:
  ///
  /// * search/playlist/song rows: `encrypted_media_url` inside `more_info`,
  ///   `duration` also inside `more_info`;
  /// * album detail rows: `encrypted_media_url` and `duration` at top level.
  ///
  /// Returns null when the row lacks an encrypted media URL (can't be played).
  static JioSaavnSong? fromRawMap(Map<String, dynamic> raw) {
    final token = raw['token']?.toString();
    if (token == null || token.isEmpty) return null;

    final more = raw['more_info'];
    final moreMap = more is Map ? Map<String, dynamic>.from(more) : <String, dynamic>{};

    final enc = (moreMap['encrypted_media_url'] ?? raw['encrypted_media_url'])
        ?.toString();
    if (enc == null || enc.isEmpty) return null;

    final subtitle = raw['subtitle']?.toString() ?? '';

    // El artista estructurado (more_info.artists.primary) es más fiable que
    // parsear el subtítulo ("Kendo kaponi ft. Jay Wheeler - APOCALIPTO").
    var artist = '';
    final artists = moreMap['artists'];
    if (artists is Map) {
      final primary = artists['primary'];
      if (primary is List && primary.isNotEmpty && primary.first is Map) {
        final name = primary.first['name']?.toString().trim() ?? '';
        if (name.isNotEmpty) artist = name;
      }
    }
    if (artist.isEmpty) {
      final sep = subtitle.indexOf(' - ');
      artist = sep > 0 ? subtitle.substring(0, sep) : subtitle;
    }

    return JioSaavnSong(
      token: token,
      title: raw['title']?.toString() ?? '',
      artist: artist,
      album: moreMap['album']?.toString(),
      durationSeconds:
          int.tryParse((moreMap['duration'] ?? raw['duration'])?.toString() ?? ''),
      thumbnailUrl: jioSaavnImage(raw['image']),
      encryptedMediaUrl: enc,
    );
  }

  /// Searches the JioSaavn catalog for songs matching [query].
  Future<List<JioSaavnSong>> searchSongs(
    String query, {
    bool useCache = true,
  }) async {
    final data = await _getJsonWithFallback('/songs', {'q': query});
    if (data is! Map || data['results'] is! List) return const [];

    final songs = <JioSaavnSong>[];
    for (final raw in data['results'] as List) {
      if (raw is! Map) continue;
      final song = fromRawMap(Map<String, dynamic>.from(raw));
      if (song != null) songs.add(song);
    }
    return songs;
  }

  /// GET against the primary base; on network/5xx failure retries against
  /// the mirror. Returns the parsed JSON map or throws after both fail.
  Future<dynamic> _getJsonWithFallback(
      String path, Map<String, dynamic> params) async {
    Object? lastError;
    for (final base in _bases) {
      try {
        final res = await _dio.get('$base$path', queryParameters: params);
        return res.data;
      } catch (e) {
        print('[JioSaavn] GET $base$path failed: $e — trying mirror…');
        lastError = e;
      }
    }
    throw lastError ?? Exception('All JioSaavn API bases failed');
  }

  /// Fetches a single song's detail by its JioSaavn token.
  Future<JioSaavnSong?> songByToken(String token) async {
    final data = await _getJsonWithFallback('/song', {'token': token});
    if (data is! Map) return null;
    return fromRawMap(Map<String, dynamic>.from(data));
  }

  /// Finds a song on JioSaavn matching loose metadata (title/artist/album).
  Future<JioSaavnMatch?> findMatch({
    required String title,
    required String artist,
    String? album,
    int? durationSeconds,
    bool useCache = true,
  }) async {
    final cacheKey = '$artist|$title|${album ?? ''}|${durationSeconds ?? ''}';
    if (useCache && _matchCache.containsKey(cacheKey)) {
      return _matchCache[cacheKey];
    }

    // Con el álbum en la consulta la búsqueda de JioSaavn es mucho más
    // precisa (un título como "11:11" solo devuelve canciones irrelevantes),
    // y con el título "nucleo" (sin el "(feat. X)") coincide con el
    // nombre que usa JioSaavn y no rompe la búsqueda por los paréntesis.
    final albumWord = (album ?? '').trim();
    final coreTitle = _coreTitle(title);
    final queries = <String>[
      if (albumWord.isNotEmpty) ...[
        '$artist $coreTitle $albumWord',
        '$coreTitle $artist $albumWord',
      ],
      '$artist $coreTitle',
      '$coreTitle $artist',
      coreTitle,
    ];

    for (final query in queries) {
      List<JioSaavnSong> songs;
      try {
        songs = await searchSongs(query, useCache: useCache);
      } catch (e) {
        print('[JioSaavn] search failed for "$query": $e');
        continue;
      }
      final hit = _bestMatch(
        candidates: songs,
        title: title,
        artist: artist,
        album: album,
        durationSeconds: durationSeconds,
      );
      if (hit != null) {
        final m = JioSaavnMatch(song: hit, method: 'metadata');
        if (useCache) _matchCache[cacheKey] = m;
        return m;
      }
    }

    if (useCache) _matchCache[cacheKey] = null;
    return null;
  }

  /// Scores candidate songs against the given metadata and returns the best.
  ///
  /// Rules: el título tiene que correlacionar realmente (exacto o contenido),
  /// el artista debe aparecer como palabra entera en el título o ser el
  /// artista principal del subtítulo, y coincidir el álbum otorga un bonus
  /// fuerte (misma grabación). Un cover con título parecido que "contiene" al
  /// artista solo como substring no es válido.
  JioSaavnSong? _bestMatch({
    required List<JioSaavnSong> candidates,
    required String title,
    required String artist,
    String? album,
    int? durationSeconds,
  }) {
    // El título "nucleo" (sin "(feat. X)") es con el que JioSaavn suele
    // nombrar su canción; el comparador principal lo usa y el título completo
    // se mantiene como ancla de contención cuando JioSaavn SÍ incluye el feat.
    final nCore = _normalize(_coreTitle(title));
    final nTitle = _normalize(title);
    final nAlbum =
        album == null ? '' : _normalize(album);

    JioSaavnSong? best;
    int bestScore = 0;

    for (final song in candidates) {
      int score = 0;
      final sTitle = _normalize(song.title);

      final titleExact = sTitle == nCore;
      final titleContains =
          sTitle.contains(nCore) ||
              nCore.contains(sTitle) ||
              sTitle.contains(nTitle) ||
              nTitle.contains(sTitle);
      // Sin correlación de título no hay candidato válido: evita que un
      // resultado irrelevante con la palabra "roa" dentro de "Guava Road"
      // gane por puntos de artista/duración.
      if (!titleContains) continue;

      if (titleExact) {
        score += 10;
      } else {
        score += 5;
      }

      final hasArtist =
          _containsWord(song.title, artist) || _containsWord(song.artist, artist);
      if (hasArtist) score += 4;

      // Solo se acepta un candidato con el artista corroborado (como palabra
      // entera en el título o artista principal del subtítulo). Sin esto un
      // cover con "roa" dentro de "Guava Road", o un "11:11" de otro artista
      // con la misma duración, gana puntos por artista/duración y se
      // reproduce otra canción.
      if (!hasArtist) continue;

      // Duración: corrobora la versión (penaliza cortes muy distintos).
      if (durationSeconds != null && song.durationSeconds != null) {
        final diff = (durationSeconds - song.durationSeconds!).abs();
        if (diff <= 3) {
          score += 2;
        } else if (diff > 20) {
          score -= 3;
        }
      }

      // El álbum es señalizador fuerte: misma grabación.
      if (nAlbum.isNotEmpty &&
          song.album != null &&
          nAlbum.length >= 4) {
        final sAlbum = _normalize(song.album!);
        if (sAlbum.isNotEmpty &&
            (sAlbum == nAlbum ||
                sAlbum.contains(nAlbum) ||
                nAlbum.contains(sAlbum))) {
          score += 4;
        }
      }

      if (score > bestScore) {
        bestScore = score;
        best = song;
      }
    }

    if (best == null || bestScore < 5) return null;
    return best;
  }

  /// Decrypts a JioSaavn `encrypted_media_url` into a permanent media URL.
  static String? decryptMediaUrl(String encrypted) {
    try {
      final cipher = base64Decode(encrypted.replaceAll(' ', '+'));
      final dec = DesEcb.decrypt(cipher, _desKey.codeUnits);
      var end = dec.length;
      while (end > 0 && dec[end - 1] == 0x04) {
        end -= 1;
      }
      return utf8.decode(dec.sublist(0, end), allowMalformed: true);
    } catch (e) {
      print('[JioSaavn] decrypt failed: $e');
      return null;
    }
  }

  /// Upgrades the media URL to the best bitrate available on the CDN.
  Future<String> _bestQualityUrl(String decrypted) async {
    final base = decrypted.replaceFirst(RegExp(r'_\d+\.mp4$'), '');
    for (final quality in _qualities) {
      final candidate = '${base}_$quality.mp4';
      try {
        final res = await _dio.get<Uint8List>(
          candidate,
          options: Options(
            responseType: ResponseType.bytes,
            headers: {'Range': 'bytes=0-15'},
            validateStatus: (status) => status == 206,
            receiveTimeout: const Duration(seconds: 5),
          ),
        );
      final type = res.headers.value('content-type') ?? '';
      if (type.startsWith('audio/')) {
        print('[JioSaavn] Best quality probe: $quality kbps → $candidate');
        return candidate;
      }
      } catch (_) {
        // Try a lower bitrate.
      }
    }
    return decrypted;
  }

  /// Resolves a playable stream URL for [song], using a short-TTL cache so
  /// auto-advance at track end is near-instant. Pass [forceFresh] on retries
  /// after a cached URL may have expired.
  Future<JioSaavnStream?> resolveStream(
    JioSaavnSong song, {
    bool forceFresh = false,
  }) async {
    if (!forceFresh && _streamCache.containsKey(song.token)) {
      final ts = _streamCacheTs[song.token]!;
      if (DateTime.now().millisecondsSinceEpoch - ts < 10 * 60 * 1000) {
        return _streamCache[song.token];
      }
      _streamCache.remove(song.token);
      _streamCacheTs.remove(song.token);
    }

    try {
      final decrypted = decryptMediaUrl(song.encryptedMediaUrl);
      if (decrypted == null) return null;

      final url = await _bestQualityUrl(decrypted);
      final bitrate =
          int.tryParse(RegExp(r'_(\d+)\.mp4$').firstMatch(url)?.group(1) ?? '');

      final stream = JioSaavnStream(
        token: song.token,
        url: url,
        bitrate: bitrate,
        mimeType: 'audio/mp4',
      );
      _streamCache[song.token] = stream;
      _streamCacheTs[song.token] = DateTime.now().millisecondsSinceEpoch;
      return stream;
    } catch (e) {
      print('[JioSaavn] resolveStream failed: $e');
      return null;
    }
  }
}