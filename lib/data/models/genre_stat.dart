import 'package:on_audio_query/on_audio_query.dart';

class GenreStat {
  GenreStat({required this.name, this.representativeSong});

  final String name;
  final Set<int> albumIds = <int>{};
  int trackCount = 0;
  int totalDurationMs = 0;
  SongModel? representativeSong;
  final List<SongModel> representativeSongs = <SongModel>[];

  int get albumCount => albumIds.length;
}

enum GenreSort {
  nameAsc,
  nameDesc,
  mostTracks,
  leastTracks,
  mostAlbums,
  leastAlbums,
}

