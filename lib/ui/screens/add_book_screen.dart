import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/book.dart';
import '../../data/models/reading_status.dart';
import '../../data/services/app_exceptions.dart';
import '../../data/services/isbn_validator.dart';
import '../../providers/book_providers.dart';
import '../../providers/database_provider.dart';
import '../theme/app_colors.dart';
import 'book_detail_screen.dart';
import 'scanner_screen.dart';

/// Screen for discovering books via online title/author search,
/// adding books manually (including offline or non-ISBN editions),
/// or editing existing book metadata.
class AddBookScreen extends ConsumerStatefulWidget {
  /// Optional pre-filled ISBN (e.g. when redirected from scanner fallback)
  final String? initialIsbn;

  /// Initial tab index when adding a new book: 0 = Online search, 1 = Manual form
  final int initialTabIndex;

  /// When provided, opens directly in metadata edit mode for an existing book
  final Book? bookToEdit;

  /// Whether this screen is embedded inside HomeScreen's navigation shell
  final bool isEmbedded;

  const AddBookScreen({
    super.key,
    this.initialIsbn,
    this.initialTabIndex = 0,
    this.bookToEdit,
    this.isEmbedded = false,
  });

  @override
  ConsumerState<AddBookScreen> createState() => _AddBookScreenState();
}

class _AddBookScreenState extends ConsumerState<AddBookScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;

  // ── Online search state ──
  final _onlineSearchController = TextEditingController();
  List<Book> _searchResults = const [];
  bool _isSearchingOnline = false;
  String? _onlineErrorMessage;
  bool _hasSearchedOnce = false;

  // ── Manual / Edit form state ──
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _subtitleController;
  late final TextEditingController _authorsController;
  late final TextEditingController _isbnController;
  late final TextEditingController _publisherController;
  late final TextEditingController _publishedDateController;
  late final TextEditingController _pageCountController;
  late final TextEditingController _categoriesController;
  late final TextEditingController _coverUrlController;
  late final TextEditingController _descriptionController;
  ReadingStatus _selectedStatus = ReadingStatus.planToRead;
  bool _isSaving = false;

  bool get _isEditMode => widget.bookToEdit != null;

  @override
  void initState() {
    super.initState();
    if (!_isEditMode) {
      _tabController = TabController(
        length: 2,
        vsync: this,
        initialIndex: widget.initialTabIndex.clamp(0, 1),
      );
    }

    final edit = widget.bookToEdit;
    _titleController = TextEditingController(text: edit?.title ?? '');
    _subtitleController = TextEditingController(text: edit?.subtitle ?? '');
    _authorsController = TextEditingController(text: edit?.authors ?? '');
    _isbnController = TextEditingController(
      text: edit != null
          ? (edit.isManualIsbn ? '' : edit.isbn)
          : (widget.initialIsbn ?? ''),
    );
    _publisherController = TextEditingController(text: edit?.publisher ?? '');
    _publishedDateController =
        TextEditingController(text: edit?.publishedDate ?? '');
    _pageCountController = TextEditingController(
      text: edit?.pageCount != null ? '${edit!.pageCount}' : '',
    );
    _categoriesController = TextEditingController(text: edit?.categories ?? '');
    _coverUrlController = TextEditingController(text: edit?.coverUrl ?? '');
    _descriptionController =
        TextEditingController(text: edit?.description ?? '');
    if (edit != null) {
      _selectedStatus = ReadingStatus.fromString(edit.status);
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _onlineSearchController.dispose();
    _titleController.dispose();
    _subtitleController.dispose();
    _authorsController.dispose();
    _isbnController.dispose();
    _publisherController.dispose();
    _publishedDateController.dispose();
    _pageCountController.dispose();
    _categoriesController.dispose();
    _coverUrlController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditMode) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Könyv adatainak szerkesztése'),
          backgroundColor: AppColors.background,
        ),
        body: SafeArea(child: _buildManualForm()),
      );
    }

    final content = SafeArea(
      child: Column(
        children: [
          _buildHeader(),
          _buildTabSelector(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildOnlineSearchTab(),
                _buildManualForm(),
              ],
            ),
          ),
        ],
      ),
    );

    if (widget.isEmbedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: content,
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          if (!widget.isEmbedded) ...[
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.surface,
                side: const BorderSide(color: AppColors.surfaceBorder),
              ),
            ),
            const SizedBox(width: 12),
          ],
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Könyv hozzáadása',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Keress online cím szerint, vagy vigyél fel könyvet kézzel',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          // Quick shortcut to camera barcode scanner
          Tooltip(
            message: 'Vonalkód szkennelése',
            child: IconButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ScannerScreen()),
                );
              },
              icon: const Icon(
                Icons.qr_code_scanner_rounded,
                color: AppColors.primary,
              ),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.surface,
                side: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.surfaceBorder),
        ),
        padding: const EdgeInsets.all(4),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(10),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelColor: AppColors.background,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          tabs: const [
            Tab(
              height: 40,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.travel_explore_rounded, size: 18),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Online keresés',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Tab(
              height: 40,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.edit_note_rounded, size: 18),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Kézi felvétel',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab 1: Online Search ──

  Widget _buildOnlineSearchTab() {
    final existingBooks = ref.watch(bookListProvider).valueOrNull ?? const [];
    final existingIsbns = <String>{
      for (final b in existingBooks) ...IsbnValidator.getAllFormats(b.isbn),
      for (final b in existingBooks) b.isbn,
    };

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _onlineSearchController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _performOnlineSearch(),
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Cím, szerző vagy ISBN (pl. Egri csillagok)...',
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: AppColors.textMuted,
                        ),
                        suffixIcon: _onlineSearchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: AppColors.textMuted,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _onlineSearchController.clear();
                                    _searchResults = const [];
                                    _onlineErrorMessage = null;
                                    _hasSearchedOnce = false;
                                  });
                                },
                              )
                            : null,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed:
                          _isSearchingOnline ? null : _performOnlineSearch,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                      ),
                      child: _isSearchingOnline
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.background,
                              ),
                            )
                          : const Text('Keresés'),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _buildOnlineSearchBody(existingIsbns),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOnlineSearchBody(Set<String> existingIsbns) {
    if (_isSearchingOnline) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 16),
            Text(
              'Keresés a nemzetközi könyvadatbázisokban...',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    if (_onlineErrorMessage != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.error.withValues(alpha: 0.12),
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                color: AppColors.error,
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _onlineErrorMessage!,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _performOnlineSearch,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Újrapróbálás'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    _titleController.text = _onlineSearchController.text.trim();
                    _tabController?.animateTo(1);
                  },
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('Kézi felvétel offline'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (!_hasSearchedOnce) {
      final suggestions = [
        'A Pál utcai fiúk',
        'Egri csillagok',
        'Dune Frank Herbert',
        '1984 George Orwell',
        'Harry Potter',
        'The Witcher',
      ];
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.manage_search_rounded,
              size: 56,
              color: AppColors.primary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            const Text(
              'Keress rá bármelyik könyvre',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'Írd be a könyv címét, szerzőjét vagy ISBN számát a Google Books és Open Library katalógusokban való kereséshez.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            const Text(
              'Gyors javaslatok kipróbáláshoz:',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: suggestions.map((suggestion) {
                return ActionChip(
                  avatar: const Icon(
                    Icons.search_rounded,
                    size: 15,
                    color: AppColors.primary,
                  ),
                  label: Text(suggestion),
                  onPressed: () {
                    _onlineSearchController.text = suggestion;
                    _performOnlineSearch();
                  },
                );
              }).toList(),
            ),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search_off_rounded,
              size: 48,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 12),
            const Text(
              'Nem található könyv ezzel a kifejezéssel',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Próbálj meg más kulcsszót, vagy add hozzá a könyvet manuálisan!',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                _titleController.text = _onlineSearchController.text.trim();
                _tabController?.animateTo(1);
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Hozzáadás kézzel'),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: _searchResults.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final candidate = _searchResults[index];
        final isAlreadyAdded = existingIsbns.contains(candidate.isbn);

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isAlreadyAdded
                  ? AppColors.accent.withValues(alpha: 0.4)
                  : AppColors.surfaceBorder,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 58,
                  height: 86,
                  child: candidate.coverUrl != null
                      ? CachedNetworkImage(
                          imageUrl: candidate.coverUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => _buildMiniPlaceholder(),
                        )
                      : _buildMiniPlaceholder(),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      candidate.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (candidate.authors != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        candidate.authors!,
                        style: const TextStyle(
                          color: AppColors.secondaryLight,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (candidate.publishedDate != null)
                          Text(
                            candidate.publishedDate!,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        if (candidate.pageCount != null)
                          Text(
                            '• ${candidate.pageCount} oldal',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        if (candidate.externalRating != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                size: 14,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                candidate.externalRating!.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              isAlreadyAdded
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: AppColors.accent,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Mentve',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : IconButton.filled(
                      onPressed: () => _addCandidateBook(candidate),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.background,
                      ),
                      tooltip: 'Hozzáadás a könyvtárhoz',
                      icon: const Icon(Icons.add_rounded),
                    ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMiniPlaceholder() {
    return Container(
      color: AppColors.surfaceLight,
      child: const Center(
        child: Icon(
          Icons.menu_book_rounded,
          color: AppColors.textMuted,
          size: 24,
        ),
      ),
    );
  }

  Future<void> _performOnlineSearch() async {
    final query = _onlineSearchController.text.trim();
    if (query.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isSearchingOnline = true;
      _onlineErrorMessage = null;
      _hasSearchedOnce = true;
    });

    try {
      final api = ref.read(bookApiServiceProvider);
      final results = await api.searchBooksOnline(query);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _onlineErrorMessage = e.userMessage;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _onlineErrorMessage =
            'Váratlan hiba történt a keresés során. Kérjük, próbáld újra!';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSearchingOnline = false;
        });
      }
    }
  }

  Future<void> _addCandidateBook(Book candidate) async {
    try {
      final saved = await ref.read(bookListProvider.notifier).addBook(candidate);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('„${saved.title}” hozzáadva a könyvtáradhoz!'),
          backgroundColor: AppColors.success,
          action: SnackBarAction(
            label: 'Megnyitás',
            textColor: AppColors.background,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BookDetailScreen(book: saved),
                ),
              );
            },
          ),
        ),
      );
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.userMessage),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  // ── Tab 2 / Edit Mode: Manual Book Form ──

  Widget _buildManualForm() {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Form(
            key: _formKey,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 520;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTextField(
                      controller: _titleController,
                      label: 'Könyv címe *',
                      hint: 'pl. Egri csillagok',
                      icon: Icons.title_rounded,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Kérjük, add meg a könyv címét!';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    _buildTextField(
                      controller: _subtitleController,
                      label: 'Alcím (opcionális)',
                      hint: 'pl. Történelmi regény',
                      icon: Icons.subtitles_outlined,
                    ),
                    const SizedBox(height: 14),
                    _buildTextField(
                      controller: _authorsController,
                      label: 'Szerző(k)',
                      hint: 'pl. Gárdonyi Géza',
                      icon: Icons.person_outline_rounded,
                    ),
                    const SizedBox(height: 14),

                    if (isWide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildIsbnField()),
                          const SizedBox(width: 12),
                          Expanded(child: _buildPageCountField()),
                        ],
                      )
                    else ...[
                      _buildIsbnField(),
                      const SizedBox(height: 14),
                      _buildPageCountField(),
                    ],
                    const SizedBox(height: 14),

                    if (isWide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _publisherController,
                              label: 'Kiadó',
                              hint: 'pl. Móra Könyvkiadó',
                              icon: Icons.business_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTextField(
                              controller: _publishedDateController,
                              label: 'Kiadás éve / dátuma',
                              hint: 'pl. 2023',
                              icon: Icons.calendar_today_rounded,
                            ),
                          ),
                        ],
                      )
                    else ...[
                      _buildTextField(
                        controller: _publisherController,
                        label: 'Kiadó',
                        hint: 'pl. Móra Könyvkiadó',
                        icon: Icons.business_rounded,
                      ),
                      const SizedBox(height: 14),
                      _buildTextField(
                        controller: _publishedDateController,
                        label: 'Kiadás éve / dátuma',
                        hint: 'pl. 2023',
                        icon: Icons.calendar_today_rounded,
                      ),
                    ],
                    const SizedBox(height: 14),

                    _buildTextField(
                      controller: _categoriesController,
                      label: 'Kategóriák / Műfajok',
                      hint: 'pl. Regény, Klasszikus, Sci-fi',
                      icon: Icons.category_outlined,
                    ),
                    const SizedBox(height: 14),

                    _buildTextField(
                      controller: _coverUrlController,
                      label: 'Borítókép URL (opcionális)',
                      hint: 'https://...',
                      icon: Icons.image_outlined,
                      keyboardType: TextInputType.url,
                      validator: (v) {
                        final trimmed = v?.trim() ?? '';
                        if (trimmed.isEmpty) return null;
                        final uri = Uri.tryParse(trimmed);
                        if (uri == null ||
                            (!uri.isScheme('http') && !uri.isScheme('https'))) {
                          return 'Érvényes http:// vagy https:// URL-t adj meg!';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    if (!_isEditMode) ...[
                      const Text(
                        'Olvasási állapot',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ReadingStatus.values.map((status) {
                          final selected = _selectedStatus == status;
                          return ChoiceChip(
                            avatar: Icon(
                              status.icon,
                              size: 16,
                              color: status.color,
                            ),
                            label: Text(status.label),
                            selected: selected,
                            onSelected: (_) =>
                                setState(() => _selectedStatus = status),
                            selectedColor: status.color.withValues(alpha: 0.2),
                            checkmarkColor: status.color,
                            labelStyle: TextStyle(
                              color: selected
                                  ? status.color
                                  : AppColors.textSecondary,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w400,
                              fontSize: 12,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],

                    _buildTextField(
                      controller: _descriptionController,
                      label: 'Leírás / Fülszöveg (opcionális)',
                      hint: 'Rövid ismertető a könyvről...',
                      icon: Icons.notes_rounded,
                      maxLines: 4,
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _submitForm,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.background,
                                ),
                              )
                            : Icon(
                                _isEditMode
                                    ? Icons.save_rounded
                                    : Icons.library_add_rounded,
                              ),
                        label: Text(
                          _isEditMode
                              ? 'Módosítások mentése'
                              : 'Könyv mentése a könyvtárba',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIsbnField() {
    return _buildTextField(
      controller: _isbnController,
      label: 'ISBN (üresen hagyható)',
      hint: 'pl. 9789631196009',
      icon: Icons.qr_code_rounded,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9Xx-\s]')),
      ],
      validator: (v) {
        final trimmed = v?.trim() ?? '';
        if (trimmed.isEmpty) return null; // Optional for manual books!
        if (IsbnValidator.normalize(trimmed) == null) {
          return 'Érvénytelen 10 vagy 13 jegyű ISBN szám.';
        }
        return null;
      },
    );
  }

  Widget _buildPageCountField() {
    return _buildTextField(
      controller: _pageCountController,
      label: 'Oldalszám',
      hint: 'pl. 352',
      icon: Icons.menu_book_outlined,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      validator: (v) {
        final trimmed = v?.trim() ?? '';
        if (trimmed.isEmpty) return null;
        final pages = int.tryParse(trimmed);
        if (pages == null || pages <= 0 || pages > 50000) {
          return '1 és 50000 közötti számot adj meg.';
        }
        return null;
      },
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: validator,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: maxLines == 1
                ? Icon(icon, color: AppColors.textMuted, size: 20)
                : null,
          ),
        ),
      ],
    );
  }

  String? _nullIfEmpty(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _submitForm() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);

    try {
      final rawIsbn = _isbnController.text.trim();
      final String resolvedIsbn;
      if (rawIsbn.isNotEmpty) {
        resolvedIsbn = IsbnValidator.normalize(rawIsbn)!;
      } else if (_isEditMode) {
        resolvedIsbn = widget.bookToEdit!.isManualIsbn
            ? widget.bookToEdit!.isbn
            : 'LOCAL-${DateTime.now().millisecondsSinceEpoch}';
      } else {
        resolvedIsbn = 'LOCAL-${DateTime.now().millisecondsSinceEpoch}';
      }

      final pageCount = int.tryParse(_pageCountController.text.trim());
      final notifier = ref.read(bookListProvider.notifier);

      if (_isEditMode) {
        final original = widget.bookToEdit!;
        final clampedCurrentPage =
            (pageCount != null && original.currentPage != null)
                ? original.currentPage!.clamp(0, pageCount)
                : original.currentPage;

        final updated = original.copyWith(
          isbn: resolvedIsbn,
          title: _titleController.text.trim(),
          subtitle: _nullIfEmpty(_subtitleController),
          authors: _nullIfEmpty(_authorsController),
          publisher: _nullIfEmpty(_publisherController),
          publishedDate: _nullIfEmpty(_publishedDateController),
          pageCount: pageCount,
          currentPage: clampedCurrentPage,
          categories: _nullIfEmpty(_categoriesController),
          coverUrl: _nullIfEmpty(_coverUrlController),
          description: _nullIfEmpty(_descriptionController),
        );

        final saved = await notifier.updateBook(updated);
        if (!mounted) return;
        Navigator.pop(context, saved);
        return;
      }

      final now = DateTime.now();
      final newBook = Book(
        isbn: resolvedIsbn,
        title: _titleController.text.trim(),
        subtitle: _nullIfEmpty(_subtitleController),
        authors: _nullIfEmpty(_authorsController),
        publisher: _nullIfEmpty(_publisherController),
        publishedDate: _nullIfEmpty(_publishedDateController),
        pageCount: pageCount,
        currentPage: _selectedStatus == ReadingStatus.completed ? pageCount : 0,
        categories: _nullIfEmpty(_categoriesController),
        coverUrl: _nullIfEmpty(_coverUrlController),
        status: _selectedStatus.name,
        dateAdded: now,
        dateStarted: (_selectedStatus == ReadingStatus.reading ||
                _selectedStatus == ReadingStatus.completed)
            ? now
            : null,
        dateFinished: _selectedStatus == ReadingStatus.completed ? now : null,
        description: _nullIfEmpty(_descriptionController),
      );

      final saved = await notifier.addBook(newBook);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('„${saved.title}” sikeresen elmentve!'),
          backgroundColor: AppColors.success,
        ),
      );

      if (widget.isEmbedded) {
        // Reset form and open the newly created book detail
        _formKey.currentState?.reset();
        _titleController.clear();
        _subtitleController.clear();
        _authorsController.clear();
        _isbnController.clear();
        _publisherController.clear();
        _publishedDateController.clear();
        _pageCountController.clear();
        _categoriesController.clear();
        _coverUrlController.clear();
        _descriptionController.clear();
        setState(() => _selectedStatus = ReadingStatus.planToRead);

        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => BookDetailScreen(book: saved)),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => BookDetailScreen(book: saved)),
        );
      }
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.userMessage),
          backgroundColor: AppColors.error,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hiba történt a mentés során.'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}

