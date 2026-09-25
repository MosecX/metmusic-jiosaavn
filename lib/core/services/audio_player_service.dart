import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'dart:async';

import '../models/models.dart';
import 'addon_service.dart';
import 'account_service.dart';
import 'audio_handler.dart';
import 'history_service.dart';
import 'connectivity_service.dart';
import 'download_manager_service.dart';

import 'discord_rpc_service.dart';
class AudioPlayerService with ChangeNotifier {
  final AppAudioHandler _handler;
  final AddonService _addonService;

  // Local state mirrored from Handler
  Track? _currentTrack;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  Duration _bufferedPosition = Duration.zero; // Added
  double _volume = 0.8;

  List<Track> _queue = [];
  int _currentIndex = -1;

  // Custom LoopMode mirroring AudioService RepeatMode
  LoopMode _loopMode = LoopMode.off;
  bool _shuffleEnabled = false;

  // Lyrics
  List<LyricLine> _lyrics = [];
  int _currentLyricIndex = -1;
  bool _isFetchingLyrics = false;

  // Track loading state (set while a track is being prepared/buffered)
  bool _isLoadingTrack = false;
  String? _loadingTrackId;
  String? _lastPlaybackError;

  // Getters
  List<Track> get queue => _queue;
  List<Track> get internalQueue => _queue;
  Track? get currentTrack => _currentTrack;
  bool get isPlaying => _isPlaying;
  Duration get duration => _duration;
  Duration get position => _position;
  Duration get bufferedPosition => _bufferedPosition; // Added
  // Note: AudioHandler doesn't expose volume in state usually,
  // but we can manage it somewhat or just assume system volume + local override?
  // We'll trust the stored _volume and re-apply if needed, but JustAudio handles it.
  double get volume => _volume;
  int get currentIndex => _currentIndex;
  bool get shuffleEnabled => _shuffleEnabled;
  LoopMode get loopMode => _loopMode;
  List<LyricLine> get lyrics => _lyrics;
  int get currentLyricIndex => _currentLyricIndex;
  bool get isFetchingLyrics => _isFetchingLyrics;
  bool get isLoadingTrack => _isLoadingTrack;
  String? get loadingTrackId => _loadingTrackId;
  String? get lastPlaybackError => _lastPlaybackError;

  void clearLastPlaybackError() {
    _lastPlaybackError = null;
    notifyListeners();
  }


  int get sliderValue {
    if (_duration.inMilliseconds > 0) {
      final val = (_position.inMilliseconds * 1000 ~/ _duration.inMilliseconds);
      return val > 1000 ? 1000 : (val < 0 ? 0 : val);
    }
    return 0;
  }

  // Added buffered value for UI
  int get bufferedSliderValue {
    if (_duration.inMilliseconds > 0) {
      final val =
          (_bufferedPosition.inMilliseconds * 1000 ~/ _duration.inMilliseconds);
      return val > 1000 ? 1000 : (val < 0 ? 0 : val);
    }
    return 0;
  }

  final HistoryService _historyService;
  final AccountService _accountService;
  final ConnectivityService _connectivityService;
  final DownloadManagerService _downloadManager;
  final DiscordRpcService _discordRpcService; // Discord

  /// Invoked when playback is blocked because the account is not approved.
  /// UI registers this to show the auth screen.
  Future<void> Function()? onPlaybackBlocked;

  /// Invoked when playback is blocked because we're offline and the track
  /// is not downloaded. UI registers this to show a notice.
  Future<void> Function()? onOfflineBlocked;

  AudioPlayerService({
    required AppAudioHandler handler,
    required AddonService addonService,
    required HistoryService historyService,
    required AccountService accountService,
    required ConnectivityService connectivityService,
    required DownloadManagerService downloadManager,
    required DiscordRpcService discordRpcService,
  })  : _handler = handler,
        _addonService = addonService,
        _historyService = historyService,
        _accountService = accountService,
        _connectivityService = connectivityService,
        _downloadManager = downloadManager,
        _discordRpcService = discordRpcService {
    _init();
  }

  void _init() {
    // Listen to Playback State
    _handler.playbackState.listen((state) {
      _position = state.position;
      _bufferedPosition = state.bufferedPosition; // Added
      _updateCurrentLyric(); // Keep lyrics in sync with position

      switch (state.repeatMode) {
        case AudioServiceRepeatMode.none:
          _loopMode = LoopMode.off;
          break;
        case AudioServiceRepeatMode.one:
          _loopMode = LoopMode.one;
          break;
        case AudioServiceRepeatMode.all:
          _loopMode = LoopMode.all;
          break;
        default:
          _loopMode = LoopMode.off;
      }

      _shuffleEnabled = (state.shuffleMode == AudioServiceShuffleMode.all);

      if (state.queueIndex != null) {
        _currentIndex = state.queueIndex!;
      }

      if (_isPlaying != state.playing) {
        _isPlaying = state.playing;
        _updateDiscordPresence(debounced: true); // Update Discord on Play/Pause
      }

      notifyListeners();
    });

    // Listen to MediaItem (Current Track)
    _handler.mediaItem.listen((item) {
      if (item != null) {
        if (item.extras != null && item.extras!.containsKey('track')) {
          _currentTrack =
              Track.fromJson(Map<String, dynamic>.from(item.extras!['track']));
        } else {
          _currentTrack = Track(
              id: item.id,
              title: item.title,
              artist: item.artist ?? 'Unknown',
              albumCover: item.artUri?.toString(),
              duration: item.duration?.inSeconds);
        }
        _duration = item.duration ?? Duration.zero;

        // New Track Logic
        if (_currentTrack != null) {
          _fetchLyrics(_currentTrack!);
          _historyService.addPlayed(_currentTrack!);
          _updateDiscordPresence(debounced: true);
        }
        notifyListeners();
      }
    });

    // Track loading state (spinner while a track is being prepared)
    _loadingTrackId = _handler.loadingTrackId.value;
    _isLoadingTrack = _loadingTrackId != null;
    _handler.loadingTrackId.addListener(() {
      _loadingTrackId = _handler.loadingTrackId.value;
      _isLoadingTrack = _loadingTrackId != null;
      notifyListeners();
    });

    _handler.playbackError.addListener(() {
      final msg = _handler.playbackError.value;
      if (msg != null) {
        _lastPlaybackError = msg;
        notifyListeners();
      }
    });

    // Listen to Queue
    _handler.queue.listen((items) {
      _queue = items.map((item) {
        if (item.extras != null && item.extras!.containsKey('track')) {
          return Track.fromJson(
              Map<String, dynamic>.from(item.extras!['track']));
        }
        return Track(
            id: item.id, title: item.title, artist: item.artist ?? 'Unknown');
      }).toList();
      notifyListeners();
    });

    // Throttle position updates to 200ms to reduce bridge pressure on Windows
    DateTime lastNotify = DateTime.now();
    AudioService.position.listen((pos) {
      _position = pos;
      _updateCurrentLyric();

      if (DateTime.now().difference(lastNotify).inMilliseconds > 200) {
        lastNotify = DateTime.now();
        notifyListeners();
      }
    });

    // Optimization: Listen to shuffle/repeat changes directly or via streams.

    // Update Discord on track changes, state changes, or seeks.
  }

  // Logic refactored into stream listeners for performance.

  void _stopTicker() {
    // Ticker removed
  }

  // Controls

  Future<bool> _ensurePlayAccess() async {
    if (_accountService.isApproved) return true;
    if (onPlaybackBlocked != null) {
      await onPlaybackBlocked!();
    }
    return false;
  }

  bool _trackPlayable(Track track) {
    if (_connectivityService.isOnline) return true;
    return _downloadManager.isDownloaded(track.id) &&
        _downloadManager.getLocalPath(track.id) != null;
  }

  Future<bool> _ensureOfflineTrack(Track track) async {
    if (_trackPlayable(track)) return true;
    if (onOfflineBlocked != null) await onOfflineBlocked!();
    return false;
  }

  Track? _queueTrackAt(int index) {
    if (_queue.isEmpty) return null;
    if (index < 0 || index >= _queue.length) return null;
    return _queue[index];
  }

  Future<void> playTrack(Track track) async {
    if (!await _ensurePlayAccess()) return;
    if (!await _ensureOfflineTrack(track)) return;
    await _handler.setRequestQueue([track]);
  }

  Future<void> playFromQueue(int index) async {
    // We can invoke custom action or skip
    await _handler.skipToQueueItem(index);
  }

  Future<void> playAll(List<Track> tracks, {int startIndex = 0}) async {
    if (!await _ensurePlayAccess()) return;
    var queue = tracks;
    if (!_connectivityService.isOnline) {
      queue = queue.where(_trackPlayable).toList();
      if (queue.isEmpty) {
        if (onOfflineBlocked != null) await onOfflineBlocked!();
        return;
      }
    }
    await _handler.setRequestQueue(queue, pendingIndex: startIndex);
  }

  Future<void> addToQueue(Track track) async {
    if (!await _ensureOfflineTrack(track)) return;
    await _handler.addTrackToQueue(track);
  }

  // ... (Other queue methods similarly simplified or proxied)
  void clearQueue() {
    _handler.stop();
    _handler.setRequestQueue([]);
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await _handler.pause();
    } else {
      await _handler.play();
    }
  }

  Future<void> pause() => _handler.pause();
  Future<void> resume() => _handler.play();
  Future<void> stop() => _handler.stop();

  Future<void> seekToSlider(int value) async {
    if (_duration.inMilliseconds > 0) {
      final position = Duration(
          milliseconds: (value / 1000 * _duration.inMilliseconds).round());
      await _handler.seek(position);
      _updateDiscordPresence();
    }
  }

  Future<void> seekTo(Duration position) async {
    await _handler.seek(position);
    _updateDiscordPresence();
  }

  Future<void> nextTrack() async {
    if (_connectivityService.isOnline) {
      await _handler.skipToNext();
      return;
    }
    var idx = _currentIndex + 1;
    if (_loopMode == LoopMode.all && idx >= _queue.length) idx = 0;
    final next = _queueTrackAt(idx);
    if (next == null) return;
    if (!_trackPlayable(next)) {
      if (onOfflineBlocked != null) await onOfflineBlocked!();
      return;
    }
    await _handler.skipToNext();
  }

  Future<void> previousTrack() async {
    if (_connectivityService.isOnline) {
      await _handler.skipToPrevious();
      return;
    }
    if (_position.inSeconds > 3) {
      await seekTo(Duration.zero);
      return;
    }
    var idx = _currentIndex - 1;
    if (_loopMode == LoopMode.all && idx < 0) idx = _queue.length - 1;
    final prev = _queueTrackAt(idx);
    if (prev == null) return;
    if (!_trackPlayable(prev)) {
      if (onOfflineBlocked != null) await onOfflineBlocked!();
      return;
    }
    await _handler.skipToPrevious();
  }

  Future<void> toggleShuffle() async {
    final newMode = _shuffleEnabled
        ? AudioServiceShuffleMode.none
        : AudioServiceShuffleMode.all;
    await _handler.setShuffleMode(newMode);
  }

  Future<void> setVolume(double volume) async {
    _volume = volume;
    await _handler.setVolume(volume);
    notifyListeners();
  }

  Future<void> playSingleTrack(Track track) async {
    await playTrack(track);
  }

  Future<void> playNext(Track track) async {
    if (!await _ensureOfflineTrack(track)) return;
    await _handler.insertNext(track);
  }

  Future<void> removeFromQueue(int index) async {
    await _handler.removeFromQueue(index);
  }

  // Previous methods...
  Future<void> toggleLoop() async {
    var newMode = AudioServiceRepeatMode.none;
    switch (_loopMode) {
      case LoopMode.off:
        newMode = AudioServiceRepeatMode.all;
        break; // Toggle sequence: Off -> All -> One
      case LoopMode.all:
        newMode = AudioServiceRepeatMode.one;
        break;
      case LoopMode.one:
        newMode = AudioServiceRepeatMode.none;
        break;
    }
    await _handler.setRepeatMode(newMode);
  }

  // Lyrics Logic (Kept here as it's UI/API specific, not core player)
  Future<void> _fetchLyrics(Track track) async {
    _isFetchingLyrics = true;
    _lyrics = [];
    _currentLyricIndex = -1;
    notifyListeners();

    try {
      final lrcText = await _addonService.getLyrics(
        track.artist, 
        track.title, 
        album: track.albumTitle,
        duration: track.duration,
        addonId: track.addonId ?? 'net.lrclib',


      );

      if (lrcText != null) {
        _lyrics = _parseLrc(lrcText);
      } else {
        _lyrics = [];
      }
    } catch (e) {
      print('[Player] Lyrics fetch error: $e');
      _lyrics = [];
    }

    _isFetchingLyrics = false;
    notifyListeners();
  }

  List<LyricLine> _parseLrc(String lrcText) {
    // Same parsing logic...
    final List<LyricLine> result = [];
    final pattern = RegExp(r'\[(\d+):(\d+\.?\d*)\](.*)');

    for (final line in lrcText.split('\n')) {
      final match = pattern.firstMatch(line);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = double.parse(match.group(2)!);
        final text = match.group(3)!.trim();

        final timestamp = Duration(
          minutes: minutes,
          milliseconds: (seconds * 1000).round(),
        );

        result.add(LyricLine(timestamp: timestamp, text: text));
      }
    }
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }

  void _updateCurrentLyric() {
    if (_lyrics.isEmpty) return;
    int newIndex = -1;
    for (int i = 0; i < _lyrics.length; i++) {
      // Small offset for better sync visual
      if (_position >= _lyrics[i].timestamp) {
        newIndex = i;
      } else {
        break;
      }
    }
    if (newIndex != _currentLyricIndex) {
      _currentLyricIndex = newIndex;
      // notifyListeners() is called in position stream listener
    }
  }

  Future<void> seekToLyric(int index) async {
    if (index >= 0 && index < _lyrics.length) {
      await seekTo(_lyrics[index].timestamp);
    }
  }

  Timer? _discordDebounceTimer;

  void _updateDiscordPresence({bool debounced = false}) {
    if (debounced) {
      _discordDebounceTimer?.cancel();
      _discordDebounceTimer = Timer(const Duration(milliseconds: 500), () {
        _performDiscordUpdate();
      });
    } else {
      _performDiscordUpdate();
    }
  }

  void _performDiscordUpdate() {
    if (_currentTrack == null) {
      _discordRpcService.clearPresence();
      return;
    }
    try {
      _discordRpcService.updatePresence(
        track: _currentTrack!,
        isPlaying: _isPlaying,
        position: _position,
        duration: _duration,
      );
    } catch (e) {
      print('[DiscordRPC] Update error: $e');
    }
  }

  @override
  void dispose() {
    _discordDebounceTimer?.cancel();
    _stopTicker();
    _discordRpcService.dispose();
    super.dispose();
  }
}

enum LoopMode { off, all, one }
