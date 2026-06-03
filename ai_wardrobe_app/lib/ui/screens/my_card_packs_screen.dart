import 'package:flutter/material.dart';

import '../../models/card_pack.dart';
import '../../services/api_config.dart';
import '../../services/card_pack_api_service.dart';
import '../../services/local_card_pack_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/app_remote_image.dart';
import 'card_pack_detail_screen.dart';
import 'creator/card_pack_creator_screen.dart';

class MyCardPacksScreen extends StatefulWidget {
  const MyCardPacksScreen({super.key});

  @override
  State<MyCardPacksScreen> createState() => _MyCardPacksScreenState();
}

class _MyCardPacksScreenState extends State<MyCardPacksScreen> {
  List<CardPack> _packs = const <CardPack>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPacks();
  }

  Future<void> _loadPacks() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await ApiSession.loadToken();
      final userId = ApiSession.currentUserId;
      if (userId == null || userId.isEmpty) {
        throw StateError('Please sign in before managing card packs.');
      }

      final remotePacks = await CardPackApiService.listCardPacks(
        creatorId: userId,
        limit: 100,
      );
      remotePacks.sort(_comparePackDate);
      if (!mounted) return;
      setState(() {
        _packs = remotePacks;
        _loading = false;
      });
    } catch (e) {
      try {
        final localPacks = await LocalCardPackService.listCardPacks();
        if (!mounted) return;
        setState(() {
          _packs = localPacks;
          _loading = false;
          _error = localPacks.isEmpty && !e.toString().contains('404')
              ? e.toString()
              : null;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  int _comparePackDate(CardPack left, CardPack right) {
    final leftDate = left.publishedAt ?? left.createdAt;
    final rightDate = right.publishedAt ?? right.createdAt;
    return rightDate.compareTo(leftDate);
  }

  Future<void> _openPack(CardPack pack) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CardPackDetailScreen(
          packId: pack.id,
          managementMode: true,
        ),
      ),
    );
    if (changed == true && mounted) {
      _loadPacks();
    }
  }

  Future<void> _createPack() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CardPackCreatorScreen()),
    );
    if (mounted) {
      _loadPacks();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textS = isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My card packs'),
        actions: [
          IconButton(
            tooltip: 'Create',
            onPressed: _createPack,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: textP))
          : _error != null
          ? _ErrorState(
              error: _error!,
              textP: textP,
              textS: textS,
              onRetry: _loadPacks,
            )
          : _packs.isEmpty
          ? _EmptyState(textP: textP, textS: textS, onCreate: _createPack)
          : RefreshIndicator(
              onRefresh: _loadPacks,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                itemCount: _packs.length,
                itemBuilder: (context, index) {
                  final pack = _packs[index];
                  return _ManagedPackTile(
                    pack: pack,
                    textP: textP,
                    textS: textS,
                    isDark: isDark,
                    onTap: () => _openPack(pack),
                  );
                },
              ),
            ),
    );
  }
}

class _ManagedPackTile extends StatelessWidget {
  const _ManagedPackTile({
    required this.pack,
    required this.textP,
    required this.textS,
    required this.isDark,
    required this.onTap,
  });

  final CardPack pack;
  final Color textP;
  final Color textS;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDark ? AppColors.darkSurface : Colors.white,
      child: ListTile(
        onTap: onTap,
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
                    fit: BoxFit.cover,
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: textP,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${pack.itemCount} items | ${pack.importCount} imports',
            style: TextStyle(fontSize: 12, color: textS),
          ),
        ),
        trailing: _StatusChip(status: pack.status, textP: textP, textS: textS),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.status,
    required this.textP,
    required this.textS,
  });

  final PackStatus status;
  final Color textP;
  final Color textS;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      PackStatus.published => 'Published',
      PackStatus.archived => 'Archived',
      PackStatus.draft => 'Draft',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: textS.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textP,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.textP,
    required this.textS,
    required this.onCreate,
  });

  final Color textP;
  final Color textS;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.collections_bookmark_outlined, size: 44, color: textS),
          const SizedBox(height: 10),
          Text(
            'No card packs yet',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: textP,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create card pack'),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.error,
    required this.textP,
    required this.textS,
    required this.onRetry,
  });

  final String error;
  final Color textP;
  final Color textS;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 44, color: textS),
            const SizedBox(height: 10),
            Text('Unable to load card packs', style: TextStyle(color: textP)),
            const SizedBox(height: 6),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: textS),
            ),
            const SizedBox(height: 16),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
