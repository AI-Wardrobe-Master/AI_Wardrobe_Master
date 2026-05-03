import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_strings_provider.dart';
import '../../models/card_pack.dart';
import '../../models/creator.dart';
import '../../models/wardrobe.dart';
import '../../services/card_pack_api_service.dart';
import '../../services/creator_api_service.dart';
import '../../services/local_card_pack_service.dart';
import '../../services/wardrobe_service.dart';
import '../../state/wardrobe_refresh_notifier.dart';
import '../../theme/app_theme.dart';
import '../widgets/app_remote_image.dart';
import '../widgets/creator/creator_list_item.dart';
import 'card_pack_detail_screen.dart';
import 'creator/card_pack_creator_screen.dart';
import 'creator/creator_profile_screen.dart';
import 'shared_wardrobe_detail_screen.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key, this.refreshSignal = 0});

  final int refreshSignal;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  List<Wardrobe> _wardrobes = [];
  List<CardPack> _cardPacks = [];
  List<Creator> _creators = [];
  bool _loadingWardrobes = false;
  bool _loadingCreators = false;
  bool _openingWid = false;
  String? _errorWardrobes;
  String? _errorCreators;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this);
    WardrobeRefreshNotifier.tick.addListener(_handleRefresh);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        _loadData();
      }
    });
    _searchController.addListener(() {
      final nextQuery = _searchController.text.trim();
      if (nextQuery == _searchQuery) {
        return;
      }
      setState(() => _searchQuery = nextQuery);
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 250), () {
        if (mounted) {
          _loadData();
        }
      });
    });
    _loadData();
  }

  @override
  void didUpdateWidget(covariant DiscoverScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshSignal != widget.refreshSignal) {
      _loadData();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WardrobeRefreshNotifier.tick.removeListener(_handleRefresh);
    _searchDebounce?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleRefresh() {
    if (mounted) {
      _loadData();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    if (_tabController.index == 0) {
      await _loadWardrobes();
    } else {
      await _loadCreators();
    }
  }

  Future<void> _loadWardrobes() async {
    if (_loadingWardrobes) return;
    setState(() {
      _loadingWardrobes = true;
      _errorWardrobes = null;
    });
    try {
      final query = _searchQuery.isNotEmpty ? _searchQuery : null;
      List<Wardrobe> wardrobes = const <Wardrobe>[];
      try {
        wardrobes = await WardrobeService.listPublicWardrobes(search: query);
      } catch (_) {
        wardrobes = const <Wardrobe>[];
      }
      final cardPacks = await _loadPublishedCardPacks(search: query);
      if (!mounted) return;
      setState(() {
        _wardrobes = wardrobes;
        _cardPacks = cardPacks;
        _loadingWardrobes = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorWardrobes = e.toString();
        _loadingWardrobes = false;
      });
    }
  }

  Future<List<CardPack>> _loadPublishedCardPacks({String? search}) async {
    final merged = <String, CardPack>{};
    try {
      final remotePacks = await CardPackApiService.listCardPacks(
        search: search,
        status: 'PUBLISHED',
        limit: 100,
      );
      for (final pack in remotePacks) {
        merged[pack.id] = pack;
      }
    } catch (_) {
      // Local published packs are still useful while the public feed is down.
    }

    final localPacks = await LocalCardPackService.listCardPacks(
      status: 'PUBLISHED',
    );
    for (final pack in localPacks) {
      if (pack.type == PackType.outfit) {
        continue;
      }
      final query = search?.trim().toLowerCase();
      final matchesQuery =
          query == null ||
          query.isEmpty ||
          pack.name.toLowerCase().contains(query) ||
          (pack.description?.toLowerCase().contains(query) ?? false);
      if (matchesQuery) {
        merged[pack.id] = pack;
      }
    }

    final packs = merged.values.toList()
      ..sort((left, right) {
        final leftDate = left.publishedAt ?? left.createdAt;
        final rightDate = right.publishedAt ?? right.createdAt;
        return rightDate.compareTo(leftDate);
      });
    return packs;
  }

  Future<void> _loadCreators() async {
    if (_loadingCreators) return;
    setState(() {
      _loadingCreators = true;
      _errorCreators = null;
    });
    try {
      final creators = await CreatorApiService.listCreators(
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
      );
      if (!mounted) return;
      setState(() {
        _creators = creators;
        _loadingCreators = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorCreators = e.toString();
        _loadingCreators = false;
      });
    }
  }

  List<Wardrobe> get _filteredWardrobes {
    if (_searchQuery.isEmpty) return _wardrobes;
    final query = _searchQuery.toLowerCase();
    return _wardrobes.where((wardrobe) {
      return wardrobe.name.toLowerCase().contains(query) ||
          wardrobe.wid.toLowerCase().contains(query) ||
          (wardrobe.ownerUid?.toLowerCase().contains(query) ?? false) ||
          (wardrobe.ownerUsername?.toLowerCase().contains(query) ?? false) ||
          (wardrobe.description?.toLowerCase().contains(query) ?? false) ||
          wardrobe.tags.any((tag) => tag.toLowerCase().contains(query));
    }).toList();
  }

  Future<void> _openWardrobeIdSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty || _openingWid) {
      return;
    }
    setState(() => _openingWid = true);
    try {
      final wardrobe = await _resolveWardrobeSearchTarget(query);
      if (!mounted) {
        return;
      }
      if (wardrobe == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No shared wardrobe found for WID: $query')),
        );
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SharedWardrobeDetailScreen(wardrobeWid: wardrobe.wid),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _openingWid = false);
      }
    }
  }

  Future<Wardrobe?> _resolveWardrobeSearchTarget(String rawQuery) async {
    final query = rawQuery.trim();
    final normalized = query.toLowerCase();
    final exactMatch = _wardrobes.cast<Wardrobe?>().firstWhere(
      (wardrobe) => wardrobe?.wid.toLowerCase() == normalized,
      orElse: () => null,
    );
    if (exactMatch != null) {
      return exactMatch;
    }

    final visibleMatches = _filteredWardrobes
        .where((wardrobe) => wardrobe.wid.toLowerCase().contains(normalized))
        .toList();
    if (visibleMatches.length == 1) {
      return visibleMatches.single;
    }

    final remote = await WardrobeService.fetchWardrobeByWid(
      query,
      cacheRemote: false,
    );
    if (remote != null) {
      return remote;
    }

    if (visibleMatches.isNotEmpty) {
      return visibleMatches.first;
    }
    return null;
  }

  List<Creator> get _filteredCreators {
    if (_searchQuery.isEmpty) return _creators;
    final query = _searchQuery.toLowerCase();
    return _creators.where((creator) {
      return creator.displayName.toLowerCase().contains(query) ||
          creator.username.toLowerCase().contains(query) ||
          (creator.brandName?.toLowerCase().contains(query) ?? false) ||
          (creator.bio?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStringsProvider.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textS = isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.discoverTitle,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: textP,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  s.discoverSubtitle,
                  style: TextStyle(fontSize: 12, color: textS),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText:
                        'Search by WID, tag, creator, or wardrobe name...',
                    hintStyle: TextStyle(color: textS),
                    prefixIcon: Icon(Icons.search, color: textS),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Open WID',
                                icon: _openingWid
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: textS,
                                        ),
                                      )
                                    : Icon(
                                        Icons.open_in_new_rounded,
                                        color: textS,
                                      ),
                                onPressed: _openingWid
                                    ? null
                                    : _openWardrobeIdSearch,
                              ),
                              IconButton(
                                icon: Icon(Icons.clear, color: textS),
                                onPressed: _searchController.clear,
                              ),
                            ],
                          )
                        : null,
                    filled: true,
                    fillColor: isDark
                        ? AppColors.darkSurface
                        : Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _openWardrobeIdSearch(),
                ),
                const SizedBox(height: 12),
                TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: 'Wardrobes'),
                    Tab(text: 'Creators'),
                  ],
                  labelColor: textP,
                  unselectedLabelColor: textS,
                  indicatorColor: isDark
                      ? AppColors.darkAccentBlue
                      : AppColors.accentBlue,
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildWardrobesTab(textP, textS, isDark),
                _buildCreatorsTab(textP, textS),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWardrobesTab(Color textP, Color textS, bool isDark) {
    if (_loadingWardrobes) {
      return Center(child: CircularProgressIndicator(color: textP));
    }

    if (_errorWardrobes != null) {
      return _ErrorState(
        title: 'Error loading wardrobes',
        detail: _errorWardrobes!,
        textP: textP,
        textS: textS,
        onRetry: _loadWardrobes,
      );
    }

    final filteredWardrobes = _filteredWardrobes;
    final filteredPacks = _filteredCardPacks;
    if (filteredWardrobes.isEmpty && filteredPacks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 40, color: textS),
            const SizedBox(height: 8),
            Text(
              'No shared wardrobes yet',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textP,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Published card packs and shared outfit wardrobes will both appear here.',
              style: TextStyle(fontSize: 12, color: textS),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CardPackCreatorScreen(),
                  ),
                );
                if (mounted) {
                  _loadWardrobes();
                }
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create Card Pack'),
              style: FilledButton.styleFrom(
                backgroundColor: isDark
                    ? AppColors.darkAccentBlue
                    : AppColors.accentBlue,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadWardrobes,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        itemCount: filteredPacks.length + filteredWardrobes.length,
        itemBuilder: (context, index) {
          if (index < filteredPacks.length) {
            return _buildCardPackTile(
              filteredPacks[index],
              textP,
              textS,
              isDark,
            );
          }
          final wardrobe = filteredWardrobes[index - filteredPacks.length];
          return _buildWardrobeTile(wardrobe, textP, textS, isDark);
        },
      ),
    );
  }

  Widget _buildWardrobeTile(
    Wardrobe wardrobe,
    Color textP,
    Color textS,
    bool isDark,
  ) {
    final label = wardrobe.source == 'CARD_PACK'
        ? 'Card Pack'
        : 'Shared Wardrobe';
    final publisher = wardrobe.ownerUsername?.trim().isNotEmpty == true
        ? wardrobe.ownerUsername!
        : wardrobe.ownerUid;
    final visibleTags = wardrobe.tags
        .where((tag) => tag.trim().isNotEmpty)
        .take(3)
        .toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDark ? AppColors.darkSurface : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  SharedWardrobeDetailScreen(wardrobeWid: wardrobe.wid),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildWardrobeCover(wardrobe, textS),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            wardrobe.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              height: 1.15,
                              color: textP,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildSmallChip(label, textP, textS),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'WID ${wardrobe.wid}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: textS,
                      ),
                    ),
                    if (publisher != null && publisher.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        'By $publisher',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: textS),
                      ),
                    ],
                    if (wardrobe.description?.isNotEmpty == true) ...[
                      const SizedBox(height: 5),
                      Text(
                        wardrobe.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.25,
                          color: textS,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          '${wardrobe.itemCount} items',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: textP,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Wrap(
                            spacing: 5,
                            runSpacing: 5,
                            children: visibleTags.map((tag) {
                              return _buildSmallChip(tag, textP, textS);
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWardrobeCover(Wardrobe wardrobe, Color textS) {
    final coverUrl = wardrobe.coverImageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 88,
        height: 108,
        child: coverUrl == null || coverUrl.isEmpty
            ? _buildCoverPlaceholder(textS)
            : AppRemoteImage(
                url: coverUrl,
                fit: BoxFit.cover,
                placeholder: Container(color: textS.withValues(alpha: 0.08)),
                errorWidget: _buildCoverPlaceholder(textS),
              ),
      ),
    );
  }

  Widget _buildCoverPlaceholder(Color textS) {
    return Container(
      color: textS.withValues(alpha: 0.10),
      child: Icon(Icons.image_outlined, color: textS),
    );
  }

  Widget _buildSmallChip(String label, Color textP, Color textS) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: textS.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: textP,
        ),
      ),
    );
  }

  List<CardPack> get _filteredCardPacks {
    if (_searchQuery.isEmpty) return _cardPacks;
    final query = _searchQuery.toLowerCase();
    return _cardPacks.where((pack) {
      return pack.name.toLowerCase().contains(query) ||
          (pack.description?.toLowerCase().contains(query) ?? false) ||
          (pack.creatorUid?.toLowerCase().contains(query) ?? false) ||
          (pack.creatorUsername?.toLowerCase().contains(query) ?? false) ||
          (pack.wardrobeWid?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  Widget _buildCardPackTile(
    CardPack pack,
    Color textP,
    Color textS,
    bool isDark,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDark ? AppColors.darkSurface : Colors.white,
      child: ListTile(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CardPackDetailScreen(packId: pack.id),
            ),
          );
        },
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 56,
            height: 56,
            child: pack.coverImageUrl == null || pack.coverImageUrl!.isEmpty
                ? Container(
                    color: textS.withValues(alpha: 0.1),
                    child: Icon(
                      Icons.collections_bookmark_outlined,
                      color: textS,
                    ),
                  )
                : AppRemoteImage(
                    url: pack.coverImageUrl!,
                    fit: BoxFit.contain,
                    placeholder: Container(color: textS.withValues(alpha: 0.1)),
                    errorWidget: Container(
                      color: textS.withValues(alpha: 0.1),
                      child: Icon(Icons.image_outlined, color: textS),
                    ),
                  ),
          ),
        ),
        title: Text(
          pack.name,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: textP,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (pack.wardrobeWid != null)
                Text(
                  'WID: ${pack.wardrobeWid}',
                  style: TextStyle(fontSize: 12, color: textS),
                ),
              if (pack.creatorUid != null)
                Text(
                  'Publisher UID: ${pack.creatorUid}',
                  style: TextStyle(fontSize: 12, color: textS),
                ),
              if (pack.description?.isNotEmpty == true)
                Text(
                  pack.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: textS),
                ),
            ],
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.accentBlue.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Card Pack',
                style: TextStyle(fontSize: 11, color: textP),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${pack.itemCount} items',
              style: TextStyle(fontSize: 11, color: textS),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreatorsTab(Color textP, Color textS) {
    if (_loadingCreators) {
      return Center(child: CircularProgressIndicator(color: textP));
    }

    if (_errorCreators != null) {
      return _ErrorState(
        title: 'Error loading creators',
        detail: _errorCreators!,
        textP: textP,
        textS: textS,
        onRetry: _loadCreators,
      );
    }

    final filtered = _filteredCreators;
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_outline, size: 40, color: textS),
            const SizedBox(height: 8),
            Text(
              'No creators found',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textP,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCreators,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final creator = filtered[index];
          return CreatorListItem(
            creator: creator,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      CreatorProfileScreen(creatorId: creator.userId),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String title;
  final String detail;
  final Color textP;
  final Color textS;
  final Future<void> Function() onRetry;

  const _ErrorState({
    required this.title,
    required this.detail,
    required this.textP,
    required this.textS,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: textS),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(color: textP)),
          const SizedBox(height: 4),
          Text(
            detail,
            style: TextStyle(fontSize: 12, color: textS),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
