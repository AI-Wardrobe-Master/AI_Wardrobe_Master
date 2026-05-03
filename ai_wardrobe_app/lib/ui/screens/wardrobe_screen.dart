import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_strings.dart';
import '../../l10n/app_strings_provider.dart';
import '../../models/wardrobe.dart';
import '../../services/clothing_api_service.dart';
import '../../services/import_api_service.dart';
import '../../services/local_clothing_service.dart';
import '../../state/current_wardrobe_controller.dart';
import '../../state/wardrobe_refresh_notifier.dart';
import '../../services/wardrobe_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/app_remote_image.dart';
import 'clothing_detail_screen.dart';
import 'wardrobe_management_screen.dart';

/// Module 3: Wardrobe tab — multi-wardrobe selector, items grid, add/remove, category filter, virtual support.
class WardrobeScreen extends StatefulWidget {
  const WardrobeScreen({super.key, this.initialWardrobeId});

  final String? initialWardrobeId;

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
    WardrobeRefreshNotifier.tick.addListener(_handleExternalRefresh);
    _searchController.addListener(() {
      setState(
        () => _searchQuery = _searchController.text.trim().toLowerCase(),
      );
    });
    _loadWardrobes();
  }

  @override
  void dispose() {
    WardrobeRefreshNotifier.tick.removeListener(_handleExternalRefresh);
    _searchController.dispose();
    super.dispose();
  }

  void _handleExternalRefresh() {
    if (mounted) {
      _loadItems();
    }
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
          _currentWardrobe = list.firstWhere(
            (wardrobe) => wardrobe.id == widget.initialWardrobeId,
            orElse: () => list.first,
          );
          CurrentWardrobeController.setCurrentWardrobeId(_currentWardrobe!.id);
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
          _loadItems();
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loadingWardrobes = false;
        _loadingItems = false;
      });
    }
  }

  Future<void> _loadItems() async {
    setState(() {
      _loadingItems = true;
      _error = null;
    });
    final allItems = <WardrobeItemWithClothing>[];

    void publishItems() {
      allItems.sort(
        (a, b) => (b.addedAt ?? DateTime(1970)).compareTo(
          a.addedAt ?? DateTime(1970),
        ),
      );
      if (!mounted) return;
      setState(() {
        _items = List<WardrobeItemWithClothing>.of(allItems);
        _loadingItems = false;
      });
    }

    if (_currentWardrobe != null) {
      try {
        final list = await WardrobeService.fetchWardrobeItems(
          _currentWardrobe!.id,
        );
        allItems.addAll(list);
      } catch (e) {
        _error = e.toString();
      }
    }
    publishItems();

    // Regular wardrobes should only supplement remote data with true local-only
    // entries for the currently selected wardrobe.
    final includeOwnedLocals =
        _currentWardrobe == null || _currentWardrobe?.isVirtual != true;
    final includeImported = _currentWardrobe?.isVirtual == true;

    if (includeOwnedLocals) {
      try {
        final localItems =
            await LocalClothingService.listItems(
              wardrobeId: _currentWardrobe?.id,
              includeCachedRemote: false,
            ).timeout(
              const Duration(seconds: 2),
              onTimeout: () => const <Map<String, dynamic>>[],
            );
        for (final item in localItems) {
          final source = item['source']?.toString();
          final sourceType = item['sourceType']?.toString();
          final syncStatus = item['syncStatus']?.toString();
          final itemId = item['id'] as String;
          if (source == 'IMPORTED' ||
              sourceType == 'CARD_PACK_IMPORT' ||
              sourceType == 'REMOTE_CACHE' ||
              sourceType == 'DEMO_3D_PREVIEW' ||
              syncStatus == 'SYNCED' ||
              !itemId.startsWith('local_')) {
            continue;
          }
          if (allItems.any((entry) => entry.clothingItemId == itemId)) continue;

          allItems.add(
            WardrobeItemWithClothing(
              id: 'local_$itemId',
              wardrobeId: _currentWardrobe?.id ?? 'default',
              clothingItemId: itemId,
              addedAt:
                  DateTime.tryParse(item['createdAt'] as String? ?? '') ??
                  DateTime.now(),
              displayOrder: allItems.length,
              clothingItem: ClothingItemBrief(
                id: itemId,
                name: item['name'] as String?,
                source: 'OWNED',
                finalTags: item['finalTags'] as List<dynamic>? ?? [],
                imageUrl: item['imageUrl'] as String?,
                images: Map<String, dynamic>.from(
                  item['images'] as Map? ?? const <String, dynamic>{},
                ),
                addedAt: DateTime.tryParse(item['createdAt'] as String? ?? ''),
              ),
            ),
          );
        }
      } catch (_) {}
    }

    if (includeImported) {
      try {
        final importedItems = await ImportApiService.getImportedItems().timeout(
          const Duration(seconds: 2),
          onTimeout: () => const <Map<String, dynamic>>[],
        );
        for (final item in importedItems) {
          final itemId = item['id'] as String;
          if (allItems.any((entry) => entry.clothingItemId == itemId)) continue;

          allItems.add(
            WardrobeItemWithClothing(
              id: 'imported_$itemId',
              wardrobeId: _currentWardrobe?.id ?? 'virtual',
              clothingItemId: itemId,
              addedAt:
                  DateTime.tryParse(item['createdAt'] as String? ?? '') ??
                  DateTime.now(),
              displayOrder: allItems.length,
              clothingItem: ClothingItemBrief(
                id: itemId,
                name: item['name'] as String?,
                source: 'IMPORTED',
                finalTags: item['finalTags'] as List<dynamic>? ?? [],
                imageUrl: item['imageUrl'] as String?,
                images: Map<String, dynamic>.from(
                  item['images'] as Map? ?? const <String, dynamic>{},
                ),
                addedAt: DateTime.tryParse(item['createdAt'] as String? ?? ''),
              ),
            ),
          );
        }
      } catch (_) {}
    }

    publishItems();
  }

  List<WardrobeItemWithClothing> get _filteredItems {
    var list = _items;
    final key = _selectedCategoryIndex < _categoryKeys.length
        ? _categoryKeys[_selectedCategoryIndex]
        : 'all';
    if (key != 'all') {
      list = list.where((e) {
        return _matchesCategory(e.clothingItem, key);
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

  void _clearSearchAndFilters() {
    _searchController.clear();
    setState(() {
      _selectedCategoryIndex = 0;
      _searchQuery = '';
    });
  }

  Future<void> _shareWardrobe(Wardrobe wardrobe) async {
    var latestWardrobe = wardrobe;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          wardrobe.isPublic
              ? 'Wardrobe already shared'
              : 'Publish wardrobe to Discover?',
        ),
        content: Text(
          wardrobe.isPublic
              ? '"${wardrobe.name}" is already public. Its WID can be copied again for testing or sharing.'
              : 'This will make "${wardrobe.name}" visible in Discover. Other users can find it by WID (${wardrobe.wid}), name, publisher, or clothing tags. The original clothing cards stay in your wardrobe.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: Icon(
              wardrobe.isPublic ? Icons.copy_rounded : Icons.public_rounded,
            ),
            label: Text(wardrobe.isPublic ? 'Copy WID' : 'Publish'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    if (!wardrobe.isPublic) {
      latestWardrobe = await WardrobeService.updateWardrobe(
        wardrobe.id,
        isPublic: true,
      );
      await _loadWardrobes();
    }

    final shareText =
        'AI Wardrobe share code: ${latestWardrobe.wid}\nWardrobe: ${latestWardrobe.name}';
    await Clipboard.setData(ClipboardData(text: shareText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          latestWardrobe.isPublic
              ? 'Published to Discover. WID copied: ${latestWardrobe.wid}'
              : 'Share code copied: ${latestWardrobe.wid}',
        ),
      ),
    );
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

  Future<void> _deleteClothingCard(WardrobeItemWithClothing entry) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete clothing card?'),
        content: Text(
          'This will permanently remove "${entry.clothingItem?.name ?? entry.clothingItemId}" from your wardrobe and clear its local cache.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete != true) {
      return;
    }

    try {
      await ClothingApiService.deleteClothingItem(entry.clothingItemId);
      if (!mounted) {
        return;
      }
      setState(() {
        _items = _items
            .where((item) => item.clothingItemId != entry.clothingItemId)
            .toList();
      });
      await _loadItems();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Clothing card deleted')));
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _handleItemLongPress(WardrobeItemWithClothing entry) async {
    final isMainWardrobe = _currentWardrobe?.isMain ?? false;
    if (isMainWardrobe) {
      await _deleteClothingCard(entry);
      return;
    }
    await _removeFromWardrobe(entry);
  }

  Future<void> _openItemDetails(WardrobeItemWithClothing entry) async {
    final clothing = entry.clothingItem;
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ClothingDetailScreen(
          itemId: entry.clothingItemId,
          initialName: clothing?.name,
          wardrobe: _currentWardrobe,
          initialTags: clothing?.tagValues ?? const <String>[],
        ),
      ),
    );
    if (deleted == true && mounted) {
      await _loadItems();
    }
  }

  Widget _buildItemImage(String itemId) {
    final entry = _items.cast<WardrobeItemWithClothing?>().firstWhere(
      (item) => item?.clothingItemId == itemId,
      orElse: () => null,
    );
    final imageUrl = entry?.clothingItem?.previewImageUrl;

    if (imageUrl == null || imageUrl.isEmpty) {
      return Container(
        color: _isDark ? AppColors.darkSurface : Colors.grey.shade200,
        child: Center(
          child: Icon(Icons.checkroom_rounded, size: 32, color: _textSecondary),
        ),
      );
    }

    return AppRemoteImage(
      url: imageUrl,
      fit: BoxFit.cover,
      placeholder: Container(
        color: _isDark ? AppColors.darkSurface : Colors.grey.shade200,
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: _textSecondary,
          ),
        ),
      ),
      errorWidget: Container(
        color: _isDark ? AppColors.darkSurface : Colors.grey.shade200,
        child: Icon(Icons.image_outlined, color: _textSecondary),
      ),
    );
  }

  bool _matchesCategory(ClothingItemBrief? clothing, String key) {
    if (clothing == null) {
      return false;
    }
    final rawTokens = <String>{
      clothing.categoryTag?.toLowerCase() ?? '',
      clothing.category?.toLowerCase() ?? '',
      ...clothing.tagValues.map((tag) => tag.toLowerCase()),
    }.where((token) => token.trim().isNotEmpty);

    final normalizedTokens = rawTokens
        .map(_normalizeCategoryToken)
        .where((token) => token.isNotEmpty)
        .toSet();
    final normalizedKey = _normalizeCategoryToken(key);
    if (normalizedTokens.contains(normalizedKey)) {
      return true;
    }
    return normalizedTokens.any(
      (token) => token.contains(normalizedKey) || normalizedKey.contains(token),
    );
  }

  String _normalizeCategoryToken(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'top':
      case 'tops':
      case 'shirt':
      case 'shirts':
      case 'upper':
        return 'tops';
      case 'bottom':
      case 'bottoms':
      case 'pants':
      case 'pant':
      case 'trousers':
      case 'jeans':
      case 'skirt':
        return 'bottoms';
      case 'outwear':
      case 'outerwear':
      case 'coat':
      case 'jacket':
      case 'hoodie':
        return 'outerwear';
      case 'accessory':
      case 'accessories':
      case 'hat':
      case 'bag':
      case 'scarf':
      case 'belt':
        return 'accessories';
      default:
        return raw.trim().toLowerCase();
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
    final hasActiveFilter =
        _selectedCategoryIndex != 0 || _searchQuery.isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(s),
            const SizedBox(height: 12),
            if (_loadingWardrobes)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              )
            else if (_error != null && _wardrobes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: _buildInlineError(s, onRetry: _loadWardrobes),
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
                    isScrollControlled: true,
                    builder: (ctx) {
                      final height = MediaQuery.sizeOf(ctx).height;
                      return SafeArea(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: height * 0.72),
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
                              Flexible(
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: _wardrobes.length,
                                  itemBuilder: (context, index) {
                                    final w = _wardrobes[index];
                                    return ListTile(
                                      title: Text(
                                        w.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: w.isVirtual
                                          ? Text(s.virtualWardrobeLabel)
                                          : null,
                                      trailing: _currentWardrobe?.id == w.id
                                          ? Icon(Icons.check, color: _accent)
                                          : null,
                                      onTap: () => Navigator.of(ctx).pop(w),
                                    );
                                  },
                                ),
                              ),
                              const Divider(height: 1),
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
                    },
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
                    children: [
                      Expanded(
                        child: Text(
                          _currentWardrobe?.name ?? '—',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_currentWardrobe?.isVirtual == true) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: 14,
                          color: _textSecondary,
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
                              child: Text(s.retry),
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
                              hasActiveFilter
                                  ? s.noMatchingClothes
                                  : s.noClothesYet,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (hasActiveFilter) ...[
                              TextButton(
                                onPressed: _clearSearchAndFilters,
                                child: Text(s.clearSearchFilters),
                              ),
                            ] else
                              Text(
                                s.useAddToStart,
                                textAlign: TextAlign.center,
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
                            onTap: () => _openItemDetails(entry),
                            onLongPress: () => _handleItemLongPress(entry),
                            child: Card(
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: _buildItemImage(
                                      entry.clothingItemId,
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

  Widget _buildHeader(AppStrings s) {
    final titleBlock = Column(
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
        ),
      ],
    );

    final manageButton = OutlinedButton.icon(
      onPressed: _openManageWardrobes,
      style: OutlinedButton.styleFrom(
        foregroundColor: _textPrimary,
        backgroundColor: Theme.of(context).cardColor,
        side: BorderSide(color: Theme.of(context).dividerColor),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: const StadiumBorder(),
      ),
      icon: const Icon(Icons.tune_rounded, size: 18),
      label: Text(
        s.manageWardrobes,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    final shareButton =
        _currentWardrobe != null && _currentWardrobe!.isMain != true
        ? OutlinedButton.icon(
            onPressed: () => _shareWardrobe(_currentWardrobe!),
            style: OutlinedButton.styleFrom(
              foregroundColor: _textPrimary,
              backgroundColor: Theme.of(context).cardColor,
              side: BorderSide(color: Theme.of(context).dividerColor),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: const StadiumBorder(),
            ),
            icon: const Icon(Icons.share_outlined, size: 18),
            label: const Text('Share'),
          )
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 430;
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleBlock,
              const SizedBox(height: 12),
              Row(
                children: [
                  if (shareButton != null) ...[
                    Expanded(child: shareButton),
                    const SizedBox(width: 8),
                  ],
                  Expanded(child: manageButton),
                ],
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 12),
            if (shareButton != null) ...[
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: shareButton,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: manageButton,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInlineError(AppStrings s, {required VoidCallback onRetry}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: _textSecondary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _error!,
                  style: TextStyle(fontSize: 13, color: _textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: Text(s.retry)),
        ],
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
}
