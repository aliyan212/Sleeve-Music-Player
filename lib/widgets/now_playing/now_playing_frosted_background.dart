import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';

/// Renders a luxurious frosted glass background using the album artwork
/// scaled, blurred, and layered with a subtle scrim and vignette.
class NowPlayingFrostedBackground extends StatelessWidget {
  final Uint8List? artworkBytes;
  final Color fallbackColor;
  final bool isDark;
  final Widget child;

  const NowPlayingFrostedBackground({
    super.key,
    required this.artworkBytes,
    required this.fallbackColor,
    required this.isDark,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final bytes = artworkBytes;

    final imageWidget = bytes != null && bytes.isNotEmpty
        ? Image.memory(
            bytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
          )
        : null;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Base backing color
        Container(
          color: isDark ? const Color(0xFF0C0D11) : fallbackColor,
        ),

        // Artwork blurred layer
        if (imageWidget != null) ...[
          Positioned.fill(
            child: imageWidget,
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 52, sigmaY: 52),
              child: Container(
                color: (isDark ? Colors.black : Colors.white).withValues(
                  alpha: isDark ? 0.58 : 0.42,
                ),
              ),
            ),
          ),
        ] else
          Positioned.fill(
            child: Container(
              color: isDark ? const Color(0xFF101217) : fallbackColor,
            ),
          ),

        // Subtle gradient vignette for depth
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 1.25,
                  colors: [
                    Colors.transparent,
                    (isDark ? Colors.black : Colors.white).withValues(
                      alpha: isDark ? 0.32 : 0.18,
                    ),
                  ],
                  stops: const [0.5, 1.0],
                ),
              ),
            ),
          ),
        ),

        // Foreground content
        child,
      ],
    );
  }
}
