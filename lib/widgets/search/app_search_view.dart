import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/album_stat.dart';
import '../../data/models/genre_stat.dart';
import '../../services/app_state_controller.dart';
import '../../services/playback_controller.dart';
import '../../ui/shared/app_empty_state.dart';
import '../../ui/shared/fast_artwork_widget.dart';
import '../../utils/format_utils.dart';
import '../../utils/song_sort_utils.dart';

enum SearchFilter {
  all,
  tracks,
  albums,
  artists,
  albumArtists,
  composers,
  genres,
}

class SearchCategoryManager {
  static const String _prefKey = 'search_enabled_categories_v3';
  static const Set<String> defaultCategories = {
    'tracks',
    'albums',
    'artists',
    'albumArtists',
    'composers',
    'genres',
  };

  static Future<Set<String>> getEnabledCategories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefKey);
      if (list == null || list.isEmpty) {
        return Set<String>.from(defaultCategories);
      }
      return list.toSet();
    } catch (_) {
      return Set<String>.from(defaultCategories);
    }
  }

  static Future<void> saveEnabledCategories(Set<String> categories) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefKey, categories.toList());
    } catch (_) {}
  }

  static void showSettingsSheet(BuildContext context, {VoidCallback? onChanged}) async {
    final initialCategories = await getEnabledCategories();
    final Set<String> enabledCategories = Set.from(initialCategories);

    if (!context.mounted) {
      return;
    }

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Widget buildSwitch(String key, String label, IconData icon) {
              return SwitchListTile.adaptive(
                title: Text(label),
                secondary: Icon(icon),
                value: enabledCategories.contains(key),
                onChanged: (val) {
                  if (!val && enabledCategories.length <= 1) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('At least one category must remain active.')),
                    );
                    return;
                  }
                  HapticFeedback.selectionClick();
                  setSheetState(() {
                    if (val) {
                      enabledCategories.add(key);
                    } else {
                      enabledCategories.remove(key);
                    }
                  });
                  saveEnabledCategories(enabledCategories);
                  onChanged?.call();
                },
              );
            }
            
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text('Search Categories', style: Theme.of(context).textTheme.titleLarge),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        buildSwitch('tracks', 'Tracks', Icons.music_note_rounded),
                        buildSwitch('albums', 'Albums', Icons.album_rounded),
                        buildSwitch('artists', 'Artists', Icons.person_rounded),
                        buildSwitch('albumArtists', 'Album Artists', Icons.group_rounded),
                        buildSwitch('composers', 'Composers', Icons.draw_rounded),
                        buildSwitch('genres', 'Genres', Icons.style_rounded),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setSheetState(() {
                        enabledCategories.clear();
                        enabledCategories.addAll(defaultCategories);
                      });
                      saveEnabledCategories(enabledCategories);
                      onChanged?.call();
                    },
                    child: const Text('Reset to Defaults'),
                  ),
                ],
              ),
            );
          }
        );
      }
    );
  }
}

class SearchHistoryManager {
  static const String _key = 'search_recent_queries';
  static const int maxHistory = 10;

  static Future<List<String>> getHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_key) ?? <String>[];
    } catch (_) {
      return <String>[];
    }
  }

  static Future<void> addQuery(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = (prefs.getStringList(_key) ?? <String>[]).toList();
      list.removeWhere((item) => item.toLowerCase() == q.toLowerCase());
      list.insert(0, q);
      if (list.length > maxHistory) {
        list.removeRange(maxHistory, list.length);
      }
      await prefs.setStringList(_key, list);
    } catch (_) {}
  }

  static Future<void> removeQuery(String query) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = (prefs.getStringList(_key) ?? <String>[]).toList();
      list.removeWhere((item) => item.toLowerCase() == query.trim().toLowerCase());
      await prefs.setStringList(_key, list);
    } catch (_) {}
  }

  static Future<void> clearHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}

Widget buildHighlightedText({
  required String text,
  required String query,
  required TextStyle baseStyle,
  required Color highlightColor,
  int maxLines = 1,
  TextOverflow overflow = TextOverflow.ellipsis,
}) {
  final cleanQuery = query.trim();
  if (cleanQuery.isEmpty) {
    return Text(text, style: baseStyle, maxLines: maxLines, overflow: overflow);
  }

  final lowerText = text.toLowerCase();
  final lowerQuery = cleanQuery.toLowerCase();

  final spans = <TextSpan>[];
  int start = 0;

  while (true) {
    final matchIndex = lowerText.indexOf(lowerQuery, start);
    if (matchIndex == -1) {
      if (start < text.length) {
        spans.add(TextSpan(text: text.substring(start)));
      }
      break;
    }

    if (matchIndex > start) {
      spans.add(TextSpan(text: text.substring(start, matchIndex)));
    }

    final matchEnd = matchIndex + lowerQuery.length;
    spans.add(
      TextSpan(
        text: text.substring(matchIndex, matchEnd),
        style: TextStyle(color: highlightColor, fontWeight: FontWeight.w700),
      ),
    );

    start = matchEnd;
  }

  return Text.rich(TextSpan(style: baseStyle, children: spans), maxLines: maxLines, overflow: overflow);
}

class AppSearchView extends StatefulWidget {
  final SearchFilter initialFilter;
  final String? initialQuery;

  const AppSearchView({
    super.key,
    this.initialFilter = SearchFilter.all,
    this.initialQuery,
  });

  static Future<void> show(
    BuildContext context, {
    SearchFilter initialFilter = SearchFilter.all,
    String? initialQuery,
  }) async {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AppSearchView(
          initialFilter: initialFilter,
          initialQuery: initialQuery,
        ),
      ),
    );
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  @override
  State<AppSearchView> createState() => _AppSearchViewState();
}

class _AppSearchViewState extends State<AppSearchView> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _searchBarKey = GlobalKey();
  late SearchFilter _selectedFilter;
  String _query = '';
  List<String> _recentSearches = [];
  Set<String> _enabledCategories = Set.from(SearchCategoryManager.defaultCategories);

  @override
  void initState() {
    super.initState();
    _selectedFilter = widget.initialFilter;
    _query = (widget.initialQuery ?? '').trim();
    _controller = TextEditingController(text: widget.initialQuery ?? '');
    _loadRecentSearches();
    _loadCategories();
  }
  
  Future<void> _loadCategories() async {
    final cats = await SearchCategoryManager.getEnabledCategories();
    if (mounted) {
      setState(() => _enabledCategories = cats);
    }
  }

  Future<void> _loadRecentSearches() async {
    final history = await SearchHistoryManager.getHistory();
    if (mounted) {
      setState(() => _recentSearches = history);
    }
  }

  void _unfocusAndHideKeyboard() {
    _focusNode.unfocus();
    if (mounted) FocusScope.of(context).unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  void _handlePointerDown(PointerDownEvent event) {
    final renderBox = _searchBarKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      final pos = renderBox.localToGlobal(Offset.zero);
      final rect = pos & renderBox.size;
      if (!rect.contains(event.position)) {
        if (_focusNode.hasFocus || (FocusManager.instance.primaryFocus?.hasFocus ?? false)) {
          _unfocusAndHideKeyboard();
        }
      }
    }
  }

  @override
  void dispose() {
    _focusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _dismissSearchAndPop() {
    _unfocusAndHideKeyboard();
    Navigator.of(context).pop();
  }

  void _recordQueryAndSave(String q) {
    if (q.trim().isNotEmpty) {
      SearchHistoryManager.addQuery(q.trim());
      _loadRecentSearches();
    }
  }

  String _getHintText() {
    return switch (_selectedFilter) {
      SearchFilter.all => 'Search...',
      SearchFilter.tracks => 'Search tracks...',
      SearchFilter.albums => 'Search albums...',
      SearchFilter.artists => 'Search artists...',
      SearchFilter.albumArtists => 'Search album artists...',
      SearchFilter.composers => 'Search composers...',
      SearchFilter.genres => 'Search genres...',
    };
  }

  void _removeCategory(String categoryKey, String title) {
    if (_enabledCategories.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least one search category must remain active.'), duration: Duration(seconds: 2)),
      );
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _enabledCategories.remove(categoryKey));
    SearchCategoryManager.saveEnabledCategories(_enabledCategories);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title hidden from search results'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            setState(() => _enabledCategories.add(categoryKey));
            SearchCategoryManager.saveEnabledCategories(_enabledCategories);
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }
  
  void _showCategoryFilterSheet() {
    SearchCategoryManager.showSettingsSheet(
      context, 
      onChanged: _loadCategories,
    );
  }

  Widget _buildFilterChip({
    required SearchFilter filter,
    required String label,
    int? count,
    required String categoryKey,
  }) {
    // Only show if it's the currently selected filter OR it's enabled in settings.
    if (!(_enabledCategories.contains(categoryKey) || _selectedFilter == filter)) {
      return const SizedBox.shrink();
    }
    
    final cs = Theme.of(context).colorScheme;
    final isSelected = _selectedFilter == filter;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: isSelected,
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            if (count != null && count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isSelected ? cs.primary.withValues(alpha: 0.18) : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isSelected ? cs.primary : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
        onSelected: (_) {
          HapticFeedback.selectionClick();
          setState(() => _selectedFilter = filter);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final appState = AppStateController.instance;
    final songs = appState.songs;

    final q = _query.trim().toLowerCase();

    String norm(String? v) => (v ?? '').trim().toLowerCase();
    bool exact(String? v) => q.isNotEmpty && norm(v) == q;
    bool starts(String? v) => norm(v).startsWith(q);
    bool contains(String? v) => norm(v).contains(q);

    List<T> getHits<T>(Iterable<T> items, String? Function(T) getName) {
      if (q.isEmpty) return [];
      final exactMatches = <T>[];
      final startMatches = <T>[];
      final containMatches = <T>[];
      for (final s in items) {
        final n = getName(s);
        if (exact(n)) {
          exactMatches.add(s);
        } else if (starts(n)) {
          startMatches.add(s);
        } else if (contains(n)) {
          containMatches.add(s);
        }
      }
      return [...exactMatches, ...startMatches, ...containMatches];
    }

    // Tracks
    final trackHits = getHits(songs, (s) => s.title);
    
    // Albums
    final List<AlbumTabStat> albumSource = appState.cachedAlbums.isNotEmpty
        ? appState.cachedAlbums
        : () {
            final Map<int, AlbumTabStat> byAlbumId = {};
            for (final s in songs) {
              final id = s.albumId;
              if (id == null || id <= 0) continue;
              byAlbumId.putIfAbsent(id, () => AlbumTabStat(
                albumId: id, representativeSong: s, title: s.album ?? 'Unknown Album',
                artist: s.artist ?? 'Unknown Artist', trackCount: 1, year: 0,
              ));
            }
            return byAlbumId.values.toList();
          }();
    final albumHits = getHits(albumSource, (s) => s.title);

    // Track Artists
    final List<AlbumArtistStat> trackArtistSource = appState.cachedTrackArtists.isNotEmpty
        ? appState.cachedTrackArtists
        : () {
            final Map<String, AlbumArtistStat> byName = {};
            for (final s in songs) {
              final name = (s.artist ?? '').trim();
              if (name.isEmpty) continue;
              final stat = byName.putIfAbsent(name.toLowerCase(), () => AlbumArtistStat(name: name, representativeSong: s));
              stat.trackCount++;
            }
            return byName.values.toList();
          }();
    final artistHits = getHits(trackArtistSource, (s) => s.name);
    
    // Album Artists
    final List<AlbumArtistStat> albumArtistSource = appState.cachedAlbumArtists.isNotEmpty
        ? appState.cachedAlbumArtists
        : () {
            final Map<String, AlbumArtistStat> byName = {};
            for (final s in songs) {
              final name = (albumArtistFor(s)).trim();
              if (name.isEmpty) continue;
              final stat = byName.putIfAbsent(name.toLowerCase(), () => AlbumArtistStat(name: name, representativeSong: s));
              stat.trackCount++;
              if (s.albumId != null && s.albumId! > 0) stat.albumIds.add(s.albumId!);
            }
            return byName.values.toList();
          }();
    final albumArtistHits = getHits(albumArtistSource, (s) => s.name);
    
    // Composers
    final List<AlbumArtistStat> composerSource = appState.cachedComposers.isNotEmpty
        ? appState.cachedComposers
        : () {
            final Map<String, AlbumArtistStat> byName = {};
            for (final s in songs) {
              final name = (s.composer ?? '').trim();
              if (name.isEmpty) continue;
              final stat = byName.putIfAbsent(name.toLowerCase(), () => AlbumArtistStat(name: name, representativeSong: s));
              stat.trackCount++;
            }
            return byName.values.toList();
          }();
    final composerHits = getHits(composerSource, (s) => s.name);
    
    // Genres
    final List<GenreStat> genreSource = appState.cachedGenres.isNotEmpty
        ? appState.cachedGenres
        : () {
            final Map<String, GenreStat> byName = {};
            for (final s in songs) {
              final name = (s.genre ?? '').trim();
              if (name.isEmpty) continue;
              final stat = byName.putIfAbsent(name.toLowerCase(), () => GenreStat(name: name, representativeSong: s));
              stat.trackCount++;
              if (s.albumId != null && s.albumId! > 0) stat.albumIds.add(s.albumId!);
            }
            return byName.values.toList();
          }();
    final genreHits = getHits(genreSource, (s) => s.name);

    Widget header(String title, {String? categoryKey}) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Row(
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
            const Spacer(),
            if (categoryKey != null)
              IconButton(
                icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
                tooltip: 'Hide $title from search',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => _removeCategory(categoryKey, title),
              ),
          ],
        ),
      );
    }

    Widget searchResultTile({
      required Widget leading,
      required Widget title,
      Widget? subtitle,
      Widget? trailing,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: cs.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    leading,
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          title,
                          if (subtitle != null) ...[
                            const SizedBox(height: 3),
                            subtitle,
                          ],
                        ],
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 10),
                      trailing,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final resultItems = <Widget>[];

    void addTracks({int? limit}) {
      final list = limit != null ? trackHits.take(limit).toList() : trackHits;
      if (list.isEmpty) return;
      if (_selectedFilter == SearchFilter.all) resultItems.add(header('Tracks', categoryKey: 'tracks'));
      for (final song in list) {
        final idx = songs.indexWhere((s) => s.id == song.id);
        final artist = (song.artist ?? '').trim().isEmpty ? 'Unknown Artist' : song.artist!.trim();
        final album = (song.album ?? '').trim().isEmpty ? 'Unknown Album' : song.album!.trim();
        final duration = song.duration == null ? null : formatTime(song.duration);
        final subtitleText = duration == null ? '$artist • $album' : '$artist • $album • $duration';

        resultItems.add(
          searchResultTile(
            leading: ClipOval(
              child: FastArtworkWidget(
                id: song.id,
                type: ArtworkType.AUDIO,
                width: 52,
                height: 52,
                nullArtworkWidget: Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(color: cs.surfaceContainerHighest, shape: BoxShape.circle),
                  child: Icon(Icons.music_note_rounded, color: cs.onSurfaceVariant, size: 22),
                ),
              ),
            ),
            title: buildHighlightedText(
              text: song.title, query: _query,
              baseStyle: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.1) ?? const TextStyle(),
              highlightColor: cs.primary,
            ),
            subtitle: buildHighlightedText(
              text: subtitleText, query: _query,
              baseStyle: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600) ?? const TextStyle(),
              highlightColor: cs.primary,
            ),
            trailing: IconButton.filledTonal(
              icon: const Icon(Icons.play_arrow_rounded),
              tooltip: 'Play',
              onPressed: () {
                _recordQueryAndSave(_query);
                HapticFeedback.selectionClick();
                _dismissSearchAndPop();
                if (idx != -1) playbackController.playFromQueue(songs, initialIndex: idx);
              },
            ),
            onTap: () {
              _recordQueryAndSave(_query);
              HapticFeedback.selectionClick();
              _dismissSearchAndPop();
              if (idx != -1) playbackController.playFromQueue(songs, initialIndex: idx);
            },
          ),
        );
      }
    }

    void addAlbums({int? limit}) {
      final list = limit != null ? albumHits.take(limit).toList() : albumHits;
      if (list.isEmpty) return;
      if (_selectedFilter == SearchFilter.all) resultItems.add(header('Albums', categoryKey: 'albums'));
      for (final album in list) {
        resultItems.add(
          searchResultTile(
            leading: ClipOval(
              child: FastArtworkWidget(
                id: album.representativeSong.id,
                fallbackId: album.albumId,
                type: ArtworkType.AUDIO,
                fallbackType: ArtworkType.ALBUM,
                width: 52,
                height: 52,
                nullArtworkWidget: Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(color: cs.surfaceContainerHighest, shape: BoxShape.circle),
                  child: Icon(Icons.album_rounded, color: cs.onSurfaceVariant, size: 22),
                ),
              ),
            ),
            title: buildHighlightedText(
              text: album.title, query: _query,
              baseStyle: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.1) ?? const TextStyle(),
              highlightColor: cs.primary,
            ),
            subtitle: buildHighlightedText(
              text: album.artist, query: _query,
              baseStyle: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600) ?? const TextStyle(),
              highlightColor: cs.primary,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              _recordQueryAndSave(_query);
              HapticFeedback.selectionClick();
              _dismissSearchAndPop();
              appState.openAlbumPageFromSong(context, album.representativeSong);
            },
          ),
        );
      }
    }

    void buildGenericArtistTile(
      String sectionLabel, String categoryKey, List<AlbumArtistStat> hits, int? limit,
      IconData icon, String subtitlePrefix, void Function(String name) onOpen
    ) {
      final list = limit != null ? hits.take(limit).toList() : hits;
      if (list.isEmpty) return;
      if (_selectedFilter == SearchFilter.all) resultItems.add(header(sectionLabel, categoryKey: categoryKey));
      for (final stat in list) {
        resultItems.add(
          searchResultTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: FastArtworkWidget(
                id: stat.representativeSong?.id ?? 0,
                fallbackId: stat.representativeSong?.albumId,
                type: stat.representativeSong != null ? ArtworkType.AUDIO : ArtworkType.ALBUM,
                fallbackType: ArtworkType.ALBUM,
                width: 52,
                height: 52,
                nullArtworkWidget: Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                  child: Icon(icon, color: cs.onSurfaceVariant, size: 22),
                ),
              ),
            ),
            title: buildHighlightedText(
              text: stat.name, query: _query,
              baseStyle: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.1) ?? const TextStyle(),
              highlightColor: cs.primary,
            ),
            subtitle: Text(
              '$subtitlePrefix • ${stat.trackCount} ${stat.trackCount == 1 ? 'track' : 'tracks'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              _recordQueryAndSave(_query);
              HapticFeedback.selectionClick();
              _dismissSearchAndPop();
              onOpen(stat.name);
            },
          ),
        );
      }
    }

    void buildGenreTile(List<GenreStat> hits, int? limit) {
      final list = limit != null ? hits.take(limit).toList() : hits;
      if (list.isEmpty) return;
      if (_selectedFilter == SearchFilter.all) resultItems.add(header('Genres', categoryKey: 'genres'));
      for (final stat in list) {
        resultItems.add(
          searchResultTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: FastArtworkWidget(
                id: stat.representativeSong?.id ?? 0,
                fallbackId: stat.representativeSong?.albumId,
                type: stat.representativeSong != null ? ArtworkType.AUDIO : ArtworkType.ALBUM,
                fallbackType: ArtworkType.ALBUM,
                width: 52,
                height: 52,
                nullArtworkWidget: Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                  child: Icon(Icons.style_rounded, color: cs.onSurfaceVariant, size: 22),
                ),
              ),
            ),
            title: buildHighlightedText(
              text: stat.name, query: _query,
              baseStyle: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.1) ?? const TextStyle(),
              highlightColor: cs.primary,
            ),
            subtitle: Text(
              'Genre • ${stat.trackCount} ${stat.trackCount == 1 ? 'track' : 'tracks'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              _recordQueryAndSave(_query);
              HapticFeedback.selectionClick();
              _dismissSearchAndPop();
              appState.openGenrePage(context, stat);
            },
          ),
        );
      }
    }

    if (q.isNotEmpty) {
      switch (_selectedFilter) {
        case SearchFilter.all:
          if (_enabledCategories.contains('tracks')) addTracks(limit: 15);
          if (_enabledCategories.contains('albums')) addAlbums(limit: 6);
          if (_enabledCategories.contains('artists')) buildGenericArtistTile('Artists', 'artists', artistHits, 6, Icons.person_rounded, 'Artist', (name) => appState.openArtistPageByName(context, name));
          if (_enabledCategories.contains('albumArtists')) buildGenericArtistTile('Album Artists', 'albumArtists', albumArtistHits, 6, Icons.group_rounded, 'Album Artist', (name) => appState.openArtistPageByName(context, name));
          if (_enabledCategories.contains('composers')) buildGenericArtistTile('Composers', 'composers', composerHits, 6, Icons.draw_rounded, 'Composer', (name) => appState.openComposerPageByName(context, name));
          if (_enabledCategories.contains('genres')) buildGenreTile(genreHits, 6);
          break;
        case SearchFilter.tracks: 
          addTracks(); 
          break;
        case SearchFilter.albums: 
          addAlbums(); 
          break;
        case SearchFilter.artists: 
          buildGenericArtistTile('Artists', 'artists', artistHits, null, Icons.person_rounded, 'Artist', (name) => appState.openArtistPageByName(context, name)); 
          break;
        case SearchFilter.albumArtists: 
          buildGenericArtistTile('Album Artists', 'albumArtists', albumArtistHits, null, Icons.group_rounded, 'Album Artist', (name) => appState.openArtistPageByName(context, name)); 
          break;
        case SearchFilter.composers: 
          buildGenericArtistTile('Composers', 'composers', composerHits, null, Icons.draw_rounded, 'Composer', (name) => appState.openComposerPageByName(context, name)); 
          break;
        case SearchFilter.genres: 
          buildGenreTile(genreHits, null); 
          break;
      }
    }

    final hasAnyResults = resultItems.isNotEmpty;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        _unfocusAndHideKeyboard();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _handlePointerDown,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: KeyedSubtree(
                    key: _searchBarKey,
                    child: SearchBar(
                      controller: _controller,
                      focusNode: _focusNode,
                      autoFocus: true,
                      onTapOutside: (_) => _unfocusAndHideKeyboard(),
                      hintText: _getHintText(),
                      leading: IconButton(
                        icon: const Icon(Icons.arrow_back_rounded),
                        tooltip: 'Back',
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          _dismissSearchAndPop();
                        },
                      ),
                      trailing: [
                        if (_controller.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            tooltip: 'Clear',
                            onPressed: () {
                              _controller.clear();
                              setState(() => _query = '');
                            },
                          ),
                      ],
                      onChanged: (val) {
                        setState(() => _query = val.trim());
                      },
                      onSubmitted: (val) {
                        _recordQueryAndSave(val);
                        _unfocusAndHideKeyboard();
                      },
                    ),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          selected: _selectedFilter == SearchFilter.all,
                          label: const Text('All'),
                          onSelected: (_) {
                            HapticFeedback.selectionClick();
                            setState(() => _selectedFilter = SearchFilter.all);
                          },
                        ),
                      ),
                      _buildFilterChip(filter: SearchFilter.tracks, label: 'Tracks', count: trackHits.length, categoryKey: 'tracks'),
                      _buildFilterChip(filter: SearchFilter.albums, label: 'Albums', count: albumHits.length, categoryKey: 'albums'),
                      _buildFilterChip(filter: SearchFilter.artists, label: 'Artists', count: artistHits.length, categoryKey: 'artists'),
                      _buildFilterChip(filter: SearchFilter.albumArtists, label: 'Album Artists', count: albumArtistHits.length, categoryKey: 'albumArtists'),
                      _buildFilterChip(filter: SearchFilter.composers, label: 'Composers', count: composerHits.length, categoryKey: 'composers'),
                      _buildFilterChip(filter: SearchFilter.genres, label: 'Genres', count: genreHits.length, categoryKey: 'genres'),
                      IconButton(
                        icon: const Icon(Icons.tune_rounded, size: 20),
                        tooltip: 'Customize categories',
                        onPressed: _showCategoryFilterSheet,
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.28)),
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification is ScrollStartNotification) _unfocusAndHideKeyboard();
                      return false;
                    },
                    child: q.isEmpty
                        ? _buildRecentSearchesView(cs)
                        : !hasAnyResults
                            ? AppEmptyState(
                                icon: Icons.search_off_rounded,
                                title: 'No results found',
                                message: 'We couldn’t find any matches for "$_query". Check for typos or adjust filters.',
                              )
                            : ListView(
                                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                children: resultItems,
                              ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentSearchesView(ColorScheme cs) {
    if (_recentSearches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_rounded, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
              const SizedBox(height: 12),
              Text(
                'Search for tracks, albums, artists, or genres',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 4),
          child: Row(
            children: [
              Text('Recent Searches', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, letterSpacing: 0.1)),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  HapticFeedback.selectionClick();
                  await SearchHistoryManager.clearHistory();
                  _loadRecentSearches();
                },
                child: const Text('Clear all'),
              ),
            ],
          ),
        ),
        for (final item in _recentSearches)
          ListTile(
            leading: Icon(Icons.history_rounded, color: cs.onSurfaceVariant),
            title: Text(item, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            trailing: IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              tooltip: 'Remove',
              onPressed: () async {
                HapticFeedback.selectionClick();
                await SearchHistoryManager.removeQuery(item);
                _loadRecentSearches();
              },
            ),
            onTap: () {
              HapticFeedback.selectionClick();
              _controller.text = item;
              _controller.selection = TextSelection.fromPosition(TextPosition(offset: item.length));
              setState(() => _query = item);
              _unfocusAndHideKeyboard();
            },
          ),
      ],
    );
  }
}
