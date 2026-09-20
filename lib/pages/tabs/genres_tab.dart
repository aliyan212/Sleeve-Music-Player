import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../data/models/genre_stat.dart';
import '../../services/app_state_controller.dart';
import '../../services/playback_controller.dart';
import '../../ui/shared/alphabetical_bubble_scroller.dart';
import '../../ui/shared/app_action_sheet.dart';
import '../../ui/shared/app_empty_state.dart';
import '../../ui/shared/app_sort_bottom_sheet.dart';
import '../../ui/shared/bottom_bars_gutter.dart';
import '../../utils/format_utils.dart';
import '../../widgets/genre_collage_artwork.dart';
import '../../widgets/search/app_search_view.dart';

class GenresTab extends StatefulWidget {
  const GenresTab({super.key});

  @override
  State<GenresTab> createState() => _GenresTabState();
}

class _GenresTabState extends State<GenresTab> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _showGenreOptionsModal(
    BuildContext context,
    AppStateController appState,
    GenreStat stat,
  ) {

    List<SongModel> songsForGenre() {
      final target = stat.name.toLowerCase();
      return appState.songs.where((s) {
        final raw = s.genre?.trim();
        if (raw == null || raw.isEmpty) {
          return target == 'unknown genre';
        }
        final parts = raw
            .split(RegExp(r'[/;]'))
            .map((e) => e.trim().toLowerCase())
            .where((e) => e.isNotEmpty);
        return parts.contains(target);
      }).toList(growable: false);
    }

    final headerThumbnail = GenreCollageArtwork(
      genre: stat,
      size: 48,
      borderRadius: 10,
    );

    final headerSubtitle =
        '${stat.albumCount} albums • ${stat.trackCount} tracks • ${formatPlaylistDuration(stat.totalDurationMs)}';

    showAppActionSheet<void>(
      context: context,
      headerThumbnail: headerThumbnail,
      headerTitle: stat.name,
      headerSubtitle: headerSubtitle,
      items: [
        AppActionItem(
          icon: Icons.category_rounded,
          title: 'Open Genre',
          subtitle: 'View all songs and albums in this genre',
          onTap: () => appState.openGenrePage(context, stat),
        ),
        AppActionItem(
          icon: Icons.play_arrow_rounded,
          title: 'Play Genre',
          subtitle: 'Start playback of all songs in this genre',
          onTap: () async {
            final songs = songsForGenre();
            if (songs.isNotEmpty) {
              await playbackController.playFromQueue(songs, initialIndex: 0);
            }
          },
        ),
        AppActionItem(
          icon: Icons.playlist_add_rounded,
          title: 'Play next',
          subtitle: 'Insert genre tracks after current song',
          onTap: () async {
            final songs = songsForGenre();
            if (songs.isNotEmpty) {
              await playbackController.insertAllInQueue(songs);
            }
          },
        ),
        AppActionItem(
          icon: Icons.queue_music_rounded,
          title: 'Add to queue',
          subtitle: 'Append genre tracks to queue end',
          onTap: () async {
            final songs = songsForGenre();
            if (songs.isNotEmpty) {
              await playbackController.addAllToQueueEnd(songs);
            }
          },
        ),
        AppActionItem(
          icon: Icons.shuffle_rounded,
          title: 'Shuffle Genre',
          subtitle: 'Shuffle and play tracks in this genre',
          onTap: () async {
            final songs = songsForGenre();
            if (songs.isNotEmpty) {
              final shuffled = List<SongModel>.from(songs)..shuffle();
              await playbackController.playFromQueue(shuffled, initialIndex: 0);
            }
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateController.instance;
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final genres = appState.cachedGenres;
        final genreSort = appState.genreSort;

        String sortLabel(GenreSort s) {
          switch (s) {
            case GenreSort.nameAsc:
              return 'Name (A → Z)';
            case GenreSort.nameDesc:
              return 'Name (Z → A)';
            case GenreSort.mostTracks:
              return 'Most Tracks';
            case GenreSort.leastTracks:
              return 'Least Tracks';
            case GenreSort.mostAlbums:
              return 'Most Albums';
            case GenreSort.leastAlbums:
              return 'Least Albums';
          }
        }

        final cs = Theme.of(context).colorScheme;

        final isNumeric = genreSort == GenreSort.mostTracks ||
            genreSort == GenreSort.leastTracks ||
            genreSort == GenreSort.mostAlbums ||
            genreSort == GenreSort.leastAlbums;

        return AlphabeticalBubbleScroller(
          scrollController: _scrollController,
          itemCount: genres.length,
          headerHeight: 142.0,
          itemHeight: 80.0,
          sortKey: genreSort,
          isNumericSort: isNumeric,
          sectionKeyOf: (index) {
            final g = genres[index];
            switch (genreSort) {
              case GenreSort.nameAsc:
              case GenreSort.nameDesc:
                return g.name;
              case GenreSort.mostTracks:
              case GenreSort.leastTracks:
                return '${g.trackCount}';
              case GenreSort.mostAlbums:
              case GenreSort.leastAlbums:
                return '${g.albumCount}';
            }
          },
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar.large(
                title: const Text('Genres'),
                expandedHeight: 164,
                backgroundColor: cs.surface.withValues(alpha: 0.90),
                surfaceTintColor: Colors.transparent,
                foregroundColor: cs.onSurface,
                titleTextStyle: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.search_rounded),
                    tooltip: 'Search',
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      appState.openSearch(initialFilter: SearchFilter.genres);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.sort_rounded),
                    tooltip: 'Sort genres',
                    onPressed: () {
                      showGenresSortBottomSheet(
                        context,
                        currentSort: genreSort,
                        onSortSelected: (mode) {
                          appState.applyGenreSort(mode);
                        },
                      );
                    },
                  ),
                  const SizedBox(width: 4),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: Text(
                    '${genres.length} genres • Sort: ${sortLabel(genreSort)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              if (genres.isEmpty)
                AppEmptyState.sliver(
                  icon: Icons.category_outlined,
                  title: 'No genres found',
                  message: 'Your library does not contain any genres yet.',
                )
              else
                SliverFixedExtentList(
                  itemExtent: 80.0,
                  delegate: SliverChildBuilderDelegate((context, i) {
                    final stat = genres[i];
                    final subtitle =
                        '${stat.albumCount} albums • ${stat.trackCount} tracks';

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
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
                            onTap: () {
                              HapticFeedback.selectionClick();
                              appState.openGenrePage(context, stat);
                            },
                            onLongPress: () {
                              HapticFeedback.mediumImpact();
                              _showGenreOptionsModal(context, appState, stat);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  GenreCollageArtwork(
                                    genre: stat,
                                    size: 52,
                                    borderRadius: 14,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          stat.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                            letterSpacing: -0.2,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          subtitle,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: cs.onSurfaceVariant,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.more_vert_rounded),
                                    iconSize: 20,
                                    color: cs.onSurfaceVariant,
                                    tooltip: 'Options',
                                    onPressed: () {
                                      HapticFeedback.selectionClick();
                                      _showGenreOptionsModal(
                                        context,
                                        appState,
                                        stat,
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }, childCount: genres.length),
                ),
              buildBottomBarsGutter(context),
            ],
          ),
        );
      },
    );
  }
}
