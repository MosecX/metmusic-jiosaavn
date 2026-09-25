import 'dart:async';
import 'package:flutter/foundation.dart'; // kIsWeb
import '../utils/platform_helper.dart';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../models/models.dart';
import '../models/addon_models.dart';
import 'download_manager_service.dart';
import 'addon_service.dart';

/// The AudioHandler manages the audio player and the playlist.
/// It exposes the standard AudioService interface to the UI (and system).
/// Uses just_audio Player directly.
///
/// All playback is sourced from JioSaavn: every track in the catalog IS a
/// JioSaavn track, so stream resolution goes straight through the JioSaavn
/// addon handler (no cross-matching/fallback).
class AppAudioHandler extends BaseAudioHandler with SeekHandler {
  late final AudioPlayer _player;
  final DownloadManagerService _downloadManager;
  final AddonService _addonService;

  // Internal Queue State
  List<Track> _internalQueue = [];
  int _currentIndex = -1;
  int _lastRequestId = 0;
  bool _isSwitchingTrack = false;
  bool _isLoadingTrack = false;
  final ValueNotifier<String?> loadingTrackId = ValueNotifier<String?>(null);
  final ValueNotifier<String?> playbackError = ValueNotifier<String?>(null);

  final List<StreamSubscription> _subscriptions = [];

  // Cache of resolved stream results keyed by track id (with a TTL) so that
  // advancing the queue at track end is near-instant instead of re-fetching
  // the stream URL over the network on every switch.
  final Map<String, AddonStreamResult> _streamCache = {};
  final Map<String, int> _streamCacheTs = {};

  AppAudioHandler({
    required DownloadManagerService downloadManager,
    required AddonService addonService,
  })  : _downloadManager = downloadManager,
        _addonService = addonService {
    _init();
  }

  // Expose explicit state for UI polling
  Duration get currentPosition => _player.position;

  bool get isPlayerPlaying => _player.playing;

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
    _player.play();
  }

  @override
  Future<void> pause() async {
    _player.pause();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    return super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
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
    final requestId = ++_lastRequestId;
    _isSwitchingTrack = true;
    _isLoadingTrack = true;
    loadingTrackId.value = track.id;
    playbackError.value = null;
    if (requestId == _lastRequestId) {
      mediaItem.add(_toMediaItem(track));
    }
    _broadcastState();

    try {
      await _player.stop();
    } catch (e) {
      print('[AudioHandler] Stop error (ignored): $e');
    }

    if (requestId != _lastRequestId) return;

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
      // Robust retry loop: guarantee playback by re-fetching a fresh stream
      // URL and retrying setAudioSource on any failure (null URL, expired
      // URL, transient network issue, etc.).
      const int maxAttempts = 5;
      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        if (requestId != _lastRequestId) return;

        try {
          final streamResult = await _resolveStream(track, forceFresh: attempt > 0);
          if (requestId != _lastRequestId) return;

          final url = streamResult?.url;
          if (url == null) throw Exception('No stream URL found');

          if (requestId == _lastRequestId) {
            await _setSourceAndPlay(url, track, requestId, startPosition);
            if (requestId != _lastRequestId) return;
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

      // All attempts failed — surface the error to the UI.
      if (requestId == _lastRequestId) {
        playbackError.value =
            'No se pudo reproducir "${track.title}". Comprueba tu conexión.';
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

  /// Resolve a playable stream result for a track, using a short-TTL cache so
  /// repeated switches (and especially auto-advance at track end) skip the
  /// network round-trip. Pass [forceFresh] to bypass the cache (used on retry
  /// attempts after a cached URL may have expired).
  Future<AddonStreamResult?> _resolveStream(Track track,
      {bool forceFresh = false}) async {
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

    if (_streamCache.containsKey(next.id)) return;
    _resolveStream(next).catchError((_) => null);
  }

  /// Stop (if needed), set the audio source and start playback. Used by the
  /// retry loop so each attempt re-prepares the player cleanly.
  Future<void> _setSourceAndPlay(
      String audioUrl, Track track, int requestId, Duration? startPosition) async {
    if (requestId != _lastRequestId) return;
    print('[AudioHandler] Opening media: $audioUrl');
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

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'dispose') {
      for (final sub in _subscriptions) {
        sub.cancel();
      }
      _subscriptions.clear();
      await _player.dispose();
    }
  }
}
