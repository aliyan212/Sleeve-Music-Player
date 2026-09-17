import 'package:flutter/material.dart';

/// Available destinations for the bottom navigation island dock.
enum AppTab {
  songs,
  albums,
  artists,
  genres,
  playlists,
  folders;

  String get label {
    switch (this) {
      case AppTab.songs:
        return 'Songs';
      case AppTab.albums:
        return 'Albums';
      case AppTab.artists:
        return 'Artists';
      case AppTab.genres:
        return 'Genres';
      case AppTab.playlists:
        return 'Playlists';
      case AppTab.folders:
        return 'Folders';
    }
  }

  IconData get icon {
    switch (this) {
      case AppTab.songs:
        return Icons.music_note_outlined;
      case AppTab.albums:
        return Icons.album_outlined;
      case AppTab.artists:
        return Icons.people_outline_rounded;
      case AppTab.genres:
        return Icons.category_outlined;
      case AppTab.playlists:
        return Icons.queue_music_outlined;
      case AppTab.folders:
        return Icons.folder_outlined;
    }
  }

  IconData get selectedIcon {
    switch (this) {
      case AppTab.songs:
        return Icons.music_note_rounded;
      case AppTab.albums:
        return Icons.album_rounded;
      case AppTab.artists:
        return Icons.people_rounded;
      case AppTab.genres:
        return Icons.category_rounded;
      case AppTab.playlists:
        return Icons.queue_music_rounded;
      case AppTab.folders:
        return Icons.folder_rounded;
    }
  }

  String get storageKey => name;

  static AppTab fromStorageKey(String key) {
    return AppTab.values.firstWhere(
      (e) => e.name == key,
      orElse: () => AppTab.songs,
    );
  }

  static const List<AppTab> defaultTabs = [
    AppTab.songs,
    AppTab.albums,
    AppTab.artists,
    AppTab.genres,
    AppTab.playlists,
  ];

  static List<AppTab> parseList(List<String>? keys) {
    if (keys == null || keys.isEmpty) return List.of(defaultTabs);
    final valid = <AppTab>[];
    for (final k in keys) {
      try {
        final tab = AppTab.values.firstWhere((e) => e.name == k);
        if (!valid.contains(tab)) valid.add(tab);
      } catch (_) {}
    }
    if (valid.length < 3) return List.of(defaultTabs);
    if (valid.length > 5) return valid.sublist(0, 5);
    return valid;
  }
}

