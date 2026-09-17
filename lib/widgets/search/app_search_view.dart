import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/app_state_controller.dart';
import '../../services/playback_controller.dart';
import '../../ui/shared/app_empty_state.dart';
import '../../ui/shared/fast_artwork_widget.dart';
import '../../utils/format_utils.dart';

/// Available search filter scopes.
enum SearchFilter {
  all,
  tracks,
  albums,
  artists,
}

/// Helper managing persistent recent searches in SharedPreferences.
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

/// Helper function to highlight matched substrings in text using primary theme color.
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
    return Text(
      text,
      style: baseStyle,
      maxLines: maxLines,
      overflow: overflow,
    );
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
        style: TextStyle(
          color: highlightColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    start = matchEnd;
  }

  return Text.rich(
    TextSpan(style: baseStyle, children: spans),
    maxLines: maxLines,
    overflow: overflow,
  );
}

/// Full-featured Material 3 Expressive Search Page.
class AppSearchView extends StatefulWidget {
  final SearchFilter initialFilter;
  final String? initialQuery;

  const AppSearchView({
    super.key,
    this.initialFilter = SearchFilter.all,
    this.initialQuery,
  });

  /// Opens the search view in-place from any context.
  static Future<void> show(
    BuildContext context, {
    SearchFilter initialFilter = SearchFilter.all,
    String? initialQuery,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AppSearchView(
          initialFilter: initialFilter,
          initialQuery: initialQuery,
        ),
      ),
    );
  }

  @override
  State<AppSearchView> createState() => _AppSearchViewState();
}

class _AppSearchViewState extends State<AppSearchView> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  late SearchFilter _selectedFilter;
  String _query = '';
  List<String> _recentSearches = [];

  @override
  void initState() {
    super.initState();
    _selectedFilter = widget.initialFilter;
    _query = (widget.initialQuery ?? '').trim();
    _controller = TextEditingController(text: widget.initialQuery ?? '');
    _loadRecentSearches();
  }

  Future<void> _loadRecentSearches() async {
    final history = await SearchHistoryManager.getHistory();
    if (mounted) {
      setState(() => _recentSearches = history);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _dismissSearchAndPop() {
    _focusNode.unfocus();
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop();
  }

  void _recordQueryAndSave(String q) {
    if (q.trim().isNotEmpty) {
      SearchHistoryManager.addQuery(q.trim());
      _loadRecentSearches();
    }
  }

  String _getHintText() {
    switch (_selectedFilter) {
      case SearchFilter.all:
        return 'Search tracks, albums, artists...';
      case SearchFilter.tracks:
        return 'Search tracks...';
      case SearchFilter.albums:
        return 'Search albums...';
      case SearchFilter.artists:
        return 'Search artists...';
    }
  }

  Widget _buildFilterChip({
    required SearchFilter filter,
    required String label,
    int? count,
  }) {
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
                  color: isSelected
                      ? cs.primary.withValues(alpha: 0.18)
                      : cs.surfaceContainerHighest,
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

    // 1. Artist hits (unique by artist name)
    final Map<String, SongModel> firstSongByArtist = {};
    for (final s in songs) {
      final name = (s.artist ?? '').trim();
      if (name.isEmpty) continue;
      firstSongByArtist.putIfAbsent(name.toLowerCase(), () => s);
    }

    final List<SongModel> artistHits = q.isEmpty
        ? []
        : () {
            final exactMatches = <SongModel>[];
            final startMatches = <SongModel>[];
            final containMatches = <SongModel>[];
            for (final s in firstSongByArtist.values) {
              if (exact(s.artist)) {
                exactMatches.add(s);
              } else if (starts(s.artist)) {
                startMatches.add(s);
              } else if (contains(s.artist)) {
                containMatches.add(s);
              }
            }
            return [
              ...exactMatches,
              ...startMatches,
              ...containMatches,
            ];
          }();

    // 2. Album hits (unique by albumId)
    final Map<int, SongModel> firstSongByAlbumId = {};
    for (final s in songs) {
      final albumId = s.albumId;
      if (albumId == null || albumId <= 0) continue;
      firstSongByAlbumId.putIfAbsent(albumId, () => s);
    }

    final List<SongModel> albumHits = q.isEmpty
        ? []
        : () {
            final exactMatches = <SongModel>[];
            final startMatches = <SongModel>[];
            final containMatches = <SongModel>[];
            for (final s in firstSongByAlbumId.values) {
              if (exact(s.album)) {
                exactMatches.add(s);
              } else if (starts(s.album)) {
                startMatches.add(s);
              } else if (contains(s.album)) {
                containMatches.add(s);
              }
            }
            return [
              ...exactMatches,
              ...startMatches,
              ...containMatches,
            ];
          }();

    // 3. Track hits (no arbitrary cap when filtered to tracks)
    final List<SongModel> trackHits = q.isEmpty
        ? []
        : () {
            final exactMatches = <SongModel>[];
            final startMatches = <SongModel>[];
            final containMatches = <SongModel>[];
            for (final s in songs) {
              if (exact(s.title)) {
                exactMatches.add(s);
              } else if (starts(s.title)) {
                startMatches.add(s);
              } else if (contains(s.title)) {
                containMatches.add(s);
              }
            }
            return [
              ...exactMatches,
              ...startMatches,
              ...containMatches,
            ];
          }();

    Widget header(String text) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
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
              side: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.35),
              ),
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

    // Build the results list based on filter
    final resultItems = <Widget>[];

    void addTracks({int? limit}) {
      final list = limit != null ? trackHits.take(limit).toList() : trackHits;
      if (list.isEmpty) return;
      if (_selectedFilter == SearchFilter.all) {
        resultItems.add(header('Tracks'));
      }
      for (final song in list) {
        final idx = songs.indexWhere((s) => s.id == song.id);
        final artist = (song.artist ?? '').trim().isEmpty
            ? 'Unknown Artist'
            : song.artist!.trim();
        final album = (song.album ?? '').trim().isEmpty
            ? 'Unknown Album'
            : song.album!.trim();
        final duration = song.duration == null ? null : formatTime(song.duration);
        final subtitleText =
            duration == null ? '$artist • $album' : '$artist • $album • $duration';

        resultItems.add(
          searchResultTile(
            leading: ClipOval(
              child: FastArtworkWidget(
                id: song.id,
                type: ArtworkType.AUDIO,
                width: 52,
                height: 52,
                nullArtworkWidget: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.music_note_rounded,
                    color: cs.onSurfaceVariant,
                    size: 22,
                  ),
                ),
              ),
            ),
            title: buildHighlightedText(
              text: song.title,
              query: _query,
              baseStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                  ) ??
                  const TextStyle(),
              highlightColor: cs.primary,
            ),
            subtitle: buildHighlightedText(
              text: subtitleText,
              query: _query,
              baseStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ) ??
                  const TextStyle(),
              highlightColor: cs.primary,
            ),
            trailing: IconButton.filledTonal(
              icon: const Icon(Icons.play_arrow_rounded),
              tooltip: 'Play',
              onPressed: () {
                _recordQueryAndSave(_query);
                HapticFeedback.selectionClick();
                _dismissSearchAndPop();
                if (idx != -1) {
                  playbackController.playFromQueue(songs, initialIndex: idx);
                }
              },
            ),
            onTap: () {
              _recordQueryAndSave(_query);
              HapticFeedback.selectionClick();
              _dismissSearchAndPop();
              if (idx != -1) {
                playbackController.playFromQueue(songs, initialIndex: idx);
              }
            },
          ),
        );
      }
    }

    void addAlbums({int? limit}) {
      final list = limit != null ? albumHits.take(limit).toList() : albumHits;
      if (list.isEmpty) return;
      if (_selectedFilter == SearchFilter.all) {
        resultItems.add(header('Albums'));
      }
      for (final song in list) {
        final albumId = song.albumId ?? 0;
        final albumTitle = song.album ?? 'Unknown Album';
        final artist = song.artist ?? 'Unknown Artist';

        resultItems.add(
          searchResultTile(
            leading: ClipOval(
              child: FastArtworkWidget(
                id: song.id,
                fallbackId: albumId,
                type: ArtworkType.AUDIO,
                fallbackType: ArtworkType.ALBUM,
                width: 52,
                height: 52,
                nullArtworkWidget: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.album_rounded,
                    color: cs.onSurfaceVariant,
                    size: 22,
                  ),
                ),
              ),
            ),
            title: buildHighlightedText(
              text: albumTitle,
              query: _query,
              baseStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                  ) ??
                  const TextStyle(),
              highlightColor: cs.primary,
            ),
            subtitle: buildHighlightedText(
              text: artist,
              query: _query,
              baseStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ) ??
                  const TextStyle(),
              highlightColor: cs.primary,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              _recordQueryAndSave(_query);
              HapticFeedback.selectionClick();
              _dismissSearchAndPop();
              appState.openAlbumPageFromSong(context, song);
            },
          ),
        );
      }
    }

    void addArtists({int? limit}) {
      final list = limit != null ? artistHits.take(limit).toList() : artistHits;
      if (list.isEmpty) return;
      if (_selectedFilter == SearchFilter.all) {
        resultItems.add(header('Artists'));
      }
      for (final song in list) {
        final name = (song.artist ?? '').trim();
        if (name.isEmpty) continue;

        resultItems.add(
          searchResultTile(
            leading: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.person_rounded,
                color: cs.onSurfaceVariant,
                size: 22,
              ),
            ),
            title: buildHighlightedText(
              text: name,
              query: _query,
              baseStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                  ) ??
                  const TextStyle(),
              highlightColor: cs.primary,
            ),
            subtitle: Text(
              'Artist',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              _recordQueryAndSave(_query);
              HapticFeedback.selectionClick();
              _dismissSearchAndPop();
              appState.openArtistPageByName(context, name);
            },
          ),
        );
      }
    }

    if (q.isNotEmpty) {
      switch (_selectedFilter) {
        case SearchFilter.all:
          addTracks(limit: 15);
          addAlbums(limit: 6);
          addArtists(limit: 6);
          break;
        case SearchFilter.tracks:
          addTracks(); // No cap: browse all tracks
          break;
        case SearchFilter.albums:
          addAlbums();
          break;
        case SearchFilter.artists:
          addArtists();
          break;
      }
    }

    final hasAnyResults = trackHits.isNotEmpty || albumHits.isNotEmpty || artistHits.isNotEmpty;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        _focusNode.unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            _focusNode.unfocus();
            FocusScope.of(context).unfocus();
          },
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: SearchBar(
                    controller: _controller,
                    focusNode: _focusNode,
                    autoFocus: true,
                    onTapOutside: (_) {
                      _focusNode.unfocus();
                      FocusScope.of(context).unfocus();
                    },
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
                      _focusNode.unfocus();
                      FocusScope.of(context).unfocus();
                    },
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      _buildFilterChip(
                        filter: SearchFilter.all,
                        label: 'All',
                      ),
                      _buildFilterChip(
                        filter: SearchFilter.tracks,
                        label: 'Tracks',
                        count: trackHits.length,
                      ),
                      _buildFilterChip(
                        filter: SearchFilter.albums,
                        label: 'Albums',
                        count: albumHits.length,
                      ),
                      _buildFilterChip(
                        filter: SearchFilter.artists,
                        label: 'Artists',
                        count: artistHits.length,
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: cs.outlineVariant.withValues(alpha: 0.28),
                ),
                Expanded(
                  child: q.isEmpty
                      ? _buildRecentSearchesView(cs)
                      : !hasAnyResults
                          ? AppEmptyState(
                              icon: Icons.search_off_rounded,
                              title: 'No results found',
                              message:
                                  'We couldn’t find any matches for "$_query". Check for typos or try searching by artist.',
                            )
                          : ListView(
                              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              children: resultItems,
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
              Icon(
                Icons.search_rounded,
                size: 48,
                color: cs.onSurfaceVariant.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 12),
              Text(
                'Search for tracks, albums, or artists',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
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
              Text(
                'Recent Searches',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1,
                    ),
              ),
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
            leading: Icon(
              Icons.history_rounded,
              color: cs.onSurfaceVariant,
            ),
            title: Text(
              item,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
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
              _controller.selection = TextSelection.fromPosition(
                TextPosition(offset: item.length),
              );
              setState(() => _query = item);
              _focusNode.unfocus();
              FocusScope.of(context).unfocus();
            },
          ),
      ],
    );
  }
}
