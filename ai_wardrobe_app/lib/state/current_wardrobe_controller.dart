import 'package:flutter/foundation.dart';

/// Holds the currently selected wardrobe ID so other screens (e.g. ClothingResultScreen)
/// can add new items to it without passing through navigation.
class CurrentWardrobeController {
  CurrentWardrobeController._();

  static final ValueNotifier<String?> _currentWardrobeId =
      ValueNotifier<String?>(null);

  static String? get currentWardrobeId => _currentWardrobeId.value;

  static ValueListenable<String?> get listenable => _currentWardrobeId;

  static void setCurrentWardrobeId(String? id) {
    if (_currentWardrobeId.value == id) {
      return;
    }
    _currentWardrobeId.value = id;
  }
}
