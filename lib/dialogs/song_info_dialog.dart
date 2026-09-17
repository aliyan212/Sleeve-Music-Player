import 'dart:io';
import 'package:audiotags/audiotags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;

import '../services/app_state_controller.dart';
import '../services/playback_controller.dart';
import '../ui/shared/fast_artwork_widget.dart';
import '../utils/format_utils.dart';
import '../utils/tag_write_access.dart';

/// Shows a comprehensive Material 3 bottom sheet detailing all file,
/// tag, timestamp, and playback information for [song].
Future<void> showSongInfoSheet(BuildContext context, SongModel song) {
  HapticFeedback.mediumImpact();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => SongInfoSheet(song: song),
  );
}

class SongInfoSheet extends StatefulWidget {
  final SongModel song;

  const SongInfoSheet({super.key, required this.song});

  @override
  State<SongInfoSheet> createState() => _SongInfoSheetState();
}

class _SongInfoSheetState extends State<SongInfoSheet> {
  bool _isLoading = true;

  // Enriched tags
  String? _albumArtist;
  String? _composer;
  String? _lyricist;
  String? _genre;
  int? _year;
  int? _trackNumber;
  int? _trackTotal;
  int? _discNumber;
  int? _discTotal;

  // File stats
  int? _fileSize;
  DateTime? _dateModified;
  DateTime? _dateAdded;

  @override
  void initState() {
    super.initState();
    final song = widget.song;
    _fileSize = song.size;
    _albumArtist = song.getMap['album_artist']?.toString();
    _composer = song.composer;
    _genre = song.genre;
    _year = int.tryParse(song.getMap['year']?.toString() ?? '');
    _trackNumber = song.track;
    final addedMs = AppStateController.instance.dateAddedForSong(song);
    if (addedMs > 0) {
      _dateAdded = DateTime.fromMillisecondsSinceEpoch(addedMs);
    }
    _loadSongDetails();
  }

  Future<void> _loadSongDetails() async {
    final song = widget.song;
    int? resolvedSize = _fileSize;
    DateTime? resolvedModified;
    DateTime? resolvedAdded = _dateAdded;

    // File stat on disk
    try {
      final file = File(song.data);
      if (await file.exists()) {
        final stat = await file.stat();
        resolvedSize = stat.size;
        resolvedModified = stat.modified;
      }
    } catch (_) {}

    // Fallback date modified from MediaStore
    if (resolvedModified == null) {
      final modVal = song.getMap['date_modified'];
      if (modVal != null) {
        final modParsed = modVal is int ? modVal : int.tryParse(modVal.toString());
        if (modParsed != null && modParsed > 0) {
          final ms = modParsed < 1000000000000 ? modParsed * 1000 : modParsed;
          resolvedModified = DateTime.fromMillisecondsSinceEpoch(ms);
        }
      }
    }

    // Read audio tags via AudioTags and ID3 text frames
    try {
      final file = File(song.data);
      if (await file.exists()) {
        final tag = await AudioTags.read(song.data);
        if (tag != null) {
          if (tag.albumArtist != null && tag.albumArtist!.trim().isNotEmpty) {
            _albumArtist = tag.albumArtist!.trim();
          }
          if (tag.genre != null && tag.genre!.trim().isNotEmpty) {
            _genre = tag.genre!.trim();
          }
          if (tag.year != null && tag.year! > 0) {
            _year = tag.year;
          }
          if (tag.trackNumber != null && tag.trackNumber! > 0) {
            _trackNumber = tag.trackNumber;
          }
          _trackTotal = tag.trackTotal;
          _discNumber = tag.discNumber;
          _discTotal = tag.discTotal;
        }

        // Custom ID3 frames (TCOM, TEXT) for MP3 files
        if (song.data.toLowerCase().endsWith('.mp3')) {
          final id3Frames = await readMp3Id3TextFrames(
            song.data,
            const ['TCOM', 'TEXT'],
          );
          if (id3Frames['TCOM'] != null && id3Frames['TCOM']!.trim().isNotEmpty) {
            _composer = id3Frames['TCOM']!.trim();
          }
          if (id3Frames['TEXT'] != null && id3Frames['TEXT']!.trim().isNotEmpty) {
            _lyricist = id3Frames['TEXT']!.trim();
          }
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _fileSize = resolvedSize;
        _dateModified = resolvedModified;
        _dateAdded = resolvedAdded;
        _isLoading = false;
      });
    }
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null || bytes <= 0) return 'Unknown size';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB ($bytes bytes)';
    }
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(2)} MB ($bytes bytes)';
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return 'Unknown';
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final min = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$y-$m-$d • $hour:$min $ampm';
  }

  String _formatDuration(int? ms) {
    if (ms == null || ms <= 0) return 'Unknown duration';
    final totalSec = (ms / 1000).round();
    final timeStr = formatTime(ms);
    return '$timeStr ($totalSec seconds)';
  }

  String _formatTrack(int? num, int? total) {
    if (num == null || num <= 0) return 'Not set';
    if (total != null && total > 0) return '$num of $total';
    return '$num';
  }

  String _formatDisc(int? num, int? total) {
    if (num == null || num <= 0) return '1';
    if (total != null && total > 0) return '$num of $total';
    return '$num';
  }

  void _copyToClipboard(String label, String value) {
    HapticFeedback.selectionClick();
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _copyAllDetails() {
    HapticFeedback.selectionClick();
    final s = widget.song;
    final buffer = StringBuffer();
    buffer.writeln('=== Song Info ===');
    buffer.writeln('Title: ${s.title}');
    buffer.writeln('Artist: ${s.artist ?? 'Unknown Artist'}');
    buffer.writeln('Album: ${s.album ?? 'Unknown Album'}');
    if (_albumArtist != null && _albumArtist!.isNotEmpty) {
      buffer.writeln('Album Artist: $_albumArtist');
    }
    if (_composer != null && _composer!.isNotEmpty) {
      buffer.writeln('Composer: $_composer');
    }
    if (_lyricist != null && _lyricist!.isNotEmpty) {
      buffer.writeln('Lyricist: $_lyricist');
    }
    if (_genre != null && _genre!.isNotEmpty) {
      buffer.writeln('Genre: $_genre');
    }
    if (_year != null && _year! > 0) {
      buffer.writeln('Year: $_year');
    }
    buffer.writeln('Track: ${_formatTrack(_trackNumber, _trackTotal)}');
    buffer.writeln('Disc: ${_formatDisc(_discNumber, _discTotal)}');
    buffer.writeln('Duration: ${_formatDuration(s.duration)}');
    buffer.writeln('File Name: ${p.basename(s.data)}');
    buffer.writeln('Folder: ${p.dirname(s.data)}');
    buffer.writeln('Full Path: ${s.data}');
    buffer.writeln('Size: ${_formatFileSize(_fileSize)}');
    buffer.writeln('Date Added: ${_formatDateTime(_dateAdded)}');
    buffer.writeln('Date Modified: ${_formatDateTime(_dateModified)}');
    final playCount = playbackController.playCountBySongId[s.id] ?? 0;
    buffer.writeln('Play Count: $playCount');

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All song details copied to clipboard'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final song = widget.song;

    final fileName = p.basename(song.data);
    final folderPath = p.dirname(song.data);
    final ext = p.extension(song.data).replaceAll('.', '').toUpperCase();

    final playCount = playbackController.playCountBySongId[song.id] ?? 0;
    final lastPlayedMs = playbackController.lastPlayedMsBySongId[song.id];
    final lastPlayedDate = lastPlayedMs != null && lastPlayedMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(lastPlayedMs)
        : null;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Top Pill Handle ──
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                decoration: BoxDecoration(
                  color: cs.outlineVariant.withValues(alpha: isDark ? 0.45 : 0.65),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 16, 12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 50,
                      height: 50,
                      child: FastArtworkWidget(
                        id: song.id,
                        type: ArtworkType.AUDIO,
                        width: 50,
                        height: 50,
                        nullArtworkWidget: Container(
                          color: cs.surfaceContainerHighest,
                          child: Icon(
                            Icons.music_note_rounded,
                            color: cs.onSurfaceVariant,
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${song.artist ?? 'Unknown Artist'} • ${song.album ?? 'Unknown Album'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy all details',
                    icon: const Icon(Icons.copy_all_rounded),
                    onPressed: _copyAllDetails,
                  ),
                ],
              ),
            ),

            Divider(
              height: 1,
              thickness: 1,
              color: cs.outlineVariant.withValues(alpha: isDark ? 0.25 : 0.40),
            ),

            // ── Details Body ──
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  // ── File Information ──
                  _buildSectionHeader(context, 'FILE INFORMATION', Icons.folder_rounded),
                  _buildDetailTile(
                    context,
                    label: 'File Name',
                    value: fileName,
                    onTap: () => _copyToClipboard('File Name', fileName),
                  ),
                  _buildDetailTile(
                    context,
                    label: 'Format',
                    value: ext.isNotEmpty ? '$ext Audio' : 'Audio file',
                  ),
                  _buildDetailTile(
                    context,
                    label: 'File Size',
                    value: _formatFileSize(_fileSize),
                  ),
                  _buildDetailTile(
                    context,
                    label: 'Duration',
                    value: _formatDuration(song.duration),
                  ),
                  _buildDetailTile(
                    context,
                    label: 'Folder',
                    value: folderPath,
                    onTap: () => _copyToClipboard('Folder Path', folderPath),
                  ),
                  _buildDetailTile(
                    context,
                    label: 'Full Path',
                    value: song.data,
                    onTap: () => _copyToClipboard('File Path', song.data),
                    isMonospace: true,
                  ),

                  const SizedBox(height: 14),

                  // ── Audio Tags & Metadata ──
                  _buildSectionHeader(context, 'TAGS & METADATA', Icons.label_rounded),
                  _buildDetailTile(
                    context,
                    label: 'Title',
                    value: song.title,
                    onTap: () => _copyToClipboard('Title', song.title),
                  ),
                  _buildDetailTile(
                    context,
                    label: 'Track Artist',
                    value: song.artist ?? 'Unknown Artist',
                    onTap: () => _copyToClipboard('Artist', song.artist ?? ''),
                  ),
                  _buildDetailTile(
                    context,
                    label: 'Album',
                    value: song.album ?? 'Unknown Album',
                    onTap: () => _copyToClipboard('Album', song.album ?? ''),
                  ),
                  if (_albumArtist != null && _albumArtist!.isNotEmpty)
                    _buildDetailTile(
                      context,
                      label: 'Album Artist',
                      value: _albumArtist!,
                      onTap: () => _copyToClipboard('Album Artist', _albumArtist!),
                    ),
                  if (_composer != null && _composer!.isNotEmpty)
                    _buildDetailTile(
                      context,
                      label: 'Composer',
                      value: _composer!,
                      onTap: () => _copyToClipboard('Composer', _composer!),
                    ),
                  if (_lyricist != null && _lyricist!.isNotEmpty)
                    _buildDetailTile(
                      context,
                      label: 'Lyricist',
                      value: _lyricist!,
                      onTap: () => _copyToClipboard('Lyricist', _lyricist!),
                    ),
                  _buildDetailTile(
                    context,
                    label: 'Genre',
                    value: (_genre != null && _genre!.isNotEmpty) ? _genre! : 'Unknown Genre',
                  ),
                  _buildDetailTile(
                    context,
                    label: 'Release Year',
                    value: (_year != null && _year! > 0) ? '$_year' : 'Unknown Year',
                  ),
                  _buildDetailTile(
                    context,
                    label: 'Track',
                    value: _formatTrack(_trackNumber, _trackTotal),
                  ),
                  _buildDetailTile(
                    context,
                    label: 'Disc',
                    value: _formatDisc(_discNumber, _discTotal),
                  ),

                  const SizedBox(height: 14),

                  // ── Dates & Timestamps ──
                  _buildSectionHeader(context, 'TIMESTAMPS', Icons.event_rounded),
                  _buildDetailTile(
                    context,
                    label: 'Date Added to Library',
                    value: _formatDateTime(_dateAdded),
                  ),
                  _buildDetailTile(
                    context,
                    label: 'Last Modified Date',
                    value: _formatDateTime(_dateModified),
                  ),

                  const SizedBox(height: 14),

                  // ── Playback Statistics ──
                  _buildSectionHeader(context, 'PLAYBACK STATISTICS', Icons.analytics_rounded),
                  _buildDetailTile(
                    context,
                    label: 'Play Count',
                    value: '$playCount ${playCount == 1 ? 'play' : 'plays'}',
                  ),
                  _buildDetailTile(
                    context,
                    label: 'Last Played',
                    value: lastPlayedDate != null
                        ? _formatDateTime(lastPlayedDate)
                        : 'Never played',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 8, bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: cs.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  fontSize: 11,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailTile(
    BuildContext context, {
    required String label,
    required String value,
    VoidCallback? onTap,
    bool isMonospace = false,
  }) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                      fontFamily: isMonospace ? 'monospace' : null,
                    ),
                  ),
                ),
                if (onTap != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(
                      Icons.copy_rounded,
                      size: 14,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
