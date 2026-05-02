import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/card_pack.dart';
import '../../models/wardrobe.dart';
import '../../services/api_config.dart';
import '../../services/card_pack_api_service.dart';
import '../../services/import_api_service.dart';
import '../../services/local_card_pack_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/app_remote_image.dart';
import 'shared_clothing_detail_screen.dart';

class CardPackDetailScreen extends StatefulWidget {
  final String packId;

  const CardPackDetailScreen({super.key, required this.packId});

  @override
  State<CardPackDetailScreen> createState() => _CardPackDetailScreenState();
}

class _CardPackDetailScreenState extends State<CardPackDetailScreen> {
  CardPack? _pack;
  bool _loading = true;
  String? _error;
  bool _importing = false;

  List<Map<String, dynamic>> get _packItems =>
      _pack?.items ?? const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _loadPack();
  }

  Future<void> _loadPack() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    if (LocalCardPackService.isLocalPack(widget.packId)) {
      final localPack = await LocalCardPackService.getCardPack(widget.packId);
      if (localPack != null) {
        setState(() {
          _pack = localPack;
          _loading = false;
        });
        return;
      }
    }

    try {
      final pack = await CardPackApiService.getCardPack(widget.packId);
      if (!mounted) return;
      setState(() {
        _pack = pack;
        _loading = false;
      });
    } catch (e) {
      final localPack = await LocalCardPackService.getCardPack(widget.packId);
      if (!mounted) return;
      if (localPack != null) {
        setState(() {
          _pack = localPack;
          _loading = false;
        });
        return;
      }
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _importPack() async {
    if (_pack == null || _importing) return;
    setState(() => _importing = true);
    try {
      await ImportApiService.importCardPack(_pack!.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Card pack imported successfully!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _importing = false);
      }
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
      appBar: AppBar(title: const Text('Card Pack')),
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
                  TextButton(onPressed: _loadPack, child: const Text('Retry')),
                ],
              ),
            )
          : _pack == null
          ? const Center(child: Text('Pack not found'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_pack!.coverImageUrl != null)
                    Container(
                      width: double.infinity,
                      height: 220,
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurface : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: _buildCover(textS),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    _pack!.name,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: textP,
                    ),
                  ),
                  if (_pack!.description != null &&
                      _pack!.description!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _pack!.description!,
                      style: TextStyle(fontSize: 14, color: textS),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 16, color: textS),
                      const SizedBox(width: 4),
                      Text(
                        '${_pack!.itemCount} items',
                        style: TextStyle(fontSize: 12, color: textS),
                      ),
                      const SizedBox(width: 16),
                      Icon(Icons.download_outlined, size: 16, color: textS),
                      const SizedBox(width: 4),
                      Text(
                        '${_pack!.importCount} imports',
                        style: TextStyle(fontSize: 12, color: textS),
                      ),
                    ],
                  ),
                  if (_pack!.creatorUid != null ||
                      _pack!.wardrobeWid != null) ...[
                    const SizedBox(height: 12),
                    if (_pack!.creatorUid != null)
                      Text(
                        'Publisher UID: ${_pack!.creatorUid}',
                        style: TextStyle(fontSize: 12, color: textS),
                      ),
                    if (_pack!.wardrobeWid != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Shared wardrobe WID: ${_pack!.wardrobeWid}',
                        style: TextStyle(fontSize: 12, color: textS),
                      ),
                    ],
                  ],
                  const SizedBox(height: 24),
                  _buildItemsSection(textP, textS, isDark),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _importing ? null : _importPack,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _importing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text('Import to My Wardrobe'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildItemsSection(Color textP, Color textS, bool isDark) {
    if (_packItems.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Text(
          'No item details are available for this pack.',
          style: TextStyle(fontSize: 13, color: textS),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Items',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: textP,
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _packItems.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.68,
          ),
          itemBuilder: (context, index) {
            final item = _packItems[index];
            final name = (item['name'] as String?)?.trim();
            final coverUrl = item['coverUrl'] as String?;
            final tags = _tagValues(item['finalTags']);
            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _openPackItem(item),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Theme.of(context).dividerColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.18 : 0.07,
                      ),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: _buildItemImage(coverUrl, textS),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name?.isNotEmpty == true
                                ? name!
                                : item['clothingItemId'].toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                              color: textP,
                            ),
                          ),
                          if (tags.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              tags.take(2).join(' / '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: textS),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCover(Color textS) {
    final coverImageUrl = _pack!.coverImageUrl!;
    if (coverImageUrl.startsWith('data:image')) {
      try {
        final imageBytes = base64Decode(coverImageUrl.split(',')[1]);
        return Image.memory(
          imageBytes,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => _imageFallback(textS),
        );
      } catch (_) {
        return _imageFallback(textS);
      }
    }

    return Image.network(
      resolveFileUrl(coverImageUrl),
      headers: ApiSession.authHeaders,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => _imageFallback(textS),
    );
  }

  Widget _buildItemImage(String? imageUrl, Color textS) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return _imageFallback(textS);
    }
    return AppRemoteImage(
      url: imageUrl,
      fit: BoxFit.contain,
      placeholder: const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      errorWidget: _imageFallback(textS),
    );
  }

  Widget _imageFallback(Color textS) {
    return Container(
      width: double.infinity,
      color: textS.withValues(alpha: 0.1),
      child: Icon(Icons.image_outlined, color: textS),
    );
  }

  List<String> _tagValues(dynamic rawTags) {
    final tags = <String>[];
    for (final tag in rawTags as List<dynamic>? ?? const []) {
      if (tag is Map) {
        final value = tag['value'] ?? tag['key'];
        if (value != null && value.toString().trim().isNotEmpty) {
          tags.add(value.toString());
        }
      } else if (tag != null && tag.toString().trim().isNotEmpty) {
        tags.add(tag.toString());
      }
    }
    return tags;
  }

  void _openPackItem(Map<String, dynamic> item) {
    final clothingItemId = item['clothingItemId']?.toString();
    if (clothingItemId == null || clothingItemId.isEmpty || _pack == null) {
      return;
    }
    final brief = ClothingItemBrief(
      id: clothingItemId,
      name: item['name'] as String?,
      description: item['description'] as String?,
      source: 'OWNED',
      finalTags: item['finalTags'] as List<dynamic>? ?? const [],
      imageUrl: item['coverUrl'] as String?,
      images: {
        if (item['processedFrontUrl'] != null)
          'processedFrontUrl': item['processedFrontUrl'],
        if (item['originalFrontUrl'] != null)
          'originalFrontUrl': item['originalFrontUrl'],
        if (item['coverUrl'] != null) 'imageUrl': item['coverUrl'],
        if (item['angleViews'] != null) 'angleViews': item['angleViews'],
        if (item['model3dUrl'] != null) 'model3dUrl': item['model3dUrl'],
      },
      category: item['category'] as String?,
      material: item['material'] as String?,
      style: item['style'] as String?,
    );
    final wardrobe = Wardrobe(
      id: _pack!.wardrobeId ?? _pack!.id,
      wid: _pack!.wardrobeWid ?? '',
      userId: _pack!.creatorId,
      ownerUid: _pack!.creatorUid,
      ownerUsername: _pack!.creatorUsername,
      name: _pack!.name,
      kind: 'SUB',
      type: 'VIRTUAL',
      source: 'CARD_PACK',
      description: _pack!.description,
      coverImageUrl: _pack!.coverImageUrl,
      isPublic: true,
      itemCount: _pack!.itemCount,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SharedClothingDetailScreen(item: brief, wardrobe: wardrobe),
      ),
    );
  }
}
