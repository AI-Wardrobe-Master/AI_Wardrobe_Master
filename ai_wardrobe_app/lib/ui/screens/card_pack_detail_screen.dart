import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/card_pack.dart';
import '../../services/card_pack_api_service.dart';
import '../../services/import_api_service.dart';
import '../../services/local_card_pack_service.dart';
import '../../theme/app_theme.dart';

class CardPackDetailScreen extends StatefulWidget {
  final String packId;

  const CardPackDetailScreen({
    super.key,
    required this.packId,
  });

  @override
  State<CardPackDetailScreen> createState() => _CardPackDetailScreenState();
}

class _CardPackDetailScreenState extends State<CardPackDetailScreen> {
  CardPack? _pack;
  bool _loading = true;
  String? _error;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _loadPack();
  }

  Future<void> _loadPack() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    if (LocalCardPackService.isLocalPack(widget.packId)) {
      final localPack = await LocalCardPackService.getCardPack(widget.packId);
      if (localPack != null) {
        setState(() {
          _pack = localPack;
          _loading = false;
        });
        return;
      }
    }

    try {
      final pack = await CardPackApiService.getCardPack(widget.packId);
      if (!mounted) return;
      setState(() {
        _pack = pack;
        _loading = false;
      });
    } catch (e) {
      final localPack = await LocalCardPackService.getCardPack(widget.packId);
      if (!mounted) return;
      if (localPack != null) {
        setState(() {
          _pack = localPack;
          _loading = false;
        });
        return;
      }
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _importPack() async {
    if (_pack == null || _importing) return;
    setState(() => _importing = true);
    try {
      await ImportApiService.importCardPack(_pack!.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Card pack imported successfully!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _importing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textS = isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    return Scaffold(
      appBar: AppBar(title: const Text('Card Pack')),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: textP))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: textS),
                      const SizedBox(height: 8),
                      Text('Error: $_error', style: TextStyle(color: textP)),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _loadPack,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _pack == null
                  ? const Center(child: Text('Pack not found'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_pack!.coverImageUrl != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: _buildCover(textS),
                            ),
                          const SizedBox(height: 16),
                          Text(
                            _pack!.name,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: textP,
                            ),
                          ),
                          if (_pack!.description != null &&
                              _pack!.description!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              _pack!.description!,
                              style: TextStyle(fontSize: 14, color: textS),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Icon(Icons.inventory_2_outlined,
                                  size: 16, color: textS),
                              const SizedBox(width: 4),
                              Text(
                                '${_pack!.itemCount} items',
                                style: TextStyle(fontSize: 12, color: textS),
                              ),
                              const SizedBox(width: 16),
                              Icon(Icons.download_outlined,
                                  size: 16, color: textS),
                              const SizedBox(width: 4),
                              Text(
                                '${_pack!.importCount} imports',
                                style: TextStyle(fontSize: 12, color: textS),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _importing ? null : _importPack,
                              style: FilledButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: _importing
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation(Colors.white),
                                      ),
                                    )
                                  : const Text('Import to Virtual Wardrobe'),
                            ),
                          ),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildCover(Color textS) {
    final coverImageUrl = _pack!.coverImageUrl!;
    if (coverImageUrl.startsWith('data:image')) {
      try {
        final imageBytes = base64Decode(coverImageUrl.split(',')[1]);
        return Image.memory(
          imageBytes,
          width: double.infinity,
          height: 200,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _imageFallback(textS),
        );
      } catch (_) {
        return _imageFallback(textS);
      }
    }

    return Image.network(
      coverImageUrl.startsWith('http')
          ? coverImageUrl
          : 'http://localhost:8000$coverImageUrl',
      width: double.infinity,
      height: 200,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _imageFallback(textS),
    );
  }

  Widget _imageFallback(Color textS) {
    return Container(
      width: double.infinity,
      height: 200,
      color: textS.withValues(alpha: 0.1),
      child: Icon(Icons.image_outlined, color: textS),
    );
  }
}
