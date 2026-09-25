import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/audio_player_service.dart';
import '../shared/staggered_item.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudioPlayerService>();
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusDefault)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Text(
                  'Cola actual',
                  style: text.displaySmall,
                ),
                const Spacer(),
                TextButton(
                  onPressed: player.clearQueue,
                  child: const Text('Borrar cola'),
                ),
              ],
            ),
          ),
          Expanded(
            child: player.internalQueue.isEmpty
                ? Center(
                    child: Text(
                      'La cola está vacía',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    itemCount: player.internalQueue.length,
                    itemBuilder: (context, index) {
                      final track = player.internalQueue[index];
                      final isPlaying = index == player.currentIndex;

                      return StaggeredItem(
                        index: index,
                        child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isPlaying
                              ? cs.primaryContainer
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 50,
                              height: 50,
                              child: CachedNetworkImage(
                                imageUrl: track.displayImage,
                                fit: BoxFit.cover,
                                placeholder: (_, __) =>
                                    Container(color: cs.surfaceContainer),
                                errorWidget: (_, __, ___) => Container(
                                  color: cs.surfaceContainer,
                                  child: Icon(Icons.music_note,
                                      color: cs.outline),
                                ),
                              ),
                            ),
                          ),
                          title: Text(
                            track.title,
                            style: TextStyle(
                              color: cs.onSurface,
                              fontWeight: isPlaying
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            track.artist,
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                            ),
                            maxLines: 1,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                color: Colors.red,
                                onPressed: () => player.removeFromQueue(index),
                              ),
                              IconButton(
                                icon: const Icon(Icons.play_arrow),
                                color: AppTheme.accent,
                                onPressed: () => player.playFromQueue(index),
                              ),
                            ],
                          ),
                          onTap: () => player.playFromQueue(index),
                        ),
                      ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
