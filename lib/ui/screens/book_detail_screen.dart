import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/models/book.dart';
import '../../data/models/reading_status.dart';
import '../../providers/book_providers.dart';
import '../../ui/theme/app_colors.dart';

/// Book detail screen for viewing, editing, rating, and managing a book.
///
/// Supports both "newly scanned" books and existing library books.
class BookDetailScreen extends ConsumerStatefulWidget {
  final Book book;

  const BookDetailScreen({super.key, required this.book});

  @override
  ConsumerState<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends ConsumerState<BookDetailScreen> {
  late Book _book;
  late ReadingStatus _selectedStatus;
  late double _rating;
  late TextEditingController _notesController;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _book = widget.book;
    _selectedStatus = ReadingStatus.fromString(_book.status);
    _rating = _book.rating ?? 0.0;
    _notesController = TextEditingController(text: _book.notes ?? '');
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          SliverToBoxAdapter(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 320,
      pinned: true,
      backgroundColor: AppColors.background,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.6),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back_rounded, size: 20),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.background.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.share_rounded, size: 20),
          ),
          onPressed: _shareBook,
        ),
        if (_book.id != null)
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline_rounded,
                  size: 20, color: AppColors.error),
            ),
            onPressed: _confirmDelete,
          ),
        const SizedBox(width: 8),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Blurred background cover
            if (_book.coverUrl != null)
              CachedNetworkImage(
                imageUrl: _book.coverUrl!,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => Container(
                  color: AppColors.surfaceLight,
                ),
              ),
            // Blur + dark overlay
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.background.withValues(alpha: 0.3),
                      AppColors.background.withValues(alpha: 0.8),
                      AppColors.background,
                    ],
                  ),
                ),
              ),
            ),
            // Cover image centered
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 60, bottom: 20),
                child: Hero(
                  tag: 'book-cover-${_book.isbn}',
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _book.coverUrl != null
                          ? CachedNetworkImage(
                              imageUrl: _book.coverUrl!,
                              height: 200,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) =>
                                  _buildCoverPlaceholder(),
                            )
                          : _buildCoverPlaceholder(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverPlaceholder() {
    return Container(
      width: 140,
      height: 200,
      color: AppColors.surfaceLight,
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.menu_book_rounded, color: AppColors.textMuted, size: 40),
          SizedBox(height: 8),
          Text('No Cover', style: TextStyle(color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            _book.title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          if (_book.subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              _book.subtitle!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 16,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 8),

          // Authors
          if (_book.authors != null)
            Text(
              'by ${_book.authors}',
              style: const TextStyle(
                color: AppColors.secondary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          const SizedBox(height: 20),

          // ── Rating Section ──
          _buildSection(
            'Your Rating',
            child: RatingBar.builder(
              initialRating: _rating,
              minRating: 0,
              direction: Axis.horizontal,
              allowHalfRating: true,
              itemCount: 5,
              itemSize: 36,
              unratedColor: AppColors.surfaceLight,
              glowColor: AppColors.primary.withValues(alpha: 0.3),
              itemBuilder: (context, _) => const Icon(
                Icons.star_rounded,
                color: AppColors.primary,
              ),
              onRatingUpdate: (rating) {
                setState(() {
                  _rating = rating;
                  _hasChanges = true;
                });
              },
            ),
          ),

          // ── Reading Status Section ──
          _buildSection(
            'Reading Status',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ReadingStatus.values.map((status) {
                return ChoiceChip(
                  avatar: Icon(status.icon, size: 18, color: status.color),
                  label: Text(status.label),
                  selected: _selectedStatus == status,
                  onSelected: (_) => _onStatusChanged(status),
                  selectedColor: status.color.withValues(alpha: 0.2),
                  checkmarkColor: status.color,
                  labelStyle: TextStyle(
                    color: _selectedStatus == status
                        ? status.color
                        : AppColors.textSecondary,
                    fontWeight: _selectedStatus == status
                        ? FontWeight.w600
                        : FontWeight.w400,
                    fontSize: 13,
                  ),
                  side: BorderSide(
                    color: _selectedStatus == status
                        ? status.color.withValues(alpha: 0.5)
                        : AppColors.surfaceBorder,
                  ),
                  backgroundColor: AppColors.surface,
                );
              }).toList(),
            ),
          ),

          // ── Metadata Section ──
          _buildSection(
            'Details',
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: Column(
                children: [
                  _buildMetaRow('ISBN', _book.isbn),
                  if (_book.publisher != null)
                    _buildMetaRow('Publisher', _book.publisher!),
                  if (_book.publishedDate != null)
                    _buildMetaRow('Published', _book.publishedDate!),
                  if (_book.pageCount != null)
                    _buildMetaRow('Pages', '${_book.pageCount}'),
                  if (_book.categories != null)
                    _buildMetaRow('Categories', _book.categories!),
                  _buildMetaRow('Added',
                      DateFormat.yMMMd().format(_book.dateAdded)),
                  if (_book.dateStarted != null)
                    _buildMetaRow('Started',
                        DateFormat.yMMMd().format(_book.dateStarted!)),
                  if (_book.dateFinished != null)
                    _buildMetaRow('Finished',
                        DateFormat.yMMMd().format(_book.dateFinished!)),
                ],
              ),
            ),
          ),

          // ── Description Section ──
          if (_book.description != null)
            _buildSection(
              'Description',
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: Text(
                  _book.description!,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
              ),
            ),

          // ── Notes Section ──
          _buildSection(
            'Your Notes',
            child: TextField(
              controller: _notesController,
              maxLines: 4,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
              ),
              decoration: const InputDecoration(
                hintText: 'Add your thoughts about this book...',
              ),
              onChanged: (_) => setState(() => _hasChanges = true),
            ),
          ),

          const SizedBox(height: 20),

          // Save button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _hasChanges ? _saveChanges : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                disabledBackgroundColor: AppColors.surfaceLight,
              ),
              child: Text(
                _book.id == null ? 'Add to Library' : 'Save Changes',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSection(String title, {required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
              ),
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

  void _onStatusChanged(ReadingStatus status) {
    setState(() {
      _selectedStatus = status;
      _hasChanges = true;

      // Auto-set dates based on status
      if (status == ReadingStatus.reading && _book.dateStarted == null) {
        _book = _book.copyWith(dateStarted: DateTime.now());
      }
      if (status == ReadingStatus.completed && _book.dateFinished == null) {
        _book = _book.copyWith(
          dateFinished: DateTime.now(),
          dateStarted: _book.dateStarted ?? DateTime.now(),
        );
      }
    });
  }

  Future<void> _saveChanges() async {
    final updatedBook = _book.copyWith(
      status: _selectedStatus.name,
      rating: _rating,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );

    final notifier = ref.read(bookListProvider.notifier);

    if (updatedBook.id == null) {
      await notifier.addBook(updatedBook);
    } else {
      await notifier.updateBook(updatedBook);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            updatedBook.id == null
                ? '${updatedBook.title} added to library!'
                : 'Changes saved!',
          ),
          backgroundColor: AppColors.success,
        ),
      );
      setState(() => _hasChanges = false);
    }
  }

  void _shareBook() {
    final text = StringBuffer()
      ..writeln('📖 ${_book.title}')
      ..writeln('by ${_book.authors ?? "Unknown Author"}')
      ..writeln('ISBN: ${_book.isbn}');

    if (_rating > 0) {
      text.writeln('⭐ ${_rating.toStringAsFixed(1)}/5.0');
    }
    text.writeln('Status: ${_selectedStatus.label}');

    Share.share(text.toString());
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Delete Book',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'Remove "${_book.title}" from your library? This cannot be undone.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              navigator.pop(); // Close dialog
              if (_book.id != null) {
                await ref
                    .read(bookListProvider.notifier)
                    .deleteBook(_book.id!);
              }
              if (mounted) navigator.pop(); // Close detail screen
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
