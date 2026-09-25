import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/local_library_service.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/models/models.dart';

import '../shared/track_list_tile.dart';
import '../shared/staggered_item.dart';
import '../shared/batch_download_dialog.dart';
import '../../core/services/addon_service.dart';
import '../../core/utils/app_toast.dart';

class FavouritesScreen extends StatefulWidget {
  const FavouritesScreen({super.key});

  @override
  State<FavouritesScreen> createState() => _FavouritesScreenState();
}

class _FavouritesScreenState extends State<FavouritesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LocalLibraryService>().getFavourites();
    });
  }

  @override
  Widget build(BuildContext context) {
    final localLibrary = context.watch<LocalLibraryService>();
    final player = context.read<AudioPlayerService>();
    final cs = Theme.of(context).colorScheme;
    
    final favourites = localLibrary.getFavourites();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (favourites.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.play_arrow_rounded),
                  iconSize: 40,
                  color: AppTheme.accent,
                  onPressed: () => player.playAll(favourites),
                ),
              IconButton(
                icon: const Icon(Icons.download_rounded),
                color: cs.onSurfaceVariant,
                tooltip: 'Download All Favourites',
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => BatchDownloadDialog(tracks: favourites),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.cloud_upload_rounded),
                color: AppTheme.accent,
                tooltip: 'Sync to Cloud',
                onPressed: () => _handleSync(context, favourites),
              ),
            ],
          ),
        ),
        
        Expanded(
          child: favourites.isEmpty
              ? _buildEmptyState(context)
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  itemCount: favourites.length,
                  itemBuilder: (context, index) {
                    return StaggeredItem(
                      index: index,
                      child: TrackListTile(
                        track: favourites[index],
                        tracks: favourites,
                        index: index,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _handleSync(BuildContext context, List<Track> favourites) async {
    final addonService = context.read<AddonService>();
    
    if (!addonService.supportsLibrary) {
      AppToast.show(context, 'No cloud sync addon active', isError: true);
      return;
    }

    if (!context.mounted) return;
    AppToast.show(context, 'Starting sync...');

    final libraries = await addonService.getLibraries();
    
    if (!context.mounted) return;

    if (libraries.isEmpty) {
      final success = await addonService.createLibrary('My Favourites');
      if (success) {
        final newLibs = await addonService.getLibraries();
        if (newLibs.isNotEmpty) {
          await _performSync(context, newLibs.first.id, favourites);
        }
      } else {
        AppToast.show(context, 'Failed to create cloud library', isError: true);
      }
    } else {
      await _performSync(context, libraries.first.id, favourites);
    }
  }

  Future<void> _performSync(BuildContext context, String libraryId, List<Track> tracks) async {
    final addonService = context.read<AddonService>();
    final success = await addonService.addTracksToLibrary(libraryId, tracks);
    
    if (context.mounted) {
      AppToast.show(
        context,
        success ? 'Sync successful!' : 'Sync failed',
        isError: !success,
      );
    }
  }

  Widget _buildEmptyState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.favorite_border,
            size: 80,
            color: cs.outline,
          ),
          const SizedBox(height: 20),
          Text(
            'No liked songs yet',
            style: text.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Like songs to see them here',
            style: text.bodyMedium,
          ),
        ],
      ),
    );
  }
}
