import 'package:flutter/material.dart';

import '../../l10n/app_strings_provider.dart';
import '../../models/card_pack.dart';
import '../../models/creator.dart';
import '../../services/card_pack_api_service.dart';
import '../../services/creator_api_service.dart';
import '../../services/local_card_pack_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/card_pack/card_pack_list_item.dart';
import '../widgets/creator/creator_list_item.dart';
import 'card_pack_detail_screen.dart';
import 'creator/card_pack_creator_screen.dart';
import 'creator/creator_profile_screen.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  List<CardPack> _packs = [];
  List<Creator> _creators = [];
  bool _loadingPacks = false;
  bool _loadingCreators = false;
  String? _errorPacks;
  String? _errorCreators;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        _loadData();
      }
    });
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim());
    });
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
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
      await _loadPacks();
    } else {
      await _loadCreators();
    }
  }

  Future<void> _loadPacks() async {
    if (_loadingPacks) return;
    setState(() {
      _loadingPacks = true;
      _errorPacks = null;
    });

    final allPacks = <CardPack>[];
    try {
      final apiPacks =
          await CardPackApiService.listCardPacks(status: 'PUBLISHED');
      allPacks.addAll(apiPacks);
    } catch (_) {}

    try {
      final localPacks = await LocalCardPackService.listCardPacks();
      for (final pack in localPacks) {
        if (!allPacks.any((item) => item.id == pack.id)) {
          allPacks.add(pack);
        }
      }
    } catch (e) {
      _errorPacks = e.toString();
    }

    if (!mounted) return;
    setState(() {
      _packs = allPacks;
      _loadingPacks = false;
    });
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

  List<CardPack> get _filteredPacks {
    if (_searchQuery.isEmpty) return _packs;
    final query = _searchQuery.toLowerCase();
    return _packs.where((pack) {
      return pack.name.toLowerCase().contains(query) ||
          (pack.description?.toLowerCase().contains(query) ?? false);
    }).toList();
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
    final textS = isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

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
                    hintText: 'Search...',
                    hintStyle: TextStyle(color: textS),
                    prefixIcon: Icon(Icons.search, color: textS),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, color: textS),
                            onPressed: _searchController.clear,
                          )
                        : null,
                    filled: true,
                    fillColor:
                        isDark ? AppColors.darkSurface : Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (_) {
                    if (_tabController.index == 1) {
                      _loadCreators();
                    }
                  },
                ),
                const SizedBox(height: 12),
                TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: 'Packs'),
                    Tab(text: 'Creators'),
                  ],
                  labelColor: textP,
                  unselectedLabelColor: textS,
                  indicatorColor:
                      isDark ? AppColors.darkAccentBlue : AppColors.accentBlue,
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPacksTab(textP, textS, isDark),
                _buildCreatorsTab(textP, textS),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPacksTab(Color textP, Color textS, bool isDark) {
    if (_loadingPacks) {
      return Center(child: CircularProgressIndicator(color: textP));
    }

    if (_errorPacks != null && _packs.isEmpty) {
      return _ErrorState(
        title: 'Error loading packs',
        detail: _errorPacks!,
        textP: textP,
        textS: textS,
        onRetry: _loadPacks,
      );
    }

    final filtered = _filteredPacks;
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.collections_bookmark_outlined, size: 48, color: textS),
            const SizedBox(height: 16),
            Text(
              'No card packs yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textP,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first card pack and share your styling inspiration',
              style: TextStyle(fontSize: 13, color: textS),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CardPackCreatorScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Create Card Pack'),
              style: FilledButton.styleFrom(
                backgroundColor:
                    isDark ? AppColors.darkAccentBlue : AppColors.accentBlue,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPacks,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final pack = filtered[index];
          return CardPackListItem(
            pack: pack,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CardPackDetailScreen(packId: pack.id),
                ),
              );
            },
          );
        },
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
                  builder: (_) => CreatorProfileScreen(creatorId: creator.userId),
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
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
