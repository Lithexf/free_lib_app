import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/models/book.dart';
import '../../data/models/reading_status.dart';
import '../../data/services/app_exceptions.dart';
import '../../providers/book_providers.dart';
import '../theme/app_colors.dart';
import 'add_book_screen.dart';

/// Egyszerű, átlátható könyvadatlap olvasási állapottal, haladással, értékeléssel és jegyzettel.
class BookDetailScreen extends ConsumerStatefulWidget {
  final Book book;
  final bool isNewlyScanned;

  const BookDetailScreen({
    super.key,
    required this.book,
    this.isNewlyScanned = false,
  });

  @override
  ConsumerState<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends ConsumerState<BookDetailScreen> {
  late Book _book;
  late ReadingStatus _selectedStatus;
  late double _rating;
  late int _currentPage;
  late TextEditingController _notesController;
  bool _hasChanges = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _syncFromBook(widget.book);
    _notesController = TextEditingController(text: _book.notes ?? '');
    // Esetleges korábbi képernyőről maradt lebegő értesítések eltávolítása,
    // hogy semmi se takarja ki az alsó mentés / hozzáadás gombot.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
      }
    });
  }

  void _syncFromBook(Book book) {
    _book = book;
    _selectedStatus = ReadingStatus.fromString(book.status);
    _rating = book.rating ?? 0.0;
    final total = book.pageCount ?? 0;
    if (book.status == ReadingStatus.completed.name && total > 0) {
      _currentPage = total;
    } else {
      _currentPage =
          (book.currentPage ?? 0).clamp(0, total > 0 ? total : 999999);
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    try {
      return DateFormat.yMMMd('hu').format(date);
    } catch (_) {
      return DateFormat('yyyy. MM. dd.').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (_hasChanges || _book.id == null) {
          await _saveChanges(silent: true);
        }
        if (mounted) {
          navigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Könyv adatlap'),
          actions: [
            if (_book.id != null)
              IconButton(
                tooltip: 'Szerkesztés',
                icon: const Icon(Icons.edit),
                onPressed: _editBookMetadata,
              ),
            IconButton(
              tooltip: 'Megosztás',
              icon: const Icon(Icons.share),
              onPressed: _shareBook,
            ),
            if (_book.id != null)
              IconButton(
                tooltip: 'Törlés',
                icon: const Icon(Icons.delete_outline, color: AppColors.error),
                onPressed: _confirmDelete,
              ),
          ],
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderSection(),
                  const SizedBox(height: 16),
                  _buildStatusCard(),
                  const SizedBox(height: 12),
                  _buildProgressCard(),
                  const SizedBox(height: 12),
                  _buildRatingCard(),
                  const SizedBox(height: 12),
                  _buildDetailsCard(),
                  if (_book.description != null &&
                      _book.description!.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildDescriptionCard(),
                  ],
                  const SizedBox(height: 12),
                  _buildNotesCard(),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving
                          ? null
                          : () => _saveChanges(closeAfterSave: true),
                      child: Text(
                        (_book.id == null || widget.isNewlyScanned)
                            ? 'Hozzáadás a könyvtárhoz'
                            : 'Mentés',
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 100,
            height: 145,
            child: _book.coverUrl != null && _book.coverUrl!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: _book.coverUrl!,
                    fit: BoxFit.cover,
                    memCacheWidth: 320,
                    fadeInDuration: Duration.zero,
                    errorWidget: (_, _, _) => _buildCoverPlaceholder(),
                  )
                : _buildCoverPlaceholder(),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _book.title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (_book.subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  _book.subtitle!,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
              if (_book.authors != null) ...[
                const SizedBox(height: 6),
                Text(
                  _book.authors!,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              if (_book.romajiTitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  _book.romajiTitle!,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCoverPlaceholder() {
    return Container(
      color: AppColors.surfaceLight,
      child: const Center(
        child: Icon(Icons.book, color: AppColors.textMuted, size: 32),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Olvasási állapot',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ReadingStatus.values.map((status) {
                return ChoiceChip(
                  label: Text(status.label),
                  selected: _selectedStatus == status,
                  onSelected: (_) => _onStatusChanged(status),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard() {
    final total = _book.pageCount;
    if (total == null || total <= 0) {
      return Card(
        child: ListTile(
          title: const Text(
            'Olvasási haladás',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            'Nincs megadva oldalszám.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          trailing: _book.id != null
              ? TextButton(
                  onPressed: _editBookMetadata,
                  child: const Text('Megadás'),
                )
              : null,
        ),
      );
    }

    final current = _currentPage.clamp(0, total);
    final pct = (current / total * 100).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  const Text(
                    'Olvasási haladás',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  Text(
                    '$current / $total oldal ($pct%)',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Slider(
              value: current.toDouble(),
              min: 0,
              max: total.toDouble(),
              divisions: total <= 200 ? total : null,
              onChanged: (val) => _updateCurrentPage(val.round()),
            ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _updateCurrentPage(current + 10),
                  child: const Text('+10 oldal'),
                ),
                OutlinedButton(
                  onPressed: () => _updateCurrentPage(total),
                  child: const Text('Kész'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _updateCurrentPage(int newPage) {
    final total = _book.pageCount ?? 0;
    if (total <= 0) return;

    final clamped = newPage.clamp(0, total);
    setState(() {
      _currentPage = clamped;
      _hasChanges = true;
      if (clamped >= total) {
        _selectedStatus = ReadingStatus.completed;
        _book = _book.copyWith(
          dateStarted: _book.dateStarted ?? DateTime.now(),
          dateFinished: _book.dateFinished ?? DateTime.now(),
        );
      } else if (clamped > 0 && _selectedStatus == ReadingStatus.planToRead) {
        _selectedStatus = ReadingStatus.reading;
        _book = _book.copyWith(
          dateStarted: _book.dateStarted ?? DateTime.now(),
        );
      }
    });
  }

  Widget _buildRatingCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Saját értékelés',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                if (_rating > 0) ...[
                  Text(
                    '${_rating.toStringAsFixed(1)} / 5',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _rating = 0.0;
                        _hasChanges = true;
                      });
                    },
                    child: const Text('Törlés'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            KeyedSubtree(
              key: ValueKey(_rating == 0.0 ? 'unrated' : 'rated'),
              child: RatingBar.builder(
                initialRating: _rating,
                minRating: 0,
                allowHalfRating: true,
                glow: false,
                itemCount: 5,
                itemSize: 32,
                unratedColor: AppColors.surfaceLight,
                itemBuilder: (context, _) => const Icon(
                  Icons.star,
                  color: Colors.amber,
                ),
                onRatingUpdate: (val) {
                  setState(() {
                    _rating = val;
                    _hasChanges = true;
                  });
                },
              ),
            ),
            if (_book.externalRating != null && _book.externalRating! > 0) ...[
              const Divider(height: 20),
              Text(
                'Közösségi átlag: ${_book.externalRating!.toStringAsFixed(1)} / 5'
                '${_book.externalRatingSource != null ? " (${_book.externalRatingSource})" : ""}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Adatok',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 8),
            _buildMetaRow(
              'ISBN',
              _book.isManualIsbn ? 'Nincs (kézi)' : _book.isbn,
            ),
            if (_book.publisher != null)
              _buildMetaRow('Kiadó', _book.publisher!),
            if (_book.publishedDate != null)
              _buildMetaRow('Kiadva', _book.publishedDate!),
            if (_book.pageCount != null)
              _buildMetaRow('Oldalszám', '${_book.pageCount}'),
            if (_book.categories != null)
              _buildMetaRow('Kategóriák', _book.categories!),
            _buildMetaRow('Hozzáadva', _formatDate(_book.dateAdded)),
            if (_book.dateStarted != null)
              _buildMetaRow('Elkezdve', _formatDate(_book.dateStarted!)),
            if (_book.dateFinished != null)
              _buildMetaRow('Befejezve', _formatDate(_book.dateFinished!)),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style:
                  const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Leírás',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              _book.description!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Saját jegyzet',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Jegyzet írása a könyvhöz...',
              ),
              onChanged: (_) => setState(() => _hasChanges = true),
            ),
          ],
        ),
      ),
    );
  }

  void _onStatusChanged(ReadingStatus status) {
    setState(() {
      _selectedStatus = status;
      _hasChanges = true;
      if (status == ReadingStatus.reading && _book.dateStarted == null) {
        _book = _book.copyWith(dateStarted: DateTime.now());
      }
      if (status == ReadingStatus.completed) {
        if (_book.pageCount != null && _book.pageCount! > 0) {
          _currentPage = _book.pageCount!;
        }
        if (_book.dateFinished == null) {
          _book = _book.copyWith(
            dateFinished: DateTime.now(),
            dateStarted: _book.dateStarted ?? DateTime.now(),
          );
        }
      }
    });
  }

  Future<void> _editBookMetadata() async {
    if (_hasChanges) {
      await _saveChanges(silent: true);
    }
    if (!mounted) return;
    final edited = await Navigator.push<Book>(
      context,
      MaterialPageRoute(
        builder: (_) => AddBookScreen(bookToEdit: _book),
      ),
    );
    if (edited != null && mounted) {
      setState(() => _syncFromBook(edited));
    }
  }

  Future<void> _saveChanges({
    bool silent = false,
    bool closeAfterSave = false,
  }) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final wasNew = _book.id == null;
    final trimmedNotes = _notesController.text.trim();
    final updatedBook = _book.copyWith(
      status: _selectedStatus.name,
      rating: _rating > 0 ? _rating : null,
      currentPage: _book.pageCount != null ? _currentPage : null,
      notes: trimmedNotes.isEmpty ? null : trimmedNotes,
    );

    try {
      final notifier = ref.read(bookListProvider.notifier);
      final savedBook = wasNew
          ? await notifier.addBook(updatedBook)
          : await notifier.updateBook(updatedBook);

      if (mounted) {
        setState(() {
          _book = savedBook;
          _hasChanges = false;
          _isSaving = false;
        });
        if (closeAfterSave) {
          ScaffoldMessenger.of(context).clearSnackBars();
          final navigator = Navigator.of(context);
          if (navigator.canPop()) {
            navigator.pop(savedBook);
          }
          return;
        }
      }
    } on AppException catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        if (!silent) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(content: Text(e.userMessage)),
            );
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        if (!silent) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              const SnackBar(content: Text('Hiba történt a mentéskor.')),
            );
        }
      }
    }
  }

  void _shareBook() {
    final text = StringBuffer()
      ..writeln(_book.title)
      ..writeln('Szerző: ${_book.authors ?? "Ismeretlen"}');
    if (!_book.isManualIsbn) {
      text.writeln('ISBN: ${_book.isbn}');
    }
    if (_rating > 0) {
      text.writeln('Értékelés: ${_rating.toStringAsFixed(1)} / 5');
    }
    text.writeln('Állapot: ${_selectedStatus.label}');

    SharePlus.instance.share(ShareParams(text: text.toString()));
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Könyv törlése'),
        content: Text('Biztosan törlöd a(z) "${_book.title}" című könyvet?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Mégse'),
          ),
          TextButton(
            onPressed: () async {
              final dialogNav = Navigator.of(dialogContext);
              final pageNav = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              dialogNav.pop();

              try {
                if (_book.id != null) {
                  await ref
                      .read(bookListProvider.notifier)
                      .deleteBook(_book.id!);
                }
                if (mounted) {
                  _hasChanges = false;
                  pageNav.pop();
                }
              } on AppException catch (e) {
                if (mounted) {
                  messenger.showSnackBar(SnackBar(content: Text(e.userMessage)));
                }
              }
            },
            child: const Text(
              'Törlés',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
