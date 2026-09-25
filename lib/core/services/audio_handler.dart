import 'dart:async';
import 'package:flutter/foundation.dart'; // kIsWeb
import '../utils/platform_helper.dart';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../models/models.dart';
import '../models/addon_models.dart';
import 'download_manager_service.dart';
import 'addon_service.dart';
import 'settings_service.dart';
import 'jiosaavn_service.dart';
import 'dash_service.dart';
import 'dash_native_parser.dart';
import 'dash_local_proxy_server.dart';

/// The AudioHandler manages the audio player and the playlist.
/// It exposes the standard AudioService interface to the UI (and system).
/// Uses just_audio Player directly.
class AppAudioHandler extends BaseAudioHandler with SeekHandler {
  late final AudioPlayer _player;
  final DownloadManagerService _downloadManager;
  final AddonService _addonService;
  final SettingsService _settings;

  // JioSaavn playback source (set from main.dart after boot).
  late final JioSaavnService _jioSaavn;

  // Internal Queue State
  List<Track> _internalQueue = [];
  int _currentIndex = -1;
  bool _isDashActive = false;
  Timer? _positionTimer;
  int _lastRequestId = 0;
  bool _isSwitchingTrack = false;
  bool _isLoadingTrack = false;
  final ValueNotifier<String?> loadingTrackId = ValueNotifier<String?>(null);
  final ValueNotifier<String?> playbackError = ValueNotifier<String?>(null);

  /// Non-blocking info shown in the player when playback fell back to another
  /// source (e.g. Tidal → JioSaavn). Cleared whenever a new track starts.
  final ValueNotifier<String?> playbackNotice = ValueNotifier<String?>(null);

  final List<StreamSubscription> _subscriptions = [];

  // Cache of resolved stream results keyed by track id (with a TTL) so that
  // advancing the queue at track end is near-instant instead of re-fetching
  // the stream URL over the network on every switch.
  final Map<String, AddonStreamResult> _streamCache = {};
  final Map<String, int> _streamCacheTs = {};

  AppAudioHandler({
    required DownloadManagerService downloadManager,
    required AddonService addonService,
    required SettingsService settings,
  })  : _downloadManager = downloadManager,
        _addonService = addonService,
        _settings = settings {
    _init();
  }

  /// Called from main.dart once the singleton JioSaavnService exists.
  void attachJioSaavn(JioSaavnService service) => _jioSaavn = service;

  bool get _useJioSaavnSource => _settings.isJioSaavnSource;

  // Expose explicit state for UI polling
  Duration get currentPosition {
    if (_isDashActive) return playbackState.value.position;
    return _player.position;
  }

  bool get isPlayerPlaying {
    if (_isDashActive) return playbackState.value.playing;
    return _player.playing;
  }

  Future<void> _init() async {
    _player = AudioPlayer();
    
    if (!kIsWeb) {
      _downloadManager.cleanupTemporaryFiles();
    }

    _setupPlayerListeners();
  }

  void _setupPlayerListeners() {
    // Clear existing subscriptions
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();

    // Subscribe to media_kit streams and push PlaybackState to audio_service
    _subscriptions.addAll([
      _player.playingStream.listen((_) => _broadcastState()),
      _player.positionStream.listen((_) => _broadcastState()),
      _player.bufferedPositionStream.listen((_) => _broadcastState()),
      _player.playerStateStream.listen((state) {
        _broadcastState();
        if (state.processingState == ProcessingState.ready) {
          _isSwitchingTrack = false;
        }
        if (state.processingState == ProcessingState.completed) {
          _handleTrackCompletion();
        }
      }),
      _player.durationStream.listen((_) => _broadcastState()),
    ]);

    if (kIsWeb) {
      _subscriptions.add(_player.playingStream.listen((playing) {
        if (playing) {
          _startPositionPolling();
        } else {
          _stopPositionPolling();
        }
      }));
    }
  }

  /// Broadcasts current player state to audio_service (SMTC / Bluetooth / UI)
  void _broadcastState() {
    final isPlaying = _player.playing;
    final position = _player.position;
    final buffered = _player.bufferedPosition;
    final isBuffering = _player.playerState.processingState == ProcessingState.buffering;
    final isCompleted = _player.playerState.processingState == ProcessingState.completed;

    AudioProcessingState processingState;
    if (_isLoadingTrack) {
      processingState = AudioProcessingState.buffering;
    } else if (isCompleted) {
      processingState = AudioProcessingState.completed;
    } else if (isBuffering) {
      processingState = AudioProcessingState.buffering;
    } else if (_currentIndex < 0) {
      processingState = AudioProcessingState.idle;
    } else {
      processingState = AudioProcessingState.ready;
    }

    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (isPlaying) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: processingState,
      playing: isPlaying,
      updatePosition: position,
      bufferedPosition: buffered,
      speed: _player.speed,
      queueIndex: _currentIndex,
      repeatMode: _mapLoopModeToRepeatMode(_player.loopMode),
      shuffleMode: _player.shuffleModeEnabled
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
    ));
  }

  AudioServiceRepeatMode _mapLoopModeToRepeatMode(LoopMode mode) {
    switch (mode) {
      case LoopMode.off: return AudioServiceRepeatMode.none;
      case LoopMode.one: return AudioServiceRepeatMode.one;
      case LoopMode.all: return AudioServiceRepeatMode.all;
    }
  }

  void _handleTrackCompletion() {
    if (_isSwitchingTrack) return;
    if (_player.loopMode == LoopMode.one) {
      _player.seek(Duration.zero);
      _player.play();
    } else {
      if (_currentIndex < _internalQueue.length - 1) {
        _currentIndex++;
        _playQueueItem(_currentIndex);
      } else {
        if (_player.loopMode == LoopMode.all) {
          _currentIndex = 0;
          _playQueueItem(0);
        } else {
          stop();
          _player.seek(Duration.zero);
        }
      }
    }
  }

  // ========== ACTIONS ==========

  @override
  Future<void> play() async {
    if (_isDashActive && kIsWeb) {
      DashService.resume();
      playbackState.add(playbackState.value.copyWith(playing: true, speed: 1.0));
      return;
    }
    _player.play();
  }

  @override
  Future<void> pause() async {
    if (_isDashActive && kIsWeb) {
      DashService.pause();
      playbackState.add(playbackState.value.copyWith(playing: false, speed: 0.0));
      return;
    }
    _player.pause();
  }

  @override
  Future<void> stop() async {
    if (kIsWeb) {
      DashService.stop();
      _isDashActive = false;
      _stopPositionPolling();
    }
    if (!kIsWeb && (PlatformHelper.isWindows || PlatformHelper.isLinux)) {
      DashLocalProxyServer.stop();
    }
    await _player.stop();
    _stopPositionPolling();
    return super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_isDashActive && kIsWeb) {
      DashService.seek(position.inSeconds.toDouble());
      playbackState.add(playbackState.value.copyWith(updatePosition: position));
      return;
    }
    return _player.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    if (_internalQueue.isEmpty) return;
    int nextIndex = _currentIndex + 1;
    if (_player.loopMode == LoopMode.all && nextIndex >= _internalQueue.length) {
      nextIndex = 0;
    }
    if (nextIndex < _internalQueue.length) await _playQueueItem(nextIndex);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_internalQueue.isEmpty) return;
    if (_player.position.inSeconds > 3) {
      _player.seek(Duration.zero);
      return;
    }
    int prevIndex = _currentIndex - 1;
    if (_player.loopMode == LoopMode.all && prevIndex < 0) {
      prevIndex = _internalQueue.length - 1;
    }
    if (prevIndex >= 0) await _playQueueItem(prevIndex);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        await _player.setLoopMode(LoopMode.off);
        break;
      case AudioServiceRepeatMode.one:
        await _player.setLoopMode(LoopMode.one);
        break;
      case AudioServiceRepeatMode.all:
        await _player.setLoopMode(LoopMode.all);
        break;
      default:
        await _player.setLoopMode(LoopMode.off);
    }
    _broadcastState();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode == AudioServiceShuffleMode.all;
    await _player.setShuffleModeEnabled(enabled);
    _broadcastState();
  }

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {}

  Future<void> setRequestQueue(List<Track> tracks, {int pendingIndex = 0}) async {
    _internalQueue = List.from(tracks);
    _currentIndex = pendingIndex;
    final items = tracks.map((t) => _toMediaItem(t)).toList();
    queue.add(items);
    if (_internalQueue.isNotEmpty && _currentIndex >= 0 && _currentIndex < _internalQueue.length) {
      await _playQueueItem(_currentIndex);
    }
  }

  Future<void> _playQueueItem(int index, {Duration? startPosition}) async {
    if (index < 0 || index >= _internalQueue.length) return;

    _currentIndex = index;
    final track = _internalQueue[index];
    final bool isAtmos = track.isAtmos;
    final bool wasDash = _isDashActive;
    final requestId = ++_lastRequestId;
    _isSwitchingTrack = true;
    _isLoadingTrack = true;
    loadingTrackId.value = track.id;
    playbackError.value = null;
    playbackNotice.value = null;
    if (requestId == _lastRequestId) {
      mediaItem.add(_toMediaItem(track));
    }
    _broadcastState();

    // "Idle Reset" pattern for DASH thread safety:
    // Instead of disposing/recreating the player (which leaves zombie threads in
    // ntdll.dll), we stop + set idle + wait for the OS to reap the DASH demuxer
    // worker threads before handing it a new source.
    if (kIsWeb) {
      DashService.stop();
    }
    try {
      await _player.stop();
      // Crucial 500ms delay: allows ntdll.dll to fully reap the DASH segment-
      // fetching threads and release WASAPI handles + file cache locks.
      // Without this, the second stream writes to memory the OS still considers
      // owned by the dying first stream's workers. Only needed when the
      // previous track was DASH (direct->direct / direct->dash don't need it).
      if (!kIsWeb && wasDash) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } catch (e) {
      print('[AudioHandler] Stop error (ignored): $e');
    }

    if (requestId != _lastRequestId) return;
    _isDashActive = false;

    try {
      final isDownloaded = _downloadManager.isDownloaded(track.id);
      final localPath = _downloadManager.getLocalPath(track.id);
      final bool useLocal = !kIsWeb && isDownloaded && localPath != null && PlatformHelper.fileExists(localPath);

      if (useLocal) {
        final audioUrl = Uri.file(localPath).toString();
        print('[AudioHandler] Playing local file: $audioUrl');
        if (requestId == _lastRequestId) {
          await _setSourceAndPlay(audioUrl, track, requestId, startPosition);
        }
        _preloadNext();
        return;
      }

      // ── JioSaavn playback source ──
      // When selected in settings, playback is resolved through JioSaavn:
      // the Tidal track's title/artist is searched on JioSaavn and the same
      // recording is streamed from its permanent AAC/MP4 CDN URL.
      if (_useJioSaavnSource) {
        await _playViaJioSaavn(track, requestId, startPosition);
        return;
      }

      // Robust retry loop: guarantee playback by re-fetching a fresh stream
      // URL and retrying setAudioSource on any failure (null URL, expired
      // token, DASH parse error, transient network issue, etc.).
      const int maxAttempts = 5;
      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        if (requestId != _lastRequestId) return;

        String? audioUrl;
        try {
          final streamResult = await _resolveStream(
            track, forceFresh: attempt > 0, atmos: isAtmos && attempt == 0);
          if (requestId != _lastRequestId) return;

          final url = streamResult?.url;
          final format = streamResult?.format?.toLowerCase();
          if (url == null) throw Exception('No stream URL found');

          final bool isDash =
              (format == 'dash' || url.contains('<MPD') || url.contains('.mpd'));

          if (isDash) {
            const String proxy =
                'https://webdownloadproxy.thevolecitor.workers.dev/?url=';
            if (kIsWeb) {
              final manifestUri = await DashService.getManifestUri(url,
                  proxy: proxy, trackId: track.id);
              DashService.init(manifestUri, proxy);
              _isDashActive = true;
              _startPositionPolling();

              final item = _toMediaItem(track);
              mediaItem.add(item);
              playbackState.add(playbackState.value.copyWith(
                playing: true,
                speed: 1.0,
                processingState: AudioProcessingState.ready,
                controls: [
                  MediaControl.skipToPrevious,
                  MediaControl.pause,
                  MediaControl.skipToNext
                ],
              ));
              if (requestId != _lastRequestId) return;
              final genuine = await _isGenuinePlayback(track);
              if (requestId != _lastRequestId) return;
              if (genuine) {
                _preloadNext();
                return;
              }
              print('[AudioHandler] Tidal devolvió solo un preview de '
                  '"${track.title}" — cambiando a JioSaavn.');
              playbackNotice.value =
                  'Tidal solo ofreció un preview — reproduciendo desde JioSaavn.';
              break;
            } else {
              // All native platforms (Android, Windows, Linux) serve DASH
              // through a local proxy that concatenates the init + media
              // segments into a single playable HTTP stream.
              DashLocalProxyServer.stop();
              final DashManifest manifest;
              if (url.startsWith('file://')) {
                final mpdXml =
                    await PlatformHelper.readFile(Uri.parse(url).toFilePath());
                if (mpdXml == null || mpdXml.isEmpty) {
                  throw Exception('Could not read local DASH manifest');
                }
                manifest = DashNativeParser.parseContent(mpdXml);
              } else {
                manifest = await DashNativeParser.parse(url);
              }
              audioUrl = await DashLocalProxyServer.start(
                manifest,
                proxyUrl: null, // As requested, do NOT use the Cloudflare worker
                getPosition: () => _player.position.inSeconds.toDouble(),
              );
            }
          } else {
            if (kIsWeb) DashService.stop();
            audioUrl = url;
          }

          if (requestId == _lastRequestId) {
            await _setSourceAndPlay(audioUrl, track, requestId, startPosition);
            if (requestId != _lastRequestId) return;
            final genuine = await _isGenuinePlayback(track);
            if (requestId != _lastRequestId) return;
            if (!genuine) {
              print('[AudioHandler] Tidal solo devuelve un preview de '
                  '"${track.title}" — cambiando a JioSaavn.');
              playbackNotice.value =
                  'Tidal solo ofreció un preview — reproduciendo desde JioSaavn.';
              break;
            }
            _preloadNext();
            return; // success
          }
        } catch (e) {
          print('[AudioHandler] Playback attempt ${attempt + 1}/$maxAttempts failed: $e');
        }

        // Backoff before retrying (unless a newer request superseded us).
        if (requestId == _lastRequestId && attempt < maxAttempts - 1) {
          await Future.delayed(const Duration(milliseconds: 700));
        }
      }

      // All Tidal attempts failed or only returned previews — fall back to
      // JioSaavn so playback still happens if the recording exists there.
      if (requestId == _lastRequestId) {
        print('[AudioHandler] Tidal no cargó "${track.title}" — '
            'probando JioSaavn.');
        playbackNotice.value =
            'Tidal no pudo cargar — reproduciendo desde JioSaavn.';
        await _playViaJioSaavn(track, requestId, startPosition);
      }
    } catch (e, st) {
      print('[AudioHandler] CRITICAL PLAYBACK ERROR: $e');
      print(st);
    } finally {
      if (requestId == _lastRequestId) {
        _isLoadingTrack = false;
        loadingTrackId.value = null;
        _broadcastState();
      }
      print('[AudioHandler] --- Playback Init Complete [ID: $requestId] ---');
    }
  }

  /// Playback through JioSaavn.
  ///
  /// 1. Searches JioSaavn by "artist title" (falling back to "title" and
  ///    "title artist") and keeps the candidate only when title/artist/
  ///    duration corroborate it.
  /// 2. Resolves the permanent CDN URL (bitrate upgraded up to 320).
  /// 3. Falls back silently to the Tidal stream when JioSaavn cannot provide
  ///    the recording, so playback never breaks.
  Future<void> _playViaJioSaavn(
      Track track, int requestId, Duration? startPosition) async {
    // 1. Match + 2. resolve (bounded retry ladder).
    const int maxAttempts = 3;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      if (requestId != _lastRequestId) return;
      try {
        final match = await _jioSaavn.findMatch(
          title: track.title,
          artist: track.artist,
          album: track.albumTitle,
          durationSeconds: track.duration,
          useCache: attempt == 0,
        );
        if (requestId != _lastRequestId) return;

        if (match == null) {
          print('[AudioHandler/JioSaavn] No match for "${track.title}"');
          break;
        }

        final stream = await _jioSaavn.resolveStream(
          match.song,
          forceFresh: attempt > 0,
        );
        if (requestId != _lastRequestId) return;

        if (stream != null) {
          print('[AudioHandler/JioSaavn] Playing "${track.title}" via '
              'JioSaavn (${match.method}, ${stream.mimeType}, '
              '${stream.bitrate}bps)');
          await _setSourceAndPlay(stream.url, track, requestId, startPosition);
          _preloadNext();
          return;
        }
      } catch (e) {
        print('[AudioHandler/JioSaavn] attempt ${attempt + 1}/$maxAttempts '
            'failed: $e');
      }
      if (attempt < maxAttempts - 1 && requestId == _lastRequestId) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    // 3. Graceful fallback — stream the Tidal source so playback continues.
    print('[AudioHandler/JioSaavn] Falling back to Tidal stream for ${track.id}');
    try {
      final streamResult = await _resolveStream(track, forceFresh: true);
      final url = streamResult?.url;
      if (url != null && requestId == _lastRequestId) {
        playbackNotice.value =
            'JioSaavn no encontró la canción — reproduciendo desde Tidal.';
        await _setSourceAndPlay(url, track, requestId, startPosition);
        if (requestId == _lastRequestId && await _isGenuinePlayback(track)) {
          _preloadNext();
          return;
        }
        print('[AudioHandler/JioSaavn] Fallback Tidal solo era un preview — '
            'descartado.');
      }
    } catch (e) {
      print('[AudioHandler/JioSaavn] Tidal fallback failed too: $e');
    }

    if (requestId == _lastRequestId) {
      playbackError.value =
          'No se pudo reproducir "${track.title}".';
    }
  }

  /// Normalizes `Track.duration` to whole seconds (some sources report ms).
  static int? _trackDurationSeconds(Track track) {
    final d = track.duration;
    if (d == null || d <= 0) return null;
    return d > 10000 ? d ~/ 1000 : d;
  }

  /// A Tidal preview is a ~30s clipped track while the real song is (almost
  /// always) longer. Returns true when the loaded audio is clearly shorter
  /// than the catalog duration.
  bool _isPreviewPlayback(Track track, Duration? loaded) {
    final expected = _trackDurationSeconds(track);
    if (loaded == null || expected == null || expected <= 0) return false;
    return loaded.inSeconds < expected - 15;
  }

  /// Waits until the player knows the current duration and reports whether
  /// the loaded Tidal source is a genuine full-length track. If the duration
  /// can't be determined we consider it genuine (can't prove otherwise).
  Future<bool> _isGenuinePlayback(Track track) async {
    Duration? loaded = _player.duration;
    try {
      if (loaded == null) {
        if (_isDashActive && kIsWeb) {
          for (var i = 0; i < 40; i++) {
            final s = DashService.getDuration();
            if (s > 0) {
              loaded = Duration(seconds: s.toInt());
              break;
            }
            await Future.delayed(const Duration(milliseconds: 250));
          }
        } else {
          loaded = await _player.durationStream
              .firstWhere((d) => d != null)
              .timeout(const Duration(seconds: 8));
        }
      }
    } catch (_) {
      // Timeout / no duration yet — leave loaded as null.
    }
    return !_isPreviewPlayback(track, loaded);
  }

  /// Resolve a playable stream result for a track, using a short-TTL cache so
  /// repeated switches (and especially auto-advance at track end) skip the
  /// network round-trip. Pass [forceFresh] to bypass the cache (used on retry
  /// attempts after a cached URL may have expired).
  Future<AddonStreamResult?> _resolveStream(Track track,
      {bool forceFresh = false, bool atmos = false}) async {
    final key = track.id;
    if (!forceFresh && _streamCache.containsKey(key)) {
      final ts = _streamCacheTs[key]!;
      if (DateTime.now().millisecondsSinceEpoch - ts < 5 * 60 * 1000) {
        return _streamCache[key];
      }
      _streamCache.remove(key);
      _streamCacheTs.remove(key);
    }
    final result = await _addonService.getStreamResult(
      track.addonTrackId ?? track.id,
      addonId: track.addonId,
      atmos: atmos,
    );
    if (result != null) {
      _streamCache[key] = result;
      _streamCacheTs[key] = DateTime.now().millisecondsSinceEpoch;
    }
    return result;
  }

  /// Pre-resolve the next queue item's stream in the background so that when
  /// the current track ends, advancement is near-instant.
  void _preloadNext() {
    if (_currentIndex < 0 || _internalQueue.isEmpty) return;
    final nextIdx = _currentIndex + 1;
    if (nextIdx >= _internalQueue.length) return;
    final next = _internalQueue[nextIdx];

    if (_useJioSaavnSource) {
      // Prefetch the JioSaavn match + stream for the next track.
      () async {
        try {
          final match = await _jioSaavn.findMatch(
            title: next.title,
            artist: next.artist,
            album: next.albumTitle,
            durationSeconds: next.duration,
          );
          if (match != null) {
            await _jioSaavn.resolveStream(match.song);
          }
        } catch (_) {}
      }();
      return;
    }

    if (_streamCache.containsKey(next.id)) return;
    _resolveStream(next).catchError((_) => null);
  }

  /// Stop (if needed), set the audio source and start playback. Used by the
  /// retry loop so each attempt re-prepares the player cleanly.
  Future<void> _setSourceAndPlay(
      String audioUrl, Track track, int requestId, Duration? startPosition) async {
    if (requestId != _lastRequestId) return;
    print('[AudioHandler] Opening media: $audioUrl');
    if (kIsWeb && _isDashActive) {
      // Leaving a web DASH source for a progressive one — release the DASH
      // element so it doesn't keep overriding the player.
      DashService.stop();
      _isDashActive = false;
    }
    try {
      await _player.stop();
    } catch (_) {}
    if (requestId != _lastRequestId) return;

    final item = _toMediaItem(track);
    final source = AudioSource.uri(
      Uri.parse(audioUrl),
      headers: {'User-Agent': 'MetMusic/1.0 (Flutter)'},
      tag: item,
    );

    await _player.setAudioSource(source, initialPosition: startPosition);
    if (requestId != _lastRequestId) return;
    mediaItem.add(item);
    _player.play();
  }

  MediaItem _toMediaItem(Track track) {
    Uri? artUri;

    // ON WINDOWS: The SMTC WinRT bridge throws a C++ exception
    // (0x80070057: 'null is not a valid absolute URI') if artUri is null.
    // Always provide a valid HTTPS URI on Windows/Desktop.
    const winPlaceholderArt =
        'https://raw.githubusercontent.com/google/material-design-icons/master/png/av/music_note/materialiconsoutlined/48dp/2x/outline_music_note_black_48dp.png';

    if (!kIsWeb && !PlatformHelper.isAndroid) {
      if (track.albumCover != null &&
          track.albumCover!.isNotEmpty &&
          track.albumCover!.startsWith('http')) {
        artUri = Uri.parse(track.albumCover!);
      } else {
        artUri = Uri.parse(winPlaceholderArt);
      }
    } else {
      if (track.albumCover != null && track.albumCover!.isNotEmpty) {
        artUri = track.albumCover!.startsWith('http')
            ? Uri.parse(track.albumCover!)
            : Uri.file(track.albumCover!);
      }
    }

    return MediaItem(
      id: track.id,
      album: track.albumTitle ?? '',
      title: track.title,
      artist: track.artist,
      duration: track.duration != null
          ? (track.duration! > 10000
              ? Duration(milliseconds: track.duration!)
              : Duration(seconds: track.duration!))
          : null,
      artUri: artUri,
      extras: {'track': track.toJson()},
    );
  }

  void _shuffleQueue() {
    if (_internalQueue.isEmpty) return;
    final currentTrack = _currentIndex >= 0 ? _internalQueue[_currentIndex] : null;
    _internalQueue.shuffle();
    if (currentTrack != null) {
      _internalQueue.removeWhere((t) => t.id == currentTrack.id);
      _internalQueue.insert(0, currentTrack);
      _currentIndex = 0;
    }
    queue.add(_internalQueue.map(_toMediaItem).toList());
  }

  void _unshuffleQueue() {
    // No-op — we don't store the original order
  }

  /// Volume: callers pass 0.0–1.0
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume.clamp(0.0, 1.0));
  }

  @override
  Future<void> skipToQueueItem(int index) async => await _playQueueItem(index);

  Future<void> removeFromQueue(int index) async {
    if (index >= 0 && index < _internalQueue.length) {
      bool isCurrent = index == _currentIndex;
      _internalQueue.removeAt(index);
      queue.add(_internalQueue.map(_toMediaItem).toList());
      if (index < _currentIndex) _currentIndex--;
      if (isCurrent) {
        if (_internalQueue.isEmpty) {
          stop();
        } else {
          if (_currentIndex >= _internalQueue.length) _currentIndex = 0;
          _playQueueItem(_currentIndex);
        }
      }
    }
  }

  Future<void> insertNext(Track track) async {
    if (_internalQueue.isEmpty) {
      await setRequestQueue([track]);
      return;
    }
    _internalQueue.insert(_currentIndex + 1, track);
    queue.add(_internalQueue.map(_toMediaItem).toList());
  }

  Future<void> addTrackToQueue(Track track) async {
    if (_internalQueue.isEmpty) {
      await setRequestQueue([track]);
      return;
    }
    _internalQueue.add(track);
    queue.add(_internalQueue.map(_toMediaItem).toList());
  }

  @override
  Future<void> onTaskRemoved() async => await stop();

  void _startPositionPolling() {
    if (!kIsWeb) return;
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_isDashActive) {
        final pos = DashService.getPosition();
        final dur = DashService.getDuration();
        playbackState.add(playbackState.value.copyWith(
          updatePosition: Duration(seconds: pos.toInt()),
          speed: 1.0,
          bufferedPosition: Duration(seconds: pos.toInt() + 10),
        ));
        if (dur > 0 && pos >= dur - 0.5) {
          timer.cancel();
          skipToNext();
        }
      } else {
        _broadcastState();
      }
    });
  }

  void _stopPositionPolling() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'dispose') {
      for (final sub in _subscriptions) {
        sub.cancel();
      }
      _subscriptions.clear();
      await _player.dispose();
      DashLocalProxyServer.stop();
    }
  }
}
