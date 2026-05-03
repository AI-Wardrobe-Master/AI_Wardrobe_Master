import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/wardrobe.dart';
import '../../services/api_config.dart';
import '../../services/wardrobe_service.dart';
import '../../state/wardrobe_refresh_notifier.dart';
import '../../theme/app_theme.dart';
import 'shared_clothing_detail_screen.dart';
import 'wardrobe_screen.dart';

class SharedWardrobeDetailScreen extends StatefulWidget {
  const SharedWardrobeDetailScreen({super.key, required this.wardrobeWid});

  final String wardrobeWid;

  @override
  State<SharedWardrobeDetailScreen> createState() =>
      _SharedWardrobeDetailScreenState();
}

class _SharedWardrobeDetailScreenState
    extends State<SharedWardrobeDetailScreen> {
  Wardrobe? _wardrobe;
  List<WardrobeItemWithClothing> _items = [];
  bool _loading = true;
  bool _importing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final wardrobe = await WardrobeService.fetchWardrobeByWid(
        widget.wardrobeWid,
        cacheRemote: false,
      );
      if (wardrobe == null) {
        throw Exception('Shared wardrobe not found');
      }
      final items = await WardrobeService.fetchPublicWardrobeItemsByWid(
        widget.wardrobeWid,
      );
      if (!mounted) return;
      setState(() {
        _wardrobe = wardrobe;
        _items = items;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.textPrimary;
    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;

    return Scaffold(
      appBar: AppBar(title: const Text('Shared Wardrobe')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 40, color: textSecondary),
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: textSecondary)),
                  const SizedBox(height: 12),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          : _wardrobe == null
          ? const Center(child: Text('Shared wardrobe not found'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  Text(
                    _wardrobe!.name,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_wardrobe!.description?.isNotEmpty == true)
                    Text(
                      _wardrobe!.description!,
                      style: TextStyle(fontSize: 14, color: textSecondary),
                    ),
                  const SizedBox(height: 16),
                  _MetaLine(
                    label: 'WID',
                    value: _wardrobe!.wid,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                  ),
                  if (_wardrobe!.ownerUid?.isNotEmpty == true)
                    _MetaLine(
                      label: 'Publisher UID',
                      value: _wardrobe!.ownerUid!,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                    ),
                  if (_wardrobe!.ownerUsername?.isNotEmpty == true)
                    _MetaLine(
                      label: 'Publisher',
                      value: _wardrobe!.ownerUsername!,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _importing || _items.isEmpty
                          ? null
                          : _importWardrobe,
                      icon: _importing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_rounded),
                      label: Text(
                        _importing ? 'Importing...' : 'Import to My Wardrobe',
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Items',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_items.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurface : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        _wardrobe!.source == 'CARD_PACK'
                            ? 'This shared wardrobe is a discoverable card-pack entry. Open the pack feed for item-level import details.'
                            : 'No public clothing items are attached yet.',
                        style: TextStyle(fontSize: 13, color: textSecondary),
                      ),
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.74,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                          ),
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final entry = _items[index];
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: entry.clothingItem == null
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          SharedClothingDetailScreen(
                                            item: entry.clothingItem!,
                                            wardrobe: _wardrobe!,
                                          ),
                                    ),
                                  );
                                },
                          child: Card(
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: _buildItemImage(
                                    entry.clothingItem?.previewImageUrl,
                                    textSecondary,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(
                                    entry.clothingItem?.name ??
                                        entry.clothingItemId,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildItemImage(String? imageUrl, Color textSecondary) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return _imageFallback(textSecondary);
    }
    if (imageUrl.startsWith('data:')) {
      try {
        final uri = Uri.parse(imageUrl);
        final data = uri.data;
        if (data != null) {
          return Image.memory(data.contentAsBytes(), fit: BoxFit.contain);
        }
      } catch (_) {}
      return _imageFallback(textSecondary);
    }
    if (imageUrl.startsWith('data:image')) {
      try {
        final imageBytes = base64Decode(imageUrl.split(',')[1]);
        return Image.memory(imageBytes, fit: BoxFit.contain);
      } catch (_) {
        return _imageFallback(textSecondary);
      }
    }
    return CachedNetworkImage(
      imageUrl: resolveFileUrl(imageUrl),
      httpHeaders: ApiSession.authHeaders,
      fit: BoxFit.contain,
      errorWidget: (context, url, error) => _imageFallback(textSecondary),
      placeholder: (context, url) =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  Widget _imageFallback(Color textSecondary) {
    return Container(
      color: textSecondary.withValues(alpha: 0.1),
      child: Icon(Icons.checkroom_rounded, color: textSecondary),
    );
  }

  Future<void> _importWardrobe() async {
    final wardrobe = _wardrobe;
    if (wardrobe == null) {
      return;
    }
    setState(() => _importing = true);
    try {
      final imported = await WardrobeService.importSharedWardrobe(
        wardrobeWid: wardrobe.wid,
      );
      WardrobeRefreshNotifier.requestRefresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Imported "${imported.name}" to your wardrobe.'),
        ),
      );
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WardrobeScreen(initialWardrobeId: imported.id),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) {
        setState(() => _importing = false);
      }
    }
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.label,
    required this.value,
    required this.textPrimary,
    required this.textSecondary,
  });

  final String label;
  final String value;
  final Color textPrimary;
  final Color textSecondary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13, color: textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
