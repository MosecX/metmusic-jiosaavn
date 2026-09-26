import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/download_manager_service.dart';
import '../../core/services/addon_service.dart';

/// Professional batch download dialog.
///
/// * Skips already-downloaded tracks (with a visible count).
/// * Downloads with bounded concurrency so a big album doesn't open 100
///   connections at once.
/// * Tracks per-track progress (aggregate %) and per-track failures with the
///   failing titles listed at the end so they can be retried.
/// * Resolves each track's stream URL right before downloading (JioSaavn
///   URLs are permanent, but resolving late keeps memory flat).
class BatchDownloadDialog extends StatefulWidget {
  final List<Track> tracks;

  const BatchDownloadDialog({super.key, required this.tracks});

  /// Convenience entry point: opens the dialog over [tracks].
  static Future<void> show(BuildContext context, List<Track> tracks) {
    return showDialog(
      context: context,
      builder: (_) => BatchDownloadDialog(tracks: tracks),
    );
  }

  @override
  State<BatchDownloadDialog> createState() => _BatchDownloadDialogState();
}

enum _BatchState { calculating, ready, running, finished }

class _BatchDownloadDialogState extends State<BatchDownloadDialog> {
  _BatchState _state = _BatchState.calculating;

  List<Track> _toDownload = [];
  List<Track> _failedTracks = [];
  int _alreadyDownloadedCount = 0;

  int _completed = 0;
  int _total = 0;
  double _aggregateProgress = 0; // 0..100 across all tracks
  String _statusMessage = '';
  bool _stopRequested = false;

  final Map<String, double> _trackProgress = {};
  /// Downloads run strictly one at a time: parallel requests to the JioSaavn
  /// CDN (Azure Blob) get throttled/reset, which was failing ~6 tracks per
  /// album. The quality probe adds up to 5 extra requests per track, so
  /// sequential keeps every connection healthy.
  static const int _concurrency = 1;

  @override
  void initState() {
    super.initState();
    _calculateDownloads();
  }

  Future<void> _calculateDownloads() async {
    final dm = context.read<DownloadManagerService>();
    final pending = <Track>[];
    var exists = 0;

    for (final track in widget.tracks) {
      if (dm.isDownloaded(track.id)) {
        exists++;
      } else {
        pending.add(track);
      }
    }

    if (!mounted) return;
    setState(() {
      _toDownload = pending;
      _alreadyDownloadedCount = exists;
      _total = pending.length;
      _state = _BatchState.ready;
    });
  }

  Future<void> _startDownload() async {
    setState(() {
      _state = _BatchState.running;
      _statusMessage = 'Iniciando descargas…';
    });

    final dm = context.read<DownloadManagerService>();
    final addonService = context.read<AddonService>();

    // Simple worker-pool: [_concurrency] concurrent downloads, each worker
    // pulls the next pending index. Progress is aggregated across tracks.
    int next = 0;
    double finishedProgress = 0;

    Future<void> worker() async {
      while (true) {
        if (_stopRequested || !mounted) return;
        final i = next++;
        if (i >= _toDownload.length) return;
        final track = _toDownload[i];

        // Two attempts: first with the normal (cached) stream URL, then with
        // a freshly-resolved one in case the cached URL went stale or the
        // quality probe had a transient network hiccup.
        for (int attempt = 0; attempt < 2; attempt++) {
          if (_stopRequested || !mounted) return;
          try {
            final streamResult = await addonService.getStreamResult(
              track.addonTrackId ?? track.id,
              addonId: track.addonId,
              forceFresh: attempt > 0,
            );
            final url = streamResult?.url;
            if (url == null) throw Exception('No stream URL');

            if (_stopRequested || !mounted) return;

            final ok = await dm.downloadTrack(
              track: track,
              streamUrl: url,
              onProgress: (p) {
                if (!mounted) return;
                setState(() {
                  _trackProgress[track.id] = p;
                  _aggregateProgress =
                      (finishedProgress + _partialSum()) / (_total * 100) * 100;
                });
              },
            );

            if (!ok) throw Exception('Download failed');
            if (mounted) {
              setState(() {
                _completed++;
                finishedProgress += 100;
              });
            }
            break; // success — no retry needed
          } catch (e) {
            print('[BatchDownload] ${track.title} (attempt ${attempt + 1}/2): $e');
            if (attempt == 1 && mounted) {
              setState(() => _failedTracks.add(track));
            }
          }
        }
        // Small breather between sequential downloads keeps the CDN happy.
        await Future.delayed(const Duration(milliseconds: 300));

        _trackProgress.remove(track.id);
        if (mounted) {
          setState(() {
            _aggregateProgress =
                (finishedProgress + _partialSum()) / (_total * 100) * 100;
            _statusMessage = '$_completed de $_total descargadas…';
          });
        }
      }
    }

    await Future.wait(
        List.generate(_concurrency.clamp(1, _toDownload.length), (_) => worker()));

    if (!mounted) return;
    setState(() {
      _state = _BatchState.finished;
      _statusMessage = _stopRequested
          ? 'Descarga detenida: $_completed de $_total completadas.'
          : (_failedTracks.isEmpty
              ? '¡Listo! $_completed canciones descargadas.'
              : 'Completadas $_completed de $_total. ${_failedTracks.length} fallaron.');
    });
  }

  double _partialSum() =>
      _trackProgress.values.fold(0.0, (a, b) => a + b);

  Future<void> _retryFailed() async {
    setState(() {
      _toDownload = List.of(_failedTracks);
      _failedTracks = [];
      _completed = 0;
      _total = _toDownload.length;
      _aggregateProgress = 0;
      _stopRequested = false;
      _state = _BatchState.calculating;
    });
    // Small delay so the dialog re-enters "ready" cleanly.
    await Future.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    setState(() => _state = _BatchState.ready);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final canPop = _state != _BatchState.running || _stopRequested;

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Detén la descarga antes de cerrar.')),
        );
      },
      child: AlertDialog(
        title: Text(_state == _BatchState.finished
            ? 'Descargas'
            : 'Descargar canciones'),
        content: _buildContent(cs, text),
        actions: _buildActions(cs),
      ),
    );
  }

  Widget _buildContent(ColorScheme cs, TextTheme text) {
    switch (_state) {
      case _BatchState.calculating:
        return const SizedBox(
          height: 90,
          child: Center(child: CircularProgressIndicator()),
        );

      case _BatchState.ready:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.tracks.length} canciones en total.'),
            if (_alreadyDownloadedCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Icon(Icons.download_done_rounded,
                        color: Colors.greenAccent, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '$_alreadyDownloadedCount ya están descargadas y se omitirán.',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            Text(
              _toDownload.isNotEmpty
                  ? 'Listas para descargar: ${_toDownload.length}'
                  : 'Todo ya está descargado ✅',
              style: text.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        );

      case _BatchState.running:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _total > 0
                    ? (_aggregateProgress / 100).clamp(0.0, 1.0)
                    : 0,
                minHeight: 8,
                backgroundColor: cs.surfaceContainerHigh,
                valueColor: AlwaysStoppedAnimation(AppTheme.accent),
              ),
            ),
            const SizedBox(height: 14),
            Text(_statusMessage),
            if (_failedTracks.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${_failedTracks.length} fallaron',
                    style: TextStyle(color: cs.error)),
              ),
          ],
        );

      case _BatchState.finished:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_statusMessage),
            if (_failedTracks.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Fallaron:',
                  style: text.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              ..._failedTracks.take(5).map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '• ${t.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: cs.error, fontSize: 12),
                      ),
                    ),
                  ),
              if (_failedTracks.length > 5)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '… y ${_failedTracks.length - 5} más',
                    style: TextStyle(
                        color: cs.onSurfaceVariant, fontSize: 12),
                  ),
                ),
            ],
          ],
        );
    }
  }

  List<Widget> _buildActions(ColorScheme cs) {
    switch (_state) {
      case _BatchState.calculating:
        return [const SizedBox.shrink()];

      case _BatchState.ready:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          if (_toDownload.isNotEmpty)
            ElevatedButton(
              onPressed: _startDownload,
              child: Text('Descargar ${_toDownload.length}'),
            ),
        ];

      case _BatchState.running:
        return [
          TextButton(
            onPressed: () => setState(() => _stopRequested = true),
            style: TextButton.styleFrom(foregroundColor: cs.error),
            child: const Text('Detener'),
          ),
        ];

      case _BatchState.finished:
        return [
          if (_failedTracks.isNotEmpty)
            TextButton(
              onPressed: _retryFailed,
              child: const Text('Reintentar fallidas'),
            ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ];
    }
  }
}
