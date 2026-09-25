import 'package:flutter/foundation.dart'; // For kIsWeb
import 'dart:io';
import 'package:media_kit/media_kit.dart'; // MediaKit.ensureInitialized()
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/utils/hive/hive_provider.dart';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'core/theme/app_theme.dart';
import 'core/services/settings_service.dart';
import 'core/services/audio_player_service.dart';
import 'core/services/audio_handler.dart';
import 'core/services/download_manager_service.dart';
import 'core/services/discord_rpc_service.dart';
import 'core/services/account_service.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/youtube_service.dart';
import 'core/services/spotify_service.dart';
import 'core/services/jiosaavn_service.dart';

import 'features/app_shell.dart';

import 'core/services/history_service.dart';
import 'core/services/import_service.dart';
import 'core/services/addon_service.dart';
import 'core/services/lrclib_addon_handler.dart';
import 'core/services/tidal_addon_handler.dart';
import 'core/services/local_library_service.dart';
import 'core/services/navigation_service.dart';
import 'core/utils/platform_helper.dart';

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize media_kit (required before creating any Player)
    if (!kIsWeb) PlatformHelper.ensureMpvConfig();
    MediaKit.ensureInitialized();
    if (!kIsWeb) JustAudioMediaKit.ensureInitialized();

    // Initialize Hive for local storage — store data next to the executable
    // on desktop (not in ~/Documents) for a self-contained app folder.
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      final exePath = Platform.resolvedExecutable;
      final appDir = File(exePath).parent.path;
      final hiveDir = '$appDir${Platform.pathSeparator}data';
      await Directory(hiveDir).create(recursive: true);
      await Hive.initFlutter(hiveDir);
    } else {
      await Hive.initFlutter();
    }

    // 1. Settings (needed globally)
    final settingsService = SettingsService();
    await settingsService.init();

    // 2. Core Services
    final downloadManager =
        DownloadManagerService(settingsService: settingsService);

    final historyService = HistoryService();
    await historyService.init();

    final importService = ImportService(); // New background import service
    
    final localLibraryService = LocalLibraryService();
    await localLibraryService.init();

    final addonService = AddonService(settingsService: settingsService);
    
    final lrcLibHandler = LrcLibAddonHandler();
    addonService.registerUserHandler('net.lrclib', lrcLibHandler);

    final tidalHandler = TidalAddonHandler(settingsService: settingsService);
    addonService.registerUserHandler('com.tidal.hifi', tidalHandler);

    await addonService.initAddons();

    // Make Tidal the active search provider by default
    if (addonService.activeAddonId == null) {
      await addonService.setActiveAddon('com.tidal.hifi');
    }

    // JioSaavn playback source (used when selected in Settings).
    final jioSaavnService = JioSaavnService();

    // 3. Audio Handler (Background)
    final handlerInstance = AppAudioHandler(
      downloadManager: downloadManager,
      addonService: addonService,
      settings: settingsService,
    );
    handlerInstance.attachJioSaavn(jioSaavnService);

    final audioHandler = kIsWeb
        ? handlerInstance
        : await AudioService.init(
            builder: () => handlerInstance,
            config: const AudioServiceConfig(
              androidNotificationChannelId: 'com.metmusic.app.channel.audio',
              androidNotificationChannelName: 'Audio playback',
              androidNotificationOngoing: true,
              androidNotificationIcon: 'mipmap/launcher_icon',
            ),
          );

    final discordRpcService = DiscordRpcService();
    discordRpcService.initialize();

    final youtubeService = YouTubeService();
    final spotifyService = SpotifyService();
    final accountService = AccountService(settingsService: settingsService);
    await accountService.init();

    final connectivityService = ConnectivityService(
        settingsService: settingsService);
    await connectivityService.start();

    // 4. UI Audio Service
    final audioPlayerService = AudioPlayerService(
      handler: audioHandler,
      addonService: addonService,
      historyService: historyService,
      accountService: accountService,
      connectivityService: connectivityService,
      downloadManager: downloadManager,
      discordRpcService: discordRpcService, // Inject
    );

    final navigationService = NavigationService();

    // Set system UI style
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarDividerColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
    );

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settingsService),
          ChangeNotifierProvider.value(value: audioPlayerService),
          ChangeNotifierProvider.value(value: addonService),
          ChangeNotifierProvider.value(value: historyService),
          ChangeNotifierProvider.value(value: localLibraryService),
          ChangeNotifierProvider.value(value: downloadManager),
          ChangeNotifierProvider.value(value: importService),
          ChangeNotifierProvider.value(value: accountService),
          ChangeNotifierProvider.value(value: connectivityService),
          ChangeNotifierProvider.value(value: navigationService),
          Provider.value(value: discordRpcService),
          Provider.value(value: youtubeService),
          Provider.value(value: spotifyService),
          Provider.value(value: jioSaavnService),
        ],
        child: const MetMusicApp(),
      ),
    );
  } catch (e, st) {
    print('CRITICAL BOOT ERROR: $e');
    print(st);
  }
}

class MetMusicApp extends StatelessWidget {
  const MetMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<SettingsService>().isDarkMode
        ? ThemeMode.dark
        : ThemeMode.light;

    return MaterialApp(
      title: 'MetMusic',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      builder: (context, child) => DefaultTextStyle(
        style: (Theme.of(context).textTheme.bodyMedium ??
                const TextStyle())
            .copyWith(decoration: TextDecoration.none),
        child: Material(
          type: MaterialType.transparency,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      home: const AppShell(),
    );
  }
}
