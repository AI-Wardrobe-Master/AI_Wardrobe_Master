import 'package:flutter/material.dart';

import '../../l10n/app_strings_provider.dart';
import '../../models/wardrobe.dart';
import '../../state/current_wardrobe_controller.dart';
import '../../services/wardrobe_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/clothing_metadata_art.dart';
import 'wardrobe_management_screen.dart';

/// Module 3: Wardrobe tab — multi-wardrobe selector, items grid, add/remove, category filter, virtual support.
class WardrobeScreen extends StatefulWidget {
  const WardrobeScreen({super.key});

  @override
  State<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends State<WardrobeScreen> {
  List<Wardrobe> _wardrobes = [];
  Wardrobe? _currentWardrobe;
  List<WardrobeItemWithClothing> _items = [];
  bool _loadingWardrobes = true;
  bool _loadingItems = false;
  String? _error;
  int _selectedCategoryIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _textPrimary =>
      _isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
  Color get _textSecondary =>
      _isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
  Color get _accent =>
      _isDark ? AppColors.darkAccentBlue : AppColors.accentBlue;

  static const List<String> _categoryKeys = [
    'all',
    'tops',
    'bottoms',
    'outerwear',
    'accessories',
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(
        () => _searchQuery = _searchController.text.trim().toLowerCase(),
      );
    });
    _loadWardrobes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadWardrobes() async {
    setState(() {
      _loadingWardrobes = true;
      _error = null;
    });
    try {
      final list = await WardrobeService.fetchWardrobes();
      setState(() {
        _wardrobes = list;
        _loadingWardrobes = false;
        if (_currentWardrobe == null && list.isNotEmpty) {
          _currentWardrobe = list.first;
          CurrentWardrobeController.setCurrentWardrobeId(list.first.id);
          _loadItems();
        } else if (_currentWardrobe != null) {
          final id = _currentWardrobe!.id;
          _currentWardrobe =
              list.cast<Wardrobe?>().firstWhere(
                (w) => w?.id == id,
                orElse: () => null,
              ) ??
              list.first;
          CurrentWardrobeController.setCurrentWardrobeId(_currentWardrobe!.id);
          _loadItems();
        } else {
          CurrentWardrobeController.setCurrentWardrobeId(null);
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loadingWardrobes = false;
      });
    }
  }

  Future<void> _loadItems() async {
    if (_currentWardrobe == null) return;
    setState(() => _loadingItems = true);
    try {
      final list = await WardrobeService.fetchWardrobeItems(
        _currentWardrobe!.id,
      );
      setState(() {
        _items = list;
        _loadingItems = false;
      });
    } catch (e) {
      setState(() {
        _loadingItems = false;
        _error = e.toString();
      });
    }
  }

  List<WardrobeItemWithClothing> get _filteredItems {
    var list = _items;
    final key = _selectedCategoryIndex < _categoryKeys.length
        ? _categoryKeys[_selectedCategoryIndex]
        : 'all';
    if (key != 'all') {
      list = list.where((e) {
        final cat = e.clothingItem?.categoryTag?.toLowerCase();
        if (cat == null) return false;
        return cat.contains(key);
      }).toList();
    }
    if (_searchQuery.isNotEmpty) {
      list = list.where((e) {
        final name = e.clothingItem?.name?.toLowerCase() ?? '';
        final tags = (e.clothingItem?.finalTags ?? [])
            .map((t) => t.toString().toLowerCase())
            .join(' ');
        return name.contains(_searchQuery) || tags.contains(_searchQuery);
      }).toList();
    }
    return list;
  }

  Future<void> _openManageWardrobes() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (ctx) => const WardrobeManagementScreen()),
    );
    _loadWardrobes();
  }

  Future<void> _removeFromWardrobe(WardrobeItemWithClothing entry) async {
    final s = AppStringsProvider.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.removeFromWardrobe),
        content: Text(entry.clothingItem?.name ?? entry.clothingItemId),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.removeFromWardrobe),
          ),
        ],
      ),
    );
    if (ok != true || _currentWardrobe == null) return;
    try {
      await WardrobeService.removeItemFromWardrobe(
        _currentWardrobe!.id,
        entry.clothingItemId,
      );
      _loadItems();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(s.removeFromWardrobe)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStringsProvider.of(context);
    final categories = [
      s.categoryAll,
      s.categoryTops,
      s.categoryBottoms,
      s.categoryOuterwear,
      s.categoryAccessories,
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.wardrobeTitle,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: _textPrimary,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s.wardrobeSubtitle,
                        style: TextStyle(fontSize: 12, color: _textSecondary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _openManageWardrobes,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 120),
                          child: Text(
                            _currentWardrobe?.name ?? s.manageWardrobes,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_drop_down,
                          size: 20,
                          color: _textPrimary,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Icon(
                    Icons.qr_code_scanner_rounded,
                    size: 20,
                    color: _textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loadingWardrobes)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              )
            else if (_wardrobes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.noWardrobesYet,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.createFirstWardrobe,
                      style: TextStyle(fontSize: 13, color: _textSecondary),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _openManageWardrobes,
                      icon: const Icon(Icons.add),
                      label: Text(s.createWardrobe),
                    ),
                  ],
                ),
              )
            else ...[
              InkWell(
                onTap: () async {
                  if (_wardrobes.length <= 1) {
                    _openManageWardrobes();
                    return;
                  }
                  final picked = await showModalBottomSheet<Wardrobe>(
                    context: context,
                    builder: (ctx) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              s.wardrobeTitle,
                              style: Theme.of(ctx).textTheme.titleMedium,
                            ),
                          ),
                          ..._wardrobes.map(
                            (w) => ListTile(
                              title: Text(w.name),
                              subtitle: w.isVirtual
                                  ? Text(s.virtualWardrobeLabel)
                                  : null,
                              trailing: _currentWardrobe?.id == w.id
                                  ? Icon(Icons.check, color: _accent)
                                  : null,
                              onTap: () => Navigator.of(ctx).pop(w),
                            ),
                          ),
                          ListTile(
                            leading: const Icon(Icons.settings),
                            title: Text(s.manageWardrobes),
                            onTap: () {
                              Navigator.of(ctx).pop();
                              _openManageWardrobes();
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                  if (picked != null && picked.id != _currentWardrobe?.id) {
                    setState(() {
                      _currentWardrobe = picked;
                      _items = [];
                    });
                    CurrentWardrobeController.setCurrentWardrobeId(picked.id);
                    _loadItems();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _currentWardrobe?.name ?? '—',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _textPrimary,
                        ),
                      ),
                      if (_currentWardrobe?.isVirtual == true) ...[
                        const SizedBox(width: 6),
                        Text(
                          s.virtualWardrobeLabel,
                          style: TextStyle(fontSize: 11, color: _textSecondary),
                        ),
                      ],
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_drop_down,
                        size: 20,
                        color: _textPrimary,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildCategoryChips(categories),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: s.searchWardrobe,
                  hintStyle: TextStyle(fontSize: 13, color: _textSecondary),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 20,
                    color: _textSecondary,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  filled: true,
                  fillColor: _isDark ? AppColors.darkSurface : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide(
                      color: Theme.of(context).dividerColor,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide(
                      color: Theme.of(context).dividerColor,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide(color: _accent),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error!,
                              style: TextStyle(
                                fontSize: 13,
                                color: _textSecondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () {
                                setState(() => _error = null);
                                _loadItems();
                              },
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _loadingItems
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredItems.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.checkroom_rounded,
                              size: 40,
                              color: _textSecondary,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              s.noClothesYet,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              s.useAddToStart,
                              style: TextStyle(
                                fontSize: 12,
                                color: _textSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.75,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                        itemCount: _filteredItems.length,
                        itemBuilder: (context, index) {
                          final entry = _filteredItems[index];
                          final ci = entry.clothingItem;
                          return GestureDetector(
                            onLongPress: () => _removeFromWardrobe(entry),
                            child: Card(
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: ci == null
                                        ? Container(
                                            color: _isDark
                                                ? AppColors.darkSurface
                                                : Colors.grey.shade200,
                                            child: Center(
                                              child: Icon(
                                                Icons.checkroom_rounded,
                                                size: 32,
                                                color: _textSecondary,
                                              ),
                                            ),
                                          )
                                        : ClothingMetadataArt(
                                            title: ci.name ?? ci.id,
                                            categoryLabel: _categoryLabelFor(
                                              ci,
                                            ),
                                            material: _materialLabelFor(ci),
                                            sourceLabel: ci.source == 'IMPORTED'
                                                ? 'Virtual item'
                                                : 'Owned item',
                                          ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Text(
                                      ci?.name ?? entry.clothingItemId,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: _textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (ci?.source == 'IMPORTED')
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        left: 8,
                                        right: 8,
                                        bottom: 4,
                                      ),
                                      child: Text(
                                        s.virtualWardrobeLabel,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: _textSecondary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChips(List<String> categories) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final selected = index == _selectedCategoryIndex;
          return GestureDetector(
            onTap: () {
              setState(() => _selectedCategoryIndex = index);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: selected
                    ? (_isDark ? AppColors.darkSurface : Colors.white)
                    : (_isDark
                          ? AppColors.darkBackground
                          : AppColors.background),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected ? _accent : Theme.of(context).dividerColor,
                  width: selected ? 1.4 : 1,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                categories[index],
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? _textPrimary : _textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _categoryLabelFor(ClothingItemBrief item) {
    for (final tag in item.finalTags.whereType<Map>()) {
      final key = tag['key']?.toString().trim().toLowerCase();
      if (key == 'category' || key == 'type') {
        final value = tag['value']?.toString().trim();
        if (value != null && value.isNotEmpty) {
          return value;
        }
      }
    }
    return 'Wardrobe item';
  }

  String _materialLabelFor(ClothingItemBrief item) {
    for (final tag in item.finalTags.whereType<Map>()) {
      final key = tag['key']?.toString().trim().toLowerCase();
      if (key == 'material' || key == 'fabric' || key == 'textile') {
        final value = tag['value']?.toString().trim();
        if (value != null && value.isNotEmpty) {
          return value;
        }
      }
    }
    return 'Material pending';
  }
}
