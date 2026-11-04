import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/book.dart';
import '../../data/models/reading_status.dart';
import '../../providers/book_providers.dart';
import '../theme/app_colors.dart';
import '../widgets/book_card.dart';
import '../widgets/empty_state.dart';
import 'add_book_screen.dart';
import 'book_detail_screen.dart';
import 'scanner_screen.dart';
import 'stats_screen.dart';

/// Főképernyő egyszerű navigációval (Könyvtár, Hozzáadás, Szkennelés, Statisztika).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentTab = 0; // 0 = Könyvtár, 1 = Hozzáadás, 2 = Statisztika
  bool _isGridView = true;
  bool _isSearching = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int get _selectedNavIndex {
    if (_currentTab == 0) return 0;
    if (_currentTab == 1) return 1;
    return 3;
  }

  Future<void> _onSelectDestination(int index) async {
    if (index == 2) {
      await _openScanner();
      return;
    }
    final tab = index == 3 ? 2 : index;
    setState(() => _currentTab = tab);
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
    final isWideScreen = MediaQuery.sizeOf(context).width >= 640;

    final body = IndexedStack(
      index: _currentTab,
      children: [
        _buildLibraryTab(),
        const AddBookScreen(isEmbedded: true),
        const StatsScreen(),
      ],
    );

    if (isWideScreen) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              backgroundColor: AppColors.surface,
              selectedIndex: _selectedNavIndex,
              onDestinationSelected: _onSelectDestination,
              labelType: NavigationRailLabelType.all,
              selectedIconTheme: const IconThemeData(color: AppColors.primary),
              unselectedIconTheme:
                  const IconThemeData(color: AppColors.textMuted),
              selectedLabelTextStyle: const TextStyle(
                color: AppColors.primary,
                fontSize: 12,
              ),
              unselectedLabelTextStyle: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
              ),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.library_books_outlined),
                  selectedIcon: Icon(Icons.library_books),
                  label: Text('Könyvtár'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.add_box_outlined),
                  selectedIcon: Icon(Icons.add_box),
                  label: Text('Hozzáadás'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.qr_code_scanner),
                  label: Text('Szkennelés'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.bar_chart),
                  label: Text('Statisztika'),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedNavIndex,
        onTap: _onSelectDestination,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.library_books),
            label: 'Könyvtár',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_box_outlined),
            label: 'Hozzáadás',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.qr_code_scanner),
            label: 'Szkennelés',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Statisztika',
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryTab() {
    final booksAsync = ref.watch(bookListProvider);
    final currentSort = ref.watch(bookSortOrderProvider);

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Keresés cím, szerző, ISBN...',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _searchController.clear();
                      ref.read(searchQueryProvider.notifier).state = '';
                      setState(() => _isSearching = false);
                    },
                  ),
                ),
                onChanged: (value) {
                  ref.read(searchQueryProvider.notifier).state = value;
                },
              )
            : const Text('FreeLib'),
        actions: [
          if (!_isSearching)
            IconButton(
              tooltip: 'Keresés',
              icon: const Icon(Icons.search),
              onPressed: () => setState(() => _isSearching = true),
            ),
          IconButton(
            tooltip: _isGridView ? 'Listanézet' : 'Rácsnézet',
            icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
            onPressed: () => setState(() => _isGridView = !_isGridView),
          ),
          PopupMenuButton<BookSortOrder>(
            tooltip: 'Rendezés',
            icon: const Icon(Icons.sort),
            initialValue: currentSort,
            onSelected: (sort) {
              ref.read(bookSortOrderProvider.notifier).state = sort;
            },
            itemBuilder: (context) {
              return BookSortOrder.values.map((sort) {
                return PopupMenuItem<BookSortOrder>(
                  value: sort,
                  child: Text(sort.label),
                );
              }).toList();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(bookListProvider.notifier).refresh(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildSummaryBar()),
            SliverToBoxAdapter(child: _buildFilterChips()),
            ..._buildBookSlivers(booksAsync),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryBar() {
    final stats = ref.watch(bookStatsProvider).valueOrNull;
    final total = stats?.totalCount ?? 0;
    final reading = stats?.countByStatus['reading'] ?? 0;
    final completed = stats?.countByStatus['completed'] ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Wrap(
            spacing: 16,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(
                'Összes könyv: $total',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Olvasom: $reading  •  Befejezve: $completed',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    final currentFilter = ref.watch(statusFilterProvider);

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: const Text('Összes'),
              selected: currentFilter == null,
              onSelected: (_) {
                ref.read(statusFilterProvider.notifier).state = null;
              },
            ),
          ),
          ...ReadingStatus.values.map((status) {
            final isSelected = currentFilter == status.name;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(status.label),
                selected: isSelected,
                onSelected: (_) {
                  ref.read(statusFilterProvider.notifier).state =
                      isSelected ? null : status.name;
                },
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
          child: Center(child: CircularProgressIndicator()),
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
                  Text(
                    'Hiba a betöltéskor: $error',
                    style: const TextStyle(color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
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
                  icon: Icons.search_off,
                  title: 'Nincs találat',
                  subtitle: 'Nem található a szűrésnek megfelelő könyv.',
                  actionLabel: 'Szűrők törlése',
                  actionIcon: Icons.clear,
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
                actionIcon: Icons.qr_code_scanner,
                onAction: _openScanner,
                secondaryActionLabel: 'Keresés / Kézi felvétel',
                secondaryActionIcon: Icons.add,
                onSecondaryAction: () => setState(() => _currentTab = 1),
              ),
            ),
          ];
        }

        if (_isGridView) {
          return [
            SliverPadding(
              padding: const EdgeInsets.all(12),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 190,
                  mainAxisExtent: 270,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
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
            padding: const EdgeInsets.only(bottom: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final book = books[index];
                  return BookCard(
                    book: book,
                    isGridView: false,
                    onTap: () => _openBookDetail(book),
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
      MaterialPageRoute(builder: (_) => BookDetailScreen(book: book)),
    );
    if (mounted) {
      ref.read(bookListProvider.notifier).refresh();
    }
  }
}
