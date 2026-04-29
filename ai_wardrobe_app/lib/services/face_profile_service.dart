import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';

enum FaceProfileKind { none, custom, virtualMale, virtualFemale }

class FaceProfile {
  const FaceProfile({required this.kind, this.customImageBytes});

  final FaceProfileKind kind;
  final Uint8List? customImageBytes;

  bool get hasSelection => kind != FaceProfileKind.none;
}

class FaceProfileService {
  static const _kindKeyPrefix = 'profile_face_kind_v1';
  static const _customImageKeyPrefix = 'profile_face_custom_png_v1';

  static Future<FaceProfile> load() async {
    final prefs = await SharedPreferences.getInstance();
    final suffix = await _scopeSuffix();
    final rawKind = prefs.getString('$_kindKeyPrefix$suffix');
    final kind = FaceProfileKind.values.firstWhere(
      (value) => value.name == rawKind,
      orElse: () => FaceProfileKind.none,
    );

    Uint8List? bytes;
    if (kind == FaceProfileKind.custom) {
      final encoded = prefs.getString('$_customImageKeyPrefix$suffix');
      if (encoded != null && encoded.isNotEmpty) {
        try {
          bytes = base64Decode(encoded);
        } catch (_) {
          bytes = null;
        }
      }
    }
    return FaceProfile(
      kind: bytes == null && kind == FaceProfileKind.custom
          ? FaceProfileKind.none
          : kind,
      customImageBytes: bytes,
    );
  }

  static Future<void> saveCustom(Uint8List pngBytes) async {
    final prefs = await SharedPreferences.getInstance();
    final suffix = await _scopeSuffix();
    await prefs.setString(
      '$_kindKeyPrefix$suffix',
      FaceProfileKind.custom.name,
    );
    await prefs.setString(
      '$_customImageKeyPrefix$suffix',
      base64Encode(pngBytes),
    );
  }

  static Future<void> saveVirtual(FaceProfileKind kind) async {
    if (kind != FaceProfileKind.virtualMale &&
        kind != FaceProfileKind.virtualFemale) {
      throw ArgumentError('Unsupported virtual face profile kind: $kind');
    }
    final prefs = await SharedPreferences.getInstance();
    final suffix = await _scopeSuffix();
    await prefs.setString('$_kindKeyPrefix$suffix', kind.name);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    final suffix = await _scopeSuffix();
    await prefs.remove('$_kindKeyPrefix$suffix');
    await prefs.remove('$_customImageKeyPrefix$suffix');
  }

  static Future<Uint8List?> resolveImageBytes(
    FaceProfile profile, {
    int size = 512,
  }) async {
    if (profile.kind == FaceProfileKind.custom) {
      return profile.customImageBytes;
    }
    if (profile.kind == FaceProfileKind.virtualMale ||
        profile.kind == FaceProfileKind.virtualFemale) {
      return _renderVirtualAvatar(profile.kind, size);
    }
    return null;
  }

  static Future<String> _scopeSuffix() async {
    await ApiSession.loadToken();
    final userId = ApiSession.currentUserId;
    if (userId == null || userId.isEmpty) {
      return '_offline';
    }
    return '_$userId';
  }

  static Future<Uint8List> _renderVirtualAvatar(
    FaceProfileKind kind,
    int size,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final s = size.toDouble();
    final isFemale = kind == FaceProfileKind.virtualFemale;

    final bgPaint = ui.Paint()
      ..shader = ui.Gradient.linear(
        ui.Offset.zero,
        ui.Offset(s, s),
        isFemale
            ? const [ui.Color(0xFFFFE0EA), ui.Color(0xFFB8D7FF)]
            : const [ui.Color(0xFFD8E9FF), ui.Color(0xFFCDEED7)],
      );
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, s, s), bgPaint);

    final hairPaint = ui.Paint()
      ..color = isFemale
          ? const ui.Color(0xFF3F2B3D)
          : const ui.Color(0xFF26344D);
    final facePaint = ui.Paint()..color = const ui.Color(0xFFFFD8BF);
    final linePaint = ui.Paint()
      ..color = const ui.Color(0xFF20242A)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = s * 0.014
      ..strokeCap = ui.StrokeCap.round;
    final fillPaint = ui.Paint()..color = const ui.Color(0xFF20242A);
    final blushPaint = ui.Paint()..color = const ui.Color(0xFFE9878C);

    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(s * 0.23, s * 0.62, s * 0.54, s * 0.42),
        ui.Radius.circular(s * 0.2),
      ),
      ui.Paint()
        ..color = isFemale
            ? const ui.Color(0xFF496CB3)
            : const ui.Color(0xFF3F7D64),
    );
    canvas.drawCircle(ui.Offset(s * 0.5, s * 0.45), s * 0.25, hairPaint);
    canvas.drawOval(
      ui.Rect.fromCenter(
        center: ui.Offset(s * 0.5, s * 0.48),
        width: s * 0.42,
        height: s * 0.48,
      ),
      facePaint,
    );

    if (isFemale) {
      final bang = ui.Path()
        ..moveTo(s * 0.3, s * 0.39)
        ..quadraticBezierTo(s * 0.48, s * 0.23, s * 0.72, s * 0.38)
        ..quadraticBezierTo(s * 0.58, s * 0.34, s * 0.5, s * 0.42)
        ..quadraticBezierTo(s * 0.42, s * 0.35, s * 0.3, s * 0.39)
        ..close();
      canvas.drawPath(bang, hairPaint);
    } else {
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(s * 0.31, s * 0.27, s * 0.38, s * 0.18),
          ui.Radius.circular(s * 0.1),
        ),
        hairPaint,
      );
    }

    canvas
      ..drawCircle(ui.Offset(s * 0.42, s * 0.49), s * 0.018, fillPaint)
      ..drawCircle(ui.Offset(s * 0.58, s * 0.49), s * 0.018, fillPaint)
      ..drawCircle(ui.Offset(s * 0.38, s * 0.55), s * 0.026, blushPaint)
      ..drawCircle(ui.Offset(s * 0.62, s * 0.55), s * 0.026, blushPaint);

    final mouth = ui.Path()
      ..moveTo(s * 0.44, s * 0.61)
      ..quadraticBezierTo(s * 0.5, s * 0.66, s * 0.56, s * 0.61);
    canvas.drawPath(mouth, linePaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return byteData!.buffer.asUint8List();
  }
}
