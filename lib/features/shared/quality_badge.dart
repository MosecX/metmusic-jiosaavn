import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/models/models.dart';
import '../../core/services/addon_service.dart';

/// Quality Badge — Hostinger Design System
/// Shows Hi-Res / quality badges (JioSaavn delivers up to 320 kbps AAC).
class QualityBadge extends StatefulWidget {
  final Track? track;
  final String? qualityOverride;

  const QualityBadge({
    super.key,
    required this.track,
    this.qualityOverride,
  });

  factory QualityBadge.fromQuality({
    required String quality,
  }) =>
      QualityBadge(track: null, qualityOverride: quality);

  @override
  State<QualityBadge> createState() => _QualityBadgeState();
}

class _QualityBadgeState extends State<QualityBadge> {
  static final Map<String, String> _cache = {};
  String? _quality;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant QualityBadge old) {
    super.didUpdateWidget(old);
    if (old.track?.id != widget.track?.id ||
        old.qualityOverride != widget.qualityOverride) {
      _resolve();
    }
  }

  void _resolve() {
    final track = widget.track;
    final placeholder = _metadataQuality();
    if (widget.qualityOverride != null) {
      if (mounted) setState(() => _quality = widget.qualityOverride);
      return;
    }
    if (track == null) {
      if (mounted) setState(() => _quality = placeholder);
      return;
    }
    if (placeholder != null) {
      if (mounted) setState(() => _quality = placeholder);
    }
    final key = track.addonTrackId ?? track.id;
    final cached = _cache[key];
    if (cached != null) {
      if (mounted) setState(() => _quality = cached);
      return;
    }
    final addon = context.read<AddonService>();
    addon.getTrackQuality(key).then((q) {
      final resolved = _bestQuality(placeholder, q);
      if (resolved != null) _cache[key] = resolved;
      if (mounted) setState(() => _quality = resolved);
    });
  }

  static int _qualityRank(String? q) {
    if (q == null) return -1;
    final u = q.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (u.contains('HIRES')) return 3;
    if (u.contains('LOSSLESS')) return 2;
    if (u.contains('HIGH')) return 1;
    if (u.contains('LOW')) return 0;
    return -1;
  }

  static String? _bestQuality(String? a, String? b) {
    if (a == null) return b;
    if (b == null) return a;
    return _qualityRank(a) >= _qualityRank(b) ? a : b;
  }

  String? _metadataQuality() {
    final track = widget.track;
    if (track == null) return widget.qualityOverride;
    final aq = track.audioQuality;
    if (aq != null && aq.isHiRes) return 'HI_RES_LOSSLESS';
    final raw = track.rawData ?? {};
    final tags = raw['mediaMetadata'] is Map ? raw['mediaMetadata']['tags'] : null;
    if (tags is List &&
        tags.any((t) =>
            t.toString().toUpperCase().replaceAll('_', '').contains('HIRES'))) {
      return 'HI_RES_LOSSLESS';
    }
    final q = raw['audioQuality'];
    if (q is String && q.isNotEmpty) return q;
    if (aq != null) return aq.isHiRes ? 'HI_RES_LOSSLESS' : 'LOSSLESS';
    return widget.qualityOverride;
  }

  @override
  Widget build(BuildContext context) {
    final quality = _quality;

    if (quality == null || quality.isEmpty) return const SizedBox.shrink();

    final upper = quality.toUpperCase().replaceAll('_', '');
    if (upper.contains('HIRES')) {
      return _HostingerBadge(
        label: 'Hi-Res',
        style: _BadgeStyle.hires,
      );
    }
    if (upper.contains('LOSSLESS')) {
      return _HostingerBadge(
        label: 'Lossless',
        style: _BadgeStyle.lossless,
      );
    }
    return _HostingerBadge(
      label: quality.replaceAll('_', ' '),
      style: _BadgeStyle.lossless,
    );
  }
}

/// Hostinger Badge — pill-shaped quality indicator
class _HostingerBadge extends StatelessWidget {
  final String label;
  final _BadgeStyle style;

  const _HostingerBadge({
    required this.label,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;

    switch (style) {
      case _BadgeStyle.hires:
        // Hi-Res: Yellow/Amber
        bg = const Color(0xFFFACC15);
        fg = AppTheme.surface;
      case _BadgeStyle.lossless:
        // Subtle dark pill
        bg = AppTheme.surface3;
        fg = AppTheme.textMuted;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space2,
        vertical: AppTheme.space1,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppTheme.bodyFont,
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

enum _BadgeStyle { hires, lossless }
