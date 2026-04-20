import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../l10n/app_strings_provider.dart';
import '../../../services/card_pack_api_service.dart';
import '../../../services/clothing_api_service.dart';
import '../../../services/local_card_pack_service.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/creator/clothing_item_selector.dart';

class CardPackCreatorScreen extends StatefulWidget {
  const CardPackCreatorScreen({super.key});

  @override
  State<CardPackCreatorScreen> createState() => _CardPackCreatorScreenState();
}

class _CardPackCreatorScreenState extends State<CardPackCreatorScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  List<Map<String, dynamic>> _availableItems = <Map<String, dynamic>>[];
  Set<String> _selectedItemIds = <String>{};
  File? _coverImageFile;
  Uint8List? _coverImageBytes;
  bool _loadingItems = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() {
      _loadingItems = true;
      _error = null;
    });

    try {
      final allItems = await ClothingApiService.listClothingItems(limit: 100);
      if (!mounted) {
        return;
      }
      setState(() {
        _availableItems = allItems;
        _loadingItems = false;
        if (allItems.isEmpty) {
          _error =
              'No clothing items found. Add or seed clothes first, then create a card pack from the same wardrobe data.';
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _availableItems = <Map<String, dynamic>>[];
        _loadingItems = false;
        _error = 'Failed to load clothing items: $error';
      });
    }
  }

  Future<void> _pickCoverImage() async {
    final pickedFile = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    if (pickedFile == null) {
      return;
    }

    if (kIsWeb) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _coverImageBytes = bytes;
        _coverImageFile = null;
      });
      return;
    }

    setState(() {
      _coverImageFile = File(pickedFile.path);
      _coverImageBytes = null;
    });
  }

  String? _encodeCoverImage() {
    try {
      Uint8List? bytes;
      if (kIsWeb) {
        bytes = _coverImageBytes;
      } else if (_coverImageFile != null) {
        bytes = _coverImageFile!.readAsBytesSync();
      }
      if (bytes == null) {
        return null;
      }
      return base64Encode(bytes);
    } catch (_) {
      return null;
    }
  }

  Future<void> _savePack({required bool publish}) async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter a name')));
      return;
    }

    if (_selectedItemIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one item')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final selectedItems = _availableItems
          .where((item) => _selectedItemIds.contains(item['id'].toString()))
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      final coverImageBase64 = _encodeCoverImage();
      try {
        final pack = await CardPackApiService.createCardPack(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          type: 'CLOTHING_COLLECTION',
          itemIds: _selectedItemIds.toList(),
          coverImageBase64: coverImageBase64,
        );
        if (publish) {
          await CardPackApiService.publishCardPack(pack.id);
        }
      } catch (_) {
        await LocalCardPackService.saveCardPack(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          type: 'CLOTHING_COLLECTION',
          itemIds: _selectedItemIds.toList(),
          coverImageBase64: coverImageBase64,
          published: publish,
          items: selectedItems,
        );
      }

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            publish
                ? 'Card pack published successfully!'
                : 'Card pack saved as draft!',
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $error')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
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
      appBar: AppBar(
        title: Text(s.createCardPack),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: () => _savePack(publish: false),
              child: Text(s.saveAsDraft),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Card pack and sub-wardrobe are treated as the same collection concept here. You are selecting only from the clothing currently in your wardrobe.',
              style: TextStyle(fontSize: 13, color: textS),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: s.cardPackName,
                labelStyle: TextStyle(color: textS),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              style: TextStyle(color: textP),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: s.cardPackDescription,
                labelStyle: TextStyle(color: textS),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              style: TextStyle(color: textP),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            Text(
              s.addCoverImage,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textP,
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickCoverImage,
              child: Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: _coverImageFile != null || _coverImageBytes != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: kIsWeb && _coverImageBytes != null
                            ? Image.memory(_coverImageBytes!, fit: BoxFit.cover)
                            : !kIsWeb && _coverImageFile != null
                            ? Image.file(_coverImageFile!, fit: BoxFit.cover)
                            : null,
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 48,
                            color: textS,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap to add cover image',
                            style: TextStyle(color: textS),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              s.selectItems,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textP,
              ),
            ),
            const SizedBox(height: 8),
            if (_loadingItems)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: CircularProgressIndicator(color: textP),
                ),
              )
            else if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: textS),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: TextStyle(fontSize: 13, color: textP),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _loadItems,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else
              ClothingItemSelector(
                items: _availableItems,
                selectedIds: _selectedItemIds,
                onSelectionChanged: (ids) {
                  setState(() => _selectedItemIds = ids);
                },
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : () => _savePack(publish: true),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(s.publish),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
