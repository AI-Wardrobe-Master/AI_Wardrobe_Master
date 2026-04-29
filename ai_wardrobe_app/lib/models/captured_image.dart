import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

class CapturedImage {
  const CapturedImage({
    required this.bytes,
    required this.filename,
    this.path,
  });

  final Uint8List bytes;
  final String filename;
  final String? path;

  static Future<CapturedImage> fromXFile(XFile file) async {
    final bytes = await file.readAsBytes();
    final pathSegments = Uri.parse(file.path).pathSegments;
    final filename = file.name.isNotEmpty
        ? file.name
        : pathSegments.isNotEmpty
            ? pathSegments.last
            : 'image.jpg';

    return CapturedImage(
      bytes: bytes,
      filename: filename,
      path: file.path.isEmpty ? null : file.path,
    );
  }

  Widget buildImage({BoxFit fit = BoxFit.cover}) {
    return Image.memory(bytes, fit: fit);
  }
}
