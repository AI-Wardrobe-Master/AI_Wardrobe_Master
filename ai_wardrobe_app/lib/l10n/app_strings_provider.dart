import 'package:flutter/material.dart';

import 'app_strings.dart';

/// Provides [AppStrings] for the current [Locale] to the widget tree.
class AppStringsProvider extends InheritedWidget {
  const AppStringsProvider({
    super.key,
    required this.locale,
    required super.child,
  });

  final Locale locale;

  static AppStrings of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<AppStringsProvider>();
    assert(provider != null, 'No AppStringsProvider found in context');
    return AppStrings.of(provider!.locale);
  }

  @override
  bool updateShouldNotify(AppStringsProvider oldWidget) {
    return locale != oldWidget.locale;
  }
}
