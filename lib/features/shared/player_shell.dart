import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../player/player_bar.dart';
import '../../core/services/audio_player_service.dart';

/// Wraps a pushed route so the mini player stays visible on every screen.
/// The PlayerBar renders as a shrink widget when nothing is playing.
class PlayerShell extends StatefulWidget {
  final Widget child;

  const PlayerShell({super.key, required this.child});

  @override
  State<PlayerShell> createState() => _PlayerShellState();
}

class _PlayerShellState extends State<PlayerShell> {
  late final AudioPlayerService _player;
  String? _shownError;

  @override
  void initState() {
    super.initState();
    _player = context.read<AudioPlayerService>();
    _player.addListener(_onPlayerChanged);
  }

  @override
  void dispose() {
    _player.removeListener(_onPlayerChanged);
    super.dispose();
  }

  void _onPlayerChanged() {
    final error = _player.lastPlaybackError;
    if (error != null && error != _shownError && mounted) {
      _shownError = error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 4),
        ),
      );
      _player.clearLastPlaybackError();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: widget.child),
        const SafeArea(
          top: false,
          left: false,
          right: false,
          child: PlayerBar(),
        ),
      ],
    );
  }
}
