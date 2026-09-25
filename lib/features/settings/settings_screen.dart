import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';

import '../../core/theme/app_theme.dart';
import '../shared/staggered_item.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/account_service.dart';
import '../../core/services/addon_service.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/download_manager_service.dart';
import '../../core/services/jiosaavn_service.dart';
import '../../core/services/turso_client.dart';
import '../../core/models/addon_models.dart';
import '../auth/auth_screen.dart';
import '../shared/offline_banner.dart';

/// Settings Screen — Linear design system rewrite.
/// Uses Linear section pattern: small uppercase label + card with rounded
/// items separated by subtle dividers. No shadows, flat surfaces, 9px radius.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final downloadManager = context.watch<DownloadManagerService>();
    final connectivity = context.watch<ConnectivityService>();
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      children: [
        const OfflineBanner(),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(AppTheme.space6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header — Linear style
                Text(
                  'Settings',
                  style: text.displayMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 28,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: AppTheme.space6),

                // Account
                StaggeredItem(
                  index: 0,
                  stagger: true,
                  child: _SettingsSection(
                    title: 'Account',
                    children: [_AccountTile()],
                  ),
                ),

                const SizedBox(height: AppTheme.space5),

                // Playback
                StaggeredItem(
                  index: 1,
                  stagger: true,
                  child: _SettingsSection(
                    title: 'Playback',
                    children: [
                      _QualityTile(),
                      _SectionDivider(),
                      _LyricsModeTile(),
                    ],
                  ),
                ),

                const SizedBox(height: AppTheme.space5),

                // Servers
                StaggeredItem(
                  index: 2,
                  stagger: true,
                  child: _SettingsSection(
                    title: 'Servers',
                    children: [
                      _ServerStatusTile(
                        icon: Icons.dns_outlined,
                        title: 'JioSaavn API',
                        probe: () =>
                            context.read<AddonService>().checkApiHealth(),
                        expandable: true,
                      ),
                      _SectionDivider(),
                      _ServerStatusTile(
                        icon: Icons.cloud_outlined,
                        title: 'Account database (Turso)',
                        probe: _probeAccountDatabase,
                      ),
                      _SectionDivider(),
                      _ConnectionTile(),
                    ],
                  ),
                ),

                const SizedBox(height: AppTheme.space5),

                // Appearance
                StaggeredItem(
                  index: 3,
                  stagger: true,
                  child: _SettingsSection(
                    title: 'Appearance',
                    children: [
                      _ThemeTile(),
                    ],
                  ),
                ),

                const SizedBox(height: AppTheme.space5),

                // Downloads
                StaggeredItem(
                  index: 4,
                  stagger: true,
                  child: _SettingsSection(
                    title: 'Downloads & storage',
                    children: [
                      _DownloadLocationTile(),
                      _SectionDivider(),
                      _DownloadedCountTile(),
                      _SectionDivider(),
                      _StorageSizeTile(),
                      if (downloadManager.hasActiveDownloads) ...[
                        _SectionDivider(),
                        _ActiveDownloadsTile(),
                      ],
                      _SectionDivider(),
                      _ClearDownloadsTile(),
                    ],
                  ),
                ),

                const SizedBox(height: AppTheme.space5),

                // About
                StaggeredItem(
                  index: 5,
                  stagger: true,
                  child: _SettingsSection(
                    title: 'About',
                    children: [
                      ListTile(
                        leading: Icon(Icons.info_outline, color: cs.onSurfaceVariant, size: 20),
                        title: Text('Version', style: TextStyle(color: cs.onSurface)),
                        subtitle: Text('1.0.0', style: TextStyle(color: cs.onSurfaceVariant)),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppTheme.space8),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Probes the Turso account database with a trivial SQL round-trip.
  Future<ApiHealthStatus?> _probeAccountDatabase() async {
    final stopwatch = Stopwatch()..start();
    try {
      await tursoExecuteOne(
        TursoClient(
          url: AccountService.dbUrl,
          authToken: AccountService.authToken,
        ),
        'SELECT 1 AS ok',
        const [],
      );
      stopwatch.stop();
      return ApiHealthStatus(
        online: true,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e) {
      stopwatch.stop();
      return ApiHealthStatus(
        online: false,
        error: e.toString(),
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  void _clearCache() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final dcs = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: Text('Delete downloads?', style: TextStyle(fontWeight: FontWeight.w600)),
          content: Text(
              'This will remove all downloaded songs from your device. This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: dcs.error),
              onPressed: () async {
                final settings = context.read<SettingsService>();
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(dialogContext);
                await settings.clearCache();
                if (mounted) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Downloads deleted')),
                  );
                }
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}

// ── Section Divider ───────────────────────────────────────────────────
class _SectionDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppTheme.space3),
      child: Divider(height: 1, color: cs.outline, thickness: 1),
    );
  }
}

// ── Section Container (Linear pattern) ────────────────────────────────
class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section label — Linear: small, uppercase, tracked
        Padding(
          padding: EdgeInsets.only(
            left: AppTheme.space2,
            bottom: AppTheme.space2,
          ),
          child: Text(
            title.toUpperCase(),
            style: text.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              fontSize: 11,
              letterSpacing: 0.5,
              fontFamily: AppTheme.bodyFont,
            ),
          ),
        ),
        // Container
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainer, // Linear #f4f2f4
            border: Border.all(color: cs.outline, width: 1), // Linear #191d20
            borderRadius: BorderRadius.circular(AppTheme.radiusMd), // 9px
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }
}

// ── Account Tile ──────────────────────────────────────────────────────
class _AccountTile extends StatelessWidget {
  const _AccountTile();

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountService>();
    final cs = Theme.of(context).colorScheme;

    if (!account.isLoggedIn) {
      return ListTile(
        leading: Icon(Icons.account_circle_outlined, color: cs.onSurfaceVariant, size: 20),
        title: Text('Sign in', style: TextStyle(color: cs.onSurface)),
        subtitle: Text('Required to play music', style: TextStyle(color: cs.onSurfaceVariant)),
        trailing: Icon(Icons.chevron_right, color: cs.outline, size: 18),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AuthScreen()),
          );
        },
      );
    }

    final statusColor = account.isApproved ? AppTheme.success : AppTheme.warning;
    final statusLabel = account.isApproved
        ? 'APPROVED'
        : (account.isPending ? 'PENDING' : 'REJECTED');

    return ListTile(
      leading: Icon(Icons.account_circle, color: cs.primary, size: 22),
      title: Text(
        '@${account.user!.username}',
        style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(account.user!.email, style: TextStyle(color: cs.onSurfaceVariant)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                color: statusColor,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                fontFamily: AppTheme.bodyFont,
              ),
            ),
          ),
          const SizedBox(width: AppTheme.space1),
          TextButton(
            onPressed: () async {
              await account.logout();
            },
            child: Text(
              'Sign out',
              style: TextStyle(color: cs.error, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AuthScreen()),
        );
      },
    );
  }
}// ── Pill Badge (shared by Playback + Quality tiles) ───────────────────
class _PillBadge extends StatelessWidget {
  final String label;
  const _PillBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: cs.primary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          fontFamily: AppTheme.bodyFont,
        ),
      ),
    );
  }
}
// ── Quality Tile ──────────────────────────────────────────────────────
class _QualityTile extends StatelessWidget {
  const _QualityTile();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(Icons.high_quality_outlined, color: cs.onSurfaceVariant, size: 20),
      title: Text('Calidad de audio', style: TextStyle(color: cs.onSurface)),
      subtitle: Text(
        'AAC · hasta 320 kbps, según disponibilidad por pista',
        style: TextStyle(color: cs.onSurfaceVariant),
      ),
      trailing: const _PillBadge(label: 'Referencia'),
    );
  }
}
// ── Lyrics Mode Tile ──────────────────────────────────────────────────
class _LyricsModeTile extends StatelessWidget {
  const _LyricsModeTile();

  static const _options = [
    ('standard', 'Standard', 'Clean synced lyrics'),
    ('visualizer', 'Visualizer', 'Animated cover with illuminated lyrics'),
  ];

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final cs = Theme.of(context).colorScheme;
    final current = settings.lyricsMode;
    final option = _options.firstWhere(
      (o) => o.$1 == current,
      orElse: () => _options.first,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: Icon(Icons.lyrics_outlined, color: cs.onSurfaceVariant, size: 20),
          title: Text('Lyrics mode', style: TextStyle(color: cs.onSurface)),
          subtitle: Text(option.$3, style: TextStyle(color: cs.onSurfaceVariant)),
          trailing: PopupMenuButton<String>(
            initialValue: current,
            color: cs.surface,
            onSelected: (value) => settings.setLyricsMode(value),
            itemBuilder: (context) => [
              for (final o in _options)
                PopupMenuItem(
                  value: o.$1,
                  child: Row(
                    children: [
                      Icon(
                        o.$1 == current
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 16,
                        color: o.$1 == current ? cs.primary : cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppTheme.space2),
                      Text(o.$2),
                    ],
                  ),
                ),
            ],
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    option.$2,
                    style: TextStyle(
                      color: cs.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: AppTheme.bodyFont,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.arrow_drop_down, color: cs.primary, size: 16),
                ],
              ),
            ),
          ),
        ),
        if (current == 'visualizer')
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppTheme.space3,
              0,
              AppTheme.space3,
              AppTheme.space2,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 14, color: AppTheme.warning),
                const SizedBox(width: AppTheme.space2),
                Expanded(
                  child: Text(
                    'Visualizer mode animates the album cover and may cause lag and higher battery usage on some devices.',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ── Server Status Tile ────────────────────────────────────────────────
class _ServerStatusTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final Future<ApiHealthStatus?> Function() probe;
  final bool expandable;

  const _ServerStatusTile({
    required this.icon,
    required this.title,
    required this.probe,
    this.expandable = false,
  });

  @override
  State<_ServerStatusTile> createState() => _ServerStatusTileState();
}

class _ServerStatusTileState extends State<_ServerStatusTile> {
  ApiHealthStatus? _status;
  bool _loading = true;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _loading = true);
    final status = await widget.probe();
    if (!mounted) return;
    setState(() {
      _status = status;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final online = status?.online ?? false;
    final cs = Theme.of(context).colorScheme;
    final color = online ? AppTheme.success : AppTheme.danger;

    final tile = ListTile(
      leading: Icon(widget.icon, color: online ? cs.primary : cs.onSurfaceVariant, size: 20),
      title: Text(widget.title, style: TextStyle(color: cs.onSurface)),
      subtitle: _loading
          ? Text('Checking...', style: TextStyle(color: cs.onSurfaceVariant))
          : Text(
              status == null
                  ? 'Not configured'
                  : online
                      ? 'Online${status.version != null ? ' · v${status.version}' : ''} · ${status.latencyMs}ms'
                      : 'Offline${status.error != null ? ' · ${status.error}' : ''}',
              style: TextStyle(color: cs.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: _loading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                if (widget.expandable) ...[
                  const SizedBox(width: AppTheme.space2),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: cs.onSurfaceVariant,
                    size: 18,
                  ),
                ],
              ],
            ),
      onTap: () {
        if (widget.expandable) {
          setState(() => _expanded = !_expanded);
          if (_expanded) {
            // Trigger fresh check when expanded
            _check();
          }
        } else {
          _check();
        }
      },
    );

    if (!widget.expandable) return tile;

    return Column(
      children: [
        tile,
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: _expanded
              ? _ApiDetailedStatusPanel(
                  onRefresh: _check,
                  baseUrl: _ApiDetailedStatusPanel.baseUrlFromContext(context),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ── API Detailed Status Panel ─────────────────────────────────────────
class _ApiDetailedStatusPanel extends StatefulWidget {
  final VoidCallback onRefresh;
  final String baseUrl;

  const _ApiDetailedStatusPanel({
    required this.onRefresh,
    required this.baseUrl,
  });

  static String baseUrlFromContext(BuildContext context) {
    return JioSaavnService.apiBase;
  }

  @override
  State<_ApiDetailedStatusPanel> createState() => _ApiDetailedStatusPanelState();
}

class _ApiDetailedStatusPanelState extends State<_ApiDetailedStatusPanel> {
  final Map<String, bool?> _results = {};
  bool _probing = false;

  @override
  void initState() {
    super.initState();
    _runAllProbes();
  }

  Future<void> _runAllProbes() async {
    setState(() {
      _probing = true;
      _results.clear();
    });
    for (final probe in _ApiProbes.all) {
      if (!mounted) return;
      setState(() => _results[probe.key] = null);
      final ok = await probe.run(widget.baseUrl);
      if (!mounted) return;
      setState(() => _results[probe.key] = ok);
    }
    if (mounted) setState(() => _probing = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        AppTheme.space3,
        0,
        AppTheme.space3,
        AppTheme.space4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: AppTheme.space2),
            child: Row(
              children: [
                Icon(Icons.science_outlined, size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: AppTheme.space2),
                Expanded(
                  child: Text(
                    'Detailed API status',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: AppTheme.bodyFont,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _probing ? null : _runAllProbes,
                  icon: Icon(Icons.refresh, size: 14, color: cs.primary),
                  label: Text(
                    'Recheck',
                    style: TextStyle(
                      color: cs.primary,
                      fontSize: 12,
                      fontFamily: AppTheme.bodyFont,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: AppTheme.space2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.space2),
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(color: cs.outline, width: 1),
            ),
            child: Column(
              children: [
                for (var i = 0; i < _ApiProbes.all.length; i++) ...[
                  _SimpleCheckRow(
                    probe: _ApiProbes.all[i],
                    online: _results[_ApiProbes.all[i].key],
                  ),
                  if (i < _ApiProbes.all.length - 1)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: AppTheme.space3),
                      child: Divider(height: 1, color: cs.outline, thickness: 1),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SimpleCheckRow extends StatelessWidget {
  final _ApiProbe probe;
  final bool? online;

  const _SimpleCheckRow({required this.probe, required this.online});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLoading = online == null;
    final isOnline = online == true;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppTheme.space3,
        vertical: AppTheme.space3 + 2,
      ),
      child: Row(
        children: [
          Icon(probe.icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: AppTheme.space3),
          Expanded(
            child: Text(
              probe.label,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                fontFamily: AppTheme.bodyFont,
              ),
            ),
          ),
          if (isLoading)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: cs.primary),
            )
          else
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isOnline ? AppTheme.success : AppTheme.danger,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}

class _ApiProbe {
  final String key;
  final String label;
  final IconData icon;
  final Future<bool> Function(String baseUrl) run;

  const _ApiProbe({
    required this.key,
    required this.label,
    required this.icon,
    required this.run,
  });
}

class _ApiProbes {
  // Probes run against the JioSaavn API proxy (rthmx spec). The row in the
  // main settings panel tracks whether the source of truth is reachable.
  static const String _base = 'https://rthmx.vercel.app/api';

  static final all = <_ApiProbe>[
    _ApiProbe(
      key: 'search',
      label: 'Search songs',
      icon: Icons.search,
      run: (_) => _checkSearch(),
    ),
    _ApiProbe(
      key: 'song',
      label: 'Song detail / stream',
      icon: Icons.play_circle_outline,
      run: (_) => _checkSong(),
    ),
    _ApiProbe(
      key: 'album',
      label: 'Album detail',
      icon: Icons.album_outlined,
      run: (_) => _checkAlbum(),
    ),
    _ApiProbe(
      key: 'artist',
      label: 'Artist detail',
      icon: Icons.person_outline,
      run: (_) => _checkArtist(),
    ),
    _ApiProbe(
      key: 'cover',
      label: 'Cover image (CDN)',
      icon: Icons.image_outlined,
      run: (_) => _checkCover(),
    ),
  ];

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 10),
    headers: {'Accept': 'application/json'},
  ));

  static const _token = 'OAUEZFl3cVo'; // "MANANA" (QMIIR)
  static const _albumToken = 'YAF8sxXMEgo_';
  static const _artistToken = 'UVXieI6jW5I_'; // Beyoncé

  // Songs search: /songs?q= — 200 and at least one result.
  static Future<bool> _checkSearch() async {
    try {
      final res = await _dio.get('$_base/songs',
          queryParameters: {'q': 'manana'});
      if (res.statusCode != 200) return false;
      final results = (res.data is Map) ? res.data['results'] : null;
      return results is List && results.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // Song detail: /song?token= — 200 with an encrypted media URL (playable).
  static Future<bool> _checkSong() async {
    try {
      final res = await _dio.get('$_base/song',
          queryParameters: {'token': _token});
      if (res.statusCode != 200) return false;
      final data = _toMap(res.data);
      final more = _toMap(data['more_info']);
      final enc = more['encrypted_media_url'] ?? data['encrypted_media_url'];
      return enc is String && enc.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // Album detail: /album?token= — 200 and a non-empty songs list.
  static Future<bool> _checkAlbum() async {
    try {
      final res = await _dio.get('$_base/album',
          queryParameters: {'token': _albumToken});
      if (res.statusCode != 200) return false;
      final data = _toMap(res.data);
      final songs = data['songs'];
      return songs is List && songs.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // Artist detail: /artist?token= — 200 and a non-empty topSongs list.
  static Future<bool> _checkArtist() async {
    try {
      final res = await _dio.get('$_base/artist',
          queryParameters: {'token': _artistToken});
      if (res.statusCode != 200) return false;
      final data = _toMap(res.data);
      final top = data['topSongs'];
      return top is List && top.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // Cover image: HEAD to the JioSaavn CDN — online when 200 + image/*.
  static Future<bool> _checkCover() async {
    try {
      final res = await _dio.head(
        'https://c.saavncdn.com/230/MANANA-Portuguese-2026-20260224212033-150x150.jpg',
        options: Options(receiveTimeout: const Duration(seconds: 6)),
      );
      if (res.statusCode != 200) return false;
      final ct = res.headers.value('content-type') ?? '';
      return ct.startsWith('image/');
    } catch (_) {
      return false;
    }
  }

  static Map<String, dynamic> _toMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }
}

// ── Connection Tile ───────────────────────────────────────────────────
class _ConnectionTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final connectivity = context.watch<ConnectivityService>();
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(connectivity.connectionIcon, color: cs.onSurfaceVariant, size: 20),
      title: Text('Connection', style: TextStyle(color: cs.onSurface)),
      subtitle: Text(
        connectivity.connectionTypeLabel,
        style: TextStyle(color: cs.onSurfaceVariant),
      ),
      trailing: connectivity.hasNetwork
          ? (connectivity.canReachApi
              ? Icon(Icons.check_circle_outline, color: AppTheme.success, size: 18)
              : Icon(Icons.warning_amber_outlined, color: AppTheme.warning, size: 18))
          : Icon(Icons.signal_wifi_off, color: cs.error, size: 18),
    );
  }
}

// ── Theme Tile ────────────────────────────────────────────────────────
class _ThemeTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(Icons.dark_mode_outlined, color: cs.onSurfaceVariant, size: 20),
      title: Text('Dark mode', style: TextStyle(color: cs.onSurface)),
      trailing: Switch(
        value: settings.isDarkMode,
        onChanged: (val) => settings.toggleTheme(),
        activeThumbColor: Colors.white,
        activeTrackColor: cs.primary,
        inactiveTrackColor: cs.outline,
      ),
    );
  }
}

// ── Download Tiles ────────────────────────────────────────────────────
class _DownloadLocationTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.read<SettingsService>();

    return ListTile(
      leading: Icon(Icons.folder_open, color: cs.onSurfaceVariant, size: 20),
      title: Text('Download location', style: TextStyle(color: cs.onSurface)),
      subtitle: FutureBuilder<String>(
        future: settings.getDownloadLocation(),
        builder: (context, snapshot) => Text(
          snapshot.data ?? 'Loading...',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _DownloadedCountTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsService>();

    return ListTile(
      leading: Icon(Icons.download_done, color: cs.onSurfaceVariant, size: 20),
      title: Text('Downloaded songs', style: TextStyle(color: cs.onSurface)),
      subtitle: Text(
        '${settings.downloadedCount} songs',
        style: TextStyle(color: cs.onSurfaceVariant),
      ),
    );
  }
}

class _StorageSizeTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.read<SettingsService>();

    return ListTile(
      leading: Icon(Icons.storage, color: cs.onSurfaceVariant, size: 20),
      title: Text('Storage used', style: TextStyle(color: cs.onSurface)),
      subtitle: FutureBuilder<int>(
        future: settings.getStorageSize(),
        builder: (context, snapshot) => Text(
          _formatBytes(snapshot.data ?? 0),
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class _ActiveDownloadsTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final downloadManager = context.watch<DownloadManagerService>();

    return ListTile(
      leading: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
      ),
      title: Text(
        '${downloadManager.activeDownloads.length} active downloads',
        style: TextStyle(color: cs.onSurface),
      ),
    );
  }
}

class _ClearDownloadsTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.read<SettingsService>();

    return ListTile(
      leading: Icon(Icons.delete_outline, color: cs.error, size: 20),
      title: Text(
        'Delete downloads',
        style: TextStyle(color: cs.error, fontWeight: FontWeight.w600),
      ),
      onTap: () {
        showDialog(
          context: context,
          builder: (dialogContext) {
            final dcs = Theme.of(dialogContext).colorScheme;
            return AlertDialog(
              title: Text('Delete downloads?',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              content: Text(
                  'This will remove all downloaded songs from your device. This cannot be undone.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: dcs.error),
                  onPressed: () async {
                    await settings.clearCache();
                    if (context.mounted) {
                      Navigator.pop(dialogContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Downloads deleted')),
                      );
                    }
                  },
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
