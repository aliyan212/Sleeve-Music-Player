import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class SettingsService extends ChangeNotifier {
  static final SettingsService instance = SettingsService._();
  SettingsService._();

  static const String _filterShortTracksKey = 'filter_short_tracks';
  static const String _keepScreenAwakeKey = 'keep_screen_awake';

  bool _filterShortTracks = false;
  bool _keepScreenAwake = false;

  bool get filterShortTracks => _filterShortTracks;
  bool get keepScreenAwake => _keepScreenAwake;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _filterShortTracks = prefs.getBool(_filterShortTracksKey) ?? false;
    _keepScreenAwake = prefs.getBool(_keepScreenAwakeKey) ?? false;
    
    _applyWakelock();
  }

  Future<void> setFilterShortTracks(bool value) async {
    _filterShortTracks = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_filterShortTracksKey, value);
    notifyListeners();
  }

  Future<void> setKeepScreenAwake(bool value) async {
    _keepScreenAwake = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keepScreenAwakeKey, value);
    _applyWakelock();
    notifyListeners();
  }
  
  void _applyWakelock() {
    if (!kIsWeb) {
      WakelockPlus.toggle(enable: _keepScreenAwake);
    }
  }
}
