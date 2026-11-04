import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../data/services/app_exceptions.dart';
import '../../data/services/isbn_validator.dart';
import '../../providers/book_providers.dart';
import '../../providers/database_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/scan_overlay.dart';
import 'add_book_screen.dart';
import 'book_detail_screen.dart';

/// Egyszerű kamerás vonalkódolvasó képernyő kézi ISBN megadási lehetőséggel.
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
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasPermission) {
      return _buildPermissionDenied();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vonalkód szkennelés'),
        actions: [
          IconButton(
            tooltip: 'Zseblámpa',
            icon: Icon(_torchEnabled ? Icons.flash_on : Icons.flash_off),
            onPressed: () async {
              await _controller?.toggleTorch();
              if (mounted) {
                setState(() => _torchEnabled = !_torchEnabled);
              }
            },
          ),
          IconButton(
            tooltip: 'Kamera váltása',
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller?.switchCamera(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: MobileScanner(
                    controller: _controller!,
                    onDetect: _onDetect,
                    errorBuilder: (context, error) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Kamera hiba: ${error.errorDetails?.message ?? "Nem sikerült elindítani a kamerát."}',
                            style:
                                const TextStyle(color: AppColors.textPrimary),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const Positioned.fill(child: ScanOverlay()),
                if (_isProcessing)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
              ],
            ),
          ),
          _buildBottomManualInput(),
        ],
      ),
    );
  }

  Widget _buildBottomManualInput() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.all(14),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manualIsbnController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _onManualSubmit(),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9Xx-]')),
                    ],
                    decoration: const InputDecoration(
                      hintText: 'ISBN megadása kézzel (pl. 9780140283297)',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _onManualSubmit,
                  child: const Text('Keresés'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => _openManualFallback(),
              child: const Text('Cím szerinti keresés vagy kézi felvétel'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionDenied() {
    return Scaffold(
      appBar: AppBar(title: const Text('Vonalkód szkennelés')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.camera_alt_outlined,
                  size: 48,
                  color: AppColors.textMuted,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Kamera engedély szükséges',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'A vonalkód beolvasásához engedélyezd a kamerát, vagy add meg az ISBN számot alább.',
                  style: TextStyle(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () => openAppSettings(),
                      child: const Text('Beállítások'),
                    ),
                    OutlinedButton(
                      onPressed: () => _openManualFallback(tabIndex: 0),
                      child: const Text('Keresés cím alapján'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manualIsbnController,
                        onSubmitted: (_) => _onManualSubmit(),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9Xx-]')),
                        ],
                        decoration: const InputDecoration(
                          hintText: 'ISBN megadása kézzel',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _onManualSubmit,
                      child: const Text('Keresés'),
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

  void _onManualSubmit() {
    final text = _manualIsbnController.text.trim();
    if (text.isEmpty) return;

    final isbn = IsbnValidator.normalize(text);
    if (isbn == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Érvénytelen ISBN szám.')),
      );
      return;
    }

    _processIsbn(isbn);
  }

  Future<void> _processIsbn(String isbn) async {
    if (_isProcessing) return;

    FocusScope.of(context).unfocus();
    setState(() => _isProcessing = true);

    try {
      _controller?.stop();

      final db = ref.read(databaseProvider);
      final existing = await db.getBookByIsbn(isbn);
      if (existing != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Már a könyvtárban van: ${existing.title}'),
              action: SnackBarAction(
                label: 'Megnyitás',
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
          MaterialPageRoute(builder: (_) => BookDetailScreen(book: book)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Nem található online adat ehhez az ISBN-hez.'),
            action: SnackBarAction(
              label: 'Kézi felvétel',
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
            action: SnackBarAction(
              label: 'Kézi felvétel',
              onPressed: () => _openManualFallback(isbn: isbn, tabIndex: 1),
            ),
          ),
        );
        _controller?.start();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hiba történt a keresés közben.')),
        );
        _controller?.start();
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
}
