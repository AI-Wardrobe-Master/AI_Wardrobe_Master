import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../services/clothing_api_service.dart';
import '../../../services/local_clothing_service.dart';
import '../../../services/wardrobe_service.dart';
import '../../../theme/app_theme.dart';
import 'clothing_result_screen.dart';

class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({
    super.key,
    required this.frontImage,
    this.backImage,
    this.itemName,
    this.description,
    this.manualTags = const <String>[],
    this.autoTags = const <Map<String, String>>[],
    this.category,
    this.material,
    this.style,
    this.targetWardrobeId,
  });

  final File frontImage;
  final File? backImage;
  final String? itemName;
  final String? description;
  final List<String> manualTags;
  final List<Map<String, String>> autoTags;
  final String? category;
  final String? material;
  final String? style;
  final String? targetWardrobeId;

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  String _status = 'Uploading...';
  double _progress = 0;
  String? _itemId;
  String? _error;
  Timer? _pollTimer;

  final Map<String, String> _steps = <String, String>{
    'upload': 'pending',
    'classification': 'pending',
    'backgroundRemoval': 'pending',
    'modelGeneration': 'pending',
    'angleRendering': 'pending',
  };

  @override
  void initState() {
    super.initState();
    _startUpload();
  }

  Future<void> _startUpload() async {
    try {
      final frontBytes = await widget.frontImage.readAsBytes();
      final backBytes = widget.backImage == null
          ? null
          : await widget.backImage!.readAsBytes();
      setState(() {
        _status = 'Uploading images...';
        _progress = 0.05;
        _steps['upload'] = 'processing';
        _error = null;
      });

      final result = await ClothingApiService.createClothingItem(
        frontImage: widget.frontImage,
        backImage: widget.backImage,
        name: widget.itemName,
        description: widget.description,
        manualTags: widget.manualTags,
        category: widget.category,
        material: widget.material,
        style: widget.style,
        wardrobeId: widget.targetWardrobeId,
      );

      final responseData = result['data'] as Map<String, dynamic>? ?? result;
      final processingTaskId = responseData['processingTaskId'] as String?;
      final itemId = responseData['id'] as String?;

      if (itemId == null && processingTaskId == null) {
        throw Exception(
          'Invalid response: missing item ID or processing task ID',
        );
      }

      if (itemId != null) {
        await LocalClothingService.cacheRemoteItem(
          <String, dynamic>{
            'id': itemId,
            'name': widget.itemName?.trim().isNotEmpty == true
                ? widget.itemName!.trim()
                : 'Imported Item',
            'description': widget.description ?? '',
            'source': 'OWNED',
            'sourceType': 'MANUAL_CAPTURE',
            'syncStatus': 'PENDING_SYNC',
            'predictedTags': widget.autoTags,
            'finalTags': <Map<String, String>>[
              ...widget.autoTags,
              ...widget.manualTags.map(
                (tag) => <String, String>{'key': 'manual', 'value': tag},
              ),
              if ((widget.category ?? '').trim().isNotEmpty)
                <String, String>{
                  'key': 'category',
                  'value': widget.category!.trim(),
                },
              if ((widget.material ?? '').trim().isNotEmpty)
                <String, String>{
                  'key': 'material',
                  'value': widget.material!.trim(),
                },
              if ((widget.style ?? '').trim().isNotEmpty)
                <String, String>{'key': 'style', 'value': widget.style!.trim()},
            ],
            'customTags': widget.manualTags,
            'category': widget.category,
            'material': widget.material,
            'style': widget.style,
            'images': <String, dynamic>{
              'originalFrontUrl':
                  'data:image/jpeg;base64,${base64Encode(frontBytes)}',
              'processedFrontUrl':
                  'data:image/jpeg;base64,${base64Encode(frontBytes)}',
              if (backBytes != null)
                'originalBackUrl':
                    'data:image/jpeg;base64,${base64Encode(backBytes)}',
              if (backBytes != null)
                'processedBackUrl':
                    'data:image/jpeg;base64,${base64Encode(backBytes)}',
            },
          },
          wardrobeIds: widget.targetWardrobeId == null
              ? const <String>[]
              : <String>[widget.targetWardrobeId!],
        );
      }

      _itemId = itemId ?? processingTaskId;
      setState(() {
        _steps['upload'] = 'completed';
        _steps['classification'] = 'processing';
        _progress = 0.1;
        _status = 'Upload successful! Processing...';
      });

      await Future<void>.delayed(const Duration(milliseconds: 500));
      _startPolling();
    } catch (error) {
      setState(() {
        _error =
            'Upload failed: $error\n\nYou can still save this clothing item locally and continue using it offline.';
        _status = 'Upload failed';
        _steps['upload'] = 'failed';
      });
    }
  }

  void _startPolling() {
    int consecutiveErrors = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_itemId == null) {
        return;
      }
      try {
        final response = await ClothingApiService.getProcessingStatus(_itemId!);
        final data = response['data'] as Map<String, dynamic>? ?? response;
        final status = data['status'] as String? ?? '';
        final progress = (data['progress'] as num?)?.toDouble() ?? 0;
        final steps =
            data['steps'] as Map<String, dynamic>? ?? <String, dynamic>{};
        consecutiveErrors = 0;

        setState(() {
          _progress = progress / 100;
          for (final entry in steps.entries) {
            _steps[entry.key] = entry.value as String;
          }
          _status = _statusLabel(steps);
        });

        if (status == 'COMPLETED') {
          _pollTimer?.cancel();
          setState(() {
            _progress = 1.0;
            _status = 'Processing completed!';
          });
          await Future<void>.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            await _finalizeRemoteItem();
          }
        } else if (status == 'FAILED') {
          _pollTimer?.cancel();
          setState(() {
            _error =
                data['errorMessage'] as String? ??
                'Processing failed. You can save locally instead.';
            _status = 'Processing failed';
          });
        }
      } catch (_) {
        consecutiveErrors++;
        if (consecutiveErrors >= 5) {
          _pollTimer?.cancel();
          setState(() {
            _error =
                'Failed to check processing status. You can still save the clothing item locally.';
            _status = 'Connection error';
          });
        }
      }
    });
  }

  String _statusLabel(Map<String, dynamic> steps) {
    if (steps['angleRendering'] == 'processing') return 'Rendering angles...';
    if (steps['modelGeneration'] == 'processing')
      return 'Generating 3D preview...';
    if (steps['backgroundRemoval'] == 'processing')
      return 'Removing background...';
    if (steps['classification'] == 'processing')
      return 'Generating placeholder classification...';
    return 'Processing...';
  }

  Future<void> _finalizeRemoteItem() async {
    if (_itemId == null) {
      return;
    }
    final mergedTags = <Map<String, String>>[
      ...widget.autoTags,
      ...widget.manualTags.map(
        (tag) => <String, String>{'key': 'manual', 'value': tag},
      ),
      if ((widget.category ?? '').trim().isNotEmpty)
        <String, String>{'key': 'category', 'value': widget.category!.trim()},
      if ((widget.material ?? '').trim().isNotEmpty)
        <String, String>{'key': 'material', 'value': widget.material!.trim()},
      if ((widget.style ?? '').trim().isNotEmpty)
        <String, String>{'key': 'style', 'value': widget.style!.trim()},
    ];

    await ClothingApiService.updateClothingItem(
      _itemId!,
      name: widget.itemName,
      description: widget.description,
      finalTags: mergedTags,
      customTags: widget.manualTags,
      isConfirmed: true,
      category: widget.category,
      material: widget.material,
      style: widget.style,
      wardrobeIds: widget.targetWardrobeId == null
          ? null
          : <String>[widget.targetWardrobeId!],
    );

    if (widget.targetWardrobeId != null) {
      await WardrobeService.addItemToWardrobe(
        widget.targetWardrobeId!,
        _itemId!,
      );
    }

    if (!mounted) {
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ClothingResultScreen(itemId: _itemId!),
      ),
    );
  }

  Future<void> _saveOffline() async {
    try {
      setState(() {
        _status = 'Saving locally...';
      });
      final itemId = await LocalClothingService.saveItem(
        frontImageBytes: await widget.frontImage.readAsBytes(),
        backImageBytes: widget.backImage == null
            ? null
            : await widget.backImage!.readAsBytes(),
        name: widget.itemName?.trim().isNotEmpty == true
            ? widget.itemName!.trim()
            : 'Imported Item',
        description: widget.description,
        autoTags: widget.autoTags,
        manualTags: widget.manualTags,
        category: widget.category,
        material: widget.material,
        style: widget.style,
        wardrobeIds: widget.targetWardrobeId == null
            ? const <String>[]
            : <String>[widget.targetWardrobeId!],
      );

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Clothing item saved locally. It will remain available even if the backend is offline.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ClothingResultScreen(itemId: itemId),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save locally: $error')));
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textS = isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.accentYellow.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: _error != null
                    ? const Icon(
                        Icons.error_outline,
                        size: 48,
                        color: Colors.redAccent,
                      )
                    : const _SpinningIcon(),
              ),
              const SizedBox(height: 32),
              Text(
                _status,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: textP,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _error != null ? 0 : _progress,
                  minHeight: 8,
                  backgroundColor: isDark ? Colors.white12 : Colors.black12,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.accentBlue,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(_progress * 100).toInt()}%',
                style: TextStyle(fontSize: 13, color: textS),
              ),
              const SizedBox(height: 32),
              ..._steps.entries.map(
                (entry) =>
                    _StepRow(label: _stepLabel(entry.key), status: entry.value),
              ),
              const Spacer(flex: 3),
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.accentYellow.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.accentYellow.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'The remote AI pipeline is unavailable right now. You can save the clothing card locally with the same metadata and keep working offline.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: textP, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _saveOffline,
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: const Text('Save Offline Instead'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accentYellow,
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Go Back'),
                    ),
                    const SizedBox(width: 12),
                    if (_itemId != null)
                      FilledButton(
                        onPressed: () {
                          setState(() {
                            _error = null;
                            _status = 'Retrying...';
                          });
                          _startPolling();
                        },
                        child: const Text('Retry'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _stepLabel(String key) {
    return switch (key) {
      'upload' => 'Upload',
      'classification' => 'Auto Classification',
      'backgroundRemoval' => 'Background Removal',
      'modelGeneration' => '3D Preview Generation',
      'angleRendering' => 'Angle Rendering',
      _ => key,
    };
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.label, required this.status});

  final String label;
  final String status;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final icon = switch (status) {
      'completed' => const Icon(
        Icons.check_circle,
        color: Colors.green,
        size: 20,
      ),
      'processing' => const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      'failed' => const Icon(Icons.cancel, color: Colors.redAccent, size: 20),
      _ => Icon(
        Icons.circle_outlined,
        color: isDark ? Colors.white24 : Colors.black26,
        size: 20,
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: status == 'processing'
                  ? FontWeight.w600
                  : FontWeight.w400,
              color: status == 'pending'
                  ? (isDark ? Colors.white38 : Colors.black38)
                  : (isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpinningIcon extends StatefulWidget {
  const _SpinningIcon();

  @override
  State<_SpinningIcon> createState() => _SpinningIconState();
}

class _SpinningIconState extends State<_SpinningIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: const Icon(
        Icons.view_in_ar,
        size: 48,
        color: AppColors.accentBlue,
      ),
    );
  }
}
