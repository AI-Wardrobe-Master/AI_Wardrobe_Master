import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

import '../../../services/clothing_api_service.dart';
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
      });

      final result = await ClothingApiService.createClothingItem(
        frontImage: widget.frontImage,
        backImage: widget.backImage,
      );

      _itemId = result['id'] as String;
      setState(() {
        _steps['upload'] = 'completed';
        _status = 'Processing...';
      });

      _startPolling();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _status = 'Upload failed';
      });
    }
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_itemId == null) return;
      try {
        final data = await ClothingApiService.getProcessingStatus(_itemId!);
        final status = data['status'] as String? ?? '';
        final progress = (data['progress'] as num?)?.toDouble() ?? 0;
        final steps = data['steps'] as Map<String, dynamic>? ?? {};

        setState(() {
          _progress = progress / 100;
          for (final entry in steps.entries) {
            _steps[entry.key] = entry.value as String;
          }
          _status = _statusLabel(steps);
        });

        if (status == 'COMPLETED') {
          _pollTimer?.cancel();
          _onCompleted();
        } else if (status == 'FAILED') {
          _pollTimer?.cancel();
          setState(() {
            _error = data['errorMessage'] as String? ?? 'Processing failed';
            _status = 'Failed';
          });
        }
      } catch (_) {}
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
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Go Back'),
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
