import 'package:flutter/material.dart';

import '../../l10n/app_strings_provider.dart';
import '../../models/wardrobe.dart';
import '../../services/wardrobe_service.dart';
import '../../state/wardrobe_refresh_notifier.dart';
import '../../theme/app_theme.dart';
import '../widgets/app_remote_image.dart';
import 'wardrobe_screen.dart';

class ImportedLooksScreen extends StatefulWidget {
  const ImportedLooksScreen({super.key});

  @override
  State<ImportedLooksScreen> createState() => _ImportedLooksScreenState();
}

class _ImportedLooksScreenState extends State<ImportedLooksScreen> {
  List<Wardrobe> _wardrobes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WardrobeRefreshNotifier.tick.addListener(_handleRefresh);
    _loadImports();
  }

  @override
  void dispose() {
    WardrobeRefreshNotifier.tick.removeListener(_handleRefresh);
    super.dispose();
  }

  void _handleRefresh() {
    if (mounted) {
      _loadImports();
    }
  }

  Future<void> _loadImports() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final wardrobes = await WardrobeService.fetchWardrobes();
      final imported = wardrobes
          .where((wardrobe) => wardrobe.source == 'IMPORTED')
          .toList();
      if (!mounted) return;
      setState(() {
        _wardrobes = imported;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStringsProvider.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textS = isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;

    return Scaffold(
      appBar: AppBar(title: Text(s.importedLooks)),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: textP))
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: textS),
                  const SizedBox(height: 8),
                  Text('Error: $_error', style: TextStyle(color: textP)),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _loadImports,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : _wardrobes.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 48, color: textS),
                  const SizedBox(height: 8),
                  Text(
                    'No imported wardrobes yet',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textP,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Import a shared wardrobe from Discover to see it here',
                    style: TextStyle(fontSize: 12, color: textS),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadImports,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _wardrobes.length,
                itemBuilder: (context, index) {
                  final wardrobe = _wardrobes[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: isDark ? AppColors.darkSurface : Colors.white,
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 56,
                          height: 72,
                          child: wardrobe.coverImageUrl == null
                              ? Icon(Icons.inventory_2_outlined, color: textS)
                              : AppRemoteImage(
                                  url: wardrobe.coverImageUrl!,
                                  fit: BoxFit.cover,
                                ),
                        ),
                      ),
                      title: Text(
                        wardrobe.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: textP,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            wardrobe.description?.isNotEmpty == true
                                ? wardrobe.description!
                                : 'Imported shared wardrobe',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: textS),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.checkroom_outlined,
                                size: 14,
                                color: textS,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${wardrobe.itemCount} items',
                                style: TextStyle(fontSize: 12, color: textS),
                              ),
                              const Spacer(),
                              Text(
                                wardrobe.wid,
                                style: TextStyle(fontSize: 12, color: textS),
                              ),
                            ],
                          ),
                        ],
                      ),
                      trailing: Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 16,
                        color: textS,
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                WardrobeScreen(initialWardrobeId: wardrobe.id),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
    );
  }
}
