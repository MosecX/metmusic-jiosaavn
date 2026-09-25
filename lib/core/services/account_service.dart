import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/account_models.dart';
import '../models/models.dart';
import 'settings_service.dart';
import 'jiosaavn_addon_handler.dart';

class AccountService extends ChangeNotifier {
  final SettingsService _settings;
  final Dio _dio;

  AccountUser? _user;
  List<FavoriteRow> _favorites = [];
  bool _favoritesLoaded = false;
  bool _loading = false;
  String? _error;

  AccountService({required SettingsService settingsService})
      : _settings = settingsService,
        _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 25),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        ));

  String get _base => _settings.accountApiBase;

  String? get _cookie => _settings.sessionCookie;

  Options get _authOptions {
    if (kIsWeb) {
      return Options(extra: {'withCredentials': true});
    }
    return Options(
      headers: {
        if (_cookie != null) 'Cookie': 'session=$_cookie',
      },
    );
  }

  AccountUser? get user => _user;
  bool get isLoggedIn => _user != null;
  bool get isApproved => _user?.isApproved ?? false;
  bool get isPending => _user?.isPending ?? false;
  bool get isRejected => _user?.isRejected ?? false;
  bool get loading => _loading;
  String? get error => _error;
  List<FavoriteRow> get favorites => _favorites;
  bool get favoritesLoaded => _favoritesLoaded;
  List<FavoriteRow> get favoriteTracks =>
      _favorites.where((f) => f.itemType == 'track').toList();
  List<FavoriteRow> get favoriteAlbums =>
      _favorites.where((f) => f.itemType == 'album').toList();
  List<FavoriteRow> get favoriteArtists =>
      _favorites.where((f) => f.itemType == 'artist').toList();

  bool isFavorite(String type, String itemId) =>
      _favorites.any((f) => f.itemType == type && f.itemId == itemId);

  Future<void> init() async {
    if (kIsWeb || _settings.sessionCookie != null) {
      final ok = await _fetchMe();
      if (ok) {
        await loadFavorites();
      }
    }
    notifyListeners();
  }

  Future<bool> _fetchMe() async {
    try {
      final res = await _dio.get('$_base/api/auth/me', options: _authOptions);
      final data = res.data;
      if (data is Map && data['user'] is Map) {
        _user = AccountUser.fromJson(Map<String, dynamic>.from(data['user']));
        notifyListeners();
        return true;
      }
      _user = null;
      await _settings.clearSessionCookie();
    } catch (e) {
      _user = null;
      if (e is DioException && e.response?.statusCode == 401) {
        await _settings.clearSessionCookie();
      }
    }
    notifyListeners();
    return _user != null;
  }

  Future<bool> login({
    required String identifier,
    required String password,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final res = await _dio.post('$_base/api/auth/login', data: {
        'identifier': identifier,
        'password': password,
      });
      final data = res.data is Map ? Map<String, dynamic>.from(res.data) : {};
      final user = data['user'];
      if (user is Map) {
        _user = AccountUser.fromJson(Map<String, dynamic>.from(user));
        final setCookie = res.headers.value('set-cookie');
        if (setCookie != null) {
          final m = RegExp(r'session=([^;]+)').firstMatch(setCookie);
          if (m != null) {
            await _settings.setSessionCookie(m.group(1)!);
          }
        }
        _loading = false;
        notifyListeners();
        unawaited(loadFavorites());
        return true;
      }
      _error = 'Respuesta inválida del servidor';
    } on DioException catch (e) {
      _error = _messageFrom(e);
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
    return false;
  }

  Future<bool> register({
    required String username,
    required String email,
    required String password,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final res = await _dio.post('$_base/api/auth/register', data: {
        'username': username,
        'email': email,
        'password': password,
      });
      final data = res.data is Map ? Map<String, dynamic>.from(res.data) : {};
      final user = data['user'];
      if (user is Map) {
        _user = AccountUser.fromJson(Map<String, dynamic>.from(user));
        final setCookie = res.headers.value('set-cookie');
        if (setCookie != null) {
          final m = RegExp(r'session=([^;]+)').firstMatch(setCookie);
          if (m != null) {
            await _settings.setSessionCookie(m.group(1)!);
          }
        }
        _loading = false;
        notifyListeners();
        unawaited(loadFavorites());
        return true;
      }
      _error = 'Respuesta inválida del servidor';
    } on DioException catch (e) {
      _error = _messageFrom(e);
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
    return false;
  }

  Future<void> logout() async {
    try {
      await _dio.post('$_base/api/auth/logout', options: _authOptions);
    } catch (_) {}
    _user = null;
    _favorites = [];
    _favoritesLoaded = false;
    await _settings.clearSessionCookie();
    notifyListeners();
  }

  // ========== FAVORITES ==========

  Future<void> loadFavorites() async {
    if (!isLoggedIn) {
      _favorites = [];
      _favoritesLoaded = false;
      notifyListeners();
      return;
    }
    try {
      final res = await _dio.get('$_base/api/library/favorites',
          options: _authOptions);
      final data = res.data is Map ? Map<String, dynamic>.from(res.data) : {};
      final list = data['favorites'] is List
          ? List<dynamic>.from(data['favorites'])
          : const [];
      _favorites = list
          .map((e) => FavoriteRow.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _favoritesLoaded = true;
      notifyListeners();
    } catch (e) {
      print('[Account] loadFavorites error: $e');
    }
  }

  Future<bool> addFavorite({
    required String type,
    required String itemId,
    required Map<String, dynamic> data,
  }) async {
    try {
      await _dio.post('$_base/api/library/favorites',
          data: {
            'type': type,
            'itemId': itemId,
            'data': data,
          },
          options: _authOptions);
      _favorites.insert(
          0, FavoriteRow(id: 0, itemType: type, itemId: itemId, data: data));
      notifyListeners();
      return true;
    } catch (e) {
      print('[Account] addFavorite error: $e');
      return false;
    }
  }

  Future<bool> removeFavorite({
    required String type,
    required String itemId,
  }) async {
    try {
      await _dio.delete('$_base/api/library/favorites',
          queryParameters: {'type': type, 'id': itemId},
          options: _authOptions);
      _favorites
          .removeWhere((f) => f.itemType == type && f.itemId == itemId);
      notifyListeners();
      return true;
    } catch (e) {
      print('[Account] removeFavorite error: $e');
      return false;
    }
  }

  Future<bool> toggleFavorite({
    required String type,
    required String itemId,
    Map<String, dynamic>? data,
  }) async {
    if (isFavorite(type, itemId)) {
      return removeFavorite(type: type, itemId: itemId);
    }
    return addFavorite(type: type, itemId: itemId, data: data ?? {});
  }

  // ========== PLAYLISTS ==========

  Future<List<UserPlaylist>> getPlaylists() async {
    try {
      final res = await _dio.get('$_base/api/library/playlists',
          options: _authOptions);
      final data = res.data is Map ? Map<String, dynamic>.from(res.data) : {};
      final list = data['playlists'] is List
          ? List<dynamic>.from(data['playlists'])
          : const [];
      return list
          .map((e) => UserPlaylist.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      print('[Account] getPlaylists error: $e');
      return [];
    }
  }

  Future<UserPlaylist?> createPlaylist(String name, {String description = ''}) async {
    try {
      final res = await _dio.post('$_base/api/library/playlists',
          data: {'name': name, 'description': description},
          options: _authOptions);
      final data = res.data is Map ? Map<String, dynamic>.from(res.data) : {};
      if (data['playlist'] is Map) {
        return UserPlaylist.fromJson(Map<String, dynamic>.from(data['playlist']));
      }
    } catch (e) {
      print('[Account] createPlaylist error: $e');
    }
    return null;
  }

  Future<(UserPlaylist, List<Track>)?> getPlaylistDetail(int id) async {
    try {
      final res = await _dio.get('$_base/api/library/playlists/$id',
          options: _authOptions);
      final data = res.data is Map ? Map<String, dynamic>.from(res.data) : {};
      if (data['playlist'] is! Map) return null;
      final playlist =
          UserPlaylist.fromJson(Map<String, dynamic>.from(data['playlist']));
      final list = data['tracks'] is List
          ? List<dynamic>.from(data['tracks'])
          : const [];
      final tracks = list
          .map((e) => PlaylistTrackRow.fromJson(Map<String, dynamic>.from(e)))
          .map((r) => trackFromStored(r.data))
          .toList();
      return (playlist, tracks);
    } catch (e) {
      print('[Account] getPlaylistDetail error: $e');
      return null;
    }
  }

  Future<bool> deletePlaylist(int id) async {
    try {
      await _dio.delete('$_base/api/library/playlists/$id',
          options: _authOptions);
      return true;
    } catch (e) {
      print('[Account] deletePlaylist error: $e');
      return false;
    }
  }

  Future<bool> addTrackToPlaylist(int id, Track track) async {
    try {
      await _dio.post('$_base/api/library/playlists/$id/tracks',
          data: {'track': storedTrackFromTrack(track)},
          options: _authOptions);
      return true;
    } catch (e) {
      print('[Account] addTrackToPlaylist error: $e');
      return false;
    }
  }

  Future<bool> removeTrackFromPlaylist(int id, String trackId) async {
    try {
      await _dio.delete('$_base/api/library/playlists/$id/tracks',
          queryParameters: {'trackId': trackId}, options: _authOptions);
      return true;
    } catch (e) {
      print('[Account] removeTrackFromPlaylist error: $e');
      return false;
    }
  }

  // ========== HELPERS ==========

  String _messageFrom(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] != null) {
      return data['error'].toString();
    }
    switch (e.response?.statusCode) {
      case 401:
        return 'Credenciales inválidas';
      case 409:
        return 'Ese usuario o correo ya está registrado';
      case 400:
        return 'Datos inválidos';
    }
    return 'Error de red. Verifica tu conexión.';
  }
}

// ========== STORED TRACK MAPPING ==========

/// Stored covers keep the JioSaavn CDN URL directly — no UUID indirection.
String? coverUuidFromUrl(String? url) =>
    (url == null || url.isEmpty) ? null : url;

String coverUrlFromUuid(String? uuid, {int size = 640}) {
  if (uuid == null || uuid.isEmpty) return '';
  return uuid;
}

AudioQuality qualityFromString(String? quality) {
  if (quality == null || quality.isEmpty) {
    return AudioQuality(isHiRes: false);
  }
  final isHiRes = quality.toUpperCase().replaceAll('_', '').contains('HIRES');
  return AudioQuality(
    isHiRes: isHiRes,
    maximumBitDepth: isHiRes ? 24 : null,
    maximumSamplingRate: isHiRes ? 96.0 : null,
  );
}

Map<String, dynamic> storedTrackFromTrack(Track track) {
  final raw = (track.rawData is Map)
      ? Map<String, dynamic>.from(track.rawData as Map)
      : <String, dynamic>{};
  final aq = track.audioQuality;
  final quality = aq != null
      ? (aq.isHiRes ? 'HI_RES_LOSSLESS' : 'LOSSLESS')
      : (raw['audioQuality'] is String ? raw['audioQuality'] as String : 'LOSSLESS');

  final rawId = track.addonTrackId ?? track.id;

  final rawAlbum = raw['album'] is Map
      ? Map<String, dynamic>.from(raw['album'] as Map)
      : <String, dynamic>{};
  final rawArtist = raw['artists'] is List &&
          (raw['artists'] as List).isNotEmpty &&
          (raw['artists'] as List).first is Map
      ? Map<String, dynamic>.from((raw['artists'] as List).first as Map)
      : <String, dynamic>{};
  final albumId = track.albumId ?? rawAlbum['id']?.toString();
  final albumTitle = track.albumTitle ?? rawAlbum['title']?.toString();
  final albumCover = coverUuidFromUrl(
    track.albumCover ?? rawAlbum['cover']?.toString() ?? raw['cover']?.toString() ?? raw['image']?.toString(),
  );
  final artistId = track.artistId ?? rawArtist['id']?.toString();
  final artistName = track.artist != 'Unknown Artist'
      ? track.artist
      : rawArtist['name']?.toString() ?? 'Unknown Artist';

  return {
    'id': rawId,
    'addonId': track.addonId,
    'addonTrackId': rawId,
    'title': track.title,
    'duration': track.duration ?? 0,
    'explicit': raw['isExplicit'] ?? raw['explicit'] ?? false,
    'audioQuality': quality,
    'artist': {
      'id': artistId,
      'name': artistName,
    },
    'artists': raw['artists'],
    'cover': albumCover,
    'album': {
      'id': albumId,
      'title': albumTitle,
      'cover': albumCover,
    },
  };
}

Track trackFromStored(Map<String, dynamic> data) {
  final artist = data['artist'];
  final album = data['album'];
  final artistName =
      artist is Map ? (artist['name']?.toString() ?? 'Unknown Artist') : 'Unknown Artist';
  final albumTitle = album is Map
      ? (album['title']?.toString())
      : (data['albumTitle']?.toString());
  final cover = album is Map ? album['cover']?.toString() : null;
  final rawId = data['addonTrackId']?.toString() ?? data['id']?.toString() ?? '';
  final addonId = data['addonId']?.toString() ?? JioSaavnAddonHandler.addonId;
  return Track(
    id: rawId.isNotEmpty ? '${addonId}_$rawId' : (data['id']?.toString() ?? ''),
    title: data['title']?.toString() ?? 'Unknown Title',
    artist: artistName,
    albumTitle: albumTitle,
    albumCover: coverUrlFromUuid(cover),
    albumId: album is Map ? album['id']?.toString() : null,
    artistId: artist is Map ? artist['id']?.toString() : null,
    duration: data['duration'] is int
        ? data['duration']
        : int.tryParse(data['duration']?.toString() ?? ''),
    audioQuality: qualityFromString(data['audioQuality']?.toString()),
    addonId: addonId,
    addonTrackId: rawId,
    rawData: data,
  );
}
