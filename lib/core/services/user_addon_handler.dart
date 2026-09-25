import 'package:flutter/widgets.dart';
import '../models/addon_models.dart';
import '../models/models.dart';



/// Abstract base class for user-based addons.
///
/// User-based addons run on the device and implement this interface.
/// The built-in DAB addon is the primary example. Third-party user addons
/// would also implement this class and be registered at startup.
///
/// Server-based addons do NOT implement this — they are driven by HTTP
/// calls inside AddonService directly (Eclipse spec).
abstract class UserAddonHandler {
  /// Search for tracks/albums/artists/playlists.
  /// Returns null if the addon cannot perform search or an error occurred.
  Future<AddonSearchResult?> search(String query);

  /// Resolve a playable stream URL for the given track ID.
  /// Returns null if resolution fails.
  Future<AddonStreamResult?> getStreamResult(String trackId);

  /// Fetch full album detail (tracks list). Returns null if not supported.
  Future<AddonAlbum?> getAlbumDetail(String albumId) async => null;

  /// Fetch full artist detail (topTracks + albums). Returns null if not supported.
  Future<AddonArtist?> getArtistDetail(String artistId) async => null;

  /// Fetch full playlist detail (tracks list). Returns null if not supported.
  Future<AddonPlaylist?> getPlaylistDetail(String playlistId) async => null;

  /// Fetch recommended tracks based on a seed track id. Empty list if unsupported.
  Future<List<AddonTrack>> getRecommendations(String seedTrackId, {int limit = 24}) async => [];

  /// Search only albums. Empty list if unsupported.
  Future<List<AddonAlbum>> searchAlbums(String query, {int limit = 10}) async => [];

  /// Probe API health. Returns null when the endpoint doesn't report status.
  Future<ApiHealthStatus?> checkHealth() async => null;

  /// Resolve the negotiated playback quality for a track (e.g. LOSSLESS vs
  /// HI_RES_LOSSLESS). Returns null if the addon cannot probe quality.
  Future<String?> getStreamInfo(String trackId) async => null;

  /// Fetch the native catalog audio quality for a track (e.g. HI_RES_LOSSLESS).
  /// Returns null if the addon cannot resolve it.
  Future<String?> getTrackAudioQuality(String trackId) async => null;

  /// Fetch synced/unsynced lyrics in LRC format.
  /// Return null if the addon does not support lyrics.
  Future<String?> getLyrics(String artist, String title,
      {String? album, int? duration}) async =>
      null;


  // ========== LIBRARY METHODS ==========

  /// Fetch all remote libraries/collections for this user.
  Future<List<MusicLibrary>> getLibraries() async => [];

  /// Fetch tracks for a specific remote library.
  Future<List<Track>> getLibraryTracks(String libraryId, {int? limit}) async => [];

  /// Create a new remote library.
  Future<bool> createLibrary(String name) async => false;

  /// Update an existing remote library's name.
  Future<bool> updateLibrary(String libraryId, {required String name}) async => false;

  /// Delete a remote library.
  Future<bool> deleteLibrary(String libraryId) async => false;

  /// Add tracks to a remote library.
  Future<bool> addTracksToLibrary(String libraryId, List<Track> tracks) async => false;

  /// Add a track to a remote library.
  Future<bool> addTrackToLibrary(String libraryId, Track track) async => false;

  /// Remove a track from a remote library.
  Future<bool> removeTrackFromLibrary(String libraryId, String trackId) async => false;

  /// Optional: build a widget that is displayed inside the addon's card
  /// on the Addons screen. Use this for addon-specific UI like login forms,
  /// account info, or library management buttons.
  ///
  /// Return null to show no extra UI.
  Widget? buildAddonPageWidget(BuildContext context) => null;

  /// The manifest for this addon — used to register it in AddonService.
  AddonManifest get manifest;
}
