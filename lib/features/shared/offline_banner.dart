import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/connectivity_service.dart';

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final connectivity = context.watch<ConnectivityService>();
    if (connectivity.hasNetwork) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: cs.error,
      child: Row(
        children: [
          Icon(Icons.cloud_off, color: cs.onError, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sin conexión a internet — solo canciones descargadas',
              style: TextStyle(
                color: cs.onError,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
