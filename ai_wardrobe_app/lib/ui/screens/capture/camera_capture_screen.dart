import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../theme/app_theme.dart';
import 'image_preview_screen.dart';

class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  CameraController? _controller;
  bool _isReady = false;
  bool _isCapturing = false;

  bool _capturingFront = true; // true = front phase, false = back phase
  File? _frontImage;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _showFallbackPicker();
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _controller = CameraController(back, ResolutionPreset.high);
      await _controller!.initialize();
      if (mounted) setState(() => _isReady = true);
    } catch (_) {
      _showFallbackPicker();
    }
  }

  void _showFallbackPicker() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) {
      if (mounted) Navigator.pop(context);
      return;
    }
    _onPhotoCaptured(File(picked.path));
  }

  Future<void> _takePhoto() async {
    if (_controller == null || _isCapturing) return;
    setState(() => _isCapturing = true);
    try {
      final xFile = await _controller!.takePicture();
      _onPhotoCaptured(File(xFile.path));
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  void _onPhotoCaptured(File photo) {
    Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ImagePreviewScreen(
          imageFile: photo,
          label: _capturingFront ? 'Front View' : 'Back View',
        ),
      ),
    ).then((confirmed) {
      if (confirmed != true) return;

      if (_capturingFront) {
        setState(() {
          _frontImage = photo;
          _capturingFront = false;
        });
        _showBackPrompt();
      } else {
        _finishCapture(photo);
      }
    });
  }

  void _showBackPrompt() {
    showModalBottomSheet<String>(
      context: context,
      isDismissible: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.flip_camera_android_rounded, size: 40),
                const SizedBox(height: 12),
                const Text(
                  'Capture the back?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'A back photo improves 3D quality.\nYou can skip if you prefer.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(ctx).textTheme.bodySmall?.color,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, 'skip'),
                        child: const Text('Skip'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, 'capture'),
                        child: const Text('Capture Back'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ).then((choice) {
      if (choice == 'skip') {
        _finishCapture(null);
      }
      // else stay on camera for back capture
    });
  }

  void _finishCapture(File? backImage) {
    Navigator.pop(context, {'front': _frontImage, 'back': backImage});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Camera preview
            if (_isReady && _controller != null)
              Positioned.fill(child: CameraPreview(_controller!))
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            // Top bar
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  _circleButton(Icons.close, () => Navigator.pop(context)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _capturingFront ? 'Front' : 'Back',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const Spacer(),
                  _circleButton(
                    Icons.photo_library_outlined,
                    _showFallbackPicker,
                  ),
                ],
              ),
            ),

            // Guide overlay
            Center(
              child: IgnorePointer(
                child: Container(
                  width: 260,
                  height: 340,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppColors.accentYellow.withValues(alpha: 0.7),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),

            // Bottom hint + shutter
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.only(bottom: 30, top: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _capturingFront
                          ? 'Place clothing inside the frame'
                          : 'Now capture the back side',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: _takePhoto,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                        child: Center(
                          child: Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isCapturing
                                  ? Colors.grey
                                  : AppColors.accentYellow,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: Colors.black45,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}
