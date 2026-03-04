import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class OutfitCanvasScreen extends StatefulWidget {
  const OutfitCanvasScreen({super.key});

  @override
  State<OutfitCanvasScreen> createState() => _OutfitCanvasScreenState();
}

class _OutfitCanvasScreenState extends State<OutfitCanvasScreen> {
  String? _activeSlot;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _textP =>
      _isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
  Color get _textS =>
      _isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
  Color get _accent =>
      _isDark ? AppColors.darkAccentBlue : AppColors.accentBlue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Visualize')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tap on the mannequin to choose pieces.',
                style: TextStyle(fontSize: 12, color: _textS),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Theme.of(context).dividerColor,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _buildCanvas(context),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _activeSlot = null;
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _textP,
                        side: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                      child: const Text('Clear'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {},
                      style: FilledButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Save look'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCanvas(BuildContext context) {
    const slots = <_BodySlot>[
      _BodySlot(label: 'Head', alignment: Alignment(0, -0.8)),
      _BodySlot(label: 'Torso', alignment: Alignment(0, -0.25)),
      _BodySlot(label: 'Legs', alignment: Alignment(0, 0.25)),
      _BodySlot(label: 'Feet', alignment: Alignment(0, 0.75)),
      _BodySlot(label: 'Hands', alignment: Alignment(-0.7, -0.05)),
      _BodySlot(label: 'Hands', alignment: Alignment(0.7, -0.05)),
    ];

    final mainColor = _isDark
        ? Colors.white.withOpacity(0.18)
        : Colors.black.withOpacity(0.08);
    final armColor = _isDark
        ? Colors.white.withOpacity(0.14)
        : Colors.black.withOpacity(0.06);

    return Stack(
      children: [
        Align(
          alignment: Alignment.center,
          child: SizedBox(
            width: 140,
            height: 260,
            child: Stack(
              children: [
                Align(
                  alignment: const Alignment(0, 0),
                  child: Container(
                    width: 70,
                    height: 130,
                    decoration: BoxDecoration(
                      color: mainColor,
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
                Align(
                  alignment: const Alignment(0, -0.9),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: mainColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Align(
                  alignment: const Alignment(0, 0.9),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 20,
                        height: 70,
                        decoration: BoxDecoration(
                          color: mainColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 20,
                        height: 70,
                        decoration: BoxDecoration(
                          color: mainColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ],
                  ),
                ),
                Align(
                  alignment: const Alignment(0, 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 38,
                        height: 14,
                        decoration: BoxDecoration(
                          color: armColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      const SizedBox(width: 64),
                      Container(
                        width: 38,
                        height: 14,
                        decoration: BoxDecoration(
                          color: armColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: 110,
            height: 10,
            decoration: BoxDecoration(
              color: _isDark
                  ? Colors.white.withOpacity(0.04)
                  : Colors.black.withOpacity(0.06),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        ...slots.map(
          (slot) => Align(
            alignment: slot.alignment,
            child: GestureDetector(
              onTap: () => _onSlotTap(slot.label),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _activeSlot == slot.label
                      ? AppColors.accentYellow.withOpacity(0.35)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: _activeSlot == slot.label
                        ? _accent
                        : Colors.transparent,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_activeSlot != null)
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Selected: $_activeSlot',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _textP,
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _onSlotTap(String label) {
    setState(() {
      _activeSlot = label;
    });
    _showSlotSheet(label);
  }

  void _showSlotSheet(String label) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _isDark ? AppColors.darkSurface : Colors.white,
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
                  'Select $label item',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _textP,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Here we will show hats, tops, pants, shoes, etc. connected to your wardrobe.',
                  style: TextStyle(fontSize: 13, color: _textS),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BodySlot {
  const _BodySlot({
    required this.label,
    required this.alignment,
  });

  final String label;
  final Alignment alignment;
}
