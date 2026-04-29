import 'package:flutter/material.dart';

import '../../l10n/app_strings_provider.dart';
import '../../models/import_history.dart';
import '../../services/import_api_service.dart';
import '../../theme/app_theme.dart';
import 'card_pack_detail_screen.dart';

class ImportedLooksScreen extends StatefulWidget {
  const ImportedLooksScreen({super.key});

  @override
  State<ImportedLooksScreen> createState() => _ImportedLooksScreenState();
}

class _ImportedLooksScreenState extends State<ImportedLooksScreen> {
  List<ImportHistory> _imports = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadImports();
  }

  Future<void> _loadImports() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final imports = await ImportApiService.getImportHistory();
      if (!mounted) return;
      setState(() {
        _imports = imports;
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
    final textS = isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

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
              : _imports.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              size: 48, color: textS),
                          const SizedBox(height: 8),
                          Text(
                            'No imported looks yet',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: textP,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Import card packs from creators to see them here',
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
                        itemCount: _imports.length,
                        itemBuilder: (context, index) {
                          final import = _imports[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            color: isDark ? AppColors.darkSurface : Colors.white,
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(16),
                              title: Text(
                                import.cardPackName,
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
                                    'by ${import.creatorName}',
                                    style: TextStyle(fontSize: 12, color: textS),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(Icons.inventory_2_outlined,
                                          size: 14, color: textS),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${import.itemCount} items',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: textS,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        _formatDate(import.importedAt),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: textS,
                                        ),
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
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CardPackDetailScreen(
                                      packId: import.cardPackId,
                                    ),
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

  String _formatDate(DateTime date) {
    final difference = DateTime.now().difference(date);
    if (difference.inDays == 0) return 'Today';
    if (difference.inDays == 1) return 'Yesterday';
    if (difference.inDays < 7) return '${difference.inDays} days ago';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
