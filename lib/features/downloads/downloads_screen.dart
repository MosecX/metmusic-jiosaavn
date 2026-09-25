import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../shared/staggered_item.dart';
import '../../core/services/settings_service.dart';

import '../../core/services/audio_player_service.dart';
import '../../core/services/download_manager_service.dart';
import '../../features/shared/track_list_tile.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final tracks = settings.getDownloadedTracksList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (tracks.isNotEmpty)
                    ElevatedButton.icon(
                      onPressed: () {
                        final player = context.read<AudioPlayerService>();
                        player.playAll(tracks);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: AppTheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radiusDefault),
                        ),
                      ),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Play All'),
                    ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
              child: FutureBuilder<int>(
                future: settings.getStorageSize(),
                builder: (context, snapshot) {
                  final sizeBytes = snapshot.data ?? 0;
                  final sizeMB = (sizeBytes / (1024 * 1024)).toStringAsFixed(1);
                  return Text(
                    '${tracks.length} songs • $sizeMB MB',
                    style: text.bodyMedium,
                  );
                },
              ),
            ),
          ),
          if (tracks.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_off,
                        size: 64,
                        color: cs.outline),
                    const SizedBox(height: 15),
                    Text(
                      'No downloaded songs yet',
                      style: text.bodyMedium,
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = tracks[index];
                  return StaggeredItem(
                    index: index,
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      child: TrackListTile(
                        track: track,
                        tracks: tracks,
                        index: index,
                      removeLabel: 'Delete Download',
                      onRemove: () async {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Deleting download...')),
                        );
                        final dm = context.read<DownloadManagerService>();
                        await dm.deleteDownload(track.id);
                      },
                    ),
                  ),
                  );
                },
                childCount: tracks.length,
              ),
            ),
          const SliverToBoxAdapter(
            child: SizedBox(height: 100),
          ),
        ],
      ),
    );
  }
}
