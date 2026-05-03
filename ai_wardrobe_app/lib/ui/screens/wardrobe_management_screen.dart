import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_strings_provider.dart';
import '../../models/wardrobe.dart';
import '../../services/wardrobe_service.dart';
import '../../state/wardrobe_refresh_notifier.dart';
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

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

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
    final result = await showDialog<_WardrobeNameResult>(
      context: context,
      builder: (_) => _WardrobeNameDialog(
        title: s.createWardrobe,
        initialName: '',
        initialType: 'REGULAR',
        showTypeSelector: true,
        nameLabel: s.wardrobeName,
        requiredMessage: s.wardrobeNameRequired,
        cancelLabel: s.cancel,
        submitLabel: s.create,
        regularLabel: s.regularWardrobeLabel,
        virtualLabel: s.virtualWardrobeLabel,
      ),
    );
    if (result == null) return;
    try {
      await WardrobeService.createWardrobe(
        name: result.name,
        type: result.type,
      );
      WardrobeRefreshNotifier.requestRefresh();
      _load();
    } catch (e) {
      _showSnackBar(e.toString());
    }
  }

  Future<void> _renameWardrobe(Wardrobe w) async {
    final s = AppStringsProvider.of(context);
    final result = await showDialog<_WardrobeNameResult>(
      context: context,
      builder: (_) => _WardrobeNameDialog(
        title: s.renameWardrobe,
        initialName: w.name,
        initialType: w.type,
        showTypeSelector: false,
        nameLabel: s.wardrobeName,
        requiredMessage: s.wardrobeNameRequired,
        cancelLabel: s.cancel,
        submitLabel: s.save,
        regularLabel: s.regularWardrobeLabel,
        virtualLabel: s.virtualWardrobeLabel,
      ),
    );
    if (result == null) return;
    final name = result.name;
    if (name == w.name) return;
    try {
      await WardrobeService.updateWardrobe(w.id, name: name);
      WardrobeRefreshNotifier.requestRefresh();
      _load();
    } catch (e) {
      _showSnackBar(e.toString());
    }
  }

  Future<void> _deleteWardrobe(Wardrobe w) async {
    final s = AppStringsProvider.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deleteWardrobe),
        content: Text(s.deleteWardrobeConfirmNamed(w.name, w.itemCount)),
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
      WardrobeRefreshNotifier.requestRefresh();
      _load();
    } catch (e) {
      _showSnackBar(e.toString());
    }
  }

  Future<void> _shareWardrobe(Wardrobe wardrobe) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          wardrobe.isPublic
              ? 'Wardrobe already shared'
              : 'Publish wardrobe to Discover?',
        ),
        content: Text(
          wardrobe.isPublic
              ? '"${wardrobe.name}" is already visible in Discover. You can copy its WID again for sharing or testing.'
              : 'After publishing, "${wardrobe.name}" will appear in Discover and can be opened by searching its WID (${wardrobe.wid}). Its clothing items stay in your wardrobe.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: Icon(
              wardrobe.isPublic ? Icons.copy_rounded : Icons.public_rounded,
            ),
            label: Text(wardrobe.isPublic ? 'Copy WID' : 'Publish'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      var latestWardrobe = wardrobe;
      final wasAlreadyPublic = wardrobe.isPublic;
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
      WardrobeRefreshNotifier.requestRefresh();
      _showSnackBar(
        wasAlreadyPublic
            ? 'WID copied: ${latestWardrobe.wid}'
            : 'Published to Discover. WID copied: ${latestWardrobe.wid}',
      );
    } catch (e) {
      _showSnackBar(e.toString());
    }
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
                  Icon(Icons.error_outline, color: _textSecondary),
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _textSecondary),
                  ),
                  const SizedBox(height: 8),
                  TextButton(onPressed: _load, child: Text(s.retry)),
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

class _WardrobeNameResult {
  const _WardrobeNameResult({required this.name, required this.type});

  final String name;
  final String type;
}

class _WardrobeNameDialog extends StatefulWidget {
  const _WardrobeNameDialog({
    required this.title,
    required this.initialName,
    required this.initialType,
    required this.showTypeSelector,
    required this.nameLabel,
    required this.requiredMessage,
    required this.cancelLabel,
    required this.submitLabel,
    required this.regularLabel,
    required this.virtualLabel,
  });

  final String title;
  final String initialName;
  final String initialType;
  final bool showTypeSelector;
  final String nameLabel;
  final String requiredMessage;
  final String cancelLabel;
  final String submitLabel;
  final String regularLabel;
  final String virtualLabel;

  @override
  State<_WardrobeNameDialog> createState() => _WardrobeNameDialogState();
}

class _WardrobeNameDialogState extends State<_WardrobeNameDialog> {
  late final TextEditingController _nameController;
  late final FocusNode _nameFocusNode;
  late String _type;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _nameFocusNode = FocusNode();
    _type = widget.initialType == 'VIRTUAL' ? 'VIRTUAL' : 'REGULAR';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _nameFocusNode.requestFocus();
      _nameController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _nameController.text.length,
      );
    });
  }

  @override
  void dispose() {
    _nameFocusNode.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = widget.requiredMessage);
      return;
    }
    Navigator.of(context).pop(_WardrobeNameResult(name: name, type: _type));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameController,
            focusNode: _nameFocusNode,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: widget.nameLabel,
              errorText: _nameError,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (widget.showTypeSelector) ...[
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'REGULAR',
                  label: Text(widget.regularLabel),
                ),
                ButtonSegment(
                  value: 'VIRTUAL',
                  label: Text(widget.virtualLabel),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (value) {
                setState(() => _type = value.first);
              },
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.submitLabel)),
      ],
    );
  }
}
