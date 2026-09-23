import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Custom scanner overlay with animated scan window.
///
/// Draws a semi-transparent dark background with a clear scanning window,
/// animated border, and instruction text positioned above the window.
class ScanOverlay extends StatefulWidget {
  const ScanOverlay({super.key});

  @override
  State<ScanOverlay> createState() => _ScanOverlayState();
}

class _ScanOverlayState extends State<ScanOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Square scan window — responsive to screen size
        // Use the smaller of width*0.65 or height*0.35 to ensure it fits
        final scanSize = min(constraints.maxWidth * 0.65, constraints.maxHeight * 0.35);

        // Center the scan window vertically, shifted slightly up to leave room
        // for the bottom bar (manual ISBN entry)
        final left = (constraints.maxWidth - scanSize) / 2;
        final top = (constraints.maxHeight - scanSize) / 2 - constraints.maxHeight * 0.08;

        return AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            return CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _ScanOverlayPainter(
                animationValue: _animation.value,
                scanLeft: left,
                scanTop: top,
                scanSize: scanSize,
              ),
              child: child,
            );
          },
          child: _buildInstructionText(top),
        );
      },
    );
  }

  Widget _buildInstructionText(double scanTop) {
    return SafeArea(
      child: Column(
        children: [
          // Position the text above the scan window
          SizedBox(height: max(scanTop - 50, 60)),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.background.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.glassBorder,
              ),
            ),
            child: const Text(
              'Align barcode within the frame',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  final double animationValue;
  final double scanLeft;
  final double scanTop;
  final double scanSize;

  _ScanOverlayPainter({
    required this.animationValue,
    required this.scanLeft,
    required this.scanTop,
    required this.scanSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scanRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(scanLeft, scanTop, scanSize, scanSize),
      const Radius.circular(20),
    );

    // Draw dark overlay with cutout
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutoutPath = Path()..addRRect(scanRect);
    final overlayPath =
        Path.combine(PathOperation.difference, backgroundPath, cutoutPath);

    canvas.drawPath(
      overlayPath,
      Paint()..color = Colors.black.withValues(alpha: 0.6),
    );

    // Draw animated border
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = AppColors.primary
          .withValues(alpha: 0.5 + 0.5 * animationValue);

    canvas.drawRRect(scanRect, borderPaint);

    // Draw corner accents
    _drawCornerAccents(canvas, scanRect, animationValue);

    // Draw scan line
    final scanLineY =
        scanRect.top + 10 + (scanRect.height - 20) * animationValue;
    final scanLinePaint = Paint()
      ..shader = LinearGradient(
        colors: [
          AppColors.primary.withValues(alpha: 0.0),
          AppColors.primary.withValues(alpha: 0.6),
          AppColors.primary.withValues(alpha: 0.0),
        ],
      ).createShader(
        Rect.fromLTWH(scanLeft + 10, scanLineY, scanSize - 20, 2),
      )
      ..strokeWidth = 2;

    canvas.drawLine(
      Offset(scanLeft + 20, scanLineY),
      Offset(scanLeft + scanSize - 20, scanLineY),
      scanLinePaint,
    );
  }

  void _drawCornerAccents(
      Canvas canvas, RRect scanRect, double animationValue) {
    final cornerLength = 30.0;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = AppColors.primary;

    final rect = scanRect.outerRect;
    final r = scanRect.tlRadiusX;

    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(rect.left, rect.top + r + cornerLength)
        ..lineTo(rect.left, rect.top + r)
        ..arcTo(
          Rect.fromLTWH(rect.left, rect.top, r * 2, r * 2),
          pi,
          pi / 2,
          false,
        )
        ..lineTo(rect.left + r + cornerLength, rect.top),
      paint,
    );

    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(rect.right - r - cornerLength, rect.top)
        ..lineTo(rect.right - r, rect.top)
        ..arcTo(
          Rect.fromLTWH(rect.right - r * 2, rect.top, r * 2, r * 2),
          -pi / 2,
          pi / 2,
          false,
        )
        ..lineTo(rect.right, rect.top + r + cornerLength),
      paint,
    );

    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(rect.left, rect.bottom - r - cornerLength)
        ..lineTo(rect.left, rect.bottom - r)
        ..arcTo(
          Rect.fromLTWH(rect.left, rect.bottom - r * 2, r * 2, r * 2),
          pi,
          -pi / 2,
          false,
        )
        ..lineTo(rect.left + r + cornerLength, rect.bottom),
      paint,
    );

    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(rect.right - r - cornerLength, rect.bottom)
        ..lineTo(rect.right - r, rect.bottom)
        ..arcTo(
          Rect.fromLTWH(
              rect.right - r * 2, rect.bottom - r * 2, r * 2, r * 2),
          pi / 2,
          -pi / 2,
          false,
        )
        ..lineTo(rect.right, rect.bottom - r - cornerLength),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanOverlayPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.scanSize != scanSize;
  }
}
