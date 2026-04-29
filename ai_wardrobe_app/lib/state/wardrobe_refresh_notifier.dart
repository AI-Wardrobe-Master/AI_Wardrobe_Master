import 'package:flutter/foundation.dart';

class WardrobeRefreshNotifier {
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);

  static void requestRefresh() {
    tick.value += 1;
  }
}
