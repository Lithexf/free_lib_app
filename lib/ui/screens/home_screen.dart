import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/book.dart';
import '../../data/models/reading_status.dart';
import '../../providers/book_providers.dart';
import '../../ui/theme/app_colors.dart';
import '../widgets/book_card.dart';
import '../widgets/empty_state.dart';
import 'add_book_screen.dart';
import 'book_detail_screen.dart';
import 'scanner_screen.dart';
import 'stats_screen.dart';

/// Main library dashboard with responsive navigation (BottomNav on phones, NavigationRail on wide screens).
///
/// Views: Library, Add/Discover (Online Search + Manual), Scanner action, Statistics.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// Active content tab: 0 = Library, 1 = Add/Discover, 2 = Stats
  int _currentTab = 0;
  bool _isGridView = true;
  bool _isSearching = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Maps 4 UI navigation destinations (Library, Add, Scan, Stats) to actions/tabs.
  int get _selectedNavIndex {
    if (_currentTab == 0) return 0;
    if (_currentTab == 1) return 1;
    return 3; // Stats is destination index 3 (index 2 is Scanner modal)
  }

  Future<void> _onSelectDestination(int navIndex) async {
    if (navIndex == 2) {
      await _openScanner();
      return;
    }
    final targetTab = navIndex == 3 ? 2 : navIndex;
    setState(() => _currentTab = targetTab);
  }

  Future<void> _openScanner() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
    if (mounted) {
      ref.read(bookListProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final useNavigationRail = screenWidth >= 640;

    final bodyStack = IndexedStack(
      index: _currentTab,
      children: [
        _buildLibraryTab(),
        const AddBookScreen(isEmbedded: true),
        const StatsScreen(),
      ],
    );

    if (useNavigationRail) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Row(
          children: [
            NavigationRail(
              backgroundColor: AppColors.surface,
              selectedIndex: _selectedNavIndex,
              onDestinationSelected: _onSelectDestination,
              labelType: NavigationRailLabelType.all,
              indicatorColor: AppColors.primary.withValues(alpha: 0.16),
              selectedIconTheme: const IconThemeData(color: AppColors.primary),
              unselectedIconTheme:
                  const IconThemeData(color: AppColors.textMuted),
              selectedLabelTextStyle: const TextStyle(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelTextStyle: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.library_books_outlined),
                  selectedIcon: Icon(Icons.library_books_rounded),
                  label: Text('Könyvtár'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.add_box_outlined),
                  selectedIcon: Icon(Icons.add_box_rounded),
                  label: Text('Hozzáadás'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.qr_code_scanner_rounded),
                  label: Text('Szkenner'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  selectedIcon: Icon(Icons.bar_chart_rounded),
                  label: Text('Statisztika'),
                ),
              ],
            ),
            const VerticalDivider(width: 1, color: AppColors.surfaceBorder),
            Expanded(child: bodyStack),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: bodyStack,
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
      child: NavigationBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        height: 66,
        selectedIndex: _selectedNavIndex,
        onDestinationSelected: _onSelectDestination,
        indicatorColor: AppColors.primary.withValues(alpha: 0.15),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined, color: AppColors.textMuted),
            selectedIcon:
                Icon(Icons.library_books_rounded, color: AppColors.primary),
            label: 'Könyvtár',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_box_outlined, color: AppColors.textMuted),
            selectedIcon: Icon(Icons.add_box_rounded, color: AppColors.primary),
            label: 'Hozzáadás',
          ),
          NavigationDestination(
            icon:
                Icon(Icons.qr_code_scanner_rounded, color: AppColors.textMuted),
            selectedIcon:
                Icon(Icons.qr_code_scanner_rounded, color: AppColors.primary),
            label: 'Szkennelés',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined, color: AppColors.textMuted),
            selectedIcon:
                Icon(Icons.bar_chart_rounded, color: AppColors.primary),
            label: 'Statisztika',
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryTab() {
    final booksAsync = ref.watch(bookListProvider);

    return SafeArea(
      child: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        onRefresh: () => ref.read(bookListProvider.notifier).refresh(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildAppBar()),
            SliverToBoxAdapter(child: _buildBookCounter()),
            SliverToBoxAdapter(child: _buildFilterChips()),
            ..._buildBookSlivers(booksAsync),
          ],
        ),
      ),
    );
  }

  Widget _buildBookCounter() {
    final stats = ref.watch(bookStatsProvider).valueOrNull;
    final totalBooks = stats?.totalCount ?? 0;
    final readingCount = stats?.countByStatus['reading'] ?? 0;
    final completedCount = stats?.countByStatus['completed'] ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withValues(alpha: 0.12),
              AppColors.secondary.withValues(alpha: 0.08),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            // Icon with gradient background
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.menu_book_rounded,
                color: AppColors.background,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),

            // Count + label
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$totalBooks',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Saját könyvek',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            // Small stats preview
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildMiniStat(
                  Icons.auto_stories,
                  AppColors.accent,
                  '$readingCount',
                  'Olvasom',
                ),
                const SizedBox(height: 4),
                _buildMiniStat(
                  Icons.check_circle_outline,
                  AppColors.primary,
                  '$completedCount',
                  'Befejezve',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(
    IconData icon,
    Color color,
    String count,
    String label,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          count,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
          ),
        ),
      ],
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
                    'A te személyes könyvtárad',
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
              tooltip: 'Keresés a könyvtárban',
              onPressed: () => setState(() => _isSearching = true),
            ),
            const SizedBox(width: 8),
            // Toggle view
            _buildAppBarButton(
              icon: _isGridView
                  ? Icons.view_list_rounded
                  : Icons.grid_view_rounded,
              tooltip: _isGridView ? 'Listanézet' : 'Rácsnézet',
              onPressed: () => setState(() => _isGridView = !_isGridView),
            ),
            const SizedBox(width: 8),
            // Sort
            _buildAppBarButton(
              icon: Icons.sort_rounded,
              tooltip: 'Rendezés',
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
                  hintText: 'Keresés cím, szerző vagy ISBN alapján...',
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: AppColors.textMuted),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.textMuted),
                    onPressed: () {
                      _searchController.clear();
                      ref.read(searchQueryProvider.notifier).state = '';
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
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: IconButton(
        tooltip: tooltip,
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
              label: const Text('Összes'),
              selected: currentFilter == null,
              onSelected: (_) {
                ref.read(statusFilterProvider.notifier).state = null;
              },
              selectedColor: AppColors.primary.withValues(alpha: 0.2),
              checkmarkColor: AppColors.primary,
              labelStyle: TextStyle(
                color: currentFilter == null
                    ? AppColors.primary
                    : AppColors.textSecondary,
                fontWeight:
                    currentFilter == null ? FontWeight.w600 : FontWeight.w500,
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
                },
                selectedColor: status.color.withValues(alpha: 0.15),
                checkmarkColor: status.color,
                labelStyle: TextStyle(
                  color: isSelected ? status.color : AppColors.textSecondary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
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

  List<Widget> _buildBookSlivers(AsyncValue<List<Book>> booksAsync) {
    final activeFilter = ref.watch(statusFilterProvider);
    final activeQuery = ref.watch(searchQueryProvider);
    final hasActiveFilter =
        activeFilter != null || activeQuery.trim().isNotEmpty;

    return booksAsync.when(
      loading: () => const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      ],
      error: (error, _) => [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
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
                    'Hiba a könyvek betöltésekor:\n$error',
                    style: const TextStyle(color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () =>
                        ref.read(bookListProvider.notifier).refresh(),
                    child: const Text('Újra'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
      data: (books) {
        if (books.isEmpty) {
          if (hasActiveFilter) {
            return [
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.filter_alt_off_rounded,
                  title: 'Nincs találat a szűrésre',
                  subtitle:
                      'Egyetlen könyv sem felel meg a jelenlegi keresési vagy állapot-szűrési feltételeknek.',
                  actionLabel: 'Szűrők törlése',
                  actionIcon: Icons.clear_all_rounded,
                  onAction: () {
                    _searchController.clear();
                    ref.read(searchQueryProvider.notifier).state = '';
                    ref.read(statusFilterProvider.notifier).state = null;
                    setState(() => _isSearching = false);
                  },
                ),
              ),
            ];
          }

          return [
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                actionLabel: 'Vonalkód szkennelése',
                actionIcon: Icons.qr_code_scanner_rounded,
                onAction: _openScanner,
                secondaryActionLabel: 'Online keresés / Kézi felvétel',
                secondaryActionIcon: Icons.travel_explore_rounded,
                onSecondaryAction: () => setState(() => _currentTab = 1),
              ),
            ),
          ];
        }

        if (_isGridView) {
          return [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 205,
                  mainAxisExtent: 300,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final book = books[index];
                    return BookCard(
                      book: book,
                      isGridView: true,
                      onTap: () => _openBookDetail(book),
                    );
                  },
                  childCount: books.length,
                ),
              ),
            ),
          ];
        }

        return [
          SliverPadding(
            padding: const EdgeInsets.only(top: 6, bottom: 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final book = books[index];
                  return Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 860),
                      child: BookCard(
                        book: book,
                        isGridView: false,
                        onTap: () => _openBookDetail(book),
                      ),
                    ),
                  );
                },
                childCount: books.length,
              ),
            ),
          ),
        ];
      },
    );
  }

  Future<void> _openBookDetail(Book book) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookDetailScreen(book: book),
      ),
    );
    if (mounted) {
      ref.read(bookListProvider.notifier).refresh();
    }
  }

  void _showSortDialog() {
    final currentSort = ref.read(bookSortOrderProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
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
                  'Rendezés',
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
                      Navigator.pop(sheetContext);
                    },
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  );
                }),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}
