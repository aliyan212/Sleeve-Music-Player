import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/app_state_controller.dart';
import '../../data/models/album_stat.dart';
import '../../dialogs/batch_tag_editor_dialog.dart';
import '../../ui/shared/fast_artwork_widget.dart';
import '../../ui/shared/app_action_sheet.dart';
import '../../ui/shared/bottom_bars_gutter.dart';
import '../../ui/shared/alphabetical_bubble_scroller.dart';
import '../../ui/shared/app_empty_state.dart';
import '../../utils/song_sort_utils.dart';
import '../../widgets/search/app_search_view.dart';
import '../../ui/shared/app_sort_bottom_sheet.dart';
import 'package:on_audio_query/on_audio_query.dart';

class AlbumsTab extends StatefulWidget {
  const AlbumsTab({super.key});

  @override
  State<AlbumsTab> createState() => _AlbumsTabState();
}

class _AlbumsTabState extends State<AlbumsTab> {
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
        final albums = appState.cachedAlbums;
        final albumsSort = appState.albumsSort;

    String sortLabel(AlbumsSort s) {
      switch (s) {
        case AlbumsSort.titleAsc:
          return 'Title (A → Z)';
        case AlbumsSort.titleDesc:
          return 'Title (Z → A)';
        case AlbumsSort.artistAsc:
          return 'Artist (A → Z)';
        case AlbumsSort.artistDesc:
          return 'Artist (Z → A)';
        case AlbumsSort.yearAsc:
          return 'Year (Oldest First)';
        case AlbumsSort.yearDesc:
          return 'Year (Newest First)';
        case AlbumsSort.albumArtistYear:
          return 'Album Artist / Year';
        case AlbumsSort.mostTracks:
          return 'Most Tracks';
        case AlbumsSort.leastTracks:
          return 'Least Tracks';
      }
    }

    final cs = Theme.of(context).colorScheme;

    final isNumeric = albumsSort == AlbumsSort.yearAsc ||
        albumsSort == AlbumsSort.yearDesc ||
        albumsSort == AlbumsSort.mostTracks ||
        albumsSort == AlbumsSort.leastTracks;

    return AlphabeticalBubbleScroller(
      scrollController: _scrollController,
      itemCount: albums.length,
      headerHeight: 144.0,
      itemHeight: 86.0,
      sortKey: albumsSort,
      isNumericSort: isNumeric,
      sectionKeyOf: (index) {
        final a = albums[index];
        switch (albumsSort) {
          case AlbumsSort.titleAsc:
          case AlbumsSort.titleDesc:
            return a.title;
          case AlbumsSort.artistAsc:
          case AlbumsSort.artistDesc:
          case AlbumsSort.albumArtistYear:
            return a.artist;
          case AlbumsSort.yearAsc:
          case AlbumsSort.yearDesc:
            return a.year > 0 ? '${a.year}' : '#';
          case AlbumsSort.mostTracks:
          case AlbumsSort.leastTracks:
            return '${a.trackCount}';
        }
      },
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
            SliverAppBar.large(
              title: const Text('Albums'),
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
                    appState.openSearch(initialFilter: SearchFilter.albums);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.sort_rounded),
                  tooltip: 'Sort albums',
                  onPressed: () {
                    showAlbumsSortBottomSheet(
                      context,
                      currentSort: albumsSort,
                      onSortSelected: (mode) {
                        appState.applyAlbumsSort(mode);
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
                  '${albums.length} albums • Sort: ${sortLabel(albumsSort)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (albums.isEmpty)
              AppEmptyState.sliver(
                icon: Icons.album_rounded,
                title: 'No albums found',
                message: 'Your library does not contain any albums yet.',
              )
            else
              SliverFixedExtentList(
                itemExtent: 86.0,
                delegate: SliverChildBuilderDelegate((context, i) {
                  final album = albums[i];
                  final albumId = album.albumId;
                  final song = album.representativeSong;
                  final title = album.title;
                  final artist = album.artist;
                  final tracks = album.trackCount;
                  final year = album.year;

                  final subtitle = year > 0
                      ? '$artist • $tracks tracks • $year'
                      : '$artist • $tracks tracks';

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
                            appState.openAlbumPageFromSong(context, song);
                          },
                          onLongPress: () {
                            HapticFeedback.mediumImpact();
                            _showAlbumOptionsModal(
                              context,
                              appState,
                              song,
                              title,
                              subtitle,
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: FastArtworkWidget(
                                    id: song.id,
                                    type: ArtworkType.AUDIO,
                                    fallbackId: albumId,
                                    fallbackType: ArtworkType.ALBUM,
                                    width: 54,
                                    height: 54,
                                    size: 500,
                                    quality: 100,
                                    nullArtworkWidget: Container(
                                      width: 54,
                                      height: 54,
                                      decoration: BoxDecoration(
                                        color: cs.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        Icons.album_rounded,
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
                                        title,
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
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }, childCount: albums.length),
              ),
            buildBottomBarsGutter(context),
          ],
        ),
      );
    },
  );
  }

  void _showAlbumOptionsModal(
    BuildContext context,
    AppStateController appState,
    SongModel song,
    String title,
    String subtitle,
  ) {
    final cs = Theme.of(context).colorScheme;
    final albumId = song.albumId ?? song.id;

    List<SongModel> getAlbumSongs() {
      final targetKey = albumIdentityKey(song);
      final list = appState.songs
          .where((s) => albumIdentityKey(s) == targetKey)
          .toList();
      list.sort(compareDiscAndTrack);
      return list;
    }

    final headerThumbnail = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: FastArtworkWidget(
        id: song.id,
        type: ArtworkType.AUDIO,
        fallbackId: albumId,
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
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.album_rounded,
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );

    showAppActionSheet<void>(
      context: context,
      headerThumbnail: headerThumbnail,
      headerTitle: title,
      headerSubtitle: subtitle,
      items: [
        AppActionItem(
          icon: Icons.album_rounded,
          title: 'Open Album',
          subtitle: 'View tracks in this album',
          onTap: () => appState.openAlbumPageFromSong(context, song),
        ),
        AppActionItem(
          icon: Icons.play_arrow_rounded,
          title: 'Play Album',
          subtitle: 'Start playback from track 1',
          onTap: () async {
            final albumSongs = getAlbumSongs();
            if (albumSongs.isNotEmpty) {
              await appState.playFromQueue(context, albumSongs, initialIndex: 0);
            }
          },
        ),
        AppActionItem(
          icon: Icons.playlist_add_rounded,
          title: 'Play next',
          subtitle: 'Insert album tracks after current song',
          onTap: () async {
            final albumSongs = getAlbumSongs();
            if (albumSongs.isNotEmpty) {
              await appState.insertAllInQueue(context, albumSongs);
            }
          },
        ),
        AppActionItem(
          icon: Icons.queue_music_rounded,
          title: 'Add to queue',
          subtitle: 'Append album tracks to queue end',
          onTap: () async {
            final albumSongs = getAlbumSongs();
            if (albumSongs.isNotEmpty) {
              await appState.addAllToQueueEnd(context, albumSongs);
            }
          },
        ),
        AppActionItem(
          icon: Icons.tune_rounded,
          title: 'Edit Album Tags',
          subtitle: 'Batch edit tags across all album tracks',
          onTap: () async {
            final albumSongs = getAlbumSongs();
            if (albumSongs.isEmpty) return;
            await showDialog<void>(
              context: context,
              builder: (ctx) => BatchTagEditorDialog(
                songs: albumSongs,
                onSaved: () {},
                onSongsUpdated: (updatedSongs) {
                  appState.updateSongsMetadataInPlace(updatedSongs);
                },
                runWithPlaybackSuspended: (action) =>
                    appState.runWithPlaybackSuspendedForBatchTagWrite(
                      action,
                      targetFilePaths: albumSongs.map((s) => s.data).toSet(),
                      itemCount: albumSongs.length,
                    ),
              ),
            );
          },
        ),
      ],
    );
  }
}
