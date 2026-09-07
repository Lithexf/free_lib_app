import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/book.dart';
import '../../data/models/reading_status.dart';
import '../../providers/book_providers.dart';
import '../../ui/theme/app_colors.dart';
import '../widgets/book_card.dart';
import '../widgets/empty_state.dart';
import 'book_detail_screen.dart';
import 'scanner_screen.dart';
import 'stats_screen.dart';

/// Main library dashboard with bottom navigation.
///
/// Tabs: Library (book grid), Scanner, Statistics
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentTab = 0;
  bool _isGridView = true;
  bool _isSearching = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _currentTab,
        children: [
          _buildLibraryTab(),
          const ScannerScreen(),
          const StatsScreen(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.surfaceBorder, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.library_books_rounded, 'Library'),
              _buildNavItem(1, Icons.qr_code_scanner_rounded, 'Scan'),
              _buildNavItem(2, Icons.bar_chart_rounded, 'Stats'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentTab == index;
    return GestureDetector(
      onTap: () {
        if (index == 1) {
          // Open scanner as a full page
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ScannerScreen()),
          );
          return;
        }
        setState(() => _currentTab = index);
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.primary : AppColors.textMuted,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppColors.primary : AppColors.textMuted,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryTab() {
    return SafeArea(
      child: Column(
        children: [
          _buildAppBar(),
          _buildFilterChips(),
          Expanded(child: _buildBookList()),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          if (!_isSearching) ...[
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FreeLib',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Your personal library',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            // Search button
            _buildAppBarButton(
              icon: Icons.search_rounded,
              onPressed: () => setState(() => _isSearching = true),
            ),
            const SizedBox(width: 8),
            // Toggle view
            _buildAppBarButton(
              icon: _isGridView
                  ? Icons.view_list_rounded
                  : Icons.grid_view_rounded,
              onPressed: () => setState(() => _isGridView = !_isGridView),
            ),
            const SizedBox(width: 8),
            // Sort
            _buildAppBarButton(
              icon: Icons.sort_rounded,
              onPressed: _showSortDialog,
            ),
          ] else ...[
            // Search field
            Expanded(
              child: TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search by title or author...',
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: AppColors.textMuted),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.textMuted),
                    onPressed: () {
                      _searchController.clear();
                      ref.read(searchQueryProvider.notifier).state = '';
                      ref.read(bookListProvider.notifier).refresh();
                      setState(() => _isSearching = false);
                    },
                  ),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onChanged: (query) {
                  ref.read(searchQueryProvider.notifier).state = query;
                  ref.read(bookListProvider.notifier).refresh();
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAppBarButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: IconButton(
        icon: Icon(icon, color: AppColors.textSecondary, size: 20),
        onPressed: onPressed,
        constraints: const BoxConstraints(minWidth: 42, minHeight: 42),
      ),
    );
  }

  Widget _buildFilterChips() {
    final currentFilter = ref.watch(statusFilterProvider);

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // "All" chip
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: const Text('All'),
              selected: currentFilter == null,
              onSelected: (_) {
                ref.read(statusFilterProvider.notifier).state = null;
                ref.read(bookListProvider.notifier).refresh();
              },
              selectedColor: AppColors.primary.withValues(alpha: 0.2),
              checkmarkColor: AppColors.primary,
              labelStyle: TextStyle(
                color: currentFilter == null
                    ? AppColors.primary
                    : AppColors.textSecondary,
                fontWeight: currentFilter == null
                    ? FontWeight.w600
                    : FontWeight.w500,
              ),
              side: BorderSide(
                color: currentFilter == null
                    ? AppColors.primary.withValues(alpha: 0.5)
                    : AppColors.surfaceBorder,
              ),
            ),
          ),

          // Status chips
          ...ReadingStatus.values.map((status) {
            final isSelected = currentFilter == status.name;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                avatar: Icon(status.icon, size: 16, color: status.color),
                label: Text(status.label),
                selected: isSelected,
                onSelected: (_) {
                  ref.read(statusFilterProvider.notifier).state =
                      isSelected ? null : status.name;
                  ref.read(bookListProvider.notifier).refresh();
                },
                selectedColor: status.color.withValues(alpha: 0.15),
                checkmarkColor: status.color,
                labelStyle: TextStyle(
                  color: isSelected ? status.color : AppColors.textSecondary,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 13,
                ),
                side: BorderSide(
                  color: isSelected
                      ? status.color.withValues(alpha: 0.5)
                      : AppColors.surfaceBorder,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBookList() {
    final booksAsync = ref.watch(bookListProvider);

    return booksAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
      error: (error, stack) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 48),
            const SizedBox(height: 16),
            Text(
              'Error loading books: $error',
              style: const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ref.read(bookListProvider.notifier).refresh(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (books) {
        if (books.isEmpty) {
          return EmptyState(
            actionLabel: 'Scan Your First Book',
            onAction: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ScannerScreen()),
            ),
          );
        }

        if (_isGridView) {
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.55,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: books.length,
            itemBuilder: (context, index) {
              final book = books[index];
              return BookCard(
                book: book,
                isGridView: true,
                onTap: () => _openBookDetail(book),
              );
            },
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: books.length,
          itemBuilder: (context, index) {
            final book = books[index];
            return BookCard(
              book: book,
              isGridView: false,
              onTap: () => _openBookDetail(book),
            );
          },
        );
      },
    );
  }

  void _openBookDetail(Book book) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookDetailScreen(book: book),
      ),
    );
    // Refresh list when returning from detail
    ref.read(bookListProvider.notifier).refresh();
  }

  void _showSortDialog() {
    final currentSort = ref.read(bookSortOrderProvider);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: SizedBox(
                  width: 40,
                  child: Divider(thickness: 3, color: AppColors.textMuted),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Sort By',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              ...BookSortOrder.values.map((sort) {
                final isSelected = sort == currentSort;
                return ListTile(
                  title: Text(
                    sort.label,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_rounded,
                          color: AppColors.primary)
                      : null,
                  onTap: () {
                    ref.read(bookSortOrderProvider.notifier).state = sort;
                    ref.read(bookListProvider.notifier).refresh();
                    Navigator.pop(context);
                  },
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
