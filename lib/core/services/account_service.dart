import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../models/account_models.dart';
import '../models/models.dart';
import 'settings_service.dart';
import 'jiosaavn_addon_handler.dart';
import 'turso_client.dart';

/// Account service backed directly by the project's Turso (libSQL) database —
/// no intermediate auth server. The schema is created on demand from the app
/// and passwords are stored as PBKDF2-HMAC-SHA256 hashes with per-user salts.
///
/// Every new account is active immediately (there is no external approver).
class AccountService extends ChangeNotifier {
  /// Turso database used by the built-in account system. Public so the
  /// settings screen can probe connectivity.
  static const String dbUrl = 'libsql://metmusic-jiosaavn-mosecx.aws-us-east-1.turso.io';
  static const String authToken =
      'eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9.eyJhIjoicnciLCJpYXQiOjE3OTAzNzczOTcsImlkIjoiMDFhMGRhYWUtNWMwMS03NDQ5LWI5MzMtNjZkZGI3ODhjOTFlIiwia2lkIjoiYzlpa0p2Y1Ixb2VGOFJaZ3BnS0RMTWE3OGJYNWhsUktxY0UzS3U3ellNbyIsInJpZCI6IjI5ZTJmMjZkLWFiYTMtNGM5Ny1hOWFhLWU2MTI2ZjBhMTFjOSJ9.LcCbSflECiR3f4q9fbF93ebw2U9Olor5gGKYZ8E9FS_3bXLntej6xitqoMz42mQiIZZYCO1NXapyVmc9ZH6SAA';

  static const int _pbkdf2Iterations = 60000;

  final SettingsService _settings;
  late final TursoClient _turso;

  AccountUser? _user;
  List<FavoriteRow> _favorites = [];
  bool _favoritesLoaded = false;
  bool _loading = false;
  String? _error;

  AccountService({required SettingsService settingsService})
      : _settings = settingsService {
    _turso = TursoClient(url: dbUrl, authToken: authToken);
  }

  AccountUser? get user => _user;
  bool get isLoggedIn => _user != null;
  bool get isApproved => _user != null; // Built-in accounts are always active.
  bool get isPending => false;
  bool get isRejected => false;
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

  // ========== SCHEMA (created on demand) ==========

  bool _schemaReady = false;

  Future<void> _ensureSchema() async {
    if (_schemaReady) return;
    await tursoExecute(_turso, [
      (
        sql: '''
        CREATE TABLE IF NOT EXISTS users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          username TEXT NOT NULL UNIQUE COLLATE NOCASE,
          email TEXT NOT NULL UNIQUE COLLATE NOCASE,
          password_hash TEXT NOT NULL,
          salt TEXT NOT NULL,
          role TEXT NOT NULL DEFAULT 'user',
          created_at TEXT NOT NULL
        )''',
        args: const [],
      ),
      (
        sql: '''
        CREATE TABLE IF NOT EXISTS favorites (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          item_type TEXT NOT NULL,
          item_id TEXT NOT NULL,
          data TEXT NOT NULL DEFAULT '{}',
          created_at TEXT NOT NULL,
          UNIQUE(user_id, item_type, item_id)
        )''',
        args: const [],
      ),
      (
        sql: '''
        CREATE TABLE IF NOT EXISTS playlists (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          name TEXT NOT NULL,
          description TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL
        )''',
        args: const [],
      ),
      (
        sql: '''
        CREATE TABLE IF NOT EXISTS playlist_tracks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
          track_id TEXT NOT NULL,
          position INTEGER NOT NULL DEFAULT 0,
          data TEXT NOT NULL DEFAULT '{}',
          created_at TEXT NOT NULL,
          UNIQUE(playlist_id, track_id)
        )''',
        args: const [],
      ),
    ]);
    _schemaReady = true;
  }

  // ========== SESSION RESTORE ==========

  Future<void> init() async {
    await _ensureSchema();
    final savedId = _settings.storedUserId;
    final savedName = _settings.storedUsername;
    if (savedId != null && savedName != null && savedName.isNotEmpty) {
      final rows = await tursoExecuteOne(
        _turso,
        'SELECT id, username, email, role, created_at FROM users WHERE id = ?',
        [savedId],
      );
      if (rows.rows.isNotEmpty) {
        _user = _userFromRow(rows.rows.first);
        unawaited(loadFavorites());
      } else {
        await _clearStoredUser();
      }
    }
    notifyListeners();
  }

  // ========== AUTH ==========

  Future<bool> login({
    required String identifier,
    required String password,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await _ensureSchema();
      final res = await tursoExecuteOne(
        _turso,
        'SELECT id, username, email, role, password_hash, salt, created_at '
        'FROM users WHERE username = ? OR email = ? LIMIT 1',
        [identifier.trim(), identifier.trim().toLowerCase()],
      );
      final row = res.rows.isEmpty ? null : res.rows.first;
      final hash = row?['password_hash']?.toString();
      final salt = row?['salt']?.toString();

      if (row == null || hash == null || salt == null) {
        _error = 'Usuario o contraseña incorrectos';
        return false;
      }

      final computed = _hashPassword(password, salt);
      if (!_constantTimeEquals(computed, hash)) {
        _error = 'Usuario o contraseña incorrectos';
        return false;
      }

      _user = _userFromRow(row);
      await _storeUser();
      unawaited(loadFavorites());
      return true;
    } on TursoException catch (e) {
      _error = e.message;
      return false;
    } catch (e) {
      print('[Account] login error: $e');
      _error = 'Error de conexión con la base de datos';
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
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
      await _ensureSchema();

      final name = username.trim();
      final mail = email.trim().toLowerCase();

      if (name.isEmpty || !name.contains(RegExp(r'^[a-zA-Z0-9_.-]+$'))) {
        _error = 'El usuario solo puede contener letras, números, . _ -';
        return false;
      }
      if (!mail.contains('@')) {
        _error = 'Ingresa un email válido';
        return false;
      }
      if (password.length < 6) {
        _error = 'La contraseña debe tener al menos 6 caracteres';
        return false;
      }

      final existing = await tursoExecuteOne(
        _turso,
        'SELECT id FROM users WHERE username = ? OR email = ? LIMIT 1',
        [name, mail],
      );
      if (existing.rows.isNotEmpty) {
        _error = 'Ese usuario o correo ya está registrado';
        return false;
      }

      final salt = _randomSalt();
      final hash = _hashPassword(password, salt);
      final now = DateTime.now().toUtc().toIso8601String();

      final insert = await tursoExecuteOne(
        _turso,
        'INSERT INTO users (username, email, password_hash, salt, role, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        [name, mail, hash, salt, 'user', now],
      );

      final id = insert.lastInsertId;
      if (id == null) {
        _error = 'No se pudo crear la cuenta';
        return false;
      }

      final row = await tursoExecuteOne(
        _turso,
        'SELECT id, username, email, role, created_at FROM users WHERE id = ?',
        [id],
      );
      _user = _userFromRow(row.rows.first);
      await _storeUser();
      unawaited(loadFavorites());
      return true;
    } on TursoException catch (e) {
      if (e.message.contains('UNIQUE')) {
        _error = 'Ese usuario o correo ya está registrado';
      } else {
        _error = e.message;
      }
      return false;
    } catch (e) {
      print('[Account] register error: $e');
      _error = 'Error de conexión con la base de datos';
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _user = null;
    _favorites = [];
    _favoritesLoaded = false;
    await _clearStoredUser();
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
      final res = await tursoExecuteOne(
        _turso,
        'SELECT id, item_type, item_id, data, created_at FROM favorites '
        'WHERE user_id = ? ORDER BY created_at DESC, id DESC',
        [_user!.id],
      );
      _favorites = res.rows.map(_favoriteFromRow).toList();
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
    if (!isLoggedIn) return false;
    try {
      await tursoExecuteOne(
        _turso,
        'INSERT INTO favorites (user_id, item_type, item_id, data, created_at) '
        'VALUES (?, ?, ?, ?, ?) '
        'ON CONFLICT(user_id, item_type, item_id) DO NOTHING',
        [_user!.id, type, itemId, jsonEncode(data), _now()],
      );
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
    if (!isLoggedIn) return false;
    try {
      await tursoExecuteOne(
        _turso,
        'DELETE FROM favorites WHERE user_id = ? AND item_type = ? AND item_id = ?',
        [_user!.id, type, itemId],
      );
      _favorites.removeWhere((f) => f.itemType == type && f.itemId == itemId);
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
    if (!isLoggedIn) return [];
    try {
      final res = await tursoExecuteOne(
        _turso,
        'SELECT id, name, description, created_at FROM playlists '
        'WHERE user_id = ? ORDER BY created_at DESC, id DESC',
        [_user!.id],
      );
      return res.rows.map(_playlistFromRow).toList();
    } catch (e) {
      print('[Account] getPlaylists error: $e');
      return [];
    }
  }

  Future<UserPlaylist?> createPlaylist(String name, {String description = ''}) async {
    if (!isLoggedIn) return null;
    try {
      final insert = await tursoExecuteOne(
        _turso,
        'INSERT INTO playlists (user_id, name, description, created_at) '
        'VALUES (?, ?, ?, ?)',
        [_user!.id, name.trim(), description, _now()],
      );
      final id = insert.lastInsertId;
      if (id == null) return null;
      return UserPlaylist(
        id: id,
        name: name.trim(),
        description: description,
        createdAt: _now(),
      );
    } catch (e) {
      print('[Account] createPlaylist error: $e');
      return null;
    }
  }

  Future<(UserPlaylist, List<Track>)?> getPlaylistDetail(int id) async {
    if (!isLoggedIn) return null;
    try {
      final plRes = await tursoExecuteOne(
        _turso,
        'SELECT id, name, description, created_at FROM playlists WHERE id = ? AND user_id = ?',
        [id, _user!.id],
      );
      if (plRes.rows.isEmpty) return null;

      final trRes = await tursoExecuteOne(
        _turso,
        'SELECT track_id, data FROM playlist_tracks '
        'WHERE playlist_id = ? ORDER BY position, id',
        [id],
      );

      final playlist = _playlistFromRow(plRes.rows.first);
      final tracks = trRes.rows.map((r) {
        final data = _parseJsonMap(r['data']);
        data['id'] ??= r['track_id']?.toString();
        return trackFromStored(data);
      }).toList();
      return (playlist, tracks);
    } catch (e) {
      print('[Account] getPlaylistDetail error: $e');
      return null;
    }
  }

  Future<bool> deletePlaylist(int id) async {
    if (!isLoggedIn) return false;
    try {
      await tursoExecute(_turso, [
        (sql: 'DELETE FROM playlist_tracks WHERE playlist_id = ?', args: [id]),
        (sql: 'DELETE FROM playlists WHERE id = ? AND user_id = ?',
            args: [id, _user!.id]),
      ]);
      return true;
    } catch (e) {
      print('[Account] deletePlaylist error: $e');
      return false;
    }
  }

  Future<bool> addTrackToPlaylist(int id, Track track) async {
    if (!isLoggedIn) return false;
    try {
      final countRes = await tursoExecuteOne(
        _turso,
        'SELECT COUNT(*) AS n FROM playlist_tracks WHERE playlist_id = ?',
        [id],
      );
      final position = int.tryParse(countRes.firstValue('n')?.toString() ?? '0') ?? 0;

      await tursoExecuteOne(
        _turso,
        'INSERT INTO playlist_tracks (playlist_id, track_id, position, data, created_at) '
        'VALUES (?, ?, ?, ?, ?) '
        'ON CONFLICT(playlist_id, track_id) DO NOTHING',
        [
          id,
          track.addonTrackId ?? track.id,
          position,
          jsonEncode(storedTrackFromTrack(track)),
          _now(),
        ],
      );
      return true;
    } catch (e) {
      print('[Account] addTrackToPlaylist error: $e');
      return false;
    }
  }

  Future<bool> removeTrackFromPlaylist(int id, String trackId) async {
    if (!isLoggedIn) return false;
    try {
      await tursoExecuteOne(
        _turso,
        'DELETE FROM playlist_tracks WHERE playlist_id = ? AND track_id = ?',
        [id, trackId],
      );
      return true;
    } catch (e) {
      print('[Account] removeTrackFromPlaylist error: $e');
      return false;
    }
  }

  // ========== ROW MAPPERS ==========

  AccountUser _userFromRow(Map<String, dynamic> row) {
    return AccountUser(
      id: int.tryParse(row['id']?.toString() ?? '') ?? 0,
      username: row['username']?.toString() ?? '',
      email: row['email']?.toString() ?? '',
      role: row['role']?.toString() ?? 'user',
      status: 'approved',
      createdAt: row['created_at']?.toString(),
    );
  }

  FavoriteRow _favoriteFromRow(Map<String, dynamic> row) {
    return FavoriteRow(
      id: int.tryParse(row['id']?.toString() ?? '') ?? 0,
      itemType: row['item_type']?.toString() ?? 'track',
      itemId: row['item_id']?.toString() ?? '',
      data: _parseJsonMap(row['data']),
      createdAt: row['created_at']?.toString(),
    );
  }

  UserPlaylist _playlistFromRow(Map<String, dynamic> row) {
    return UserPlaylist(
      id: int.tryParse(row['id']?.toString() ?? '') ?? 0,
      name: row['name']?.toString() ?? 'Playlist',
      description: row['description']?.toString() ?? '',
      createdAt: row['created_at']?.toString(),
    );
  }

  static Map<String, dynamic> _parseJsonMap(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  // ========== CREDENTIALS HELPERS ==========

  static String _randomSalt() {
    final rnd = Random.secure();
    return base64UrlEncode(List<int>.generate(16, (_) => rnd.nextInt(256)));
  }

  /// PBKDF2-HMAC-SHA256 (RFC 2898) implemented over package:crypto.
  static Uint8List _pbkdf2(
      String password, String salt, int iterations, int keyLength) {
    final hmac = Hmac(sha256, utf8.encode(password));
    final saltBytes = utf8.encode(salt);
    final blocks = (keyLength + 31) ~/ 32;
    final out = <int>[];

    for (var block = 1; block <= blocks; block++) {
      // U1 = PRF(password, salt || INT_32_BE(block))
      final saltBlock = BytesBuilder()
        ..add(saltBytes)
        ..addByte((block >> 24) & 0xff)
        ..addByte((block >> 16) & 0xff)
        ..addByte((block >> 8) & 0xff)
        ..addByte(block & 0xff);
      var u = hmac.convert(saltBlock.toBytes()).bytes;

      final acc = Uint8List.fromList(u);
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < acc.length; j++) {
          acc[j] ^= u[j];
        }
      }
      out.addAll(acc);
    }
    return Uint8List.fromList(out.sublist(0, keyLength));
  }

  static String _hashPassword(String password, String salt) {
    final bytes = _pbkdf2(password, salt, _pbkdf2Iterations, 32);
    return base64Encode(bytes);
  }

  static bool _constantTimeEquals(String a, String b) {
    final ab = a.codeUnits;
    final bb = b.codeUnits;
    var diff = ab.length ^ bb.length;
    for (var i = 0; i < ab.length && i < bb.length; i++) {
      diff |= ab[i] ^ bb[i];
    }
    return diff == 0;
  }

  // ========== LOCAL SESSION PERSISTENCE ==========

  Future<void> _storeUser() async {
    if (_user == null) return;
    await _settings.setStoredUser(_user!.id, _user!.username);
  }

  Future<void> _clearStoredUser() async {
    await _settings.clearStoredUser();
  }

  static String _now() => DateTime.now().toUtc().toIso8601String();
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
