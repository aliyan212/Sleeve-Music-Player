import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../services/playback_controller.dart';
import '../ui/shared/app_action_sheet.dart';
import '../ui/shared/fast_artwork_widget.dart';
import '../dialogs/tag_editor_dialog.dart';
import '../dialogs/lyrics_editor_dialog.dart';
import '../dialogs/song_info_dialog.dart';

Future<void> showSongOptionsSheet({
  required BuildContext context,
  required SongModel song,
  required int index,
  required void Function(int songId) onEnterSelectionMode,
  required void Function(SongModel) onOpenNowPlaying,
  required void Function(SongModel) onOpenAlbum,
  required void Function(SongModel) onOpenArtist,
  required void Function(SongModel) onSongUpdated,
  required Future<void> Function(Future<void> Function() action, {String? targetFilePath}) runWithPlaybackSuspended,
  required Future<void> Function() onPlaySong,
}) async {
  if (!context.mounted) return;
  final hasAlbum = (song.albumId ?? 0) > 0;
  final artistName = (song.artist ?? '').trim();
  final hasArtist =
      artistName.isNotEmpty && artistName.toLowerCase() != 'unknown artist';

  final cs = Theme.of(context).colorScheme;

  Future<void> playNext() async {
    if (playbackController.player.currentIndex == null || playbackController.player.audioSources.isEmpty) {
      await onPlaySong();
      return;
    }
    try {
      await playbackController.insertInQueue(song);
      HapticFeedback.selectionClick();
    } catch (_) {
      await onPlaySong();
    }
  }

  Future<void> addToQueue() async {
    if (playbackController.player.audioSources.isEmpty) {
      await onPlaySong();
      return;
    }
    try {
      await playbackController.addToQueueEnd(song);
      HapticFeedback.selectionClick();
    } catch (_) {
      await onPlaySong();
    }
  }

  final headerThumbnail = ClipOval(
    child: FastArtworkWidget(
      id: song.id,
      type: ArtworkType.AUDIO,
      width: 48,
      height: 48,
      nullArtworkWidget: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.music_note_rounded,
          color: cs.onSurfaceVariant,
        ),
      ),
    ),
  );

  final subtitleParts = <String>[];
  if (hasArtist) subtitleParts.add(artistName);
  if (hasAlbum && song.album != null && song.album!.trim().isNotEmpty) {
    subtitleParts.add(song.album!.trim());
  }
  final headerSubtitle = subtitleParts.isNotEmpty
      ? subtitleParts.join(' • ')
      : (song.artist ?? 'Unknown Artist');

  final sections = <AppActionSection>[
    AppActionSection(
      title: 'Selection',
      items: [
        AppActionItem(
          icon: Icons.checklist_rounded,
          title: 'Select',
          subtitle: 'Select multiple songs to add to a playlist',
          onTap: () => onEnterSelectionMode(song.id),
        ),
      ],
    ),
    AppActionSection(
      title: 'Playback',
      items: [
        AppActionItem(
          icon: Icons.play_arrow_rounded,
          title: 'Play',
          subtitle: 'Start playing this track',
          onTap: onPlaySong,
        ),
        AppActionItem(
          icon: Icons.playlist_add_rounded,
          title: 'Play next',
          subtitle: 'Insert after the current track',
          onTap: playNext,
        ),
        AppActionItem(
          icon: Icons.queue_music_rounded,
          title: 'Add to queue',
          subtitle: 'Append to the end of the queue',
          onTap: addToQueue,
        ),
      ],
    ),
    if (hasAlbum || hasArtist)
      AppActionSection(
        title: 'Library',
        items: [
          if (hasAlbum)
            AppActionItem(
              icon: Icons.album_rounded,
              title: 'Open album',
              subtitle: 'View all tracks in this album',
              onTap: () => onOpenAlbum(song),
            ),
          if (hasArtist)
            AppActionItem(
              icon: Icons.person_rounded,
              title: 'Open artist',
              subtitle: 'View albums by this artist',
              onTap: () => onOpenArtist(song),
            ),
        ],
      ),
    AppActionSection(
      title: 'Details',
      items: [
        AppActionItem(
          icon: Icons.info_outline_rounded,
          title: 'Song info',
          subtitle: 'File details, tags, and timestamps',
          onTap: () => showSongInfoSheet(context, song),
        ),
      ],
    ),
    AppActionSection(
      title: 'Edit',
      items: [
        AppActionItem(
          icon: Icons.edit_rounded,
          title: 'Edit tags',
          subtitle: 'Title, artist, album, cover art',
          onTap: () async {
            await showDialog<bool>(
              context: context,
              builder: (dctx) => TagEditorDialog(
                song: song,
                onSaved: () {},
                onSongUpdated: onSongUpdated,
                runWithPlaybackSuspended: (action) => runWithPlaybackSuspended(
                  action,
                  targetFilePath: song.data,
                ),
              ),
            );
          },
        ),
        AppActionItem(
          icon: Icons.lyrics_rounded,
          title: 'Edit lyrics',
          subtitle: 'Paste lyrics or synced LRC',
          onTap: () async {
            await showDialog<bool>(
              context: context,
              builder: (dctx) => LyricsEditorDialog(
                song: song,
                currentLyrics: null,
                onSaved: () {},
                onLyricsSaved: (_) {},
                runWithPlaybackSuspended: (action) => runWithPlaybackSuspended(
                  action,
                  targetFilePath: song.data,
                ),
              ),
            );
          },
        ),
      ],
    ),
  ];

  await showAppActionSheet(
    context: context,
    headerThumbnail: headerThumbnail,
    headerTitle: song.title,
    headerSubtitle: headerSubtitle,
    sections: sections,
  );
}
