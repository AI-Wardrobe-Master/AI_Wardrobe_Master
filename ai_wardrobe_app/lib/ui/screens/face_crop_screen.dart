import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class FaceCropScreen extends StatefulWidget {
  const FaceCropScreen({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<FaceCropScreen> createState() => _FaceCropScreenState();
}

class _FaceCropScreenState extends State<FaceCropScreen> {
  ui.Image? _image;
  Rect? _cropRect;
  Rect? _imagePaintRect;
  Offset? _lastDragPosition;
  bool _resizing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _decodeImage();
  }

  Future<void> _decodeImage() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() => _image = frame.image);
  }

  Rect _containedImageRect(Size canvasSize) {
    final image = _image!;
    final imageRatio = image.width / image.height;
    final canvasRatio = canvasSize.width / canvasSize.height;
    double width;
    double height;
    if (imageRatio > canvasRatio) {
      width = canvasSize.width;
      height = width / imageRatio;
    } else {
      height = canvasSize.height;
      width = height * imageRatio;
    }
    final left = (canvasSize.width - width) / 2;
    final top = (canvasSize.height - height) / 2;
    return Rect.fromLTWH(left, top, width, height);
  }

  Rect _initialCrop(Rect imageRect) {
    final side = math.min(imageRect.width, imageRect.height) * 0.54;
    return Rect.fromCenter(center: imageRect.center, width: side, height: side);
  }

  Rect _clampCrop(Rect rect, Rect imageRect) {
    final minSide = math.min(imageRect.width, imageRect.height) * 0.22;
    final maxSide = math.min(imageRect.width, imageRect.height);
    final side = rect.width.clamp(minSide, maxSide).toDouble();
    final center = Offset(
      rect.center.dx.clamp(
        imageRect.left + side / 2,
        imageRect.right - side / 2,
      ),
      rect.center.dy.clamp(
        imageRect.top + side / 2,
        imageRect.bottom - side / 2,
      ),
    );
    return Rect.fromCenter(center: center, width: side, height: side);
  }

  Future<void> _saveCrop() async {
    final image = _image;
    final cropRect = _cropRect;
    final imagePaintRect = _imagePaintRect;
    if (image == null ||
        cropRect == null ||
        imagePaintRect == null ||
        _saving) {
      return;
    }
    setState(() => _saving = true);

    try {
      final scaleX = image.width / imagePaintRect.width;
      final scaleY = image.height / imagePaintRect.height;
      final source =
          Rect.fromLTRB(
            (cropRect.left - imagePaintRect.left) * scaleX,
            (cropRect.top - imagePaintRect.top) * scaleY,
            (cropRect.right - imagePaintRect.left) * scaleX,
            (cropRect.bottom - imagePaintRect.top) * scaleY,
          ).intersect(
            Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            ),
          );

      const outputSize = 512.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.high;
      canvas.drawColor(Colors.white, BlendMode.src);
      canvas.drawImageRect(
        image,
        source,
        const Rect.fromLTWH(0, 0, outputSize, outputSize),
        paint,
      );
      final picture = recorder.endRecording();
      final output = await picture.toImage(
        outputSize.toInt(),
        outputSize.toInt(),
      );
      final byteData = await output.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted) return;
      Navigator.of(context).pop(byteData?.buffer.asUint8List());
    } finally {
      if (mounted) setState(() => _saving = false);
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
      appBar: AppBar(
        title: const Text('Crop face photo'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _saveCrop,
            child: Text(_saving ? 'Saving...' : 'Use crop'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                'Drag the square over the face. Pull the corner to resize it.',
                style: TextStyle(color: textS, fontSize: 13),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurface : Colors.white,
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: _image == null
                        ? const Center(child: CircularProgressIndicator())
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final size = constraints.biggest;
                              final imageRect = _containedImageRect(size);
                              _imagePaintRect = imageRect;
                              _cropRect ??= _initialCrop(imageRect);
                              _cropRect = _clampCrop(_cropRect!, imageRect);

                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanStart: (details) {
                                  final crop = _cropRect!;
                                  _lastDragPosition = details.localPosition;
                                  _resizing =
                                      (details.localPosition - crop.bottomRight)
                                          .distance <
                                      46;
                                },
                                onPanUpdate: (details) {
                                  final last = _lastDragPosition;
                                  if (last == null) return;
                                  final current = details.localPosition;
                                  final delta = current - last;
                                  final crop = _cropRect!;
                                  setState(() {
                                    if (_resizing) {
                                      final side = math.max<double>(
                                        crop.width +
                                            math.max(delta.dx, delta.dy) * 2,
                                        1,
                                      );
                                      _cropRect = _clampCrop(
                                        Rect.fromCenter(
                                          center: crop.center,
                                          width: side,
                                          height: side,
                                        ),
                                        imageRect,
                                      );
                                    } else {
                                      _cropRect = _clampCrop(
                                        crop.shift(delta),
                                        imageRect,
                                      );
                                    }
                                    _lastDragPosition = current;
                                  });
                                },
                                onPanEnd: (_) {
                                  _lastDragPosition = null;
                                  _resizing = false;
                                },
                                child: CustomPaint(
                                  size: size,
                                  painter: _FaceCropPainter(
                                    image: _image!,
                                    imageRect: imageRect,
                                    cropRect: _cropRect!,
                                    textColor: textP,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FaceCropPainter extends CustomPainter {
  const _FaceCropPainter({
    required this.image,
    required this.imageRect,
    required this.cropRect,
    required this.textColor,
  });

  final ui.Image image;
  final Rect imageRect;
  final Rect cropRect;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.high;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      imageRect,
      paint,
    );

    final overlay = Paint()..color = Colors.black.withValues(alpha: 0.42);
    final full = Path()..addRect(Offset.zero & size);
    final cutout = Path()
      ..addRRect(RRect.fromRectAndRadius(cropRect, const Radius.circular(8)));
    canvas.drawPath(
      Path.combine(PathOperation.difference, full, cutout),
      overlay,
    );

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(cropRect, const Radius.circular(8)),
      border,
    );

    final guide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.6);
    for (var i = 1; i < 3; i++) {
      final dx = cropRect.left + cropRect.width * i / 3;
      canvas.drawLine(
        Offset(dx, cropRect.top),
        Offset(dx, cropRect.bottom),
        guide,
      );
      final dy = cropRect.top + cropRect.height * i / 3;
      canvas.drawLine(
        Offset(cropRect.left, dy),
        Offset(cropRect.right, dy),
        guide,
      );
    }

    final handle = Paint()..color = Colors.white;
    canvas.drawCircle(cropRect.bottomRight, 8, handle);
    canvas.drawCircle(
      cropRect.bottomRight,
      5,
      Paint()..color = AppColors.accentBlue,
    );
  }

  @override
  bool shouldRepaint(covariant _FaceCropPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.imageRect != imageRect ||
        oldDelegate.cropRect != cropRect ||
        oldDelegate.textColor != textColor;
  }
}
