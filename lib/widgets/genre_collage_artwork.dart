import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../data/models/genre_stat.dart';
import '../ui/shared/fast_artwork_widget.dart';

class GenreCollageArtwork extends StatelessWidget {
  final GenreStat genre;
  final double size;
  final double borderRadius;

  const GenreCollageArtwork({
    super.key,
    required this.genre,
    this.size = 80,
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final songs = genre.representativeSongs;

    Widget placeholder() {
      return Container(
        width: size,
        height: size,
        color: cs.surfaceContainerHighest,
        child: Center(
          child: Icon(
            Icons.category_rounded,
            size: size * 0.4,
            color: cs.primary,
          ),
        ),
      );
    }

    if (songs.isEmpty) {
      if (genre.representativeSong != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: FastArtworkWidget(
            id: genre.representativeSong!.albumId ?? genre.representativeSong!.id,
            type: ArtworkType.ALBUM,
            width: size,
            height: size,
            nullArtworkWidget: placeholder(),
          ),
        );
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: placeholder(),
      );
    }

    if (songs.length < 4) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: FastArtworkWidget(
          id: songs.first.albumId ?? songs.first.id,
          type: ArtworkType.ALBUM,
          width: size,
          height: size,
          nullArtworkWidget: placeholder(),
        ),
      );
    }

    // 2x2 collage
    final half = size / 2;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: Column(
          children: [
            Row(
              children: [
                _buildCell(songs[0], half, cs),
                _buildCell(songs[1], half, cs),
              ],
            ),
            Row(
              children: [
                _buildCell(songs[2], half, cs),
                _buildCell(songs[3], half, cs),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCell(SongModel song, double cellSize, ColorScheme cs) {
    return SizedBox(
      width: cellSize,
      height: cellSize,
      child: FastArtworkWidget(
        id: song.albumId ?? song.id,
        type: ArtworkType.ALBUM,
        width: cellSize,
        height: cellSize,
        nullArtworkWidget: Container(
          width: cellSize,
          height: cellSize,
          color: cs.surfaceContainerHighest,
          child: Icon(
            Icons.music_note_rounded,
            size: cellSize * 0.45,
            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}
