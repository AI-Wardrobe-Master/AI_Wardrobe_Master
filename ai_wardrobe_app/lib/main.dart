import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'ui/root_shell.dart';

void main() {
  runApp(const WardrobeApp());
}

class WardrobeApp extends StatelessWidget {
  const WardrobeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) {
        return MaterialApp(
          title: 'AI Wardrobe Master',
          debugShowCheckedModeBanner: false,
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: themeController.mode,
          home: const RootShell(),
        );
      },
    );
  }
}


