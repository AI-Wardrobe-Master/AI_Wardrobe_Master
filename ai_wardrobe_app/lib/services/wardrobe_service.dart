import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/wardrobe.dart';
import 'api_config.dart';
import 'auth_service.dart';

/// Module 3: Wardrobe API. Fetch wardrobes, items, add/remove, create/rename/delete wardrobe.
class WardrobeService {
  static final _dio = Dio(BaseOptions(baseUrl: apiBaseUrl));

  static const _demoUserId = 'guest-demo-user';
  static const _demoPrimaryWardrobeId = 'guest-demo-wardrobe';
  static int _demoWardrobeCounter = 1;
  static int _demoItemCounter = 6;

  static final List<Wardrobe> _demoWardrobes = <Wardrobe>[
    const Wardrobe(
      id: _demoPrimaryWardrobeId,
      userId: _demoUserId,
      name: 'Demo Closet',
      type: 'REGULAR',
      description: 'Local demo wardrobe available when backend is offline.',
      itemCount: 5,
    ),
    const Wardrobe(
      id: 'guest-virtual-wardrobe',
      userId: _demoUserId,
      name: 'Shared Looks',
      type: 'VIRTUAL',
      description: 'Imported references used for local preview demos.',
      itemCount: 2,
    ),
  ];

  static final Map<String, List<WardrobeItemWithClothing>>
  _demoItemsByWardrobe = <String, List<WardrobeItemWithClothing>>{
    _demoPrimaryWardrobeId: <WardrobeItemWithClothing>[
      _demoEntry(
        id: 'demo-item-1',
        wardrobeId: _demoPrimaryWardrobeId,
        clothingItemId: 'demo-upper-shirt',
        name: 'Relaxed Oxford Shirt',
        source: 'OWNED',
        tags: const [
          {'key': 'category', 'value': 'shirt'},
          {'key': 'material', 'value': 'Cotton poplin'},
          {'key': 'color', 'value': 'Blue stripe'},
        ],
      ),
      _demoEntry(
        id: 'demo-item-2',
        wardrobeId: _demoPrimaryWardrobeId,
        clothingItemId: 'demo-upper-jacket',
        name: 'Soft Tailored Blazer',
        source: 'OWNED',
        tags: const [
          {'key': 'category', 'value': 'blazer'},
          {'key': 'material', 'value': 'Light wool blend'},
          {'key': 'color', 'value': 'Warm grey'},
        ],
      ),
      _demoEntry(
        id: 'demo-item-3',
        wardrobeId: _demoPrimaryWardrobeId,
        clothingItemId: 'demo-lower-pants',
        name: 'Wide Pleated Trousers',
        source: 'OWNED',
        tags: const [
          {'key': 'category', 'value': 'pants'},
          {'key': 'material', 'value': 'Draped twill'},
          {'key': 'color', 'value': 'Charcoal'},
        ],
      ),
      _demoEntry(
        id: 'demo-item-4',
        wardrobeId: _demoPrimaryWardrobeId,
        clothingItemId: 'demo-feet-loafers',
        name: 'Leather Penny Loafers',
        source: 'OWNED',
        tags: const [
          {'key': 'category', 'value': 'loafers'},
          {'key': 'material', 'value': 'Polished leather'},
          {'key': 'color', 'value': 'Espresso'},
        ],
      ),
      _demoEntry(
        id: 'demo-item-5',
        wardrobeId: _demoPrimaryWardrobeId,
        clothingItemId: 'demo-head-beret',
        name: 'Wool Beret',
        source: 'OWNED',
        tags: const [
          {'key': 'category', 'value': 'beret'},
          {'key': 'material', 'value': 'Merino wool blend'},
          {'key': 'color', 'value': 'Ivory'},
        ],
      ),
    ],
    'guest-virtual-wardrobe': <WardrobeItemWithClothing>[
      _demoEntry(
        id: 'demo-item-6',
        wardrobeId: 'guest-virtual-wardrobe',
        clothingItemId: 'demo-virtual-cardigan',
        name: 'Imported Knit Cardigan',
        source: 'IMPORTED',
        tags: const [
          {'key': 'category', 'value': 'cardigan'},
          {'key': 'material', 'value': 'Soft alpaca knit'},
          {'key': 'color', 'value': 'Stone'},
        ],
      ),
      _demoEntry(
        id: 'demo-item-7',
        wardrobeId: 'guest-virtual-wardrobe',
        clothingItemId: 'demo-virtual-skirt',
        name: 'Imported Satin Skirt',
        source: 'IMPORTED',
        tags: const [
          {'key': 'category', 'value': 'skirt'},
          {'key': 'material', 'value': 'Fluid satin'},
          {'key': 'color', 'value': 'Olive'},
        ],
      ),
    ],
  };

  static Future<Dio> _client() async {
    await AuthService.ensureDemoSession();
    _dio.options.headers['Authorization'] = 'Bearer ${AuthService.token}';
    return _dio;
  }

  static bool get _useGuestDemoData => localDemoOnly || AuthService.isGuestMode;

  static Future<List<Wardrobe>> fetchWardrobes() async {
    if (_useGuestDemoData) {
      return _snapshotDemoWardrobes();
    }

    final dio = await _client();
    final resp = await dio.get('/wardrobes');
    final raw = resp.data;
    final list = (raw is Map && raw['items'] != null)
        ? raw['items'] as List
        : <dynamic>[];
    return list
        .map((e) => Wardrobe.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<WardrobeItemWithClothing>> fetchWardrobeItems(
    String wardrobeId,
  ) async {
    if (_useGuestDemoData) {
      return List<WardrobeItemWithClothing>.from(
        _demoItemsByWardrobe[wardrobeId] ?? const <WardrobeItemWithClothing>[],
      );
    }

    final dio = await _client();
    final resp = await dio.get('/wardrobes/$wardrobeId/items');
    final raw = resp.data;
    final list = (raw is Map && raw['items'] != null)
        ? raw['items'] as List
        : <dynamic>[];
    return list
        .map(
          (e) => WardrobeItemWithClothing.fromJson(e as Map<String, dynamic>),
        )
        .toList();
  }

  static Future<Wardrobe> createWardrobe({
    required String name,
    String type = 'REGULAR',
    String? description,
  }) async {
    if (_useGuestDemoData) {
      final wardrobe = Wardrobe(
        id: 'guest-created-wardrobe-${_demoWardrobeCounter++}',
        userId: _demoUserId,
        name: name,
        type: type,
        description: description,
        itemCount: 0,
        createdAt: DateTime.now(),
      );
      _demoWardrobes.add(wardrobe);
      _demoItemsByWardrobe[wardrobe.id] = <WardrobeItemWithClothing>[];
      return wardrobe;
    }

    final dio = await _client();
    final body = <String, dynamic>{
      'name': name,
      'type': type,
      if (description != null && description.isNotEmpty)
        'description': description,
    };
    final resp = await dio.post('/wardrobes', data: body);
    return Wardrobe.fromJson(resp.data as Map<String, dynamic>);
  }

  static Future<Wardrobe> updateWardrobe(
    String wardrobeId, {
    String? name,
    String? description,
  }) async {
    if (_useGuestDemoData) {
      final index = _demoWardrobes.indexWhere(
        (wardrobe) => wardrobe.id == wardrobeId,
      );
      if (index == -1) {
        throw Exception('Demo wardrobe not found');
      }
      final current = _demoWardrobes[index];
      final updated = Wardrobe(
        id: current.id,
        userId: current.userId,
        name: name ?? current.name,
        type: current.type,
        description: description ?? current.description,
        itemCount: (_demoItemsByWardrobe[current.id] ?? const []).length,
        createdAt: current.createdAt,
        updatedAt: DateTime.now(),
      );
      _demoWardrobes[index] = updated;
      return updated;
    }

    final dio = await _client();
    final body = <String, dynamic>{
      ...?(name != null ? {'name': name} : null),
      ...?(description != null ? {'description': description} : null),
    };
    final resp = await dio.patch('/wardrobes/$wardrobeId', data: body);
    return Wardrobe.fromJson(resp.data as Map<String, dynamic>);
  }

  static Future<void> deleteWardrobe(String wardrobeId) async {
    if (_useGuestDemoData) {
      _demoWardrobes.removeWhere((wardrobe) => wardrobe.id == wardrobeId);
      _demoItemsByWardrobe.remove(wardrobeId);
      return;
    }

    final dio = await _client();
    await dio.delete('/wardrobes/$wardrobeId');
  }

  static Future<void> addItemToWardrobe(
    String wardrobeId,
    String clothingItemId,
  ) async {
    if (_useGuestDemoData) {
      final items = _demoItemsByWardrobe.putIfAbsent(
        wardrobeId,
        () => <WardrobeItemWithClothing>[],
      );
      final exists = items.any((item) => item.clothingItemId == clothingItemId);
      if (exists) {
        return;
      }
      items.add(
        _demoEntry(
          id: 'demo-item-${_demoItemCounter++}',
          wardrobeId: wardrobeId,
          clothingItemId: clothingItemId,
          name: 'New demo item',
          source: 'OWNED',
          tags: const [
            {'key': 'category', 'value': 'shirt'},
            {'key': 'material', 'value': 'Material pending'},
          ],
        ),
      );
      return;
    }

    final dio = await _client();
    await dio.post(
      '/wardrobes/$wardrobeId/items',
      data: {'clothingItemId': clothingItemId},
    );
  }

  static Future<void> removeItemFromWardrobe(
    String wardrobeId,
    String clothingItemId,
  ) async {
    if (_useGuestDemoData) {
      _demoItemsByWardrobe[wardrobeId]?.removeWhere(
        (item) => item.clothingItemId == clothingItemId,
      );
      return;
    }

    final dio = await _client();
    await dio.delete('/wardrobes/$wardrobeId/items/$clothingItemId');
  }

  @visibleForTesting
  static void resetDemoDataForTest() {
    _demoWardrobes
      ..clear()
      ..addAll(<Wardrobe>[
        const Wardrobe(
          id: _demoPrimaryWardrobeId,
          userId: _demoUserId,
          name: 'Demo Closet',
          type: 'REGULAR',
          description: 'Local demo wardrobe available when backend is offline.',
          itemCount: 5,
        ),
        const Wardrobe(
          id: 'guest-virtual-wardrobe',
          userId: _demoUserId,
          name: 'Shared Looks',
          type: 'VIRTUAL',
          description: 'Imported references used for local preview demos.',
          itemCount: 2,
        ),
      ]);
    _demoItemsByWardrobe
      ..clear()
      ..addAll(<String, List<WardrobeItemWithClothing>>{
        _demoPrimaryWardrobeId: <WardrobeItemWithClothing>[
          _demoEntry(
            id: 'demo-item-1',
            wardrobeId: _demoPrimaryWardrobeId,
            clothingItemId: 'demo-upper-shirt',
            name: 'Relaxed Oxford Shirt',
            source: 'OWNED',
            tags: const [
              {'key': 'category', 'value': 'shirt'},
              {'key': 'material', 'value': 'Cotton poplin'},
              {'key': 'color', 'value': 'Blue stripe'},
            ],
          ),
          _demoEntry(
            id: 'demo-item-2',
            wardrobeId: _demoPrimaryWardrobeId,
            clothingItemId: 'demo-upper-jacket',
            name: 'Soft Tailored Blazer',
            source: 'OWNED',
            tags: const [
              {'key': 'category', 'value': 'blazer'},
              {'key': 'material', 'value': 'Light wool blend'},
              {'key': 'color', 'value': 'Warm grey'},
            ],
          ),
          _demoEntry(
            id: 'demo-item-3',
            wardrobeId: _demoPrimaryWardrobeId,
            clothingItemId: 'demo-lower-pants',
            name: 'Wide Pleated Trousers',
            source: 'OWNED',
            tags: const [
              {'key': 'category', 'value': 'pants'},
              {'key': 'material', 'value': 'Draped twill'},
              {'key': 'color', 'value': 'Charcoal'},
            ],
          ),
          _demoEntry(
            id: 'demo-item-4',
            wardrobeId: _demoPrimaryWardrobeId,
            clothingItemId: 'demo-feet-loafers',
            name: 'Leather Penny Loafers',
            source: 'OWNED',
            tags: const [
              {'key': 'category', 'value': 'loafers'},
              {'key': 'material', 'value': 'Polished leather'},
              {'key': 'color', 'value': 'Espresso'},
            ],
          ),
          _demoEntry(
            id: 'demo-item-5',
            wardrobeId: _demoPrimaryWardrobeId,
            clothingItemId: 'demo-head-beret',
            name: 'Wool Beret',
            source: 'OWNED',
            tags: const [
              {'key': 'category', 'value': 'beret'},
              {'key': 'material', 'value': 'Merino wool blend'},
              {'key': 'color', 'value': 'Ivory'},
            ],
          ),
        ],
        'guest-virtual-wardrobe': <WardrobeItemWithClothing>[
          _demoEntry(
            id: 'demo-item-6',
            wardrobeId: 'guest-virtual-wardrobe',
            clothingItemId: 'demo-virtual-cardigan',
            name: 'Imported Knit Cardigan',
            source: 'IMPORTED',
            tags: const [
              {'key': 'category', 'value': 'cardigan'},
              {'key': 'material', 'value': 'Soft alpaca knit'},
              {'key': 'color', 'value': 'Stone'},
            ],
          ),
          _demoEntry(
            id: 'demo-item-7',
            wardrobeId: 'guest-virtual-wardrobe',
            clothingItemId: 'demo-virtual-skirt',
            name: 'Imported Satin Skirt',
            source: 'IMPORTED',
            tags: const [
              {'key': 'category', 'value': 'skirt'},
              {'key': 'material', 'value': 'Fluid satin'},
              {'key': 'color', 'value': 'Olive'},
            ],
          ),
        ],
      });
    _demoWardrobeCounter = 1;
    _demoItemCounter = 6;
  }

  static List<Wardrobe> _snapshotDemoWardrobes() {
    return _demoWardrobes
        .map(
          (wardrobe) => Wardrobe(
            id: wardrobe.id,
            userId: wardrobe.userId,
            name: wardrobe.name,
            type: wardrobe.type,
            description: wardrobe.description,
            itemCount: (_demoItemsByWardrobe[wardrobe.id] ?? const []).length,
            createdAt: wardrobe.createdAt,
            updatedAt: wardrobe.updatedAt,
          ),
        )
        .toList();
  }

  static WardrobeItemWithClothing _demoEntry({
    required String id,
    required String wardrobeId,
    required String clothingItemId,
    required String name,
    required String source,
    required List<Map<String, String>> tags,
  }) {
    return WardrobeItemWithClothing(
      id: id,
      wardrobeId: wardrobeId,
      clothingItemId: clothingItemId,
      clothingItem: ClothingItemBrief(
        id: clothingItemId,
        name: name,
        source: source,
        finalTags: tags,
      ),
    );
  }
}
