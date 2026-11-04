import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../data/services/app_exceptions.dart';
import '../../data/services/isbn_validator.dart';
import '../../providers/book_providers.dart';
import '../../providers/database_provider.dart';
import '../../ui/theme/app_colors.dart';
import '../widgets/scan_overlay.dart';
import 'add_book_screen.dart';
import 'book_detail_screen.dart';

/// Full-screen barcode scanner for ISBN detection.
///
/// Features:
/// - Camera preview with custom animated scan overlay
/// - Torch toggle with visual state, camera flip
/// - Debounced scan detection
/// - Manual ISBN entry & fallback to manual book creation when offline or unlisted
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen>
    with WidgetsBindingObserver {
  MobileScannerController? _controller;
  bool _isProcessing = false;
  bool _hasPermission = false;
  bool _permissionChecked = false;
  bool _torchEnabled = false;
  final _manualIsbnController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_hasPermission) {
      _recheckPermissionOnResume();
    }
  }

  Future<void> _recheckPermissionOnResume() async {
    final status = await Permission.camera.status;
    if (!mounted) return;
    if (status.isGranted && !_hasPermission) {
      setState(() {
        _hasPermission = true;
        _controller ??= MobileScannerController(
          detectionSpeed: DetectionSpeed.normal,
          facing: CameraFacing.back,
          torchEnabled: false,
        );
      });
    }
  }

  Future<void> _checkPermission() async {
    try {
      final status = await Permission.camera.request();
      if (!mounted) return;
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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasPermission = false;
        _permissionChecked = true;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
          // Camera preview — fills entire screen
          Positioned.fill(
            child: MobileScanner(
              controller: _controller!,
              onDetect: _onDetect,
              errorBuilder: (context, error) {
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: AppColors.error,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Szkenner hiba\n\n${error.errorDetails?.message ?? "Kérjük, ellenőrizd a kamera engedélyeket és a kamerát."}',
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        OutlinedButton.icon(
                          onPressed: () => _openManualFallback(),
                          icon: const Icon(Icons.edit_note_rounded),
                          label: const Text('Kézi könyvfelvétel megnyitása'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Scan overlay (darkens background, draws animated square frame)
          const Positioned.fill(
            child: ScanOverlay(),
          ),

          // Top bar with controls
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: _buildTopBar(),
          ),

          // Bottom bar with manual entry — anchored to bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomBar(),
          ),

          // Processing indicator
          if (_isProcessing)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppColors.primary),
                      SizedBox(height: 16),
                      Text(
                        'Könyv keresése...',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Back button
            _buildCircleButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Vissza',
              onPressed: () => Navigator.pop(context),
            ),
            const Spacer(),
            // Torch toggle
            _buildCircleButton(
              icon: _torchEnabled
                  ? Icons.flash_on_rounded
                  : Icons.flash_off_rounded,
              tooltip: 'Zseblámpa',
              isActive: _torchEnabled,
              onPressed: () async {
                await _controller?.toggleTorch();
                if (mounted) {
                  setState(() => _torchEnabled = !_torchEnabled);
                }
              },
            ),
            const SizedBox(width: 12),
            // Camera flip
            _buildCircleButton(
              icon: Icons.cameraswitch_rounded,
              tooltip: 'Kamera váltása',
              onPressed: () => _controller?.switchCamera(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool isActive = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.primary.withValues(alpha: 0.85)
            : AppColors.background.withValues(alpha: 0.6),
        shape: BoxShape.circle,
        border: Border.all(
          color: isActive ? AppColors.primary : AppColors.glassBorder,
        ),
      ),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(
          icon,
          color: isActive ? AppColors.background : AppColors.textPrimary,
          size: 22,
        ),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            AppColors.background.withValues(alpha: 0.88),
            AppColors.background,
          ],
          stops: const [0.0, 0.35, 1.0],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Vagy add meg az ISBN-t manuálisan',
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
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _onManualSubmit(),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9Xx-]')),
                          ],
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'pl. 978-0-14-028329-7',
                            prefixIcon: const Icon(
                              Icons.keyboard_rounded,
                              color: AppColors.textMuted,
                            ),
                            filled: true,
                            fillColor: AppColors.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: AppColors.surfaceBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: AppColors.surfaceBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppColors.primary,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 50,
                        width: 50,
                        child: ElevatedButton(
                          onPressed: _onManualSubmit,
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Icon(Icons.search_rounded, size: 24),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: () => _openManualFallback(),
                    icon: const Icon(Icons.travel_explore_rounded, size: 17),
                    label: const Text(
                      'Cím szerinti keresés vagy kézi felvétel',
                      style: TextStyle(fontSize: 13),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primaryLight,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionDenied() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Szkenner'),
        backgroundColor: AppColors.background,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.error.withValues(alpha: 0.1),
                  ),
                  child: const Icon(
                    Icons.camera_alt_outlined,
                    size: 44,
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Kamera engedély szükséges',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'A FreeLib-nek szüksége van a kamera hozzáférésre a vonalkódok szkenneléséhez. Az ISBN-t manuálisan is megadhatod, vagy kereshetsz cím alapján.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => openAppSettings(),
                      icon: const Icon(Icons.settings_rounded),
                      label: const Text('Beállítások megnyitása'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _openManualFallback(tabIndex: 0),
                      icon: const Icon(Icons.travel_explore_rounded),
                      label: const Text('Cím szerinti keresés'),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const Divider(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manualIsbnController,
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _onManualSubmit(),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9Xx-]')),
                        ],
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          hintText: 'ISBN megadása manuálisan',
                          prefixIcon: Icon(
                            Icons.keyboard_rounded,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _onManualSubmit,
                        child: const Icon(Icons.search_rounded),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openManualFallback({String? isbn, int tabIndex = 0}) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => AddBookScreen(
          initialIsbn: isbn,
          initialTabIndex: tabIndex,
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
          content:
              Text('Érvénytelen ISBN. Kérjük, 10 vagy 13 jegyű kódot adj meg.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    _processIsbn(isbn);
  }

  /// Look up ISBN and navigate to detail screen (with offline/unfound fallback)
  Future<void> _processIsbn(String isbn) async {
    if (_isProcessing) return;

    FocusScope.of(context).unfocus();
    setState(() => _isProcessing = true);

    try {
      // Pause scanner while processing
      _controller?.stop();

      // Check for duplicate via database (checks both ISBN-10 and ISBN-13)
      final db = ref.read(databaseProvider);
      final existing = await db.getBookByIsbn(isbn);
      if (existing != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'A(z) „${existing.title}” már a könyvtáradban van!',
              ),
              backgroundColor: AppColors.accent,
              action: SnackBarAction(
                label: 'Megnyitás',
                textColor: AppColors.background,
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BookDetailScreen(book: existing),
                    ),
                  );
                },
              ),
            ),
          );
          _controller?.start();
        }
        return;
      }

      final book = await ref.read(bookListProvider.notifier).scanAndAdd(isbn);

      if (!mounted) return;

      if (book != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => BookDetailScreen(book: book),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Nem található online adat ehhez az ISBN-hez. Felveheted kézzel!',
            ),
            backgroundColor: AppColors.surfaceLight,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Kézi felvétel',
              textColor: AppColors.primary,
              onPressed: () => _openManualFallback(isbn: isbn, tabIndex: 1),
            ),
          ),
        );
        _controller?.start();
      }
    } on AppException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.userMessage),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Kézi felvétel',
              textColor: Colors.white,
              onPressed: () => _openManualFallback(isbn: isbn, tabIndex: 1),
            ),
          ),
        );
        _controller?.start();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Váratlan hiba történt a könyv keresése közben.'),
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
