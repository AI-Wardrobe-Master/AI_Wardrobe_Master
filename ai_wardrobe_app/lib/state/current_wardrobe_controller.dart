/// Holds the currently selected wardrobe ID so other screens (e.g. ClothingResultScreen)
/// can add new items to it without passing through navigation.
class CurrentWardrobeController {
  CurrentWardrobeController._();

  static String? _currentWardrobeId;

  static String? get currentWardrobeId => _currentWardrobeId;

  static void setCurrentWardrobeId(String? id) {
    _currentWardrobeId = id;
  }
}
