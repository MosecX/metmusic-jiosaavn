import 'models.dart';

List<String>? _asStringList(dynamic value) =>
    value is List ? List<String>.from(value.map((e) => e.toString())) : null;

List<String>? mergeAtmos(dynamic audioModes, dynamic mediaTags,
    {bool isAtmos = false}) {
  final set = <String>{};
  if (audioModes is List) set.addAll(audioModes.map((e) => e.toString()));
  if (mediaTags is List) set.addAll(mediaTags.map((e) => e.toString()));
  if (isAtmos) set.add('ATMOS');
  return set.isEmpty ? null : set.toList();
}

/// Normalize a backend quality string (e.g. "HIRES_LOSSLESS" with no
/// underscore, or "LOSSLESS") to the canonical app form used by the badge.
String? _normQualityStr(dynamic q) {
  if (q == null) return null;
  final s = q.toString().toUpperCase().replaceAll('_', '');
  if (s.contains('HIRES')) return 'HI_RES_LOSSLESS';
  if (s.contains('LOSSLESS')) return 'LOSSLESS';
  if (s.contains('HIGH')) return 'HIGH';
  if (s.contains('LOW')) return 'LOW';
  return q.toString();
}

String? _firstArtistName(dynamic artists) {
  if (artists is List && artists.isNotEmpty) {
    final a = artists.first;
    if (a is Map) return a['name']?.toString();
  }
  return null;
}

String? _firstArtistId(dynamic artists) {
  if (artists is List && artists.isNotEmpty) {
    final a = artists.first;
    if (a is Map) return a['id']?.toString();
  }
  return null;
}

/// Quality string for the Tidal-style album badge: 'ATMOS' (Dolby Atmos),
/// 'HI_RES_LOSSLESS' (Hi-Res), 'LOSSLESS', or null. Prefers the album-level
/// audioQuality/isAtmos and falls back to its tracks when those are absent
/// (e.g. album summaries that only carry a track list).
String? albumBadgeQuality(AddonAlbum album) {
  if (album.isAtmos) return 'ATMOS';
  final aq = album.audioQuality;
  if (aq != null && aq.isNotEmpty) return aq;
  final tracks = album.tracks;
  if (tracks != null && tracks.isNotEmpty) {
    for (final t in tracks) {
      final q = t.quality ?? '';
      if (q.replaceAll('_', '').contains('HIRES')) return 'HI_RES_LOSSLESS';
      if (q.contains('LOSSLESS')) return 'LOSSLESS';
    }
  }
  return null;
}

/// Addon type: 'server' (Eclipse-spec HTTP server) or 'user' (device-side handler)
enum AddonType { server, user }

/// What an addon is capable of providing
/// Matches Eclipse spec resource names
class AddonResource {
  static const String search = 'search';
  static const String stream = 'stream';
  static const String catalog = 'catalog'; // /album, /artist, /playlist endpoints
  static const String library = 'library'; // Library synchronization endpoints
  static const String lyrics = 'lyrics'; // User addons only
}

/// Content type controls which player UI Eclipse / MetMusic uses
enum AddonContentType { music, audiobook, podcast }

/// The manifest describes an addon — stored locally after install.
/// For server addons this is fetched from GET /manifest.json.
/// For user addons (like the built-in DAB addon) it is hardcoded in the handler.
class AddonManifest {
  final String id;
  final String name;
  final String version;
  final String? description;
  final String? icon; // URL to square icon image
  final List<String> resources; // e.g. ['search', 'stream', 'catalog']
  final List<String> types; // e.g. ['track', 'album', 'artist', 'playlist']
  final AddonContentType contentType;
  final AddonType addonType;
  final String? baseUrl; // Required for server addons; null for user addons
  final DateTime installedAt;
  final bool isBuiltIn;

  AddonManifest({
    required this.id,
    required this.name,
    required this.version,
    this.description,
    this.icon,
    required this.resources,
    this.types = const ['track'],
    this.contentType = AddonContentType.music,
    required this.addonType,
    this.baseUrl,
    required this.installedAt,
    this.isBuiltIn = false,
  });

  bool get supportsSearch => resources.contains(AddonResource.search);
  bool get supportsStream => resources.contains(AddonResource.stream);
  bool get supportsCatalog => resources.contains(AddonResource.catalog);

  /// sync / cloud library support — strictly looks for 'library' tag.
  bool get supportsLibrary => resources.contains(AddonResource.library);
  
  /// dedicated sync support — strictly looks for the 'library' tag
  bool get supportsSync => resources.contains(AddonResource.library);

  bool get supportsLyrics => resources.contains(AddonResource.lyrics);

  String get addonTypeLabel {
    if (isBuiltIn) return 'BUILT-IN';
    switch (addonType) {
      case AddonType.server:
        return 'SERVER';
      case AddonType.user:
        return 'USER';
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'description': description,
        'icon': icon,
        'resources': resources,
        'types': types,
        'contentType': contentType.name,
        'addonType': addonType.name,
        'baseUrl': baseUrl,
        'installedAt': installedAt.toIso8601String(),
        'isBuiltIn': isBuiltIn,
      };

  factory AddonManifest.fromJson(Map<String, dynamic> json) {
    return AddonManifest(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown Addon',
      version: json['version'] ?? '0.0.0',
      description: json['description'],
      icon: json['icon'],
      resources: List<String>.from(json['resources'] ?? []),
      types: List<String>.from(json['types'] ?? ['track']),
      contentType: _parseContentType(json['contentType']),
      addonType: json['addonType'] == 'server' ? AddonType.server : AddonType.user,
      baseUrl: json['baseUrl'],
      installedAt: json['installedAt'] != null
          ? DateTime.tryParse(json['installedAt']) ?? DateTime.now()
          : DateTime.now(),
      isBuiltIn: json['isBuiltIn'] ?? false,
    );
  }

  /// Parse manifest from a raw Eclipse-spec /manifest.json response.
  /// The caller provides the baseUrl (from where the manifest was fetched)
  /// and whether to treat this as a server or user addon.
  factory AddonManifest.fromEclipseJson(
    Map<String, dynamic> json, {
    required String baseUrl,
    AddonType addonType = AddonType.server,
  }) {
    return AddonManifest(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown Addon',
      version: json['version'] ?? '0.0.0',
      description: json['description'],
      icon: json['icon'],
      resources: List<String>.from(json['resources'] ?? []),
      types: List<String>.from(json['types'] ?? ['track']),
      contentType: _parseContentType(json['contentType']),
      addonType: addonType,
      baseUrl: baseUrl,
      installedAt: DateTime.now(),
      isBuiltIn: false,
    );
  }

  static AddonContentType _parseContentType(dynamic value) {
    switch (value) {
      case 'audiobook':
        return AddonContentType.audiobook;
      case 'podcast':
        return AddonContentType.podcast;
      default:
        return AddonContentType.music;
    }
  }
}

// ---------------------------------------------------------------------------
// Search result models — matches Eclipse Music spec + DAB response fields
// ---------------------------------------------------------------------------

/// A track result from any addon
class AddonTrack {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final int? duration; // seconds
  final String? artworkURL;
  final String? isrc;
  final String? format; // mp3, flac, aac, m4a
  final String? quality; // HI_RES_LOSSLESS, LOSSLESS, HIGH, ...
  final String? streamURL; // optional — if present, skip /stream call
  final String? artistId;
  final String? albumId;
  final int? popularity;
  final String addonId; // which addon this track belongs to
  final Map<String, dynamic>? rawData; // full source JSON from the addon

  AddonTrack({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.duration,
    this.artworkURL,
    this.isrc,
    this.format,
    this.quality, // HI_RES_LOSSLESS, LOSSLESS, HIGH, ...
    this.streamURL, // optional — if present, skip /stream call
    this.artistId,
    this.albumId,
    this.popularity,
    required this.addonId,
    this.rawData,
  });

  factory AddonTrack.fromJson(Map<String, dynamic> json, {required String addonId}) {
    final Map<String, dynamic> raw = Map<String, dynamic>.from(json);
    final bool isAtmos = json['isAtmos'] == true ||
        (json['isAtmos']?.toString().toLowerCase() == 'true');
    if (isAtmos && raw['audioModes'] == null) {
      raw['audioModes'] = ['ATMOS'];
    }
    return AddonTrack(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? 'Unknown Title',
      artist: json['artist'] ??
          json['artistName'] ??
          _firstArtistName(json['artists']) ??
          'Unknown Artist',
      album: json['album'] is Map
          ? (json['album']['title'] ?? json['album']['name'])
          : (json['album'] ?? json['albumTitle']),
      duration: json['duration'] is int
          ? json['duration']
          : int.tryParse(json['duration']?.toString() ?? ''),
      artworkURL: json['artworkURL'] ?? json['albumCover'] ?? json['image'] ?? json['cover'],
      isrc: json['isrc'],
      format: json['format'],
      quality: _normQualityStr(json['quality'] ?? json['audioQuality']),
      streamURL: json['streamURL'] ?? json['url'],
      artistId: json['artistId']?.toString() ??
          json['artist_id']?.toString() ??
          _firstArtistId(json['artists']),
      albumId: json['albumId']?.toString() ??
          (json['album'] is Map ? json['album']['id']?.toString() : null),
      popularity: json['popularity'] is int
          ? json['popularity']
          : int.tryParse(json['popularity']?.toString() ?? ''),
      addonId: addonId,
      rawData: raw,
    );
  }

  // Convert to core Track model for seamless integration across the app
  Track toTrack() {
    return Track(
      id: '${addonId}_$id', // Ensure uniqueness across addons
      title: title,
      artist: artist,
      albumTitle: album,
      albumCover: artworkURL,
      duration: duration,
      streamURL: streamURL,
      artistId: artistId,
      albumId: albumId,
      addonId: addonId,
      addonTrackId: id,
      rawData: rawData,
    );
  }
}

/// An album result from any addon
class AddonAlbum {
  final String id;
  final String title;
  final String artist;
  final String? artworkURL;
  final int? trackCount;
  final String? year;
  final String? type; // ALBUM, SINGLE, EP, ...
  final List<String>? audioModes;
  final String? audioQuality; // canonical app form: HI_RES_LOSSLESS/LOSSLESS/...
  final List<AddonTrack>? tracks; // populated from /album/{id}
  final String addonId;

  AddonAlbum({
    required this.id,
    required this.title,
    required this.artist,
    this.artworkURL,
    this.trackCount,
    this.year,
    this.type,
    this.audioModes,
    this.audioQuality,
    this.tracks,
    required this.addonId,
  });

  bool get isAtmos =>
      audioModes?.any((e) => e.toString().contains('ATMOS')) == true;

  factory AddonAlbum.fromJson(Map<String, dynamic> json, {required String addonId}) {
    final isAtmos = json['isAtmos'] == true ||
        (json['isAtmos']?.toString().toLowerCase() == 'true');
    return AddonAlbum(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? 'Unknown Album',
      artist: json['artist'] ?? json['artistName'] ?? 'Unknown Artist',
      artworkURL: json['artworkURL'] ?? json['cover'] ?? json['image'],
      trackCount: json['trackCount'] ?? json['numberOfTracks'],
      year: json['year']?.toString(),
      type: json['type']?.toString(),
      audioModes: mergeAtmos(
          json['audioModes'],
          json['mediaMetadata'] is Map ? json['mediaMetadata']['tags'] : null,
          isAtmos: isAtmos),
      audioQuality: _normQualityStr(json['audioQuality']),
      tracks: (json['tracks'] ?? json['songs'] ?? json['songList']) != null
          ? ((json['tracks'] ?? json['songs'] ?? json['songList']) as List<dynamic>)
              .map((t) => AddonTrack.fromJson(t, addonId: addonId))
              .toList()
          : null,
      addonId: addonId,
    );
  }
}

/// An artist result from any addon
class AddonArtist {
  final String id;
  final String name;
  final String? artworkURL;
  final String? artistMixId;
  final List<String>? genres;
  final String? bio;
  final List<AddonTrack>? topTracks;
  final List<AddonAlbum>? albums;
  final String addonId;

  AddonArtist({
    required this.id,
    required this.name,
    this.artworkURL,
    this.artistMixId,
    this.genres,
    this.bio,
    this.topTracks,
    this.albums,
    required this.addonId,
  });

  factory AddonArtist.fromJson(Map<String, dynamic> json, {required String addonId}) {
    return AddonArtist(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? 'Unknown Artist',
      artworkURL: json['artworkURL'] ?? json['image'],
      artistMixId: json['artistMixId']?.toString(),
      genres: json['genres'] != null
          ? List<String>.from(json['genres'])
          : null,
      bio: json['bio'],
      topTracks: (json['topTracks'] ?? json['tracks'] ?? json['songList']) != null
          ? ((json['topTracks'] ?? json['tracks'] ?? json['songList']) as List<dynamic>)
              .map((t) => AddonTrack.fromJson(t, addonId: addonId))
              .toList()
          : null,
      albums: json['albums'] != null
          ? (json['albums'] as List<dynamic>)
              .map((a) => AddonAlbum.fromJson(a, addonId: addonId))
              .toList()
          : null,
      addonId: addonId,
    );
  }
}

/// A playlist result from any addon
class AddonPlaylist {
  final String id;
  final String title;
  final String? description;
  final String? artworkURL;
  final String? creator;
  final int? trackCount;
  final List<AddonTrack>? tracks; // populated from /playlist/{id}
  final String addonId;

  AddonPlaylist({
    required this.id,
    required this.title,
    this.description,
    this.artworkURL,
    this.creator,
    this.trackCount,
    this.tracks,
    required this.addonId,
  });

  factory AddonPlaylist.fromJson(Map<String, dynamic> json, {required String addonId}) {
    return AddonPlaylist(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? 'Unknown Playlist',
      description: json['description'],
      artworkURL: json['artworkURL'] ?? json['image'],
      creator: json['creator'],
      trackCount: json['trackCount'],
      tracks: json['tracks'] != null
          ? (json['tracks'] as List<dynamic>)
              .map((t) => AddonTrack.fromJson(t, addonId: addonId))
              .toList()
          : null,
      addonId: addonId,
    );
  }
}

/// Unified search results container — all arrays are optional
class AddonSearchResult {
  final List<AddonTrack> tracks;
  final List<AddonAlbum> albums;
  final List<AddonArtist> artists;
  final List<AddonPlaylist> playlists;

  AddonSearchResult({
    this.tracks = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
  });

  bool get isEmpty =>
      tracks.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty;

  factory AddonSearchResult.fromJson(Map<String, dynamic> json,
      {required String addonId}) {
    return AddonSearchResult(
      tracks: (json['tracks'] as List<dynamic>?)
              ?.map((t) => AddonTrack.fromJson(t, addonId: addonId))
              .toList() ??
          [],
      albums: (json['albums'] as List<dynamic>?)
              ?.map((a) => AddonAlbum.fromJson(a, addonId: addonId))
              .toList() ??
          [],
      artists: (json['artists'] as List<dynamic>?)
              ?.map((a) => AddonArtist.fromJson(a, addonId: addonId))
              .toList() ??
          [],
      playlists: (json['playlists'] as List<dynamic>?)
              ?.map((p) => AddonPlaylist.fromJson(p, addonId: addonId))
              .toList() ??
          [],
    );
  }
}

/// A mix result from any addon
class AddonMix {
  final String id;
  final String title;
  final String? subtitle;
  final String? description;
  final String? artworkURL;
  final List<AddonTrack>? tracks;
  final String addonId;

  AddonMix({
    required this.id,
    required this.title,
    this.subtitle,
    this.description,
    this.artworkURL,
    this.tracks,
    required this.addonId,
  });

  factory AddonMix.fromJson(Map<String, dynamic> json, {required String addonId}) {
    return AddonMix(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? 'Mix',
      subtitle: json['subtitle']?.toString() ?? json['subTitle']?.toString(),
      description: json['description']?.toString(),
      artworkURL: json['artworkURL'] ?? json['image'] ?? json['picture'],
      tracks: json['tracks'] != null
          ? (json['tracks'] as List<dynamic>)
              .map((t) => AddonTrack.fromJson(t, addonId: addonId))
              .toList()
          : null,
      addonId: addonId,
    );
  }
}

/// Convert an AddonTrack to a core Track with a stable, prefixed id
/// (used for download keys and offline gating).
Track trackFromAddonTrack(AddonTrack at) {
  final quality = at.quality;
  return Track(
    id: '${at.addonId}_${at.id}',
    title: at.title,
    artist: at.artist,
    albumTitle: at.album,
    albumCover: at.artworkURL,
    duration: at.duration,
    artistId: at.artistId,
    audioQuality: quality == null || quality.isEmpty
        ? null
        : AudioQuality(
            isHiRes: quality.toUpperCase().replaceAll('_', '').contains('HIRES')),
    rawData: at.rawData ??
        (quality == null || quality.isEmpty ? null : {'audioQuality': quality}),
    addonId: at.addonId,
    addonTrackId: at.id,
    streamURL: at.streamURL,
  );
}

/// Health probe result from an addon's status endpoint.
class ApiHealthStatus {
  final bool online;
  final String? error;
  final String? version;
  final int? latencyMs;

  const ApiHealthStatus({
    required this.online,
    this.error,
    this.version,
    this.latencyMs,
  });
}

/// Result from GET /stream/{id}
class AddonStreamResult {
  final String url;
  final String? format;
  final String? quality;
  final int? expiresAt; // Unix timestamp

  AddonStreamResult({
    required this.url,
    this.format,
    this.quality,
    this.expiresAt,
  });

  factory AddonStreamResult.fromJson(Map<String, dynamic> json) {
    return AddonStreamResult(
      url: json['url'] ?? '',
      format: json['format'],
      quality: json['quality'],
      expiresAt: json['expiresAt'] is int ? json['expiresAt'] : null,
    );
  }
}
