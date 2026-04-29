import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_strings_provider.dart';
import '../../models/wardrobe.dart';
import '../../services/wardrobe_service.dart';
import '../../theme/app_theme.dart';

/// 3.1 Wardrobe management: create, rename, delete. Virtual wardrobes shown with label.
class WardrobeManagementScreen extends StatefulWidget {
  const WardrobeManagementScreen({super.key});

  @override
  State<WardrobeManagementScreen> createState() =>
      _WardrobeManagementScreenState();
}

class _WardrobeManagementScreenState extends State<WardrobeManagementScreen> {
  List<Wardrobe> _wardrobes = [];
  bool _loading = true;
  String? _error;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _textPrimary =>
      _isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
  Color get _textSecondary =>
      _isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await WardrobeService.fetchWardrobes();
      setState(() {
        _wardrobes = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _createWardrobe() async {
    final s = AppStringsProvider.of(context);
    final nameController = TextEditingController();
    String type = 'REGULAR';
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setDialogState) {
            return AlertDialog(
              title: Text(s.createWardrobe),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: s.wardrobeName,
                      border: const OutlineInputBorder(),
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'REGULAR',
                        label: Text(s.regularWardrobeLabel),
                      ),
                      ButtonSegment(
                        value: 'VIRTUAL',
                        label: Text(s.virtualWardrobeLabel),
                      ),
                    ],
                    selected: {type},
                    onSelectionChanged: (v) =>
                        setDialogState(() => type = v.first),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(s.cancel),
                ),
                FilledButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) return;
                    Navigator.of(ctx).pop();
                    try {
                      await WardrobeService.createWardrobe(
                        name: name,
                        type: type,
                      );
                      _load();
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(e.toString())));
                      }
                    }
                  },
                  child: Text(s.create),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _renameWardrobe(Wardrobe w) async {
    final s = AppStringsProvider.of(context);
    final nameController = TextEditingController(text: w.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.renameWardrobe),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: s.wardrobeName,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.save),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameController.text.trim();
    if (name.isEmpty) return;
    try {
      await WardrobeService.updateWardrobe(w.id, name: name);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _deleteWardrobe(Wardrobe w) async {
    final s = AppStringsProvider.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deleteWardrobe),
        content: Text(s.deleteWardrobeConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.deleteWardrobe),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await WardrobeService.deleteWardrobe(w.id);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _shareWardrobe(Wardrobe wardrobe) async {
    var latestWardrobe = wardrobe;
    if (!wardrobe.isPublic) {
      latestWardrobe = await WardrobeService.updateWardrobe(
        wardrobe.id,
        isPublic: true,
      );
      await _load();
    }

    final shareText =
        'AI Wardrobe share code: ${latestWardrobe.wid}\nWardrobe: ${latestWardrobe.name}';
    await Clipboard.setData(ClipboardData(text: shareText));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Share code copied: ${latestWardrobe.wid}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStringsProvider.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.manageWardrobes)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!, style: TextStyle(color: _textSecondary)),
                  const SizedBox(height: 8),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          : _wardrobes.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      s.noWardrobesYet,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      s.createFirstWardrobe,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: _textSecondary),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _createWardrobe,
                      icon: const Icon(Icons.add),
                      label: Text(s.createWardrobe),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _wardrobes.length,
              itemBuilder: (context, index) {
                final w = _wardrobes[index];
                return ListTile(
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          w.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _textPrimary,
                          ),
                        ),
                      ),
                      if (w.isVirtual)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _textSecondary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            s.virtualWardrobeLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: _textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    '${w.itemCount} ${s.statClothes}',
                    style: TextStyle(fontSize: 12, color: _textSecondary),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.share_outlined),
                        onPressed: () => _shareWardrobe(w),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _renameWardrobe(w),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: () => _deleteWardrobe(w),
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: _wardrobes.isNotEmpty
          ? FloatingActionButton(
              onPressed: _createWardrobe,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
