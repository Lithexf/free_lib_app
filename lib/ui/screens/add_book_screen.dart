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

/// Könyv hozzáadása online kereséssel vagy kézi űrlappal, illetve meglévő könyv szerkesztése.
class AddBookScreen extends ConsumerStatefulWidget {
  final String? initialIsbn;
  final int initialTabIndex;
  final Book? bookToEdit;
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

class _AddBookScreenState extends ConsumerState<AddBookScreen> {
  final _onlineSearchController = TextEditingController();
  List<Book> _searchResults = const [];
  bool _isSearchingOnline = false;
  String? _onlineErrorMessage;
  bool _hasSearchedOnce = false;

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
        appBar: AppBar(title: const Text('Könyv szerkesztése')),
        body: _buildManualForm(),
      );
    }

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Könyv hozzáadása'),
          actions: [
            IconButton(
              tooltip: 'Vonalkód szkennelése',
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ScannerScreen()),
                );
              },
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Online keresés'),
              Tab(text: 'Kézi felvétel'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildOnlineSearchTab(),
            _buildManualForm(),
          ],
        ),
      ),
    );
  }

  Widget _buildOnlineSearchTab() {
    final existingBooks = ref.watch(bookListProvider).valueOrNull ?? const [];
    final existingIsbns = _searchResults.isEmpty
        ? const <String>{}
        : <String>{
            for (final b in existingBooks)
              ...IsbnValidator.getAllFormats(b.isbn),
            for (final b in existingBooks) b.isbn,
          };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _onlineSearchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _performOnlineSearch(),
                  decoration: const InputDecoration(
                    hintText: 'Cím, szerző vagy ISBN...',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isSearchingOnline ? null : _performOnlineSearch,
                child: const Text('Keresés'),
              ),
            ],
          ),
        ),
        Expanded(child: _buildOnlineSearchBody(existingIsbns)),
      ],
    );
  }

  Widget _buildOnlineSearchBody(Set<String> existingIsbns) {
    if (_isSearchingOnline) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_onlineErrorMessage != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 40, color: AppColors.error),
              const SizedBox(height: 12),
              Text(
                _onlineErrorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _performOnlineSearch,
                child: const Text('Újrapróbálás'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_hasSearchedOnce) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Írd be a könyv címét, szerzőjét vagy ISBN számát a kereséshez.',
            style: TextStyle(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nincs találat. Próbálj más kulcsszót, vagy válts a Kézi felvétel fülre.',
            style: TextStyle(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _searchResults.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _searchResults[index];
        final isAdded = existingIsbns.contains(item.isbn);

        return Card(
          child: ListTile(
            leading: SizedBox(
              width: 44,
              height: 64,
              child: item.coverUrl != null
                  ? CachedNetworkImage(
                      imageUrl: item.coverUrl!,
                      fit: BoxFit.cover,
                      memCacheWidth: 132,
                      fadeInDuration: Duration.zero,
                      errorWidget: (_, _, _) =>
                          const Icon(Icons.book, color: AppColors.textMuted),
                    )
                  : const Icon(Icons.book, color: AppColors.textMuted),
            ),
            title: Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              [
                if (item.authors != null) item.authors!,
                if (item.publishedDate != null) item.publishedDate!,
              ].join(' • '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            trailing: isAdded
                ? const Icon(Icons.check, color: AppColors.success)
                : IconButton(
                    tooltip: 'Hozzáadás',
                    icon: const Icon(Icons.add_circle_outline,
                        color: AppColors.primary),
                    onPressed: () => _addCandidateBook(item),
                  ),
          ),
        );
      },
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
      final results =
          await ref.read(bookApiServiceProvider).searchBooksOnline(query);
      if (!mounted) return;
      setState(() => _searchResults = results);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _onlineErrorMessage = e.userMessage);
    } catch (_) {
      if (!mounted) return;
      setState(() => _onlineErrorMessage = 'Hiba történt a keresés során.');
    } finally {
      if (mounted) {
        setState(() => _isSearchingOnline = false);
      }
    }
  }

  Future<void> _addCandidateBook(Book candidate) async {
    try {
      await ref.read(bookListProvider.notifier).addBook(candidate);
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(e.userMessage),
            duration: const Duration(seconds: 2),
          ),
        );
    }
  }

  Widget _buildManualForm() {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'Cím *'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'A cím megadása kötelező'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _authorsController,
                  decoration: const InputDecoration(labelText: 'Szerző'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _subtitleController,
                  decoration:
                      const InputDecoration(labelText: 'Alcím (opcionális)'),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _isbnController,
                        decoration: const InputDecoration(
                          labelText: 'ISBN (opcionális)',
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9Xx-\s]')),
                        ],
                        validator: (v) {
                          final t = v?.trim() ?? '';
                          if (t.isEmpty) return null;
                          if (IsbnValidator.normalize(t) == null) {
                            return 'Hibás ISBN';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _pageCountController,
                        decoration:
                            const InputDecoration(labelText: 'Oldalszám'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _publisherController,
                        decoration: const InputDecoration(labelText: 'Kiadó'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _publishedDateController,
                        decoration:
                            const InputDecoration(labelText: 'Kiadás éve'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _categoriesController,
                  decoration: const InputDecoration(labelText: 'Kategóriák'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _coverUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Borítókép URL (opcionális)',
                  ),
                ),
                const SizedBox(height: 12),
                if (!_isEditMode) ...[
                  DropdownButtonFormField<ReadingStatus>(
                    initialValue: _selectedStatus,
                    decoration:
                        const InputDecoration(labelText: 'Olvasási állapot'),
                    items: ReadingStatus.values.map((s) {
                      return DropdownMenuItem(
                        value: s,
                        child: Text(s.label),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedStatus = val);
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Leírás'),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _isSaving ? null : _submitForm,
                  child: Text(_isEditMode ? 'Mentés' : 'Könyv hozzáadása'),
                ),
              ],
            ),
          ),
        ),
      ),
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
      } else if (_isEditMode && widget.bookToEdit!.isManualIsbn) {
        resolvedIsbn = widget.bookToEdit!.isbn;
      } else {
        resolvedIsbn = 'LOCAL-${DateTime.now().millisecondsSinceEpoch}';
      }

      final pageCount = int.tryParse(_pageCountController.text.trim());
      final notifier = ref.read(bookListProvider.notifier);

      if (_isEditMode) {
        final orig = widget.bookToEdit!;
        final updated = orig.copyWith(
          isbn: resolvedIsbn,
          title: _titleController.text.trim(),
          subtitle: _nullIfEmpty(_subtitleController),
          authors: _nullIfEmpty(_authorsController),
          publisher: _nullIfEmpty(_publisherController),
          publishedDate: _nullIfEmpty(_publishedDateController),
          pageCount: pageCount,
          currentPage: (pageCount != null && orig.currentPage != null)
              ? orig.currentPage!.clamp(0, pageCount)
              : orig.currentPage,
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

      ScaffoldMessenger.of(context).clearSnackBars();

      if (widget.isEmbedded) {
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
        Navigator.push(
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
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(e.userMessage),
            duration: const Duration(seconds: 2),
          ),
        );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
