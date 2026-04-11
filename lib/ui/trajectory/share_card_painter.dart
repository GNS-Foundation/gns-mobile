/// Trajectory Share Card
///
/// Renders the sci-fi hex grid share card with phantom cartography.
/// Uses CustomPainter for the visual, RepaintBoundary for image capture,
/// and share_plus for sharing to Instagram Stories / X.
///
/// The visual complexity scales with breadcrumb count:
///   Seedling (1-99):      sparse, green-gray, quiet
///   Explorer (100-999):   blue tones, streets appear
///   Navigator (1k-9.9k):  cyan network, dense, alive
///   Trailblazer (10k+):   amber/orange, blazing metropolis
///
/// Privacy: The hex grid is seeded from the user's public key.
///          No geographic data is revealed. Every user gets a unique
///          phantom city that looks different but maps to nothing real.
///
/// Location: lib/ui/trajectory/share_card_painter.dart

import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../core/trajectory/trajectory_service.dart';

// ==================== DATA MODEL ====================

class ShareCardData {
  final String publicKey;
  final String handle;
  final int breadcrumbs;
  final int neighborhoods;
  final int cities;
  final int streakWeeks;
  final String tier;

  ShareCardData({
    required this.publicKey,
    required this.handle,
    required this.breadcrumbs,
    required this.neighborhoods,
    required this.cities,
    required this.streakWeeks,
    required this.tier,
  });
}

// ==================== SEEDED RNG ====================

class SeededRng {
  int _state;

  SeededRng(String seed) : _state = 0 {
    for (int i = 0; i < seed.length; i++) {
      _state = (_state * 31 + seed.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    if (_state == 0) _state = 1;
  }

  double next() {
    _state = (_state ^ (_state >> 16)) & 0x7FFFFFFF;
    _state = (_state * 2246822507) & 0x7FFFFFFF;
    _state = (_state ^ (_state >> 13)) & 0x7FFFFFFF;
    _state = (_state * 3266489909) & 0x7FFFFFFF;
    _state = (_state ^ (_state >> 16)) & 0x7FFFFFFF;
    return _state / 2147483647.0;
  }
}

// ==================== TIER COLORS ====================

class TierTheme {
  final Color accent;
  final Color hexColor;
  final Color particleColor;
  final Color badgeBg;
  final Color badgeBorder;
  final Color badgeText;
  final Color streakColor;

  TierTheme({
    required this.accent,
    required this.hexColor,
    required this.particleColor,
    required this.badgeBg,
    required this.badgeBorder,
    required this.badgeText,
    required this.streakColor,
  });

  static TierTheme forTier(String tier) {
    switch (tier) {
      case 'Trailblazer':
        return TierTheme(
          accent: const Color(0xFFFF8C40),
          hexColor: const Color(0xFFFF6B00),
          particleColor: const Color(0xFFFFB450),
          badgeBg: const Color(0x26FF6B00),
          badgeBorder: const Color(0x80FF6B00),
          badgeText: const Color(0xFFFF8C40),
          streakColor: const Color(0xFFFF6B00),
        );
      case 'Navigator':
        return TierTheme(
          accent: const Color(0xFF00E5CC),
          hexColor: const Color(0xFF00C8B4),
          particleColor: const Color(0xFF00F0DC),
          badgeBg: const Color(0x2600C8B4),
          badgeBorder: const Color(0x6600C8B4),
          badgeText: const Color(0xFF00C8B4),
          streakColor: const Color(0xFFFFAB00),
        );
      case 'Explorer':
        return TierTheme(
          accent: const Color(0xFF6AB4FF),
          hexColor: const Color(0xFF4A9EFF),
          particleColor: const Color(0xFF80C4FF),
          badgeBg: const Color(0x264A9EFF),
          badgeBorder: const Color(0x664A9EFF),
          badgeText: const Color(0xFF4A9EFF),
          streakColor: const Color(0xFFFFAB00),
        );
      default: // Seedling
        return TierTheme(
          accent: const Color(0xFF7AB87A),
          hexColor: const Color(0xFF5A8A5A),
          particleColor: const Color(0xFF90D090),
          badgeBg: const Color(0x1F5A8A5A),
          badgeBorder: const Color(0x595A8A5A),
          badgeText: const Color(0xFF5A8A5A),
          streakColor: const Color(0xFF888888),
        );
    }
  }
}

// ==================== PAINTER ====================

class ShareCardPainter extends CustomPainter {
  final ShareCardData data;
  final double animationPhase; // 0.0–1.0 for animated version, 0.5 for static

  ShareCardPainter({required this.data, this.animationPhase = 0.5});

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width;
    final H = size.height;
    final rng = SeededRng(data.publicKey);
    final complexity = (data.breadcrumbs / 10000.0).clamp(0.0, 1.0);
    final theme = TierTheme.forTier(data.tier);

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, W, H),
      Paint()..color = const Color(0xFF0C1220),
    );

    // Grid lines
    _drawGrid(canvas, W, H, rng, complexity);

    // Phantom streets
    _drawStreets(canvas, W, H, rng, complexity, theme);

    // River
    _drawRiver(canvas, W, H, rng, complexity);

    // Contours
    _drawContours(canvas, W, H, rng, complexity);

    // Building blocks
    _drawBuildings(canvas, W, H, rng, complexity);

    // Hex grid
    _drawHexGrid(canvas, W, H, rng, complexity, theme);

    // Particles (static positions for image export)
    _drawParticles(canvas, W, H, rng, complexity, theme);

    // Bottom gradient for text readability
    _drawGradient(canvas, W, H);

    // Text overlay
    _drawTextOverlay(canvas, W, H, theme);
  }

  void _drawGrid(Canvas canvas, double W, double H, SeededRng rng, double complexity) {
    final paint = Paint()
      ..color = Color.fromRGBO(0, 180, 200, 0.08 + complexity * 0.08)
      ..strokeWidth = 0.4
      ..style = PaintingStyle.stroke;

    final gs = 28.0 + rng.next() * 10 - complexity * 8;
    for (double x = 0; x < W; x += gs) {
      canvas.drawLine(Offset(x, 0), Offset(x, H), paint);
    }
    for (double y = 0; y < H; y += gs) {
      canvas.drawLine(Offset(0, y), Offset(W, y), paint);
    }
  }

  void _drawStreets(Canvas canvas, double W, double H, SeededRng rng, double complexity, TierTheme theme) {
    final streetCount = (4 + complexity * 25).toInt();

    for (int i = 0; i < streetCount; i++) {
      final alpha = 0.06 + rng.next() * 0.08 + complexity * 0.06;
      final strokeW = 0.5 + rng.next() * 1.2 + complexity * 0.8;
      final paint = Paint()
        ..color = Color.fromRGBO(0, 180, 200, alpha * 2.2)
        ..strokeWidth = strokeW
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final path = Path();
      final horiz = i < (streetCount * 0.55).toInt();

      if (horiz) {
        double x = -10 + rng.next() * W * 0.3;
        double y = rng.next() * H;
        path.moveTo(x, y);
        for (int s = 0; s < 8 + (complexity * 6).toInt(); s++) {
          x += 10 + rng.next() * 35;
          y += (rng.next() - 0.5) * 18;
          path.lineTo(x, y);
        }
      } else {
        double x = rng.next() * W;
        double y = -10 + rng.next() * H * 0.3;
        path.moveTo(x, y);
        for (int s = 0; s < 6 + (complexity * 5).toInt(); s++) {
          x += (rng.next() - 0.5) * 22;
          y += 10 + rng.next() * 30;
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  void _drawRiver(Canvas canvas, double W, double H, SeededRng rng, double complexity) {
    final paint = Paint()
      ..color = Color.fromRGBO(0, 130, 220, 0.2 + complexity * 0.15)
      ..strokeWidth = 2.0 + complexity * 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    double rx = W * 0.28 + rng.next() * W * 0.15;
    double ry = -10;
    path.moveTo(rx, ry);
    while (ry < H + 20) {
      rx += (rng.next() - 0.48) * 20;
      ry += 5 + rng.next() * 7;
      path.lineTo(rx, ry);
    }
    canvas.drawPath(path, paint);

    // Tributary (appears at Explorer+)
    if (complexity > 0.1) {
      final tPaint = Paint()
        ..color = Color.fromRGBO(0, 130, 220, 0.06 + complexity * 0.05)
        ..strokeWidth = 1.0 + complexity * 1.0
        ..style = PaintingStyle.stroke;

      final tPath = Path();
      double tx = rx - 10 + rng.next() * 20;
      double ty = H * 0.5;
      tPath.moveTo(tx, ty);
      for (int i = 0; i < 10; i++) {
        tx += (rng.next() - 0.5) * 18;
        ty += 5 + rng.next() * 10;
        tPath.lineTo(tx, ty);
      }
      canvas.drawPath(tPath, tPaint);
    }
  }

  void _drawContours(Canvas canvas, double W, double H, SeededRng rng, double complexity) {
    final count = (2 + complexity * 10).toInt();
    final paint = Paint()
      ..color = Color.fromRGBO(0, 200, 180, 0.07 + complexity * 0.08)
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;

    for (int c = 0; c < count; c++) {
      final cx = W * 0.1 + rng.next() * W * 0.8;
      final cy = H * 0.1 + rng.next() * H * 0.8;
      final ringCount = (2 + complexity * 3).toInt();
      for (int r = 1; r <= ringCount; r++) {
        final rx = 10.0 + r * 12 + rng.next() * 6;
        final ry = rx * (0.5 + rng.next() * 0.35);
        canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
          paint,
        );
      }
    }
  }

  void _drawBuildings(Canvas canvas, double W, double H, SeededRng rng, double complexity) {
    final count = (5 + complexity * 18).toInt();
    final paint = Paint()
      ..color = Color.fromRGBO(0, 180, 170, 0.07 + complexity * 0.06);

    for (int i = 0; i < count; i++) {
      canvas.drawRect(
        Rect.fromLTWH(
          rng.next() * W,
          rng.next() * H,
          6 + rng.next() * 40 + complexity * 20,
          4 + rng.next() * 18 + complexity * 10,
        ),
        paint,
      );
    }
  }

  void _drawHexGrid(Canvas canvas, double W, double H, SeededRng rng, double complexity, TierTheme theme) {
    final hr = 14.0;
    final dx = hr * 1.5;
    final dy = hr * sqrt(3);
    final cols = (W / dx).ceil() + 2;
    final rows = (H / dy).ceil() + 2;

    // Build cells with deterministic random values
    final cells = <_HexCell>[];
    for (int q = 0; q < cols; q++) {
      for (int s = 0; s < rows; s++) {
        cells.add(_HexCell(
          x: q * dx,
          y: s * dy + (q % 2) * dy / 2,
          v: rng.next(),
        ));
      }
    }
    cells.sort((a, b) => a.v.compareTo(b.v));

    final cellPct = 0.03 + complexity * 0.45;
    final visCount = (cells.length * cellPct).toInt();

    for (int i = 0; i < cells.length; i++) {
      final c = cells[i];
      final isVisited = i >= cells.length - visCount;
      final intensity = isVisited ? (i - (cells.length - visCount)) / visCount : 0.0;

      final path = Path();
      for (int k = 0; k < 6; k++) {
        final angle = (60 * k - 30) * pi / 180;
        final hx = c.x + hr * cos(angle);
        final hy = c.y + hr * sin(angle);
        if (k == 0) path.moveTo(hx, hy); else path.lineTo(hx, hy);
      }
      path.close();

      if (isVisited) {
        final Color hexFill;
        final double alpha;

        if (data.breadcrumbs >= 10000) {
          hexFill = Color.fromRGBO(
            (200 + intensity * 55).toInt(),
            (80 + intensity * 40).toInt(),
            (10 + intensity * 20).toInt(),
            1,
          );
          alpha = 0.25 + intensity * 0.65;
        } else if (data.breadcrumbs >= 1000) {
          hexFill = Color.fromRGBO(0, (180 + intensity * 60).toInt(), (220 - intensity * 90).toInt(), 1);
          alpha = 0.25 + intensity * 0.6;
        } else if (data.breadcrumbs >= 100) {
          hexFill = Color.fromRGBO((30 + intensity * 40).toInt(), (130 + intensity * 50).toInt(), (220 - intensity * 20).toInt(), 1);
          alpha = 0.22 + intensity * 0.55;
        } else {
          hexFill = Color.fromRGBO((50 + intensity * 30).toInt(), (120 + intensity * 30).toInt(), (80 + intensity * 20).toInt(), 1);
          alpha = 0.18 + intensity * 0.45;
        }

        canvas.drawPath(path, Paint()..color = hexFill.withOpacity(alpha));
        canvas.drawPath(path, Paint()
          ..color = hexFill.withOpacity((alpha + 0.2).clamp(0, 0.9))
          ..strokeWidth = 0.6
          ..style = PaintingStyle.stroke);
      } else {
        canvas.drawPath(path, Paint()
          ..color = Colors.white.withOpacity(0.015 + complexity * 0.01)
          ..strokeWidth = 0.3
          ..style = PaintingStyle.stroke);
      }
    }

    // Hot cell glow
    final hotCount = max((visCount * 0.1).toInt(), 1);
    final hotCells = cells.sublist(cells.length - hotCount);
    for (final c in hotCells) {
      canvas.drawCircle(
        Offset(c.x, c.y),
        hr * 0.3,
        Paint()..color = theme.particleColor.withOpacity(0.08 + complexity * 0.1),
      );
    }
  }

  void _drawParticles(Canvas canvas, double W, double H, SeededRng rng, double complexity, TierTheme theme) {
    final count = (5 + complexity * 50).toInt();
    for (int i = 0; i < count; i++) {
      final x = rng.next() * W;
      final y = rng.next() * H;
      final sz = 0.8 + rng.next() * 1.5 + complexity * 0.8;
      canvas.drawCircle(
        Offset(x, y),
        sz,
        Paint()..color = theme.particleColor.withOpacity(0.25 + rng.next() * 0.35),
      );
    }
  }

  void _drawGradient(Canvas canvas, double W, double H) {
    final rect = Rect.fromLTWH(0, H * 0.3, W, H * 0.7);
    final gradient = ui.Gradient.linear(
      Offset(0, H * 0.3),
      Offset(0, H),
      [
        const Color(0x000C1220),
        const Color(0x990C1220),
        const Color(0xF20C1220),
      ],
      [0.0, 0.5, 1.0],
    );
    canvas.drawRect(rect, Paint()..shader = gradient);

    // Top gradient
    final topRect = Rect.fromLTWH(0, 0, W, H * 0.1);
    final topGrad = ui.Gradient.linear(
      Offset.zero,
      Offset(0, H * 0.1),
      [const Color(0x660C1220), const Color(0x000C1220)],
    );
    canvas.drawRect(topRect, Paint()..shader = topGrad);
  }

  void _drawTextOverlay(Canvas canvas, double W, double H, TierTheme theme) {
    final bottomPad = 20.0;
    double y = H - bottomPad;

    // Brand
    _drawText(canvas, 'GLOBE CRUMBS', W / 2, y, 8,
      color: Colors.white.withOpacity(0.2), align: TextAlign.center, letterSpacing: 3, mono: true);
    y -= 20;

    // Stats row
    final statsY = y;
    final colW = W / 3;
    _drawText(canvas, '${_formatNum(data.breadcrumbs)}', colW * 0.5, statsY - 14, 18,
      color: theme.accent, mono: true, weight: FontWeight.w500);
    _drawText(canvas, 'CRUMBS', colW * 0.5, statsY + 4, 9,
      color: Colors.white.withOpacity(0.4), letterSpacing: 1.5);

    _drawText(canvas, '${data.neighborhoods}', colW * 1.5, statsY - 14, 18,
      color: theme.accent, mono: true, weight: FontWeight.w500);
    _drawText(canvas, 'HOODS', colW * 1.5, statsY + 4, 9,
      color: Colors.white.withOpacity(0.4), letterSpacing: 1.5);

    _drawText(canvas, '${data.cities}', colW * 2.5, statsY - 14, 18,
      color: theme.accent, mono: true, weight: FontWeight.w500);
    _drawText(canvas, 'CITIES', colW * 2.5, statsY + 4, 9,
      color: Colors.white.withOpacity(0.4), letterSpacing: 1.5);
    y -= 40;

    // Handle
    _drawText(canvas, '@${data.handle}', 20, y, 20,
      color: Colors.white, weight: FontWeight.w500, align: TextAlign.left);
    y -= 24;

    // Streak
    _drawText(canvas, 'week ${data.streakWeeks} streak', 20, y, 11,
      color: theme.streakColor, align: TextAlign.left);
    y -= 24;

    // Tier badge (top right)
    final badgeText = data.tier.toUpperCase();
    final badgePaint = Paint()
      ..color = theme.badgeBg
      ..style = PaintingStyle.fill;
    final badgeBorderPaint = Paint()
      ..color = theme.badgeBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(W - 110, 16, 94, 26),
      const Radius.circular(13),
    );
    canvas.drawRRect(badgeRect, badgePaint);
    canvas.drawRRect(badgeRect, badgeBorderPaint);
    _drawText(canvas, badgeText, W - 63, 29, 10,
      color: theme.badgeText, mono: true, letterSpacing: 1.5);

    // Key signature (top left)
    final sig = '${data.publicKey.substring(0, 8)}...${data.publicKey.substring(data.publicKey.length - 8)}';
    _drawText(canvas, sig, 20, 29, 8,
      color: const Color(0x5900C8B4), mono: true, align: TextAlign.left);
  }

  void _drawText(Canvas canvas, String text, double x, double y, double fontSize, {
    Color color = Colors.white,
    FontWeight weight = FontWeight.w400,
    TextAlign align = TextAlign.center,
    double letterSpacing = 0,
    bool mono = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: weight,
          fontFamily: mono ? 'monospace' : null,
          letterSpacing: letterSpacing,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
    );
    tp.layout();
    final offset = align == TextAlign.center
      ? Offset(x - tp.width / 2, y - tp.height / 2)
      : Offset(x, y - tp.height / 2);
    tp.paint(canvas, offset);
  }

  String _formatNum(int n) {
    if (n >= 10000) return '${(n / 1000).toStringAsFixed(1)}k';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }

  @override
  bool shouldRepaint(covariant ShareCardPainter oldDelegate) {
    return oldDelegate.data.breadcrumbs != data.breadcrumbs ||
           oldDelegate.animationPhase != animationPhase;
  }
}

class _HexCell {
  final double x, y, v;
  _HexCell({required this.x, required this.y, required this.v});
}

// ==================== SHARE CARD WIDGET ====================

class TrajectoryShareCard extends StatelessWidget {
  final ShareCardData data;
  final bool isStory; // true = 9:16, false = 16:9

  const TrajectoryShareCard({
    super.key,
    required this.data,
    this.isStory = true,
  });

  @override
  Widget build(BuildContext context) {
    final width = isStory ? 360.0 : 640.0;
    final height = isStory ? 640.0 : 360.0;

    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: ShareCardPainter(data: data),
        size: Size(width, height),
      ),
    );
  }
}

// ==================== SHARE UTILITY ====================

class TrajectoryShareService {
  static final _cardKey = GlobalKey();

  /// Show a share preview and share as image
  static Future<void> shareCard({
    required BuildContext context,
    required ShareCardData data,
  }) async {
    // Show preview bottom sheet with share button
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _SharePreviewSheet(data: data),
    );
  }

  /// Render the card to PNG and share
  static Future<void> renderAndShare(GlobalKey key, ShareCardData data) async {
    try {
      final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/trajectory_card.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      final text = '@${data.handle} — ${data.tier}\n'
          '${_formatNum(data.breadcrumbs)} breadcrumbs\n'
          'gcrumbs.com/get\n'
          '#TrajectoryMap';

      await Share.shareXFiles(
        [XFile(file.path)],
        text: text,
      );
    } catch (e) {
      debugPrint('Share card error: $e');
    }
  }

  static String _formatNum(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }
}

// ==================== PREVIEW SHEET ====================

class _SharePreviewSheet extends StatefulWidget {
  final ShareCardData data;
  const _SharePreviewSheet({required this.data});

  @override
  State<_SharePreviewSheet> createState() => _SharePreviewSheetState();
}

class _SharePreviewSheetState extends State<_SharePreviewSheet> {
  final _cardKey = GlobalKey();
  bool _isStory = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A14),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Format toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _formatButton('Story', true),
              const SizedBox(width: 12),
              _formatButton('Post', false),
            ],
          ),
          const SizedBox(height: 16),

          // Card preview
          Center(
            child: RepaintBoundary(
              key: _cardKey,
              child: TrajectoryShareCard(
                data: widget.data,
                isStory: _isStory,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Share button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => TrajectoryShareService.renderAndShare(_cardKey, widget.data),
              icon: const Icon(Icons.ios_share, size: 18),
              label: const Text(
                'SHARE',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                  fontSize: 14,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: TierTheme.forTier(widget.data.tier).accent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),

          // Link preview
          const SizedBox(height: 12),
          Text(
            'gcrumbs.com/get',
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }

  Widget _formatButton(String label, bool isStory) {
    final selected = _isStory == isStory;
    return GestureDetector(
      onTap: () => setState(() => _isStory = isStory),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white12 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? Colors.white24 : Colors.white10,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white38,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
