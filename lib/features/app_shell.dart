import 'package:flutter/foundation.dart';
import '../core/utils/platform_helper.dart';
import '../core/utils/reicon_helper.dart';

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../core/services/audio_player_service.dart';
import '../core/services/account_service.dart';
import '../core/services/import_service.dart';
import '../core/services/navigation_service.dart';
import 'home/home_screen.dart';
import 'library/library_screen.dart';
import 'settings/settings_screen.dart';
import 'search/search_screen.dart';
import 'auth/auth_screen.dart';
import 'player/player_bar.dart';

/// Main App Shell — Hostinger Design System layout
/// Responsive sidebar + viewport + player bar
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  final List<Widget> _screens = [];
  final GlobalKey<SearchScreenState> _searchKey = GlobalKey<SearchScreenState>();
  late FocusNode _appFocusNode;

  // Responsive breakpoint — Hostinger uses 768px
  static const double _mobileBreakpoint = 768;

  @override
  void initState() {
    super.initState();
    _appFocusNode = FocusNode();
    _requestNotificationPermission();

    _screens.addAll([
      HomeScreen(onNavigate: _onNavTap),
      const LibraryScreen(),
      const SettingsScreen(),
      SearchScreen(key: _searchKey, onNavigate: _onNavTap),
    ]);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AudioPlayerService>().onPlaybackBlocked = _openAuth;
        context.read<AudioPlayerService>().onOfflineBlocked = _showOfflineNotice;
      }
    });
  }

  Future<void> _showOfflineNotice() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Estás sin conexión. Solo puedes reproducir canciones descargadas.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openAuth() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
    );
  }

  Future<void> _requestNotificationPermission() async {
    if (kIsWeb) return;
    if (!PlatformHelper.isAndroid) return;
    await _requestAndroidPermissions();
  }

  Future<void> _requestAndroidPermissions() async {
    try {
      final dynamic permHandler = await _loadPermissionHandler();
      await permHandler.requestNotification();
      await permHandler.requestStorage();
      await permHandler.requestAudio();
    } catch (_) {}
  }

  Future<dynamic> _loadPermissionHandler() async => null;

  void _onNavTap(int index) {
    setState(() {
      _selectedIndex = index;
    });

    if (index == 3) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _searchKey.currentState?.focusSearch();
      });
    }
  }

  void _handleBack() {
    final navService = context.read<NavigationService>();
    if (navService.canGoBack) {
      navService.handleBack();
      return;
    }

    if (_selectedIndex != 0) {
      setState(() {
        _selectedIndex = 0;
      });
    }
  }

  @override
  void dispose() {
    _appFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < _mobileBreakpoint;

    return Focus(
      focusNode: _appFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (_isTextInputFocused()) {
          return KeyEventResult.ignored;
        }

        final player = context.read<AudioPlayerService>();

        switch (event.logicalKey) {
          case LogicalKeyboardKey.space:
            player.togglePlayPause();
            return KeyEventResult.handled;

          case LogicalKeyboardKey.arrowRight:
            player.nextTrack();
            return KeyEventResult.handled;

          case LogicalKeyboardKey.arrowLeft:
            player.previousTrack();
            return KeyEventResult.handled;

          case LogicalKeyboardKey.escape:
            _handleBack();
            return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () {
          if (!_appFocusNode.hasFocus) {
            FocusScope.of(context).requestFocus(_appFocusNode);
          }
        },
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _handleBack();
          },
          child: Scaffold(
            backgroundColor: AppTheme.pageBackground,
            body: Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: SafeArea(
                        bottom: false,
                        child: isMobile
                            ? _buildMobileLayout()
                            : _buildDesktopLayout(),
                      ),
                    ),
                    const PlayerBar(),
                  ],
                ),
                _buildBackgroundImportOverlay(),
              ],
            ),
            bottomNavigationBar: isMobile ? _buildHostingerBottomNav() : null,
          ),
        ),
      ),
    );
  }

  Widget _buildBackgroundImportOverlay() {
    return Consumer<ImportService>(
      builder: (context, importService, child) {
        if (!importService.isImporting || !importService.isBackgrounded) {
          return const SizedBox.shrink();
        }

        final cs = Theme.of(context).colorScheme;

        return Positioned(
          top: 10,
          right: 10,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(AppTheme.radiusDefault),
            color: cs.surfaceContainer,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.space4,
                vertical: AppTheme.space3,
              ),
              width: 300,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.radiusDefault),
                border: Border.all(
                  color: AppTheme.accent.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Importando Playlist...',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                        onPressed: () => importService.stopImport(),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.space2),
                  LinearProgressIndicator(
                    value: importService.progress,
                    backgroundColor: cs.surfaceContainerHigh,
                    color: AppTheme.accent,
                  ),
                  const SizedBox(height: AppTheme.space2),
                  Text(
                    importService.statusMessage,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${importService.importedCount} / ${importService.totalTracks} Tracks',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  bool _isTextInputFocused() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null && focus.context != null) {
      if (!focus.context!.mounted) return false;
      final editable = focus.context!.findAncestorWidgetOfExactType<EditableText>();
      return editable != null;
    }
    return false;
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        _buildHostingerSidebar(),
        Expanded(
          child: Container(
            color: AppTheme.pageBackground,
            child: IndexedStack(
              index: _selectedIndex,
              children: _screens,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return IndexedStack(
      index: _selectedIndex,
      children: _screens,
    );
  }

  /// Hostinger Design System Sidebar
  Widget _buildHostingerSidebar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: AppTheme.pageBackground,
        border: Border(
          right: BorderSide(
            color: cs.outline.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo — Hostinger style
          Padding(
            padding: const EdgeInsets.all(AppTheme.space4),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: AppTheme.brandLinearGradient(),
                    borderRadius: BorderRadius.circular(AppTheme.radiusDefault),
                  ),
                  child: ReIcon.musicNote(
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: AppTheme.space3),
                Text(
                  'BeatBoss',
                  style: TextStyle(
                    fontFamily: AppTheme.displayFont,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppTheme.space2),

          // Navigation Items — Hostinger pill style
          ..._buildHostingerNavItems(),
        ],
      ),
    );
  }

  List<Widget> _buildHostingerNavItems() {
    return [
      _buildHostingerNavItem(
        index: 0,
        icon: ReIcon.home(),
        label: 'Inicio',
      ),
      _buildHostingerNavItem(
        index: 1,
        icon: ReIcon.library(),
        label: 'Biblioteca',
      ),
      _buildHostingerNavItem(
        index: 2,
        icon: ReIcon.settings(),
        label: 'Ajustes',
      ),
    ];
  }

  /// Hostinger Navigation Item — pill-shaped with hover/focus states
  Widget _buildHostingerNavItem({
    required int index,
    required Widget icon,
    required String label,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = _selectedIndex == index ||
        (_selectedIndex == 3 && index == 0);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space3,
        vertical: AppTheme.space1,
      ),
      child: InkWell(
        onTap: () => _onNavTap(index),
        borderRadius: BorderRadius.circular(AppTheme.radiusDefault),
        hoverColor: cs.onSurface.withValues(alpha: 0.05),
        focusColor: AppTheme.accent.withValues(alpha: 0.1),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.space4,
            vertical: AppTheme.space3,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.accent.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusDefault),
            border: isSelected
                ? Border.all(
                    color: AppTheme.accent.withValues(alpha: 0.3),
                    width: 1,
                  )
                : null,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: DefaultTextStyle(
                  style: TextStyle(
                    color: isSelected ? AppTheme.accent : AppTheme.textPrimary,
                  ),
                  child: IconTheme(
                    data: IconThemeData(
                      color: isSelected ? AppTheme.accent : AppTheme.textPrimary,
                      size: 24,
                    ),
                    child: icon,
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.space3),
              Text(
                label,
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? AppTheme.accent : AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Hostinger Bottom Navigation — fixed-height bar with inner SafeArea
  /// padding (SystemUiOverlayStyle already forces a transparent black system
  /// nav bar, so we only add the real gesture-inset height when present).
  Widget _buildHostingerBottomNav() {
    final cs = Theme.of(context).colorScheme;
    final activeIndex = _selectedIndex > 2 ? 0 : _selectedIndex;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border(
          top: BorderSide(
            color: cs.outline.withValues(alpha: 0.1),
          ),
        ),
      ),
      // 68dp content bar + the real system gesture inset. On devices
      // without a gesture bar this keeps a comfortable, professional 68dp;
      // with gesture nav it grows only by the inset, never collapsing the
      // icons/labels the way the old 80dp + double-padding layout did.
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: 68,
        child: Row(
          children: [
            _buildHostingerBottomNavItem(
              index: 0,
              icon: ReIcon.home(
                color:
                    activeIndex == 0 ? AppTheme.accent : AppTheme.textPrimary,
              ),
              label: 'Inicio',
              isSelected: activeIndex == 0,
            ),
            _buildHostingerBottomNavItem(
              index: 1,
              icon: ReIcon.library(
                color:
                    activeIndex == 1 ? AppTheme.accent : AppTheme.textPrimary,
              ),
              label: 'Biblioteca',
              isSelected: activeIndex == 1,
            ),
            _buildHostingerBottomNavItem(
              index: 2,
              icon: ReIcon.settings(
                color:
                    activeIndex == 2 ? AppTheme.accent : AppTheme.textPrimary,
              ),
              label: 'Ajustes',
              isSelected: activeIndex == 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHostingerBottomNavItem({
    required int index,
    required Widget icon,
    required String label,
    required bool isSelected,
  }) {
    return Expanded(
      child: InkWell(
        onTap: () => _onNavTap(index),
        borderRadius: BorderRadius.circular(AppTheme.radiusDefault),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          // Centered within the fixed 68dp bar: icon + label stack.
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconTheme(
                data: IconThemeData(
                  color: isSelected ? AppTheme.accent : AppTheme.textPrimary,
                  size: 24,
                ),
                child: icon,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontFamily: AppTheme.bodyFont,
                  fontSize: 11.5,
                  height: 1.0,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? AppTheme.accent : AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCreatePlaylistDialog() async {
    final account = context.read<AccountService>();
    if (!account.isLoggedIn) {
      await _openAuth();
      return;
    }

    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.add_box, color: AppTheme.accent),
            const SizedBox(width: AppTheme.space2),
            const Text('Nueva Playlist'),
          ],
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nombre de la playlist',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final created = await account.createPlaylist(
                  controller.text.trim(),
                );
                if (mounted) {
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(created != null
                        ? 'Playlist "${created.name}" creada'
                        : 'Error al crear playlist'),
                  ));
                }
              }
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    controller.dispose();
  }
}

class PlayPauseIntent extends Intent {
  const PlayPauseIntent();
}

class NextTrackIntent extends Intent {
  const NextTrackIntent();
}

class PreviousTrackIntent extends Intent {
  const PreviousTrackIntent();
}

class BackIntent extends Intent {
  const BackIntent();
}
