class TestClothingItems {
  static List<Map<String, dynamic>> getTestItems() {
    return [
      {
        'id': 'test-item-1',
        'name': 'Navy Blue Polo Shirt',
        'description':
            'Classic navy blue polo shirt with embroidered logo. Custom slim fit with stretch mesh fabric.',
        'source': 'OWNED',
        'images': {
          'originalFrontUrl':
              'https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?w=400',
          'processedFrontUrl':
              'https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?w=400',
        },
        'finalTags': [
          {'key': 'category', 'value': 'POLO_SHIRT'},
          {'key': 'color', 'value': 'navy'},
          {'key': 'style', 'value': 'casual'},
        ],
        'createdAt': DateTime.now().toIso8601String(),
      },
      {
        'id': 'test-item-2',
        'name': 'White Casual T-Shirt',
        'description':
            'Comfortable white cotton t-shirt, perfect for everyday wear.',
        'source': 'OWNED',
        'images': {
          'originalFrontUrl':
              'https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?w=400',
          'processedFrontUrl':
              'https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?w=400',
        },
        'finalTags': [
          {'key': 'category', 'value': 'T_SHIRT'},
          {'key': 'color', 'value': 'white'},
          {'key': 'style', 'value': 'casual'},
        ],
        'createdAt': DateTime.now().toIso8601String(),
      },
      {
        'id': 'test-item-3',
        'name': 'Blue Denim Jeans',
        'description': 'Classic blue denim jeans with straight fit.',
        'source': 'OWNED',
        'images': {
          'originalFrontUrl':
              'https://images.unsplash.com/photo-1542272604-787c3835535d?w=400',
          'processedFrontUrl':
              'https://images.unsplash.com/photo-1542272604-787c3835535d?w=400',
        },
        'finalTags': [
          {'key': 'category', 'value': 'JEANS'},
          {'key': 'color', 'value': 'blue'},
          {'key': 'style', 'value': 'casual'},
        ],
        'createdAt': DateTime.now().toIso8601String(),
      },
      {
        'id': 'test-item-4',
        'name': 'Black Leather Jacket',
        'description': 'Stylish black leather jacket with zipper closure.',
        'source': 'OWNED',
        'images': {
          'originalFrontUrl':
              'https://images.unsplash.com/photo-1551028719-00167b16eac5?w=400',
          'processedFrontUrl':
              'https://images.unsplash.com/photo-1551028719-00167b16eac5?w=400',
        },
        'finalTags': [
          {'key': 'category', 'value': 'JACKET'},
          {'key': 'color', 'value': 'black'},
          {'key': 'material', 'value': 'leather'},
        ],
        'createdAt': DateTime.now().toIso8601String(),
      },
    ];
  }
}
