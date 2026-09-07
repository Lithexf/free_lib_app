import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Custom scanner overlay with animated scan window.
///
/// Draws a semi-transparent dark background with a clear scanning window,
/// animated border, and instruction text.
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
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return CustomPaint(
          painter: _ScanOverlayPainter(animationValue: _animation.value),
          child: child,
        );
      },
      child: _buildInstructionText(),
    );
  }

  Widget _buildInstructionText() {
    return SafeArea(
      child: Column(
        children: [
          const Spacer(),
          Container(
            margin: const EdgeInsets.only(bottom: 80),
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
        ],
      ),
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  final double animationValue;

  _ScanOverlayPainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final scanWindowWidth = size.width * 0.7;
    final scanWindowHeight = scanWindowWidth * 0.6;
    final left = (size.width - scanWindowWidth) / 2;
    final top = (size.height - scanWindowHeight) / 2 - 40;

    final scanRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, scanWindowWidth, scanWindowHeight),
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
        Rect.fromLTWH(left + 10, scanLineY, scanWindowWidth - 20, 2),
      )
      ..strokeWidth = 2;

    canvas.drawLine(
      Offset(left + 20, scanLineY),
      Offset(left + scanWindowWidth - 20, scanLineY),
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
    return oldDelegate.animationValue != animationValue;
  }
}
