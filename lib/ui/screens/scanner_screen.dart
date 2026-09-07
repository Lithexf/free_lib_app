import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../data/services/isbn_validator.dart';
import '../../providers/book_providers.dart';
import '../../ui/theme/app_colors.dart';
import '../widgets/scan_overlay.dart';
import 'book_detail_screen.dart';

/// Full-screen barcode scanner for ISBN detection.
///
/// Features:
/// - Camera preview with custom scan overlay
/// - Torch toggle, camera flip
/// - Debounced scan detection
/// - Manual ISBN entry fallback
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  MobileScannerController? _controller;
  bool _isProcessing = false;
  bool _hasPermission = false;
  bool _permissionChecked = false;
  final _manualIsbnController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final status = await Permission.camera.request();
    setState(() {
      _hasPermission = status.isGranted;
      _permissionChecked = true;
      if (_hasPermission) {
        _controller = MobileScannerController(
          detectionSpeed: DetectionSpeed.normal,
          facing: CameraFacing.back,
          torchEnabled: false,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    _manualIsbnController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_permissionChecked) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (!_hasPermission) {
      return _buildPermissionDenied();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview
          MobileScanner(
            controller: _controller!,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.error, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        'Scanner Error\n\n${error.errorDetails?.message ?? "Please ensure camera permissions are granted and Google Play Services is up to date."}',
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Scan overlay
          const ScanOverlay(),

          // Top bar with controls
          _buildTopBar(),

          // Bottom bar with manual entry
          _buildBottomBar(),

          // Processing indicator
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.primary),
                    SizedBox(height: 16),
                    Text(
                      'Looking up book...',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Back button
            _buildCircleButton(
              icon: Icons.arrow_back_rounded,
              onPressed: () => Navigator.pop(context),
            ),
            const Spacer(),
            // Torch toggle
            _buildCircleButton(
              icon: Icons.flash_on_rounded,
              onPressed: () => _controller?.toggleTorch(),
            ),
            const SizedBox(width: 12),
            // Camera flip
            _buildCircleButton(
              icon: Icons.cameraswitch_rounded,
              onPressed: () => _controller?.switchCamera(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.6),
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: IconButton(
        icon: Icon(icon, color: AppColors.textPrimary, size: 22),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              AppColors.background.withValues(alpha: 0.9),
              AppColors.background,
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Or enter ISBN manually',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manualIsbnController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9Xx-]')),
                      ],
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'e.g. 978-0-14-028329-7',
                        prefixIcon: const Icon(
                          Icons.keyboard_rounded,
                          color: AppColors.textMuted,
                        ),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: AppColors.surfaceBorder),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _onManualSubmit,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                    ),
                    child: const Icon(Icons.search_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionDenied() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Scanner'),
        backgroundColor: AppColors.background,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.error.withValues(alpha: 0.1),
                ),
                child: const Icon(
                  Icons.camera_alt_outlined,
                  size: 48,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Camera Permission Required',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'FreeLib needs camera access to scan book barcodes. You can also enter ISBNs manually below.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => openAppSettings(),
                child: const Text('Open Settings'),
              ),
              const SizedBox(height: 32),
              // Manual ISBN entry fallback
              const Divider(),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _manualIsbnController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        hintText: 'Enter ISBN manually',
                        prefixIcon:
                            Icon(Icons.keyboard_rounded, color: AppColors.textMuted),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _onManualSubmit,
                    child: const Icon(Icons.search_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Handle barcode detection from camera
  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;

    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue == null) continue;

      final isbn = IsbnValidator.normalize(rawValue);
      if (isbn != null) {
        _processIsbn(isbn);
        return;
      }
    }
  }

  /// Handle manual ISBN submission
  void _onManualSubmit() {
    final text = _manualIsbnController.text.trim();
    if (text.isEmpty) return;

    final isbn = IsbnValidator.normalize(text);
    if (isbn == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid ISBN. Please check and try again.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    _processIsbn(isbn);
  }

  /// Look up ISBN and navigate to detail screen
  Future<void> _processIsbn(String isbn) async {
    if (_isProcessing) return;

    // Check for duplicate scan
    final existingBooks = ref.read(bookListProvider).valueOrNull ?? [];
    if (existingBooks.any((b) => b.isbn == isbn)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You already scanned this book!'),
          backgroundColor: AppColors.accent,
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      // Pause scanner while processing
      _controller?.stop();

      final book = await ref.read(bookListProvider.notifier).scanAndAdd(isbn);

      if (!mounted) return;

      if (book != null) {
        // Navigate to book detail
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => BookDetailScreen(book: book),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not find book info for this ISBN.'),
            backgroundColor: AppColors.error,
          ),
        );
        _controller?.start();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
        _controller?.start();
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }
}
