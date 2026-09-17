import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class LovedSongsService extends ChangeNotifier {
  static const String _boxName = 'loved_songs';
  Box<int>? _box;
  final Set<int> _lovedIds = {};

  static final LovedSongsService instance = LovedSongsService._();
  LovedSongsService._();

  Future<void> init() async {
    if (_box != null) return;
    _box = await Hive.openBox<int>(_boxName);
    _lovedIds.addAll(_box!.values);
    notifyListeners();
  }

  Set<int> get lovedIds => Set.unmodifiable(_lovedIds);

  bool isLoved(int songId) {
    return _lovedIds.contains(songId);
  }

  Future<void> syncFromSongIds(Iterable<int> songIds) async {
    final newSet = songIds.toSet();
    if (setEquals(_lovedIds, newSet)) return;
    _lovedIds.clear();
    _lovedIds.addAll(newSet);
    if (_box != null) {
      await _box!.clear();
      await _box!.addAll(newSet);
    }
    notifyListeners();
  }

  Future<void> addLoved(int songId) async {
    if (_lovedIds.contains(songId)) return;
    _lovedIds.add(songId);
    if (_box != null) {
      await _box!.add(songId);
    }
    notifyListeners();
  }

  Future<void> removeLoved(int songId) async {
    if (!_lovedIds.contains(songId)) return;
    _lovedIds.remove(songId);
    if (_box != null) {
      final key = _box!.keys.firstWhere(
        (k) => _box!.get(k) == songId,
        orElse: () => null,
      );
      if (key != null) {
        await _box!.delete(key);
      }
    }
    notifyListeners();
  }

  Future<bool> toggleLoved(int songId) async {
    if (_lovedIds.contains(songId)) {
      await removeLoved(songId);
      return false;
    } else {
      await addLoved(songId);
      return true;
    }
  }
}

