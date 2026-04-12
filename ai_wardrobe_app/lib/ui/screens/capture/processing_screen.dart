import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

import '../../../services/clothing_api_service.dart';
import '../../../services/local_clothing_service.dart';
import '../../../theme/app_theme.dart';
import 'clothing_result_screen.dart';

class ProcessingScreen extends StatefulWidget {
  final File frontImage;
  final File? backImage;

  const ProcessingScreen({
    super.key,
    required this.frontImage,
    this.backImage,
  });

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  String _status = 'Uploading...';
  double _progress = 0;
  String? _itemId;
  String? _error;
  Timer? _pollTimer;

  final _steps = <String, String>{
    'upload': 'pending',
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
      setState(() {
        _status = 'Uploading images...';
        _progress = 0.05;
        _steps['upload'] = 'processing';
        _error = null;
      });

      final result = await ClothingApiService.createClothingItem(
        frontImage: widget.frontImage,
        backImage: widget.backImage,
      );

      final responseData = result['data'] as Map<String, dynamic>? ?? result;
      final processingTaskId = responseData['processingTaskId'] as String?;
      final itemId = responseData['id'] as String?;

      if (itemId == null && processingTaskId == null) {
        throw Exception('Invalid response: missing item ID or processing task ID');
      }

      _itemId = itemId ?? processingTaskId;
      setState(() {
        _steps['upload'] = 'completed';
        _progress = 0.1;
        _status = 'Upload successful! Processing...';
      });

      await Future.delayed(const Duration(milliseconds: 500));
      _startPolling();
    } catch (e) {
      setState(() {
        _error =
            'Upload failed: $e\n\nPlease check:\n1. Backend is running\n2. Network connection\n3. Image file is valid';
        _status = 'Upload failed';
        _steps['upload'] = 'failed';
      });
    }
  }

  void _startPolling() {
    int consecutiveErrors = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_itemId == null) return;
      try {
        final response = await ClothingApiService.getProcessingStatus(_itemId!);
        final data = response['data'] as Map<String, dynamic>? ?? response;
        final status = data['status'] as String? ?? '';
        final progress = (data['progress'] as num?)?.toDouble() ?? 0;
        final steps = data['steps'] as Map<String, dynamic>? ?? {};
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
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            _onCompleted();
          }
        } else if (status == 'FAILED') {
          _pollTimer?.cancel();
          setState(() {
            _error =
                data['errorMessage'] as String? ?? 'Processing failed. Please try again.';
            _status = 'Processing failed';
          });
        }
      } catch (_) {
        consecutiveErrors++;
        if (consecutiveErrors >= 5) {
          _pollTimer?.cancel();
          setState(() {
            _error =
                'Failed to check processing status.\n\nPlease check:\n1. Backend is running\n2. Network connection\n3. Try refreshing the page';
            _status = 'Connection error';
          });
        }
      }
    });
  }

  String _statusLabel(Map<String, dynamic> steps) {
    if (steps['angleRendering'] == 'processing') return 'Rendering angles...';
    if (steps['modelGeneration'] == 'processing') return 'Generating 3D model...';
    if (steps['backgroundRemoval'] == 'processing') return 'Removing background...';
    return 'Processing...';
  }

  void _onCompleted() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ClothingResultScreen(itemId: _itemId!),
      ),
    );
  }

  Future<void> _saveAsSimplified() async {
    try {
      setState(() {
        _status = 'Saving as simplified item...';
      });

      // This fallback keeps the upload flow usable for front-end testing even
      // when 3D generation or the backend pipeline is unavailable.
      await LocalClothingService.saveSimplifiedItem(
        frontImageBytes: await widget.frontImage.readAsBytes(),
        backImageBytes:
            widget.backImage != null ? await widget.backImage!.readAsBytes() : null,
        name: 'Imported Item',
        description: 'Simplified item (3D processing skipped)',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Item saved as simplified version! You can now use it in card packs.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
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
    final textS = isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              const Spacer(flex: 2),
              // Animation / icon
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.accentYellow.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: _error != null
                    ? Icon(Icons.error_outline, size: 48, color: Colors.redAccent)
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
              ),
              const SizedBox(height: 24),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _error != null ? 0 : _progress,
                  minHeight: 8,
                  backgroundColor: isDark ? Colors.white12 : Colors.black12,
                  valueColor: AlwaysStoppedAnimation(AppColors.accentBlue),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(_progress * 100).toInt()}%',
                style: TextStyle(fontSize: 13, color: textS),
              ),
              const SizedBox(height: 32),
              // Step list
              ..._steps.entries.map((e) => _StepRow(
                    label: _stepLabel(e.key),
                    status: e.value,
                  )),
              const Spacer(flex: 3),
              // Error retry
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
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
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
                        '3D processing failed, but you can save this as a simplified item for card packs',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: textP, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _saveAsSimplified,
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: const Text('Save as Simplified Item'),
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
      'backgroundRemoval' => 'Background Removal',
      'modelGeneration' => '3D Model Generation',
      'angleRendering' => 'Angle Rendering',
      _ => key,
    };
  }
}

class _StepRow extends StatelessWidget {
  final String label;
  final String status;

  const _StepRow({required this.label, required this.status});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final icon = switch (status) {
      'completed' => Icon(Icons.check_circle, color: Colors.green, size: 20),
      'processing' => SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      'failed' => Icon(Icons.cancel, color: Colors.redAccent, size: 20),
      _ => Icon(Icons.circle_outlined,
          color: isDark ? Colors.white24 : Colors.black26, size: 20),
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
              fontWeight:
                  status == 'processing' ? FontWeight.w600 : FontWeight.w400,
              color: status == 'pending'
                  ? (isDark ? Colors.white38 : Colors.black38)
                  : (isDark ? AppColors.darkTextPrimary : AppColors.textPrimary),
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
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _ctrl,
      child: const Icon(
        Icons.view_in_ar,
        size: 48,
        color: AppColors.accentBlue,
      ),
    );
  }
}
