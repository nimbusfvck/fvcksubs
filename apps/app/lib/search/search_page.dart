import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../app_scope.dart';
import '../catalog/media_grid_v2.dart';
import '../detail/open_versioned_item.dart';
import '../home/category_chips.dart';
import '../theme/tokens.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  /// The chip standing for "no scope". Not a category any extension declares
  /// — the registry leaves `all` out precisely so this one can mean it.
  static const String _unscoped = 'all';

  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String? _scope;
  Future<List<VersionedMediaItem>>? _results;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    setState(() => _query = trimmed);
    if (trimmed.isEmpty) {
      setState(() => _results = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _runSearch();
    });
  }

  void _runSearch() {
    if (_query.isEmpty) {
      setState(() => _results = null);
      return;
    }
    final registry = AppScope.of(context).registry;
    // A scope whose extension was switched off since it was picked is no
    // scope at all; searching for it would return nothing at all.
    final scope = _scope != null && registry.searchCategories.contains(_scope)
        ? _scope
        : null;
    setState(() {
      _results = registry.search(_query, category: scope);
    });
  }

  void _selectScope(String? scope) {
    if (scope == _scope) return;
    setState(() => _scope = scope);
    // Tapping a chip is a decision, not typing: run it now rather than
    // waiting out a debounce meant to swallow keystrokes.
    _debounce?.cancel();
    _runSearch();
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() {
      _query = '';
      _results = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scopes = [
      _unscoped,
      ...AppScope.of(context).registry.searchCategories,
    ];
    return Scaffold(
      backgroundColor: AppColors.surfaceDark,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDark,
        foregroundColor: AppColors.onDark,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: AppSpacing.md),
          child: SearchField(
            controller: _controller,
            onChanged: _onChanged,
            onClear: _clear,
            autofocus: true,
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // One scope is no choice: with nothing installed that declares a
          // searchable category, the row would be a single dead chip.
          if (scopes.length > 1)
            CategoryChips(
              key: const Key('search-scope-chips'),
              categories: scopes,
              selected: _scope ?? _unscoped,
              onSelected: (scope) =>
                  _selectScope(scope == _unscoped ? null : scope),
            ),
          Expanded(
            child: _query.isEmpty
                ? const _Prompt()
                : _Results(
                    future: _results,
                    onTap: (item) => openVersionedItem(context, item),
                    onTapWithHero: (item, heroTag) =>
                        openVersionedItem(context, item, heroTag: heroTag),
                  ),
          ),
        ],
      ),
    );
  }
}

class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    this.controller,
    this.onChanged,
    this.onClear,
    this.autofocus = false,
    this.enabled = true,
    this.onTap,
  });

  final TextEditingController? controller;

  final ValueChanged<String>? onChanged;

  final VoidCallback? onClear;

  final bool autofocus;

  final bool enabled;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      onChanged: onChanged,
      autofocus: autofocus,
      enabled: enabled,
      style: AppTypography.bodyMd.copyWith(color: AppColors.onDark),
      decoration: InputDecoration(
        hintText: 'Search',
        hintStyle: AppTypography.bodyMd.copyWith(color: AppColors.onDarkSoft),
        prefixIcon: const Icon(Icons.search, color: AppColors.onDarkSoft),
        suffixIcon: controller == null || onClear == null
            ? null
            : ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller!,
                builder: (context, value, _) => value.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: AppColors.onDarkSoft,
                        ),
                        onPressed: onClear,
                      ),
              ),
        filled: true,
        fillColor: AppColors.surfaceDarkElevated,
        contentPadding: const EdgeInsets.symmetric(vertical: 0),
        border: OutlineInputBorder(
          borderRadius: AppRadius.pill,
          borderSide: BorderSide.none,
        ),
      ),
    );

    if (enabled) return field;
    return GestureDetector(
      onTap: onTap,
      child: AbsorbPointer(child: field),
    );
  }
}

class _Prompt extends StatelessWidget {
  const _Prompt();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Text(
        'Search across every installed extension.',
        textAlign: TextAlign.center,
        style: AppTypography.bodyMd.copyWith(color: AppColors.onDarkSoft),
      ),
    ),
  );
}

class _Results extends StatelessWidget {
  const _Results({
    required this.future,
    required this.onTap,
    required this.onTapWithHero,
  });

  final Future<List<VersionedMediaItem>>? future;
  final ValueChanged<VersionedMediaItem> onTap;
  final void Function(VersionedMediaItem, Object) onTapWithHero;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<VersionedMediaItem>>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(
          child: Text(
            "Couldn't search right now.",
            style: AppTypography.bodyMd.copyWith(color: AppColors.error),
          ),
        );
      }
      final items = snapshot.data ?? const <VersionedMediaItem>[];
      if (items.isEmpty) {
        return Center(
          child: Text(
            'No results.',
            style: AppTypography.bodyMd.copyWith(color: AppColors.onDarkSoft),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: MediaGridV2(
          sections: [CatalogSectionV2(id: 'search', items: items)],
          onTap: onTap,
          onTapWithHero: onTapWithHero,
        ),
      );
    },
  );
}
