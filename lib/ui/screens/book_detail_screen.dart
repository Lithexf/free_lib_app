import 'dart:ui';
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
import '../../ui/theme/app_colors.dart';
import 'add_book_screen.dart';

/// Book detail screen for viewing, editing, rating, tracking reading progress,
/// and managing a book in the user's library.
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
  late int _currentPage;
  late TextEditingController _notesController;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _syncFromBook(widget.book);
    _notesController = TextEditingController(text: _book.notes ?? '');
  }

  void _syncFromBook(Book book) {
    _book = book;
    _selectedStatus = ReadingStatus.fromString(book.status);
    _rating = book.rating ?? 0.0;
    final total = book.pageCount ?? 0;
    if (book.status == ReadingStatus.completed.name && total > 0) {
      _currentPage = total;
    } else {
      _currentPage = (book.currentPage ?? 0).clamp(0, total > 0 ? total : 999999);
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
        if (_hasChanges) {
          await _saveChanges(silent: true);
        }
        if (mounted) {
          navigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: CustomScrollView(
          slivers: [
            _buildSliverAppBar(),
            SliverToBoxAdapter(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: _buildBody(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 300,
      pinned: true,
      backgroundColor: AppColors.background,
      leading: IconButton(
        tooltip: 'Vissza',
        icon: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.6),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back_rounded, size: 20),
        ),
        onPressed: () async {
          final navigator = Navigator.of(context);
          if (_hasChanges) {
            await _saveChanges(silent: true);
          }
          if (mounted) navigator.pop();
        },
      ),
      actions: [
        if (_book.id != null)
          IconButton(
            tooltip: 'Adatok szerkesztése',
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.edit_outlined, size: 20),
            ),
            onPressed: _editBookMetadata,
          ),
        IconButton(
          tooltip: 'Megosztás',
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
            tooltip: 'Könyv törlése',
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: AppColors.error,
              ),
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
            if (_book.coverUrl != null && _book.coverUrl!.isNotEmpty)
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
                padding: const EdgeInsets.only(top: 56, bottom: 16),
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
                      child: _book.coverUrl != null &&
                              _book.coverUrl!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: _book.coverUrl!,
                              height: 190,
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
      width: 135,
      height: 190,
      color: AppColors.surfaceLight,
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.menu_book_rounded, color: AppColors.textMuted, size: 40),
          SizedBox(height: 8),
          Text('Nincs borító', style: TextStyle(color: AppColors.textMuted)),
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
          if (_book.romajiTitle != null) ...[
            const SizedBox(height: 4),
            Text(
              _book.romajiTitle!,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (_book.originalTitle != null) ...[
            const SizedBox(height: 4),
            Text(
              _book.originalTitle!,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 14,
              ),
            ),
          ],
          const SizedBox(height: 8),

          // Authors
          if (_book.authors != null)
            Text(
              'Szerző: ${_book.authors}',
              style: const TextStyle(
                color: AppColors.secondaryLight,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          if (_book.originalAuthor != null)
            Text(
              _book.originalAuthor!,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
              ),
            ),
          const SizedBox(height: 20),

          // ── Reading Status Section ──
          _buildSection(
            'Olvasási állapot',
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

          // ── Reading Progress Section ──
          _buildSection(
            'Olvasási haladás',
            child: _buildProgressCard(),
          ),

          // ── Rating Section ──
          _buildSection(
            'Értékelések',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // User's personal rating
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.surfaceBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.person_rounded,
                            color: AppColors.primary,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Saját értékelés',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (_rating > 0) ...[
                            Text(
                              _rating.toStringAsFixed(1),
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: 'Értékelés törlése',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(
                                Icons.restart_alt_rounded,
                                size: 18,
                                color: AppColors.textMuted,
                              ),
                              onPressed: () {
                                setState(() {
                                  _rating = 0.0;
                                  _hasChanges = true;
                                });
                              },
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      KeyedSubtree(
                        key: ValueKey(_rating == 0.0 ? 'unrated' : 'rated'),
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
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Community / External rating
                _buildCommunityRatingCard(),
              ],
            ),
          ),

          // ── Metadata Section ──
          _buildSection(
            'Részletek',
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: Column(
                children: [
                  _buildMetaRow(
                    'ISBN',
                    _book.isManualIsbn ? 'Kézi rögzítés (nincs ISBN)' : _book.isbn,
                  ),
                  if (_book.publisher != null)
                    _buildMetaRow('Kiadó', _book.publisher!),
                  if (_book.publishedDate != null)
                    _buildMetaRow('Kiadva', _book.publishedDate!),
                  if (_book.pageCount != null)
                    _buildMetaRow('Oldalszám', '${_book.pageCount} oldal'),
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
          ),

          // ── Description Section ──
          if (_book.description != null && _book.description!.trim().isNotEmpty)
            _buildSection(
              'Leírás',
              child: Container(
                width: double.infinity,
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
            'Jegyzetek',
            child: TextField(
              controller: _notesController,
              maxLines: 4,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
              ),
              decoration: const InputDecoration(
                hintText: 'Írd le a gondolataidat, kedvenc idézeteidet...',
              ),
              onChanged: (_) => setState(() => _hasChanges = true),
            ),
          ),

          const SizedBox(height: 12),

          // Save button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _hasChanges ? () => _saveChanges() : null,
              icon: const Icon(Icons.check_rounded),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                disabledBackgroundColor: AppColors.surfaceLight,
              ),
              label: Text(
                _book.id == null
                    ? 'Hozzáadás a könyvtárhoz'
                    : 'Változtatások mentése',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildProgressCard() {
    final totalPages = _book.pageCount;
    if (totalPages == null || totalPages <= 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.surfaceBorder),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.menu_book_outlined,
              color: AppColors.textMuted,
              size: 22,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Add meg a könyv oldalszámát az olvasási haladás követéséhez.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
            if (_book.id != null)
              TextButton(
                onPressed: _editBookMetadata,
                child: const Text('Beállítás'),
              ),
          ],
        ),
      );
    }

    final clampedCurrent = _currentPage.clamp(0, totalPages);
    final pct = (clampedCurrent / totalPages * 100).round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.trending_up_rounded,
                color: AppColors.accent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$clampedCurrent / $totalPages oldal',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$pct%',
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.accent,
              inactiveTrackColor: AppColors.surfaceLight,
              thumbColor: AppColors.accent,
              overlayColor: AppColors.accent.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: clampedCurrent.toDouble(),
              min: 0,
              max: totalPages.toDouble(),
              divisions: totalPages,
              onChanged: (val) => _updateCurrentPage(val.round()),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildPageStepChip('-10 oldal', -10),
              _buildPageStepChip('+10 oldal', 10),
              _buildPageStepChip('+25 oldal', 25),
              ActionChip(
                avatar: const Icon(
                  Icons.done_all_rounded,
                  size: 15,
                  color: AppColors.primary,
                ),
                label: const Text('Végigolvastam'),
                onPressed: () => _updateCurrentPage(totalPages),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPageStepChip(String label, int delta) {
    return ActionChip(
      label: Text(label),
      onPressed: () => _updateCurrentPage(_currentPage + delta),
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
            width: 105,
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

  Widget _buildCommunityRatingCard() {
    final extRating = _book.externalRating;
    final extCount = _book.externalRatingCount;
    final extSource = _book.externalRatingSource;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: extRating != null && extRating > 0
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.people_rounded,
                      color: AppColors.secondary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Közösségi értékelés',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    // Source badge
                    if (extSource != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.secondary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          extSource,
                          style: const TextStyle(
                            color: AppColors.secondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),

                // Score + stars row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Big average number
                    Text(
                      extRating.toStringAsFixed(1),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 4),
                      child: Text(
                        '/ 5',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Star visualization
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: List.generate(5, (i) {
                              final starValue = i + 1;
                              if (extRating >= starValue) {
                                return const Icon(Icons.star_rounded,
                                    size: 20, color: AppColors.secondary);
                              } else if (extRating >= starValue - 0.5) {
                                return const Icon(Icons.star_half_rounded,
                                    size: 20, color: AppColors.secondary);
                              } else {
                                return const Icon(Icons.star_rounded,
                                    size: 20, color: AppColors.surfaceLight);
                              }
                            }),
                          ),
                          if (extCount != null && extCount > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              _formatRatingCount(extCount),
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),

                // Comparison hint when user has also rated
                if (_rating > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _rating > extRating
                              ? Icons.arrow_upward_rounded
                              : _rating < extRating
                                  ? Icons.arrow_downward_rounded
                                  : Icons.drag_handle_rounded,
                          size: 16,
                          color: _rating > extRating
                              ? AppColors.accent
                              : _rating < extRating
                                  ? AppColors.error
                                  : AppColors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            (_rating - extRating).abs() < 0.05
                                ? 'Az értékelésed megegyezik a közösségi átlaggal!'
                                : _rating > extRating
                                    ? 'Az értékelésed ${(_rating - extRating).toStringAsFixed(1)} értékkel magasabb az átlagnál'
                                    : 'Az értékelésed ${(extRating - _rating).toStringAsFixed(1)} értékkel alacsonyabb az átlagnál',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            )
          : const Row(
              children: [
                Icon(
                  Icons.people_rounded,
                  color: AppColors.textMuted,
                  size: 18,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Közösségi értékelés',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  'Nem elérhető',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
    );
  }

  String _formatRatingCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M értékelés';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K értékelés';
    }
    return '$count értékelés';
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
      setState(() {
        _syncFromBook(edited);
      });
    }
  }

  Future<void> _saveChanges({bool silent = false}) async {
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
      final Book savedBook;
      if (wasNew) {
        savedBook = await notifier.addBook(updatedBook);
      } else {
        savedBook = await notifier.updateBook(updatedBook);
      }

      if (mounted) {
        setState(() {
          _book = savedBook;
          _hasChanges = false;
        });

        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                wasNew
                    ? '„${savedBook.title}” hozzáadva a könyvtárhoz!'
                    : 'Változtatások elmentve!',
              ),
              backgroundColor: AppColors.success,
            ),
          );
        }
      }
    } on AppException catch (e) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.userMessage),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (_) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nem sikerült elmenteni a módosításokat.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _shareBook() {
    final text = StringBuffer()
      ..writeln('📖 ${_book.title}')
      ..writeln('Szerző: ${_book.authors ?? "Ismeretlen szerző"}');

    if (!_book.isManualIsbn) {
      text.writeln('ISBN: ${_book.isbn}');
    }
    if (_rating > 0) {
      text.writeln('⭐ Saját értékelés: ${_rating.toStringAsFixed(1)} / 5.0');
    }
    if (_book.pageCount != null && _currentPage > 0) {
      text.writeln('📑 Haladás: $_currentPage / ${_book.pageCount} oldal');
    }
    text.writeln('Állapot: ${_selectedStatus.label}');

    SharePlus.instance.share(ShareParams(text: text.toString()));
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Könyv törlése',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'Törlöd a(z) „${_book.title}” című könyvet a könyvtáradból? Ez a művelet nem vonható vissza.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
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
              dialogNav.pop(); // Close dialog

              try {
                if (_book.id != null) {
                  await ref
                      .read(bookListProvider.notifier)
                      .deleteBook(_book.id!);
                }
                if (mounted) {
                  _hasChanges = false;
                  pageNav.pop(); // Close detail screen
                }
              } on AppException catch (e) {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(e.userMessage),
                      backgroundColor: AppColors.error,
                    ),
                  );
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
