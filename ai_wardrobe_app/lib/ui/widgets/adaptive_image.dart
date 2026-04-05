import 'dart:io';

import 'package:flutter/material.dart';

class AdaptiveImage extends StatelessWidget {
  const AdaptiveImage({
    super.key,
    required this.imagePath,
    required this.fit,
    this.alignment = Alignment.center,
  });

  final String imagePath;
  final BoxFit fit;
  final Alignment alignment;

  bool get _isAsset => imagePath.startsWith('assets/');

  @override
  Widget build(BuildContext context) {
    if (_isAsset) {
      return Image.asset(
        imagePath,
        fit: fit,
        alignment: alignment,
      );
    }

    return Image.file(
      File(imagePath),
      fit: fit,
      alignment: alignment,
      errorBuilder: (context, _, __) {
        return const DecoratedBox(
          decoration: BoxDecoration(color: Color(0x14000000)),
          child: Center(
            child: Icon(Icons.broken_image_outlined),
          ),
        );
      },
    );
  }
}
