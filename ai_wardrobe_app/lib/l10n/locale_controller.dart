import 'package:flutter/material.dart';

/// Controls app locale (en / zh). Wire to Profile language dropdown.
class LocaleController extends ChangeNotifier {
  Locale _locale = const Locale('en');

  Locale get locale => _locale;

  bool get isZh => _locale.languageCode == 'zh';

  void setLocale(Locale value) {
    if (_locale == value) return;
    _locale = value;
    notifyListeners();
  }

  void setLanguageCode(String code) {
    setLocale(Locale(code));
  }
}

final localeController = LocaleController();
