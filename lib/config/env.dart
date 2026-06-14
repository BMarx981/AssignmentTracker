import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;

class Env {
  static const String _apiBaseUrlOverride =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');
  static const String devUser =
      String.fromEnvironment('DEV_USER', defaultValue: 'dev');

  static String get apiBaseUrl {
    if (_apiBaseUrlOverride.isNotEmpty) return _apiBaseUrlOverride;
    if (kIsWeb) return Uri.base.origin;
    if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    return 'http://localhost:8000';
  }
}
