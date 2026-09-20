import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../services/app_state_controller.dart';
import '../../data/models/album_stat.dart';
import '../../ui/shared/bottom_bars_gutter.dart';
import '../../ui/shared/fast_artwork_widget.dart';
import '../../ui/shared/app_action_sheet.dart';
import '../../ui/shared/alphabetical_bubble_scroller.dart';
import '../../ui/shared/app_empty_state.dart';
import '../../utils/song_sort_utils.dart';
import '../../widgets/search/app_search_view.dart';
import '../../ui/shared/app_sort_bottom_sheet.dart';

class AlbumArtistsTab extends StatefulWidget {
  const AlbumArtistsTab({super.key});

  @override
  State<AlbumArtistsTab> createState() => _AlbumArtistsTabState();
}

class _AlbumArtistsTabState extends State<AlbumArtistsTab> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateController.instance;
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final albumArtistsSort = appState.albumArtistsSort;
        final viewMode = appState.artistsViewMode;

        final List<AlbumArtistStat> artists;
        switch (viewMode) {
          case ArtistsViewMode.albumArtists:
            artists = appState.cachedAlbumArtists;
            break;
          case ArtistsViewMode.artists:
            artists = appState.cachedTrackArtists;
            break;
          case ArtistsViewMode.composers:
            artists = appState.cachedComposers;
            break;
        }

        String sortLabel(AlbumArtistsSort s) {
          switch (s) {
            case AlbumArtistsSort.nameAsc:
              return 'Name (A → Z)';
            case AlbumArtistsSort.nameDesc:
              return 'Name (Z → A)';
            case AlbumArtistsSort.mostAlbums:
              return 'Most Albums';
            case AlbumArtistsSort.leastAlbums:
              return 'Least Albums';
            case AlbumArtistsSort.mostTracks:
              return 'Most Tracks';
            case AlbumArtistsSort.leastTracks:
              return 'Least Tracks';
          }
        }

        final cs = Theme.of(context).colorScheme;

        final isNumeric = albumArtistsSort == AlbumArtistsSort.mostAlbums ||
            albumArtistsSort == AlbumArtistsSort.leastAlbums ||
            albumArtistsSort == AlbumArtistsSort.mostTracks ||
            albumArtistsSort == AlbumArtistsSort.leastTracks;

        return AlphabeticalBubbleScroller(
          scrollController: _scrollController,
          itemCount: artists.length,
          headerHeight: 200.0,
          itemHeight: 80.0,
          sortKey: albumArtistsSort,
          isNumericSort: isNumeric,
          sectionKeyOf: (index) {
            final a = artists[index];
            switch (albumArtistsSort) {
              case AlbumArtistsSort.nameAsc:
              case AlbumArtistsSort.nameDesc:
                return a.name;
              case AlbumArtistsSort.mostAlbums:
              case AlbumArtistsSort.leastAlbums:
                return '${a.albumCount}';
              case AlbumArtistsSort.mostTracks:
              case AlbumArtistsSort.leastTracks:
                return '${a.trackCount}';
            }
          },
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar.large(
                title: Text(viewMode.label),
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
                      final filter = switch (viewMode) {
                        ArtistsViewMode.albumArtists => SearchFilter.albumArtists,
                        ArtistsViewMode.artists => SearchFilter.artists,
                        ArtistsViewMode.composers => SearchFilter.composers,
                      };
                      appState.openSearch(initialFilter: filter);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.sort_rounded),
                    tooltip: 'Sort ${viewMode.label.toLowerCase()}',
                    onPressed: () {
                      showAlbumArtistsSortBottomSheet(
                        context,
                        currentSort: albumArtistsSort,
                        onSortSelected: (mode) {
                          appState.applyAlbumArtistsSort(mode);
                        },
                      );
                    },
                  ),
                  const SizedBox(width: 4),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: SegmentedButton<ArtistsViewMode>(
                    segments: const [
                      ButtonSegment(
                        value: ArtistsViewMode.albumArtists,
                        label: Text('Album Artists'),
                      ),
                      ButtonSegment(
                        value: ArtistsViewMode.artists,
                        label: Text('Artists'),
                      ),
                      ButtonSegment(
                        value: ArtistsViewMode.composers,
                        label: Text('Composers'),
                      ),
                    ],
                    selected: {viewMode},
                    onSelectionChanged: (newSelection) {
                      if (newSelection.isNotEmpty) {
                        appState.setArtistsViewMode(newSelection.first);
                      }
                    },
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                  child: Text(
                    '${artists.length} ${viewMode.label.toLowerCase()} • Sort: ${sortLabel(albumArtistsSort)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              if (artists.isEmpty)
                AppEmptyState.sliver(
                  icon: Icons.person_off_rounded,
                  title: 'No ${viewMode.label.toLowerCase()} found',
                  message: 'Your library does not contain any ${viewMode.label.toLowerCase()} yet.',
                )

            else
              SliverFixedExtentList(
                itemExtent: 80.0,
                delegate: SliverChildBuilderDelegate((context, i) {
                  final stat = artists[i];
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
                            if (viewMode == ArtistsViewMode.composers) {
                              appState.openComposerPageByName(context, stat.name);
                            } else {
                              appState.openArtistPageByName(context, stat.name);
                            }
                          },
                          onLongPress: () {
                            HapticFeedback.mediumImpact();
                            _showArtistOptionsModal(context, appState, stat, viewMode);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: FastArtworkWidget(
                                    id: stat.representativeSong?.id ??
                                        stat.representativeSong?.albumId ??
                                        0,
                                    type: stat.representativeSong != null
                                        ? ArtworkType.AUDIO
                                        : ArtworkType.ALBUM,
                                    fallbackId: stat.representativeSong?.albumId,
                                    fallbackType: ArtworkType.ALBUM,
                                    width: 48,
                                    height: 48,
                                    size: 400,
                                    quality: 100,
                                    nullArtworkWidget: Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: cs.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(
                                        Icons.person_rounded,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        stat.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -0.1,
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        subtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: cs.onSurfaceVariant,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: cs.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }, childCount: artists.length),
              ),
            buildBottomBarsGutter(context),
          ],
        ),
      );
    },
  );
  }

  void _showArtistOptionsModal(
    BuildContext context,
    AppStateController appState,
    AlbumArtistStat stat,
    ArtistsViewMode viewMode,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isComposer = viewMode == ArtistsViewMode.composers;
    final repId = stat.representativeSong?.albumId ??
        stat.representativeSong?.id ??
        0;

    List<SongModel> getArtistSongs() {
      final target = stat.name.toLowerCase().trim();
      return appState.songs.where((s) {
        if (isComposer) {
          final c = (s.composer ?? (s.getMap['composer'] as String?))?.toLowerCase().trim();
          return c == target;
        }
        final a = (s.artist ?? '').toLowerCase().trim();
        final aa = albumArtistFor(s).toLowerCase().trim();
        return a == target || aa == target;
      }).toList();
    }

    final song = stat.representativeSong;
    final headerThumbnail = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: FastArtworkWidget(
        id: song?.id ?? repId,
        type: song != null ? ArtworkType.AUDIO : ArtworkType.ALBUM,
        fallbackId: repId,
        fallbackType: ArtworkType.ALBUM,
        width: 48,
        height: 48,
        size: 400,
        quality: 100,
        nullArtworkWidget: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            isComposer ? Icons.music_note_rounded : Icons.person_rounded,
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );

    showAppActionSheet<void>(
      context: context,
      headerThumbnail: headerThumbnail,
      headerTitle: stat.name,
      headerSubtitle: '${stat.albumCount} albums • ${stat.trackCount} tracks',
      items: [
        AppActionItem(
          icon: isComposer ? Icons.music_note_rounded : Icons.person_rounded,
          title: isComposer ? 'Open Composer' : 'Open Artist',
          subtitle: isComposer
              ? 'View albums and tracks by this composer'
              : 'View albums and tracks by this artist',
          onTap: () {
            if (isComposer) {
              appState.openComposerPageByName(context, stat.name);
            } else {
              appState.openArtistPageByName(context, stat.name);
            }
          },
        ),
        AppActionItem(
          icon: Icons.play_arrow_rounded,
          title: 'Play All',
          subtitle: 'Play all songs from the beginning',
          onTap: () async {
            final artistSongs = getArtistSongs();
            if (artistSongs.isNotEmpty) {
              await appState.playFromQueue(context, artistSongs, initialIndex: 0);
            }
          },
        ),
        AppActionItem(
          icon: Icons.playlist_add_rounded,
          title: 'Play next',
          subtitle: 'Insert songs after current track',
          onTap: () async {
            final artistSongs = getArtistSongs();
            if (artistSongs.isNotEmpty) {
              await appState.insertAllInQueue(context, artistSongs);
            }
          },
        ),
        AppActionItem(
          icon: Icons.queue_music_rounded,
          title: 'Add to queue',
          subtitle: 'Append songs to queue end',
          onTap: () async {
            final artistSongs = getArtistSongs();
            if (artistSongs.isNotEmpty) {
              await appState.addAllToQueueEnd(context, artistSongs);
            }
          },
        ),
        AppActionItem(
          icon: Icons.shuffle_rounded,
          title: 'Shuffle All',
          subtitle: 'Shuffle and play all songs',
          onTap: () async {
            final artistSongs = getArtistSongs();
            if (artistSongs.isNotEmpty) {
              artistSongs.shuffle();
              await appState.playFromQueue(context, artistSongs, initialIndex: 0);
            }
          },
        ),
      ],
    );
  }
}
