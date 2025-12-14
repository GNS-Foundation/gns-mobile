/// Movement Required Dialog - Shows when user tries to drop at same location
/// 
/// Location: lib/ui/widgets/movement_dialog.dart

import 'package:flutter/material.dart';

/// Show dialog when breadcrumb drop is rejected due to same location
class MovementRequiredDialog extends StatelessWidget {
  final String title;
  final String message;
  final String? emoji;
  final VoidCallback? onDismiss;

  const MovementRequiredDialog({
    super.key,
    required this.title,
    required this.message,
    this.emoji,
    this.onDismiss,
  });

  /// Show the dialog
  static Future<void> show(
    BuildContext context, {
    required String title,
    required String message,
    String? emoji,
  }) {
    return showDialog(
      context: context,
      builder: (context) => MovementRequiredDialog(
        title: title,
        message: message,
        emoji: emoji,
      ),
    );
  }

  /// Show "same location" dialog
  static Future<void> showSameLocation(BuildContext context) {
    return show(
      context,
      emoji: '📍',
      title: 'Already Here!',
      message: 'You\'re still in the same spot.\n\n'
          'Your identity is built through movement. '
          'Walk to a new location to drop your next breadcrumb.\n\n'
          '🚶 Explore your neighborhood\n'
          '☕ Visit a café\n'
          '🌳 Take a walk in the park',
    );
  }

  /// Show "too close" dialog
  static Future<void> showTooClose(BuildContext context, {int meters = 50}) {
    return show(
      context,
      emoji: '📏',
      title: 'Too Close!',
      message: 'You\'re only ${meters}m from your last breadcrumb.\n\n'
          'Walk at least ${meters} meters to drop another. '
          'Each breadcrumb should mark a meaningful movement in your journey.',
    );
  }

  /// Show "too fast" dialog
  static Future<void> showTooFast(BuildContext context) {
    return show(
      context,
      emoji: '🚀',
      title: 'Whoa, Slow Down!',
      message: 'Your movement speed seems unrealistic.\n\n'
          'Make sure GPS has a good signal and try again in a moment.',
    );
  }

  /// Show "no GPS" dialog
  static Future<void> showNoGps(BuildContext context) {
    return show(
      context,
      emoji: '📡',
      title: 'No GPS Signal',
      message: 'Can\'t determine your location.\n\n'
          '• Make sure Location Services is enabled\n'
          '• Try moving to an open area\n'
          '• Wait for GPS to get a fix',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E2530),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (emoji != null) ...[
            Text(
              emoji!,
              style: const TextStyle(fontSize: 64),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white70,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              onDismiss?.call();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'GOT IT!',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A compact snackbar alternative for rejection messages
class MovementSnackBar {
  static void show(BuildContext context, String message, {String? emoji}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (emoji != null) ...[
              Text(emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E2530),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'OK',
          textColor: const Color(0xFF3B82F6),
          onPressed: () {},
        ),
      ),
    );
  }

  static void showSameLocation(BuildContext context) {
    show(context, 'Move to a new location to drop!', emoji: '📍');
  }

  static void showTooClose(BuildContext context) {
    show(context, 'Walk further to drop another!', emoji: '📏');
  }

  static void showSuccess(BuildContext context, int count) {
    show(context, 'Breadcrumb #$count dropped!', emoji: '🍞');
  }
}

/// Widget showing location diversity stats
class LocationDiversityCard extends StatelessWidget {
  final int totalBreadcrumbs;
  final int uniqueLocations;
  final double trustScore;

  const LocationDiversityCard({
    super.key,
    required this.totalBreadcrumbs,
    required this.uniqueLocations,
    required this.trustScore,
  });

  double get diversity => totalBreadcrumbs > 0 
      ? (uniqueLocations / totalBreadcrumbs * 100) 
      : 0;

  String get diversityRating {
    if (diversity >= 80) return 'Explorer! 🌍';
    if (diversity >= 60) return 'Wanderer 🚶';
    if (diversity >= 40) return 'Moving 👣';
    if (diversity >= 20) return 'Getting Started 📍';
    return 'Stationary 🛋️';
  }

  Color get diversityColor {
    if (diversity >= 80) return Colors.green;
    if (diversity >= 60) return Colors.lightGreen;
    if (diversity >= 40) return Colors.amber;
    if (diversity >= 20) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF161B22),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.explore, color: Color(0xFF3B82F6), size: 20),
                const SizedBox(width: 8),
                const Text(
                  'LOCATION DIVERSITY',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white70,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: diversityColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    diversityRating,
                    style: TextStyle(
                      color: diversityColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatColumn(
                  value: totalBreadcrumbs.toString(),
                  label: 'Total Crumbs',
                ),
                _StatColumn(
                  value: uniqueLocations.toString(),
                  label: 'Unique Places',
                  highlight: true,
                ),
                _StatColumn(
                  value: '${diversity.toStringAsFixed(0)}%',
                  label: 'Diversity',
                  color: diversityColor,
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: diversity / 100,
                backgroundColor: const Color(0xFF30363D),
                valueColor: AlwaysStoppedAnimation(diversityColor),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              diversity >= 50 
                  ? '🎉 Great exploration! Keep discovering new places.'
                  : '💡 Tip: Visit new locations to increase your trust score!',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String value;
  final String label;
  final bool highlight;
  final Color? color;

  const _StatColumn({
    required this.value,
    required this.label,
    this.highlight = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color ?? (highlight ? const Color(0xFF10B981) : const Color(0xFF3B82F6)),
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white54,
          ),
        ),
      ],
    );
  }
}
