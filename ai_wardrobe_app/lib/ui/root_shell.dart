import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'screens/capture/camera_capture_screen.dart';
import 'screens/capture/processing_screen.dart';
import 'screens/discover_screen.dart';
import 'screens/outfit_canvas_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/wardrobe_screen.dart';

/// Root shell that switches layout between mobile and web/desktop.
class RootShell extends StatelessWidget {
  const RootShell({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        if (kIsWeb || isWide) {
          return const _WebRootShell();
        }
        return const _MobileRootShell();
      },
    );
  }
}

// ---------------- Mobile shell: bottom navigation ----------------

class _MobileRootShell extends StatefulWidget {
  const _MobileRootShell();

  @override
  State<_MobileRootShell> createState() => _MobileRootShellState();
}

class _MobileRootShellState extends State<_MobileRootShell> {
  int _pageIndex = 0;
  int _navIndex = 0;

  final _pages = const <Widget>[
    WardrobeScreen(),
    DiscoverScreen(),
    OutfitCanvasScreen(),
    ProfileScreen(),
  ];

  void _onNavTap(int index) {
    if (index == 2) {
      _onAddPressed();
      return;
    }
    setState(() {
      _navIndex = index;
      _pageIndex = index > 2 ? index - 1 : index;
    });
  }

  void _onAddPressed() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textS = isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    final accent = isDark ? AppColors.darkAccentBlue : AppColors.accentBlue;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Add new',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: textP,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Quickly add clothes or start a new outfit.',
                  style: TextStyle(fontSize: 13, color: textS),
                ),
                const SizedBox(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color:
                          isDark ? AppColors.darkBackground : AppColors.background,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.checkroom_rounded,
                      color: textP,
                    ),
                  ),
                  title: Text(
                    'Add clothes',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: textP,
                    ),
                  ),
                  subtitle: Text(
                    'Capture or pick photos to add items.',
                    style: TextStyle(fontSize: 12, color: textS),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    _navigateToCapture();
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.accentYellow.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.style_rounded,
                      color: accent,
                    ),
                  ),
                  title: Text(
                    'Open outfit canvas',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: textP,
                    ),
                  ),
                  subtitle: Text(
                    'Play with pieces on a 2.5D canvas.',
                    style: TextStyle(fontSize: 12, color: textS),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    setState(() {
                      _navIndex = 3;
                      _pageIndex = 2;
                    });
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _navigateToCapture() async {
    final result = await Navigator.push<Map<String, File?>>(
      context,
      MaterialPageRoute(builder: (_) => const CameraCaptureScreen()),
    );
    if (result == null || !mounted) return;
    final front = result['front'];
    if (front == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProcessingScreen(
          frontImage: front,
          backImage: result['back'],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _pageIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _navIndex,
        onTap: _onNavTap,
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2_outlined),
            activeIcon: Icon(Icons.inventory_2_rounded),
            label: 'Wardrobe',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.local_fire_department_outlined),
            activeIcon: Icon(Icons.local_fire_department),
            label: 'Discover',
          ),
          BottomNavigationBarItem(
            icon: _AddNavIcon(highlight: false),
            activeIcon: _AddNavIcon(highlight: true),
            label: 'Add',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.style_outlined),
            activeIcon: Icon(Icons.style_rounded),
            label: 'Visualize',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _AddNavIcon extends StatelessWidget {
  const _AddNavIcon({required this.highlight});

  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.accentYellow
            : AppColors.accentYellow.withOpacity(0.9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(
        Icons.add,
        size: 20,
        color: AppColors.textPrimary,
      ),
    );
  }
}

// ---------------- Web/desktop shell: left navigation rail ----------------

class _WebRootShell extends StatefulWidget {
  const _WebRootShell();

  @override
  State<_WebRootShell> createState() => _WebRootShellState();
}

class _WebRootShellState extends State<_WebRootShell> {
  int _pageIndex = 0;

  final _pages = const <Widget>[
    WardrobeScreen(),
    DiscoverScreen(),
    OutfitCanvasScreen(),
    ProfileScreen(),
  ];

  void _onAddPressed() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textS = isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    final accent = isDark ? AppColors.darkAccentBlue : AppColors.accentBlue;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Add new',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: textP,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Quickly add clothes or start a new outfit.',
                  style: TextStyle(fontSize: 13, color: textS),
                ),
                const SizedBox(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color:
                          isDark ? AppColors.darkBackground : AppColors.background,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.checkroom_rounded,
                      color: textP,
                    ),
                  ),
                  title: Text(
                    'Add clothes',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: textP,
                    ),
                  ),
                  subtitle: Text(
                    'Capture or pick photos to add items.',
                    style: TextStyle(fontSize: 12, color: textS),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    _navigateToCapture();
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.accentYellow.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.style_rounded,
                      color: accent,
                    ),
                  ),
                  title: Text(
                    'Open outfit canvas',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: textP,
                    ),
                  ),
                  subtitle: Text(
                    'Play with pieces on a 2.5D canvas.',
                    style: TextStyle(fontSize: 12, color: textS),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    setState(() {
                      _pageIndex = 2;
                    });
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _navigateToCapture() async {
    final result = await Navigator.push<Map<String, File?>>(
      context,
      MaterialPageRoute(builder: (_) => const CameraCaptureScreen()),
    );
    if (result == null || !mounted) return;
    final front = result['front'];
    if (front == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProcessingScreen(
          frontImage: front,
          backImage: result['back'],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 90,
            color: Theme.of(context).cardColor,
            child: Column(
              children: [
                const SizedBox(height: 24),
                Expanded(
                  child: NavigationRail(
                    selectedIndex: _pageIndex,
                    onDestinationSelected: (index) {
                      setState(() {
                        _pageIndex = index;
                      });
                    },
                    labelType: NavigationRailLabelType.all,
                    backgroundColor: Colors.transparent,
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.inventory_2_outlined),
                        selectedIcon: Icon(Icons.inventory_2_rounded),
                        label: Text('Wardrobe'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.local_fire_department_outlined),
                        selectedIcon: Icon(Icons.local_fire_department),
                        label: Text('Discover'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.style_outlined),
                        selectedIcon: Icon(Icons.style_rounded),
                        label: Text('Visualize'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.person_outline),
                        selectedIcon: Icon(Icons.person),
                        label: Text('Profile'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _onAddPressed,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accentYellow,
                        foregroundColor: AppColors.textPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text(
                        'Add',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: Theme.of(context).dividerColor,
          ),
          Expanded(
            child: IndexedStack(
              index: _pageIndex,
              children: _pages,
            ),
          ),
        ],
      ),
    );
  }
}
