import 'package:flutter/material.dart';

import '../../../models/captured_image.dart';
import '../../../models/wardrobe.dart';
import '../../../services/wardrobe_service.dart';
import '../../../theme/app_theme.dart';
import 'processing_screen.dart';

class ClothingIntakeScreen extends StatefulWidget {
  const ClothingIntakeScreen({
    super.key,
    required this.frontImage,
    this.backImage,
  });

  final CapturedImage frontImage;
  final CapturedImage? backImage;

  @override
  State<ClothingIntakeScreen> createState() => _ClothingIntakeScreenState();
}

class _ClothingIntakeScreenState extends State<ClothingIntakeScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _tagController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _materialController = TextEditingController();
  final TextEditingController _styleController = TextEditingController();

  final List<String> _manualTags = <String>[];
  late final List<Map<String, String>> _autoTags;
  List<Wardrobe> _wardrobes = <Wardrobe>[];
  String? _selectedWardrobeId;
  bool _loadingWardrobes = true;
  bool _creatingWardrobe = false;

  @override
  void initState() {
    super.initState();
    _autoTags = <Map<String, String>>[
      const <String, String>{'key': 'intake', 'value': 'preview-ready'},
      <String, String>{
        'key': 'views',
        'value': widget.backImage == null ? 'front-only' : 'front-and-back',
      },
      const <String, String>{'key': 'pipeline', 'value': 'placeholder'},
    ];
    _nameController.text = widget.frontImage.filename.isNotEmpty
        ? widget.frontImage.filename.split('.').first
        : 'New Clothing Item';
    _loadWardrobes();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _tagController.dispose();
    _categoryController.dispose();
    _materialController.dispose();
    _styleController.dispose();
    super.dispose();
  }

  Future<void> _loadWardrobes() async {
    setState(() => _loadingWardrobes = true);
    try {
      final wardrobes = await WardrobeService.fetchWardrobes();
      if (!mounted) {
        return;
      }
      setState(() {
        _wardrobes = wardrobes;
        _selectedWardrobeId = wardrobes.isNotEmpty
            ? wardrobes
                  .firstWhere(
                    (wardrobe) => wardrobe.isMain,
                    orElse: () => wardrobes.first,
                  )
                  .id
            : null;
        _loadingWardrobes = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _loadingWardrobes = false);
    }
  }

  Future<void> _createCardPack() async {
    if (_creatingWardrobe) {
      return;
    }
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Card Pack'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Card pack name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    final name = controller.text.trim();
    if (name.isEmpty) {
      return;
    }
    setState(() => _creatingWardrobe = true);
    try {
      final wardrobe = await WardrobeService.createWardrobe(name: name);
      if (!mounted) {
        return;
      }
      setState(() {
        _wardrobes = <Wardrobe>[..._wardrobes, wardrobe];
        _selectedWardrobeId = wardrobe.id;
      });
    } finally {
      if (mounted) {
        setState(() => _creatingWardrobe = false);
      }
    }
  }

  void _addTag() {
    final value = _tagController.text.trim();
    if (value.isEmpty || _manualTags.contains(value)) {
      _tagController.clear();
      return;
    }
    setState(() {
      _manualTags.add(value);
      _tagController.clear();
    });
  }

  void _saveAndContinue() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ProcessingScreen(
          frontImage: widget.frontImage,
          backImage: widget.backImage,
          itemName: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          manualTags: _manualTags,
          autoTags: _autoTags,
          category: _categoryController.text.trim().isEmpty
              ? null
              : _categoryController.text.trim(),
          material: _materialController.text.trim().isEmpty
              ? null
              : _materialController.text.trim(),
          style: _styleController.text.trim().isEmpty
              ? null
              : _styleController.text.trim(),
          targetWardrobeId: _selectedWardrobeId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textS = isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;

    return Scaffold(
      appBar: AppBar(title: const Text('Clothing Preview')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Review and complete the clothing card before saving. The AI pipeline fields below are already wired for placeholder classification, background removal, and 3D preview generation.',
                style: TextStyle(fontSize: 13, color: textS, height: 1.5),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildImageCard(widget.frontImage, 'Front')),
                  const SizedBox(width: 12),
                  Expanded(
                    child: widget.backImage == null
                        ? _buildEmptyBackCard(textS)
                        : _buildImageCard(widget.backImage!, 'Back'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildTextField(
                controller: _nameController,
                label: 'Name',
                textColor: textP,
                hintColor: textS,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _descriptionController,
                label: 'Description',
                textColor: textP,
                hintColor: textS,
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _categoryController,
                      label: 'Category',
                      textColor: textP,
                      hintColor: textS,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTextField(
                      controller: _materialController,
                      label: 'Material',
                      textColor: textP,
                      hintColor: textS,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _styleController,
                label: 'Style',
                textColor: textP,
                hintColor: textS,
              ),
              const SizedBox(height: 20),
              Text(
                'Auto Tags',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: textP,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _autoTags
                    .map(
                      (tag) => _TagChip(
                        label: '${tag['key']}: ${tag['value']}',
                        color: AppColors.accentBlue.withValues(alpha: 0.12),
                        textColor: textP,
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 20),
              Text(
                'Manual Tags',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: textP,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _tagController,
                      label: 'Add a tag',
                      textColor: textP,
                      hintColor: textS,
                      onSubmitted: (_) => _addTag(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _addTag, child: const Text('Add')),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _manualTags
                    .map(
                      (tag) => InputChip(
                        label: Text(tag),
                        onDeleted: () {
                          setState(() => _manualTags.remove(tag));
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Save To',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: textP,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _creatingWardrobe ? null : _createCardPack,
                    icon: const Icon(Icons.add),
                    label: const Text('New Card Pack'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_loadingWardrobes)
                const LinearProgressIndicator()
              else
                DropdownButtonFormField<String>(
                  value: _selectedWardrobeId,
                  items: _wardrobes
                      .map(
                        (wardrobe) => DropdownMenuItem<String>(
                          value: wardrobe.id,
                          child: Text(
                            wardrobe.isMain
                                ? '${wardrobe.name} (Main Wardrobe)'
                                : wardrobe.name,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() => _selectedWardrobeId = value);
                  },
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkSurface.withValues(alpha: 0.5)
                      : AppColors.background,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Text(
                  '3D preview is currently a placeholder SVG. The save flow will still keep the full pipeline contract so a deployed model can replace only the processing function later.',
                  style: TextStyle(fontSize: 12, color: textS, height: 1.5),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saveAndContinue,
                      child: const Text('Save and Process'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageCard(CapturedImage image, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 0.8,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: image.buildImage(),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyBackCard(Color textS) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Back', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 0.8,
          child: Container(
            decoration: BoxDecoration(
              color: textS.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: textS.withValues(alpha: 0.2)),
            ),
            child: Center(
              child: Text('Optional', style: TextStyle(color: textS)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required Color textColor,
    required Color hintColor,
    int maxLines = 1,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: hintColor),
        border: const OutlineInputBorder(),
      ),
      style: TextStyle(color: textColor),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.color,
    required this.textColor,
  });

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
