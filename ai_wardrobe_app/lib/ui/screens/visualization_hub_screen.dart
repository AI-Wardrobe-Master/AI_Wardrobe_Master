import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'outfit_canvas_screen.dart';
import 'scene_preview_demo_screen.dart';

class VisualizationHubScreen extends StatelessWidget {
  const VisualizationHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.textPrimary;
    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;

    return DefaultTabController(
      length: 2,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Visualize',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Switch between the styling canvas and the new face-and-scene preview demo flow.',
                    style: TextStyle(fontSize: 12, color: textSecondary),
                  ),
                  const SizedBox(height: 12),
                  const TabBar(
                    tabs: [
                      Tab(text: 'Canvas Studio'),
                      Tab(text: 'Face + Scene'),
                    ],
                  ),
                ],
              ),
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  OutfitCanvasScreen(showAppBar: false),
                  ScenePreviewDemoScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
