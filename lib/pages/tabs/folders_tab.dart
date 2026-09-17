import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../../services/app_state_controller.dart';
import '../../services/playback_controller.dart';
import '../../ui/shared/app_action_sheet.dart';
import '../../ui/shared/app_empty_state.dart';
import '../../ui/shared/bottom_bars_gutter.dart';
import '../../ui/shared/fast_artwork_widget.dart';
import '../../utils/format_utils.dart';

class _FolderGroup {
  final String path;
  final String name;
  final List<SongModel> songs;
  int totalDurationMs = 0;
  SongModel? representativeSong;

  _FolderGroup({
    required this.path,
    required this.name,
    required this.songs,
  }) {
    for (final s in songs) {
      totalDurationMs += (s.duration ?? 0);
      if (representativeSong == null ||
          ((representativeSong!.albumId ?? 0) <= 0 && (s.albumId ?? 0) > 0)) {
        representativeSong = s;
      }
    }
  }
}

class FoldersTab extends StatefulWidget {
  const FoldersTab({super.key});

  @override
  State<FoldersTab> createState() => _FoldersTabState();
}

class _FoldersTabState extends State<FoldersTab> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<_FolderGroup> _computeFolders(List<SongModel> songs) {
    final map = <String, List<SongModel>>{};
    for (final s in songs) {
      final data = s.data.replaceAll('\\', '/');
      final lastSlash = data.lastIndexOf('/');
      if (lastSlash <= 0) continue;
      final dir = data.substring(0, lastSlash);
      (map[dir] ??= <SongModel>[]).add(s);
    }

    final groups = <_FolderGroup>[];
    for (final entry in map.entries) {
      final parts = entry.key.split('/');
      final folderName = parts.isNotEmpty ? parts.last : entry.key;
      groups.add(_FolderGroup(
        path: entry.key,
        name: folderName.isEmpty ? 'Root' : folderName,
        songs: entry.value,
      ));
    }

    groups.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return groups;
  }

  void _showFolderOptionsModal(
    BuildContext context,
    _FolderGroup group,
  ) {
    final cs = Theme.of(context).colorScheme;

    final headerThumbnail = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: group.representativeSong != null
          ? FastArtworkWidget(
              id: group.representativeSong!.albumId ?? group.representativeSong!.id,
              type: ArtworkType.ALBUM,
              width: 48,
              height: 48,
              nullArtworkWidget: Container(
                width: 48,
                height: 48,
                color: cs.surfaceContainerHighest,
                child: Icon(Icons.folder_rounded, color: cs.primary),
              ),
            )
          : Container(
              width: 48,
              height: 48,
              color: cs.surfaceContainerHighest,
              child: Icon(Icons.folder_rounded, color: cs.primary),
            ),
    );

    final headerSubtitle =
        '${group.songs.length} tracks • ${formatPlaylistDuration(group.totalDurationMs)}\n${group.path}';

    showAppActionSheet<void>(
      context: context,
      headerThumbnail: headerThumbnail,
      headerTitle: group.name,
      headerSubtitle: headerSubtitle,
      items: [
        AppActionItem(
          icon: Icons.play_arrow_rounded,
          title: 'Play Folder',
          subtitle: 'Start playback of all tracks in this folder',
          onTap: () async {
            if (group.songs.isNotEmpty) {
              await playbackController.playFromQueue(group.songs, initialIndex: 0);
            }
          },
        ),
        AppActionItem(
          icon: Icons.playlist_add_rounded,
          title: 'Play next',
          subtitle: 'Insert folder tracks after current song',
          onTap: () async {
            if (group.songs.isNotEmpty) {
              await playbackController.insertAllInQueue(group.songs);
            }
          },
        ),
        AppActionItem(
          icon: Icons.queue_music_rounded,
          title: 'Add to queue',
          subtitle: 'Append folder tracks to queue end',
          onTap: () async {
            if (group.songs.isNotEmpty) {
              await playbackController.addAllToQueueEnd(group.songs);
            }
          },
        ),
        AppActionItem(
          icon: Icons.shuffle_rounded,
          title: 'Shuffle Folder',
          subtitle: 'Shuffle and play tracks in this folder',
          onTap: () async {
            if (group.songs.isNotEmpty) {
              final shuffled = List<SongModel>.from(group.songs)..shuffle();
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
        final groups = _computeFolders(appState.songs);
        final cs = Theme.of(context).colorScheme;

        return CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar.large(
              title: const Text('Folders'),
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
                  icon: const Icon(Icons.folder_special_outlined),
                  tooltip: 'Manage Folders',
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    appState.openManageFoldersDialog(context);
                  },
                ),
                const SizedBox(width: 4),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Text(
                  '${groups.length} folders',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (groups.isEmpty)
              AppEmptyState.sliver(
                icon: Icons.folder_off_outlined,
                title: 'No music folders found',
                message: 'Your library folders are empty or excluded.',
              )
            else
              SliverFixedExtentList(
                itemExtent: 80.0,
                delegate: SliverChildBuilderDelegate((context, i) {
                  final group = groups[i];
                  final subtitle =
                      '${group.songs.length} tracks • ${formatPlaylistDuration(group.totalDurationMs)}';

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
                            _showFolderOptionsModal(context, group);
                          },
                          onLongPress: () {
                            HapticFeedback.mediumImpact();
                            _showFolderOptionsModal(context, group);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: group.representativeSong != null
                                      ? FastArtworkWidget(
                                          id: group.representativeSong!.albumId ??
                                              group.representativeSong!.id,
                                          type: ArtworkType.ALBUM,
                                          width: 52,
                                          height: 52,
                                          nullArtworkWidget: Container(
                                            width: 52,
                                            height: 52,
                                            color: cs.surfaceContainerHighest,
                                            child: Icon(
                                              Icons.folder_rounded,
                                              size: 26,
                                              color: cs.primary,
                                            ),
                                          ),
                                        )
                                      : Container(
                                          width: 52,
                                          height: 52,
                                          color: cs.surfaceContainerHighest,
                                          child: Icon(
                                            Icons.folder_rounded,
                                            size: 26,
                                            color: cs.primary,
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        group.name,
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
                                    _showFolderOptionsModal(context, group);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }, childCount: groups.length),
              ),
            buildBottomBarsGutter(context),

          ],
        );
      },
    );
  }
}
