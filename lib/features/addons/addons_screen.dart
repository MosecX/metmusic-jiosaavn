import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/models/addon_models.dart';
import '../../core/services/addon_service.dart';
import '../shared/staggered_item.dart';
import 'package:url_launcher/url_launcher.dart';
import 'addon_install_dialog.dart';

class AddonsScreen extends StatelessWidget {
  const AddonsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final addonService = context.watch<AddonService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Addons'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Install Addon',
            onPressed: () => AddonInstallDialog.show(context),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!addonService.installedAddons.any((a) => a.id == 'io.thevolecitor.metmusic-sync'))
            _buildSyncSetupWidget(context),
          Expanded(
            child: addonService.installedAddons.isEmpty
                ? _buildEmptyState(context)
                : _buildAddonsList(context, addonService),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncSetupWidget(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusDefault),
        border: Border.all(color: AppTheme.accent, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_sync, color: AppTheme.accent, size: 36),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('MetMusic Sync', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text('Sync favourites across devices.', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              launchUrl(Uri.parse('https://metmusic-sync-addon.thevolecitor.qzz.io'));
            },
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('Setup', style: TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.extension_off,
              size: 64, color: cs.outline),
          const SizedBox(height: 16),
          Text(
            'No addons installed',
            style: text.headlineSmall,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => AddonInstallDialog.show(context),
            icon: const Icon(Icons.add),
            label: const Text('Install Addon'),
          ),
        ],
      ),
    );
  }

  Widget _buildAddonsList(
      BuildContext context, AddonService addonService) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: addonService.installedAddons.length,
      itemBuilder: (context, index) {
        final addon = addonService.installedAddons[index];
        final isActive = addonService.activeAddonId == addon.id;
        
        return StaggeredItem(
          index: index,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _AddonCard(
              addon: addon,
              isActive: isActive,
              onSetActive: () => addonService.setActiveAddon(addon.id),
              onUninstall: () => _confirmUninstall(context, addonService, addon),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmUninstall(
      BuildContext context, AddonService addonService, AddonManifest addon) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Uninstall Addon'),
        content: Text('Are you sure you want to uninstall ${addon.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Uninstall'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      try {
        await addonService.uninstallAddon(addon.id);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${e.toString()}')),
          );
        }
      }
    }
  }
}

class _AddonCard extends StatelessWidget {
  final AddonManifest addon;
  final bool isActive;
  final VoidCallback onSetActive;
  final VoidCallback onUninstall;

  const _AddonCard({
    required this.addon,
    required this.isActive,
    required this.onSetActive,
    required this.onUninstall,
  });

  @override
  Widget build(BuildContext context) {
    final addonService = context.read<AddonService>();
    final injectedWidget =
        addonService.getUserAddonHandler(addon.id)?.buildAddonPageWidget(context);
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusDefault),
        border: Border.all(
          color: isActive
              ? AppTheme.accent
              : cs.outline,
          width: isActive ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isActive)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.accent,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                ),
              ),
              child: Center(
                child: Text(
                  'ACTIVE SEARCH PROVIDER',
                  style: TextStyle(
                    color: cs.onPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: addon.icon != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(addon.icon!, fit: BoxFit.cover),
                            )
                          : const Icon(Icons.extension, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            addon.name,
                            style: text.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.accent.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  addon.addonTypeLabel,
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.accent),
                                ),
                              ),
                              if (addon.supportsSync) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'LIBRARY',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue),
                                  ),
                                ),
                              ],
                              const SizedBox(width: 8),
                              Text(
                                'v${addon.version}',
                                style: text.bodySmall,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (addon.description != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    addon.description!,
                    style: text.bodyMedium,
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: addon.resources.map((res) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        res.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    );
                  }).toList(),
                ),
                
                if (injectedWidget != null) ...[
                  const SizedBox(height: 16),
                  injectedWidget,
                ],
                
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!addon.isBuiltIn)
                      TextButton.icon(
                        onPressed: onUninstall,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Uninstall'),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                      ),
                    const SizedBox(width: 8),
                    if (!isActive && addon.supportsSearch)
                      ElevatedButton(
                        onPressed: onSetActive,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.surfaceContainerHigh,
                          foregroundColor: cs.onSurface,
                          elevation: 0,
                        ),
                        child: const Text('Set Active'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
