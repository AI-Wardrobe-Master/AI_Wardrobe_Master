import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../models/card_pack.dart';
import '../../../models/creator.dart';
import '../../../services/api_config.dart';
import '../../../services/card_pack_api_service.dart';
import '../../../services/creator_api_service.dart';
import '../../../services/local_card_pack_service.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/card_pack/card_pack_list_item.dart';
import '../card_pack_detail_screen.dart';

class CreatorProfileScreen extends StatefulWidget {
  final String creatorId;

  const CreatorProfileScreen({
    super.key,
    required this.creatorId,
  });

  @override
  State<CreatorProfileScreen> createState() => _CreatorProfileScreenState();
}

class _CreatorProfileScreenState extends State<CreatorProfileScreen> {
  Creator? _creator;
  List<CardPack> _packs = [];
  bool _loading = true;
  bool _loadingPacks = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([_loadCreator(), _loadPacks()]);
  }

  Future<void> _loadCreator() async {
    try {
      final creator = await CreatorApiService.getCreator(widget.creatorId);
      if (!mounted) return;
      setState(() {
        _creator = creator;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadPacks() async {
    setState(() => _loadingPacks = true);
    try {
      final apiPacks = await CardPackApiService.listCardPacks(
        creatorId: widget.creatorId,
        status: 'PUBLISHED',
      );
      if (!mounted) return;
      setState(() {
        _packs = apiPacks;
        _loadingPacks = false;
      });
    } catch (_) {
      final localPacks = await LocalCardPackService.listCardPacks();
      if (!mounted) return;
      setState(() {
        _packs = localPacks
            .where((pack) => pack.creatorId == widget.creatorId)
            .toList();
        _loadingPacks = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textP = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textS = isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    return Scaffold(
      appBar: AppBar(title: const Text('Creator Profile')),
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
                        onPressed: _loadData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _creator == null
                  ? const Center(child: Text('Creator not found'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 40,
                                backgroundColor: textS.withValues(alpha: 0.1),
                                backgroundImage: _creator!.avatarUrl != null
                                    ? CachedNetworkImageProvider(
                                        resolveFileUrl(_creator!.avatarUrl!),
                                        headers: ApiSession.authHeaders,
                                      )
                                    : null,
                                child: _creator!.avatarUrl == null
                                    ? Text(
                                        _creator!.displayName.isNotEmpty
                                            ? _creator!.displayName[0].toUpperCase()
                                            : '?',
                                        style: TextStyle(
                                          color: textP,
                                          fontSize: 24,
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            _creator!.displayName,
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w700,
                                              color: textP,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (_creator!.isVerified) ...[
                                          const SizedBox(width: 4),
                                          const Icon(Icons.verified,
                                              size: 20, color: Colors.blue),
                                        ],
                                      ],
                                    ),
                                    if (_creator!.brandName != null &&
                                        _creator!.brandName!.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        _creator!.brandName!,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: textS,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (_creator!.bio != null && _creator!.bio!.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              _creator!.bio!,
                              style: TextStyle(fontSize: 14, color: textP),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              _buildStat(Icons.people_outline,
                                  '${_creator!.followerCount}', 'Followers', textS),
                              const SizedBox(width: 24),
                              _buildStat(Icons.style_outlined,
                                  '${_creator!.packCount}', 'Packs', textS),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Published Packs',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: textP,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _loadingPacks
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child:
                                        CircularProgressIndicator(color: textP),
                                  ),
                                )
                              : _packs.isEmpty
                                  ? Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Center(
                                        child: Text(
                                          'No published packs yet',
                                          style: TextStyle(color: textS),
                                        ),
                                      ),
                                    )
                                  : Column(
                                      children: _packs.map((pack) {
                                        return CardPackListItem(
                                          pack: pack,
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => CardPackDetailScreen(
                                                  packId: pack.id,
                                                ),
                                              ),
                                            );
                                          },
                                        );
                                      }).toList(),
                                    ),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildStat(IconData icon, String value, String label, Color textS) {
    return Row(
      children: [
        Icon(icon, size: 16, color: textS),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: textS,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: textS),
        ),
      ],
    );
  }
}
