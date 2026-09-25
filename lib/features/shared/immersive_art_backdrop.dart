import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Artwork-led header used by catalog pages. Only the blurred artwork shows,
/// fading seamlessly into the page surface so there is no hard cut.
class ImmersiveArtBackdrop extends StatelessWidget {
  final String? imageUrl;
  final bool isDark;

  const ImmersiveArtBackdrop({
    super.key,
    required this.imageUrl,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final hasArtwork = imageUrl != null && imageUrl!.isNotEmpty;
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasArtwork)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
              child: Transform.scale(
                scale: 1.12,
                child: CachedNetworkImage(imageUrl: imageUrl!, fit: BoxFit.cover),
              ),
            )
          else
            Container(color: isDark ? Colors.black : Theme.of(context).scaffoldBackgroundColor),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  isDark ? Colors.black : Theme.of(context).scaffoldBackgroundColor,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
