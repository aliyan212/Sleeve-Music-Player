import 'package:on_audio_query/on_audio_query.dart';


class IsolateData {
  final List<SongModel> songs;
  final List<AlbumModel> albums;
  final List<String> excludedFolders;
  final List<String> includedFolders;
  final bool filterShortTracks;

  IsolateData(
    this.songs,
    this.albums,
    this.excludedFolders,
    this.includedFolders,
    this.filterShortTracks,
  );
}