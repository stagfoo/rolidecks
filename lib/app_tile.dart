import 'package:flutter/material.dart';

import 'app_icon.dart';
import 'models.dart';
import 'theme.dart';

/// One app inside a folder.
class AppTile extends StatelessWidget {
  const AppTile({
    super.key,
    required this.app,
    required this.size,
    required this.onTap,
    this.onLongPress,
    this.accent,
    this.filed = false,
  });

  final LaunchableApp app;
  final double size;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Color? accent;

  /// Whether this app is filed on some card. Shown in the all-apps grid so it
  /// is obvious what still needs a home.
  final bool filed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              AppIconImage(app: app, size: size),
              if (filed)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: accent ?? DeckColors.textDim,
                      shape: BoxShape.circle,
                      border: Border.all(color: DeckColors.ground, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: size + 16,
            child: Text(
              app.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10.5, color: DeckColors.textDim),
            ),
          ),
        ],
      ),
    );
  }
}
