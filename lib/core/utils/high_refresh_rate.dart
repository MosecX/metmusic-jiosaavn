import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;

/// Unlocks high refresh rates (90/120/144 Hz) on Android devices whose
/// displays support them.
///
/// Flutter's Android embedding defaults to the lowest supported display mode,
/// so phones with high-refresh panels often render at 60 Hz unless the app
/// opts in. MainActivity (Kotlin side) selects the supported mode with the
/// highest refresh rate when this channel method fires; Android's power
/// saving still downshifts when idle.
void unlockHighRefreshRate() {
  try {
    const channel = MethodChannel('com.metmusic.jiosaavn/display');
    // Warm up after the first frame so the Activity and window are ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      channel.invokeMethod<bool>('setHighRefreshRate').then((ok) {
        print('[DisplayMode] High refresh rate unlocked: $ok');
      }).catchError((e) {
        print('[DisplayMode] Could not unlock high refresh rate: $e');
      });
    });
  } catch (e) {
    print('[DisplayMode] Channel error: $e');
  }
}

class AndroidDisplayModeLimiter {
  static void unlockHighRefreshRate() => unlockHighRefreshRate();
}
