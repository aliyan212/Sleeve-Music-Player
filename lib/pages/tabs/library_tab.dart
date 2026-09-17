import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../../services/app_state_controller.dart';
import '../../data/models/sort_mode.dart';
import '../../main.dart';
import 'package:flutter/services.dart';
import '../../services/playback_controller.dart';
import '../../dialogs/batch_tag_editor_dialog.dart';
import '../../ui/shared/bottom_bars_gutter.dart';
import '../../widgets/universal_song_tile.dart';
import '../../ui/shared/alphabetical_bubble_scroller.dart';
import '../../ui/shared/app_empty_state.dart';
import '../../utils/song_sort_utils.dart';
import '../../widgets/search/app_search_view.dart';
import '../../ui/shared/app_sort_bottom_sheet.dart';

enum AppMenuAction { selectTracks, refresh, manageFolders, toggleTheme, about, quit }

class LibraryTab extends StatelessWidget {
  final ScrollController scrollController;
  final ValueNotifier<bool> showSearchInAppBar;

  const LibraryTab({
    super.key,
    required this.scrollController,
    required this.showSearchInAppBar,
  });

  @override
  Widget build(BuildContext context) {
    final appState = AppStateController.instance;
    final controller = playbackController;
    final isVisible = appState.inlineDetailContent == null;
    final isSelectionMode = appState.isSelectionMode;
    final selectedSongIds = appState.selectedSongIds;
    final songs = appState.songs;

  
    final cs = Theme.of(context).colorScheme;

    Widget menuLabel(IconData icon, String label) {
      return Row(
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Text(label),
        ],
      );
    }

    final allSelected = songs.isNotEmpty && selectedSongIds.length == songs.length;

    return AlphabeticalBubbleScroller(
      scrollController: scrollController,
      itemCount: songs.length,
      headerHeight: isSelectionMode ? 108.0 : 180.0,
      itemHeight: 106.0,
      sortKey: controller.sortMode,
      isNumericSort: controller.sortMode == SortMode.year,
      sectionKeyOf: (index) {
        final s = songs[index];
        final sortMode = controller.sortMode;
        switch (sortMode) {
          case SortMode.artist:
            return s.artist ?? '';
          case SortMode.albumArtist:
            return albumArtistFor(s);
          case SortMode.year:
            final y = yearFromSong(s);
            return y > 0 ? '$y' : '#';
          case SortMode.albumArtistYear:
            return albumArtistFor(s);
        }
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        // Helps avoid transient blanking while scrubbing quickly
        // by keeping more children alive and prefetched.
        cacheExtent: 1200,
        controller: scrollController,
        slivers: [
            SliverAppBar.large(
              title: isSelectionMode
                  ? Text('${selectedSongIds.length} selected')
                  : const Text('Library'),
              expandedHeight: 164,
              backgroundColor: cs.surface.withValues(alpha: 0.90),
              surfaceTintColor: Colors.transparent,
              centerTitle: false,
              foregroundColor: cs.onSurface,
              titleTextStyle: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
              actions: [
                if (isSelectionMode) ...[
                  IconButton(
                    tooltip: allSelected ? 'Deselect all' : 'Select all',
                    icon: Icon(
                      allSelected
                          ? Icons.deselect_rounded
                          : Icons.select_all_rounded,
                    ),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      if (allSelected) {
                        appState.deselectAllSongs();
                      } else {
                        appState.selectAllSongs(songs.map((s) => s.id));
                      }
                    },
                  ),
                  IconButton(
                    tooltip: 'Play next',
                    icon: const Icon(Icons.playlist_play_rounded),
                    onPressed: selectedSongIds.isEmpty
                        ? null
                        : () async {
                            HapticFeedback.selectionClick();
                            final selectedSongs = appState.songs
                                .where((s) => selectedSongIds.contains(s.id))
                                .toList(growable: false);
                            playbackController.insertAllInQueue(selectedSongs);
                            appState.exitSelectionMode();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Playing ${selectedSongs.length} track${selectedSongs.length == 1 ? '' : 's'} next',
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                  ),
                  IconButton(
                    tooltip: 'Add to queue',
                    icon: const Icon(Icons.queue_music_rounded),
                    onPressed: selectedSongIds.isEmpty
                        ? null
                        : () async {
                            HapticFeedback.selectionClick();
                            final selectedSongs = appState.songs
                                .where((s) => selectedSongIds.contains(s.id))
                                .toList(growable: false);
                            playbackController.addAllToQueueEnd(selectedSongs);
                            appState.exitSelectionMode();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Added ${selectedSongs.length} track${selectedSongs.length == 1 ? '' : 's'} to queue',
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                  ),
                  IconButton(
                    tooltip: 'Add to playlist',
                    onPressed: selectedSongIds.isEmpty
                        ? null
                        : () async {
                            HapticFeedback.selectionClick();
                            final ids = selectedSongIds.toList(
                              growable: false,
                            );
                            final didAdd = await appState.addSongsToPlaylistFlow(context, ids);
                            if (didAdd) appState.exitSelectionMode();
                          },
                    icon: const Icon(Icons.playlist_add_rounded),
                  ),
                  IconButton(
                    tooltip: 'Edit tags',
                    onPressed: selectedSongIds.isEmpty
                        ? null
                        : () async {
                            HapticFeedback.selectionClick();
                            final selectedSongs = appState.songs
                                .where((s) => selectedSongIds.contains(s.id))
                                .toList(growable: false);
                            if (selectedSongs.isEmpty) return;
                            await showDialog<void>(
                              context: context,
                              builder: (ctx) => BatchTagEditorDialog(
                                songs: selectedSongs,
                                onSaved: () {},
                                onSongsUpdated: (updatedSongs) {
                                  appState.updateSongsMetadataInPlace(updatedSongs);
                                },
                                runWithPlaybackSuspended: (action) =>
                                    appState.runWithPlaybackSuspendedForBatchTagWrite(
                                      action,
                                      targetFilePaths: selectedSongs
                                          .map((s) => s.data)
                                          .toSet(),
                                      itemCount: selectedSongs.length,
                                    ),
                              ),
                            );
                            appState.exitSelectionMode();
                          },
                    icon: const Icon(Icons.tune_rounded),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    onPressed: selectedSongIds.isEmpty
                        ? null
                        : () async {
                            HapticFeedback.selectionClick();
                            await appState.deleteSelectedSongs(context);
                          },
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                  IconButton(
                    tooltip: 'Cancel',
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      appState.exitSelectionMode();
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ] else ...[
                  // Search "collapses" into this button when scrolled.
                  ValueListenableBuilder<bool>(
                    valueListenable: showSearchInAppBar,
                    builder: (context, showSearch, _) {
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: showSearch
                            ? IconButton(
                                key: const ValueKey('search_on'),
                                icon: const Icon(Icons.search_rounded),
                                tooltip: 'Search',
                                onPressed: () {
                                  HapticFeedback.selectionClick();
                                  appState.openSearch(initialFilter: SearchFilter.all);
                                },
                              )
                            : const SizedBox.shrink(
                                key: ValueKey('search_off'),
                              ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.sort_rounded),
                    tooltip: 'Sort library',
                    onPressed: () {
                      showSongSortBottomSheet(
                        context,
                        currentSort: controller.sortMode,
                        onSortSelected: (mode) {
                          appState.applySort(mode);
                        },
                      );
                    },
                  ),
                  PopupMenuButton<AppMenuAction>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (action) {
                      HapticFeedback.selectionClick();
                      switch (action) {
                        case AppMenuAction.selectTracks:
                          appState.enterSelectionMode();
                          break;
                        case AppMenuAction.refresh:
                          appState.ensureLibraryPermissionAndLoad();
                          break;
                        case AppMenuAction.manageFolders:
                          appState.openManageFoldersDialog(context);
                          break;
                        case AppMenuAction.toggleTheme:
                          themeNotifier.toggle();
                          break;
                        case AppMenuAction.about:
                          appState.openAboutPage(context);
                          break;
                        case AppMenuAction.quit:
                          appState.confirmQuit(context);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: AppMenuAction.selectTracks,
                        child: menuLabel(
                          Icons.checklist_rounded,
                          'Select Tracks',
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: AppMenuAction.refresh,
                        child: menuLabel(
                          Icons.refresh_rounded,
                          'Scan/Refresh Library',
                        ),
                      ),
                      PopupMenuItem(
                        value: AppMenuAction.manageFolders,
                        child: menuLabel(
                          Icons.folder_copy_rounded,
                          'Manage Folders',
                        ),
                      ),
                      PopupMenuItem(
                        value: AppMenuAction.toggleTheme,
                        child: menuLabel(
                          Icons.palette_rounded,
                          themeNotifier.themeMenuLabel,
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: AppMenuAction.about,
                        child: menuLabel(Icons.info_outline_rounded, 'About'),
                      ),
                      PopupMenuItem(
                        value: AppMenuAction.quit,
                        child: Row(
                          children: [
                            Icon(
                              Icons.power_settings_new_rounded,
                              size: 18,
                              color: cs.error,
                            ),
                            const SizedBox(width: 12),
                            Text('Quit', style: TextStyle(color: cs.error)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            if (!isSelectionMode)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Focus(
                    canRequestFocus: false,
                    descendantsAreFocusable: false,
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        FocusManager.instance.primaryFocus?.unfocus();
                        SystemChannels.textInput.invokeMethod('TextInput.hide');
                        appState.openSearch(initialFilter: SearchFilter.all);
                      },
                      child: const AbsorbPointer(
                        child: SearchBar(
                          readOnly: true,
                          hintText: 'Search tracks, albums, artists...',
                          leading: Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (songs.isEmpty)
              AppEmptyState.sliver(
                icon: Icons.music_off_rounded,
                title: 'No songs found',
                message:
                    'Add music files to your device or scan folders to populate your library.',
                actionLabel: 'Scan Library',
                actionIcon: Icons.refresh_rounded,
                onAction: () => appState.ensureLibraryPermissionAndLoad(),
              )
            else
              SliverFixedExtentList(
                itemExtent: 106.0,
                delegate: SliverChildBuilderDelegate((context, index) {
                  final song = songs[index];
                  final isSelected = selectedSongIds.contains(song.id);

                  // 1. Push the listeners DOWN to the individual item level
                  return ValueListenableBuilder<int?>(
                    valueListenable: controller.currentSongIdNotifier,
                    builder: (context, currentSongId, _) {
                      return ValueListenableBuilder<int?>(
                        valueListenable: controller.currentPlayIndexNotifier,
                        builder: (context, currentPlayIndex, _) {
                          final isCurrent = currentSongId != null
                              ? currentSongId == song.id
                              : currentPlayIndex == index;

                          // 2. ONLY listen to the player state stream if THIS song is the active one!
                          return StreamBuilder<PlayerState>(
                            stream: (isCurrent && isVisible)
                                ? controller.player.playerStateStream
                                : null,
                            builder: (context, snap) {
                              final playing = isCurrent
                                  ? (snap.data?.playing ??
                                        controller.player.playing)
                                  : false;
                              final showPause = isCurrent && playing;
                              final icon = showPause
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded;

                              final artistText =
                                  (song.artist ?? '').trim().isEmpty
                                  ? 'Unknown Artist'
                                  : song.artist!.trim();
                              final albumText = (song.album ?? '').trim().isEmpty
                                  ? 'Unknown Album'
                                  : song.album!.trim();

                              final trailing = isSelectionMode
                                  ? IconButton(
                                      icon: Icon(
                                        isSelected
                                            ? Icons.check_circle_rounded
                                            : Icons.radio_button_unchecked_rounded,
                                        color: isSelected
                                            ? cs.primary
                                            : cs.onSurfaceVariant,
                                      ),
                                      tooltip: isSelected ? 'Deselect' : 'Select',
                                      onPressed: () {
                                        HapticFeedback.selectionClick();
                                        appState.toggleSelectedSongId(song.id);
                                      },
                                    )
                                  : IconButton.filledTonal(
                                      icon: AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 220,
                                        ),
                                        transitionBuilder: (child, animation) {
                                          return ScaleTransition(
                                            scale: CurvedAnimation(
                                              parent: animation,
                                              curve: Curves.easeOutBack,
                                            ),
                                            child: FadeTransition(
                                              opacity: animation,
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: Icon(
                                          icon,
                                          key: ValueKey(icon),
                                          size: 22,
                                        ),
                                      ),
                                      tooltip: showPause ? 'Pause' : 'Play',
                                      onPressed: () async {
                                        HapticFeedback.selectionClick();
                                        if (isCurrent) {
                                          if (playing) {
                                            await controller.player.pause();
                                          } else {
                                             await appState
                                                 .checkNotificationPermission(context);
                                             unawaited(controller.player.play());
                                           }
                                           return;
                                        }
                                        controller.playSong(index);
                                      },
                                    );

                              return UniversalSongTile(
                                song: song,
                                title: song.title,
                                subtitle: artistText,
                                meta: albumText,
                                durationMs: song.duration,
                                isCurrent: isCurrent,
                                isPlaying: playing,
                                isSelected: isSelected,
                                isSelectionMode: isSelectionMode,
                                circularArtwork: true,
                                artworkSize: 52,
                                showArtworkBadges: true,
                                showShadows: true,
                                showMetaDuration: true,
                                borderRadius: BorderRadius.circular(16),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 4,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10.5,
                                ),
                                trailing: trailing,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  if (isSelectionMode) {
                                    appState.toggleSelectedSongId(song.id);
                                  } else {
                                    controller.playSong(index);
                                  }
                                },
                                onLongPress: () {
                                  HapticFeedback.mediumImpact();
                                  if (isSelectionMode) {
                                    appState.toggleSelectedSongId(song.id);
                                  } else {
                                    appState.showSongOptions(context, song,  index);
                                  }
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                }, childCount: songs.length),
              ),
            buildBottomBarsGutter(context),
          ],
        ),
      );
  }
}
