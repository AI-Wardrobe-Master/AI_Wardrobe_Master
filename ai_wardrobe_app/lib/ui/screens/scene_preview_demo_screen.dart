import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/wardrobe.dart';
import '../../services/face_profile_service.dart';
import '../../services/wardrobe_service.dart';
import '../../theme/app_theme.dart';
import 'face_crop_screen.dart';

class ScenePreviewDemoScreen extends StatefulWidget {
  const ScenePreviewDemoScreen({super.key});

  @override
  State<ScenePreviewDemoScreen> createState() => _ScenePreviewDemoScreenState();
}

class _ScenePreviewDemoScreenState extends State<ScenePreviewDemoScreen> {
  static const _demoPreviewAsset =
      'assets/visualization/preview/generated_outfit_preview.jpg';

  final _sceneController = TextEditingController();
  final _picker = ImagePicker();
  final List<WardrobeItemWithClothing> _catalog = <WardrobeItemWithClothing>[];

  FaceProfile _faceProfile = const FaceProfile(kind: FaceProfileKind.none);
  Uint8List? _faceImageBytes;
  String? _selectedItemId;
  bool _loadingFaceProfile = true;
  bool _loadingCatalog = true;
  bool _showGeneratedDemo = false;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _textPrimary =>
      _isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
  Color get _textSecondary =>
      _isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
    _loadFaceProfile();
  }

  @override
  void dispose() {
    _sceneController.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    final items = <WardrobeItemWithClothing>[];
    try {
      final wardrobes = await WardrobeService.fetchWardrobes();
      final seen = <String>{};
      for (final wardrobe in wardrobes) {
        final wardrobeItems = await WardrobeService.fetchWardrobeItems(
          wardrobe.id,
        );
        for (final item in wardrobeItems) {
          if (seen.add(item.clothingItemId)) {
            items.add(item);
          }
        }
      }
    } catch (_) {}

    if (!mounted) {
      return;
    }
    setState(() {
      _catalog
        ..clear()
        ..addAll(items);
      _loadingCatalog = false;
      if (_selectedItemId == null && items.isNotEmpty) {
        _selectedItemId = items.first.clothingItemId;
      }
    });
  }

  Future<void> _loadFaceProfile() async {
    final profile = await FaceProfileService.load();
    final imageBytes = await FaceProfileService.resolveImageBytes(profile);
    if (!mounted) {
      return;
    }
    setState(() {
      _faceProfile = profile;
      _faceImageBytes = imageBytes;
      _loadingFaceProfile = false;
      _showGeneratedDemo = false;
    });
  }

  Future<void> _pickFaceImage() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) {
      return;
    }
    final bytes = await file.readAsBytes();
    if (!mounted) {
      return;
    }
    final cropped = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => FaceCropScreen(imageBytes: bytes)),
    );
    if (cropped == null) {
      return;
    }
    await FaceProfileService.saveCustom(cropped);
    await _loadFaceProfile();
  }

  String get _faceSourceLabel {
    switch (_faceProfile.kind) {
      case FaceProfileKind.custom:
        return 'Using profile face photo';
      case FaceProfileKind.virtualMale:
        return 'Using profile virtual male avatar';
      case FaceProfileKind.virtualFemale:
        return 'Using profile virtual female avatar';
      case FaceProfileKind.none:
        return 'No profile face source selected';
    }
  }

  String get _genderForGeneration {
    return _faceProfile.kind == FaceProfileKind.virtualFemale
        ? 'FEMALE'
        : 'MALE';
  }

  Future<void> _generatePreview() async {
    setState(() {
      _showGeneratedDemo = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = _catalog.cast<WardrobeItemWithClothing?>().firstWhere(
      (item) => item?.clothingItemId == _selectedItemId,
      orElse: () => null,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text(
          'Face + Scene Demo',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: _textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'This flow automatically uses the face source saved on your Profile page. Choose one clothing card and describe the scene to generate a preview.',
          style: TextStyle(fontSize: 13, height: 1.5, color: _textSecondary),
        ),
        const SizedBox(height: 16),
        _buildFaceCard(),
        const SizedBox(height: 16),
        _buildSceneField(),
        const SizedBox(height: 16),
        _buildCatalog(selected),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _selectedItemId == null || _faceImageBytes == null
              ? null
              : _generatePreview,
          icon: const Icon(Icons.auto_awesome_rounded),
          label: const Text('Generate Demo Preview'),
        ),
        const SizedBox(height: 16),
        if (_showGeneratedDemo) _buildResultCard(selected),
      ],
    );
  }

  Widget _buildFaceCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step 1: Profile Face Source',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 84,
                  height: 84,
                  color: _isDark
                      ? AppColors.darkBackground
                      : AppColors.background,
                  child: _loadingFaceProfile
                      ? const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _faceImageBytes == null
                      ? Icon(
                          Icons.face_6_outlined,
                          color: _textSecondary,
                          size: 34,
                        )
                      : Image.memory(_faceImageBytes!, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _faceSourceLabel,
                      style: TextStyle(fontSize: 13, color: _textPrimary),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _pickFaceImage,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text(
                            _faceImageBytes == null
                                ? 'Upload Profile Face'
                                : 'Change Profile Face',
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _loadFaceProfile,
                          icon: const Icon(Icons.sync_rounded),
                          label: const Text('Sync from Profile'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSceneField() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: TextField(
        controller: _sceneController,
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(
          labelText: 'Step 2: Scene Description',
          hintText: 'Example: warm afternoon cafe terrace with soft sunlight',
        ),
      ),
    );
  }

  Widget _buildCatalog(WardrobeItemWithClothing? selected) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step 3: Choose a Clothing Card',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          if (_loadingCatalog)
            const Center(child: CircularProgressIndicator())
          else if (_catalog.isEmpty)
            Text(
              'Add clothing to your wardrobe first, then come back here for the scene demo flow.',
              style: TextStyle(fontSize: 12, color: _textSecondary),
            )
          else
            DropdownButtonFormField<String>(
              initialValue: _selectedItemId,
              items: _catalog
                  .map(
                    (entry) => DropdownMenuItem<String>(
                      value: entry.clothingItemId,
                      child: Text(
                        entry.clothingItem?.name ?? entry.clothingItemId,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedItemId = value;
                  _showGeneratedDemo = false;
                });
              },
              decoration: const InputDecoration(labelText: 'Clothing card'),
            ),
          if (selected != null) ...[
            const SizedBox(height: 12),
            Text(
              'Selected: ${selected.clothingItem?.name ?? selected.clothingItemId}',
              style: TextStyle(fontSize: 12, color: _textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultCard(WardrobeItemWithClothing? selected) {
    final sceneText = _sceneController.text.trim().isEmpty
        ? 'No scene description entered.'
        : _sceneController.text.trim();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Demo Result',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.asset(_demoPreviewAsset, fit: BoxFit.cover),
          ),
          const SizedBox(height: 12),
          Text(
            'Face source: $_faceSourceLabel',
            style: TextStyle(fontSize: 12, color: _textSecondary),
          ),
          Text(
            'Generation gender hint: $_genderForGeneration',
            style: TextStyle(fontSize: 12, color: _textSecondary),
          ),
          Text(
            'Clothing card: ${selected?.clothingItem?.name ?? 'not selected'}',
            style: TextStyle(fontSize: 12, color: _textSecondary),
          ),
          Text(
            'Scene: $sceneText',
            style: TextStyle(fontSize: 12, color: _textSecondary),
          ),
          const SizedBox(height: 10),
          Text(
            'This is a fixed demo preview while the backend generative model is still pending deployment.',
            style: TextStyle(fontSize: 12, color: _textPrimary),
          ),
        ],
      ),
    );
  }
}
