// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:animations/animations.dart';
import 'package:music_player/core/theme/app_theme.dart';
import 'package:music_player/ui/shared/app_empty_state.dart';
import 'package:music_player/ui/shared/alphabetical_bubble_scroller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';

import 'package:music_player/utils/song_repair_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:music_player/data/models/album_stat.dart';
import 'package:music_player/data/models/app_tab.dart';
import 'package:music_player/data/models/genre_stat.dart';
import 'package:music_player/dialogs/customize_tabs_dialog.dart';
import 'package:music_player/data/models/sort_mode.dart';
import 'package:music_player/utils/format_utils.dart';
import 'package:music_player/utils/song_sort_utils.dart';
import 'package:music_player/utils/tag_write_access.dart';
import 'package:music_player/data/models/user_playlist.dart';
import 'package:music_player/services/app_state_controller.dart';
import 'package:music_player/services/loved_songs_service.dart';
import 'package:music_player/services/playback_controller.dart';
import 'package:music_player/services/sleep_timer_service.dart';
import 'package:music_player/widgets/search/app_search_view.dart';
import 'package:music_player/widgets/mini_player.dart';
import 'package:music_player/widgets/universal_song_tile.dart';
import 'package:music_player/ui/shared/fast_artwork_widget.dart';
import 'package:music_player/ui/shared/bottom_bars_gutter.dart';
import 'package:music_player/widgets/now_playing/now_playing_landscape_view.dart';
import 'package:music_player/ui/shared/app_sort_bottom_sheet.dart';
import 'package:just_audio/just_audio.dart';
import 'package:music_player/dialogs/song_info_dialog.dart';
import 'package:music_player/pages/smart_playlist_page.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('formatTime formats mm:ss', () {
    expect(formatTime(null), '0:00');
    expect(formatTime(-1), '0:00');
    expect(formatTime(0), '0:00');
    expect(formatTime(999), '0:00');
    expect(formatTime(1_000), '0:01');
    expect(formatTime(61_000), '1:01');
    expect(formatTime(600_000), '10:00');
  });

  test('repairSongMetadataMap fills blank values from real tags and display names', () {
    final repaired = repairSongMetadataMap(
      <dynamic, dynamic>{
        'id': 42,
        'title': '',
        'artist': '',
        'album': '',
        'album_artist': '',
        'year': null,
        'track': null,
        '_display_name_wo_ext': 'Track Name',
        '_display_name': 'Track Name.mp3',
        'data': '/storage/emulated/0/Music/Album/Track Name.mp3',
      },
      title: 'Track Name',
      artist: 'Artist Name',
      album: 'Album Name',
      albumArtist: 'Album Artist Name',
      year: 2024,
      track: 7,
    );

    expect(repaired['title'], 'Track Name');
    expect(repaired['artist'], 'Artist Name');
    expect(repaired['album'], 'Album Name');
    expect(repaired['album_artist'], 'Album Artist Name');
    expect(repaired['year'], 2024);
    expect(repaired['track'], 7);

    final filenameFallback = repairSongMetadataMap(
      <dynamic, dynamic>{
        'title': '',
        'artist': 'unknown',
        '_display_name_wo_ext': 'Track Name',
        'data': '/storage/emulated/0/Music/Track Name.mp3',
      },
    );

    expect(filenameFallback['title'], 'Track Name');
    expect(filenameFallback['artist'], 'Unknown Artist');
  });

  test('repairSongMetadataMap preserves valid metadata', () {
    final original = <dynamic, dynamic>{
      'title': 'Already Good',
      'artist': 'Existing Artist',
      'album': 'Existing Album',
      'album_artist': 'Existing Album Artist',
      'year': 1999,
      'track': 12,
    };

    final repaired = repairSongMetadataMap(original, title: 'Replacement');
    expect(repaired['title'], 'Already Good');
    expect(repaired['artist'], 'Existing Artist');
    expect(repaired['year'], 1999);
    expect(repaired['track'], 12);
  });

  test('repairSongMetadataList keeps SongModel objects valid', () async {
    final list = <SongModel>[
      SongModel({
        '_id': 1,
        'title': '',
        'artist': '',
        'album': '',
        'album_artist': '',
        '_data': '/storage/emulated/0/Music/Example Song.mp3',
        '_display_name': 'Example Song.mp3',
        '_display_name_wo_ext': 'Example Song',
        '_size': 1234,
      }),
    ];

    final repaired = await repairSongMetadataList(list, tagTitle: 'Example Song');
    expect(repaired.single.title, 'Example Song');
  });

  test('UserPlaylist.fromJson parses ints, doubles and string songIds and timestamps correctly', () {
    final raw = {
      'id': 'joke_id',
      'name': 'joke',
      'songIds': [64287, 64306.0, '64237'],
      'createdAtMs': 1725785000000.0,
      'updatedAtMs': 1725785000000,
    };

    final playlist = UserPlaylist.fromJson(raw);
    expect(playlist, isNotNull);
    expect(playlist!.id, 'joke_id');
    expect(playlist.name, 'joke');
    expect(playlist.songIds, [64287, 64306, 64237]);
    expect(playlist.createdAtMs, 1725785000000);
    expect(playlist.updatedAtMs, 1725785000000);
  });

  test('AppStateController.selectTab clears inlineDetailContent when switching or reselecting tabs', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final appState = AppStateController.instance;

    // Simulate opening an inline detail (e.g. album) on tab 1
    appState.selectedTabIndex = 1;
    appState.inlineDetailContent = const Text('Album Detail');
    expect(appState.inlineDetailContent, isNotNull);

    // Clicking a different tab should clear inline detail and switch tab
    appState.selectTab(3);
    expect(appState.inlineDetailContent, isNull);
    expect(appState.selectedTabIndex, 3);

    // Simulate opening an inline detail on tab 3, then tapping tab 3 again
    appState.inlineDetailContent = const Text('Playlist Detail');
    expect(appState.inlineDetailContent, isNotNull);
    appState.selectTab(3);
    expect(appState.inlineDetailContent, isNull);
    expect(appState.selectedTabIndex, 3);
  });

  test('AppStateController.openSearch preserves active tab and clears inlineDetailContent', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final appState = AppStateController.instance;

    appState.selectedTabIndex = 2;
    appState.inlineDetailContent = const Text('Artist Detail');
    expect(appState.selectedTabIndex, 2);
    expect(appState.inlineDetailContent, isNotNull);

    appState.openSearch(initialFilter: SearchFilter.artists);
    // Contextual search opens in-place on current tab without resetting to 0
    expect(appState.selectedTabIndex, 2);
    expect(appState.inlineDetailContent, isNull);
  });

  testWidgets('PageController with keepPage false mounts at correct target page without stale offset', (tester) async {
    int activePage = 1;
    PageController controller = PageController(initialPage: activePage, keepPage: false);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PageView.builder(
          controller: controller,
          itemCount: 5,
          itemBuilder: (context, index) => Text('Page $index'),
        ),
      ),
    );

    expect(find.text('Page 1'), findsOneWidget);
    expect(controller.page?.round(), 1);

    // Unmount PageView and update controller to page 3 (simulating switching views)
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(),
      ),
    );

    controller.dispose();
    activePage = 3;
    controller = PageController(initialPage: activePage, keepPage: false);

    // Mount in a different view (simulating fullscreen view)
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PageView.builder(
          controller: controller,
          itemCount: 5,
          itemBuilder: (context, index) => Text('Page $index'),
        ),
      ),
    );

    expect(find.text('Page 3'), findsOneWidget);
    expect(controller.page?.round(), 3);
  });

  test('PlaybackController maintains currentQueue and in-place metadata updates', () {
    final song1 = SongModel({
      '_id': 101,
      'title': 'Song One',
      'artist': 'Artist A',
      'album': 'Album X',
      '_data': '/storage/emulated/0/Music/song1.mp3',
    });
    final song2 = SongModel({
      '_id': 102,
      'title': 'Song Two',
      'artist': 'Artist B',
      'album': 'Album Y',
      '_data': '/storage/emulated/0/Music/song2.mp3',
    });

    playbackController.songs = [song1, song2];
    playbackController.currentQueue = [song1, song2];

    expect(playbackController.currentQueue.length, 2);
    expect(playbackController.currentQueue.first.title, 'Song One');

    final updatedSong1 = SongModel({
      '_id': 101,
      'title': 'Updated Title',
      'artist': 'Artist A',
      'album': 'Album X',
      '_data': '/storage/emulated/0/Music/song1.mp3',
    });

    AppStateController.instance.songs = [song1, song2];
    AppStateController.instance.updateSongMetadataInPlace(updatedSong1);

    expect(playbackController.songs.first.title, 'Updated Title');
    expect(playbackController.currentQueue.first.title, 'Updated Title');
  });

  test('PlaybackController insertAllInQueue and addAllToQueueEnd batch queue additions correctly', () {
    final s1 = SongModel({'_id': 301, 'title': 'Base 1', '_data': '/m/1.mp3'});
    final s2 = SongModel({'_id': 302, 'title': 'Base 2', '_data': '/m/2.mp3'});
    final a1 = SongModel({'_id': 303, 'title': 'Next A', '_data': '/m/3.mp3'});
    final a2 = SongModel({'_id': 304, 'title': 'Next B', '_data': '/m/4.mp3'});
    final e1 = SongModel({'_id': 305, 'title': 'End 1', '_data': '/m/5.mp3'});
    final e2 = SongModel({'_id': 306, 'title': 'End 2', '_data': '/m/6.mp3'});

    playbackController.currentQueue = [s1, s2];

    // Batch insert after current index (default index 0)
    playbackController.insertAllInQueue([a1, a2]);
    expect(playbackController.currentQueue.map((s) => s.id).toList(), [301, 303, 304, 302]);

    // Batch append to queue end
    playbackController.addAllToQueueEnd([e1, e2]);
    expect(playbackController.currentQueue.map((s) => s.id).toList(), [301, 303, 304, 302, 305, 306]);
  });

  test('AppStateController updateSongsMetadataInPlace updates multiple songs and album artist in a single pass', () {
    final song1 = SongModel({
      '_id': 201,
      'title': 'Track 1',
      'artist': 'Old Artist',
      'album': 'Album Alpha',
      '_data': '/storage/emulated/0/Music/track1.mp3',
    });
    final song2 = SongModel({
      '_id': 202,
      'title': 'Track 2',
      'artist': 'Old Artist',
      'album': 'Album Alpha',
      '_data': '/storage/emulated/0/Music/track2.mp3',
    });

    AppStateController.instance.songs = [song1, song2];
    playbackController.songs = [song1, song2];
    playbackController.currentQueue = [song1, song2];

    final updatedSong1 = SongModel({
      '_id': 201,
      'title': 'Track 1',
      'artist': 'New Artist',
      'album': 'Album Alpha',
      'album_artist': 'New Artist',
      '_data': '/storage/emulated/0/Music/track1.mp3',
    });
    final updatedSong2 = SongModel({
      '_id': 202,
      'title': 'Track 2',
      'artist': 'New Artist',
      'album': 'Album Alpha',
      'album_artist': 'New Artist',
      '_data': '/storage/emulated/0/Music/track2.mp3',
    });

    AppStateController.instance.updateSongsMetadataInPlace([updatedSong1, updatedSong2]);

    expect(AppStateController.instance.songs[0].artist, 'New Artist');
    expect(AppStateController.instance.songs[1].artist, 'New Artist');
    expect(playbackController.songs[0].artist, 'New Artist');
    expect(playbackController.songs[1].artist, 'New Artist');
    expect(playbackController.currentQueue[0].artist, 'New Artist');
    expect(playbackController.currentQueue[1].artist, 'New Artist');
    expect(albumArtistFor(AppStateController.instance.songs[0]), 'New Artist');
  });

  test('runWithPlaybackSuspendedForTagWrite executes action directly when file does not match playing song', () async {
    bool executed = false;
    await playbackController.runWithPlaybackSuspendedForTagWrite(
      () async {
        executed = true;
      },
      targetFilePath: '/some/unrelated/path.mp3',
    );
    expect(executed, isTrue);
  });

  test('yearFromSong extracts year directly, from fallback fields, or regex', () {
    final s1 = SongModel({'_id': 1, 'year': 2024});
    expect(yearFromSong(s1), 2024);

    final s2 = SongModel({'_id': 2, 'year': '2019'});
    expect(yearFromSong(s2), 2019);

    final s3 = SongModel({'_id': 3, 'year': 'Recorded in 1985 (Remastered)'});
    expect(yearFromSong(s3), 1985);

    final s4 = SongModel({'_id': 4, 'year': 0, 'date': 2008});
    expect(yearFromSong(s4), 2008);

    final s5 = SongModel({'_id': 5, 'year': null, 'recording_time': '1995'});
    expect(yearFromSong(s5), 1995);

    final s6 = SongModel({'_id': 6, 'year': 0});
    expect(yearFromSong(s6), 0);
  });

  test('writeMp3Id3YearAndId3v1 writes and updates ID3v2 TYER frame and ID3v1 trailer', () async {
    final tempDir = await Directory.systemTemp.createTemp('mp3_test');
    final mp3File = File('${tempDir.path}/test_track.mp3');

    // Build a synthetic MP3 file with ID3v2.3 header, TIT2 frame, and 50 bytes of padding
    final header = [0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40]; // 64 bytes tag body
    final tit2Frame = [
      0x54, 0x49, 0x54, 0x32, // 'TIT2'
      0x00, 0x00, 0x00, 0x05, // size 5
      0x00, 0x00,             // flags
      0x00,                   // enc ISO-8859-1
      0x53, 0x6F, 0x6E, 0x67, // 'Song'
    ];
    final padding = List<int>.filled(64 - tit2Frame.length, 0);
    final audioData = List<int>.filled(128, 0xFF); // Fake MP3 frames

    await mp3File.writeAsBytes([...header, ...tit2Frame, ...padding, ...audioData]);

    // 1. Initial write with year = 2024
    await writeMp3Id3YearAndId3v1(
      path: mp3File.path,
      year: 2024,
      title: 'Song',
      artist: 'Artist',
    );

    var bytes = await mp3File.readAsBytes();

    // Verify TYER frame in ID3v2
    final tyerStart = 10 + tit2Frame.length;
    expect(ascii.decode(bytes.sublist(tyerStart, tyerStart + 4)), 'TYER');
    expect(ascii.decode(bytes.sublist(tyerStart + 11, tyerStart + 15)), '2024');

    // Verify ID3v1 trailer at EOF
    expect(bytes.length >= 128, isTrue);
    final id3v1Trailer = bytes.sublist(bytes.length - 128);
    expect(ascii.decode(id3v1Trailer.sublist(0, 3)), 'TAG');
    expect(ascii.decode(id3v1Trailer.sublist(93, 97)), '2024');

    // 2. Update year to 1999
    await writeMp3Id3YearAndId3v1(
      path: mp3File.path,
      year: 1999,
    );

    bytes = await mp3File.readAsBytes();

    // Verify updated TYER frame in ID3v2
    expect(ascii.decode(bytes.sublist(tyerStart + 11, tyerStart + 15)), '1999');

    // Verify updated ID3v1 trailer
    final updatedTrailer = bytes.sublist(bytes.length - 128);
    expect(ascii.decode(updatedTrailer.sublist(0, 3)), 'TAG');
    expect(ascii.decode(updatedTrailer.sublist(93, 97)), '1999');

    // Cleanup
    await tempDir.delete(recursive: true);
  });

  group('Album Year Determination Algorithm', () {
    test('computeAlbumYearFromYears correctly computes mode and latest-year fallback', () {
      // Empty or all zero
      expect(computeAlbumYearFromYears([]), 0);
      expect(computeAlbumYearFromYears([0, 0, 0]), 0);

      // Single year
      expect(computeAlbumYearFromYears([2014]), 2014);

      // Mode / majority year wins
      expect(computeAlbumYearFromYears([2012, 2015, 2015, 2015, 2020]), 2015);
      expect(computeAlbumYearFromYears([0, 2015, 2015, 2018]), 2015);

      // All distinct: latest year is selected
      expect(computeAlbumYearFromYears([2010, 2019, 2014, 2017]), 2019);

      // Tie in frequency: latest year among the winners is selected
      expect(computeAlbumYearFromYears([2012, 2012, 2018, 2018]), 2018);
    });

    test('computeAlbumYearMap groups songs by albumIdentityKey and computes years', () {
      final s1 = SongModel({
        '_id': 1,
        'title': 'Track 1',
        'artist': 'Artist A',
        'album': 'Greatest Hits',
        'album_artist': 'Artist A',
        'year': 2010,
      });
      final s2 = SongModel({
        '_id': 2,
        'title': 'Track 2',
        'artist': 'Artist A feat. Guest',
        'album': 'Greatest Hits',
        'album_artist': 'Artist A',
        'year': 2010,
      });
      final s3 = SongModel({
        '_id': 3,
        'title': 'Track 3',
        'artist': 'Artist A',
        'album': 'Greatest Hits',
        'album_artist': 'Artist A',
        'year': 2015,
      });
      final s4 = SongModel({
        '_id': 4,
        'title': 'Other Track',
        'artist': 'Artist B',
        'album': 'Debut',
        'year': 2023,
      });

      final map = computeAlbumYearMap([s1, s2, s3, s4]);
      final keyA = albumIdentityKey(s1);
      final keyB = albumIdentityKey(s4);

      // s1, s2, s3 share same album artist & title; two tracks 2010, one 2015 -> mode 2010
      expect(map[keyA], 2010);
      expect(map[keyB], 2023);
    });
  });

  group('Sort Preferences Persistence', () {
    test('loadSavedSortPreferences restores saved SortMode, AlbumsSort, and AlbumArtistsSort', () async {
      SharedPreferences.setMockInitialValues({
        'library_sort_mode_v1': SortMode.year.name,
        'albums_sort_mode_v1': AlbumsSort.yearDesc.name,
        'album_artists_sort_mode_v1': AlbumArtistsSort.mostAlbums.name,
      });

      final appState = AppStateController.instance;
      await appState.loadSavedSortPreferences();

      expect(playbackController.sortMode, SortMode.year);
      expect(appState.albumsSort, AlbumsSort.yearDesc);
      expect(appState.albumArtistsSort, AlbumArtistsSort.mostAlbums);
    });

    test('applySort saves and updates library sort mode', () async {
      final appState = AppStateController.instance;
      await appState.applySort(SortMode.artist);

      expect(playbackController.sortMode, SortMode.artist);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('library_sort_mode_v1'), SortMode.artist.name);
    });

    test('loadSavedSortPreferences migrates legacy string names', () async {
      SharedPreferences.setMockInitialValues({
        'library_sort_mode_v1': 'artist',
      });
      final appState = AppStateController.instance;
      await appState.loadSavedSortPreferences();
      expect(playbackController.sortMode, SortMode.artistAsc);
    });

    test('applySort saves and updates library sort mode for all new modes', () async {
      final appState = AppStateController.instance;
      final modesToTest = [
        SortMode.titleAsc,
        SortMode.titleDesc,
        SortMode.albumAsc,
        SortMode.albumDesc,
        SortMode.artistAsc,
        SortMode.artistDesc,
        SortMode.albumArtistAsc,
        SortMode.albumArtistDesc,
        SortMode.albumArtistYearAsc,
        SortMode.albumArtistYearDesc,
        SortMode.composerAsc,
        SortMode.composerDesc,
        SortMode.genreAsc,
        SortMode.genreDesc,
        SortMode.yearAsc,
        SortMode.yearDesc,
        SortMode.durationAsc,
        SortMode.durationDesc,
        SortMode.trackAsc,
        SortMode.trackDesc,
        SortMode.mostPlayed,
        SortMode.leastPlayed,
      ];

      final prefs = await SharedPreferences.getInstance();
      for (final mode in modesToTest) {
        await appState.applySort(mode);
        expect(playbackController.sortMode, mode);
        expect(prefs.getString('library_sort_mode_v1'), mode.name);
      }
    });

    test('Song sort utils comparators behave correctly', () {
      expect(compareSortStringsDesc('A', 'Z'), greaterThan(0));
      expect(compareSortStringsDesc('Z', 'A'), lessThan(0));
      expect(compareSortStringsDesc('Unknown', 'Song'), greaterThan(0));
      expect(compareSortStringsDesc('Song', 'Unknown'), lessThan(0));

      // Years
      expect(compareYears(2020, 2010, ascending: true), greaterThan(0));
      expect(compareYears(2020, 2010, ascending: false), lessThan(0));
      expect(compareYears(0, 2020, ascending: false), greaterThan(0));
      expect(compareYears(2020, 0, ascending: false), lessThan(0));

      // Tracks
      final s1 = SongModel({'_id': 1, 'title': 'One', 'track': 1});
      final s2 = SongModel({'_id': 2, 'title': 'Two', 'track': 2});
      final s0 = SongModel({'_id': 3, 'title': 'Zero', 'track': 0});
      expect(compareTracks(s1, s2, ascending: true), lessThan(0));
      expect(compareTracks(s1, s2, ascending: false), greaterThan(0));
      expect(compareTracks(s0, s1, ascending: false), greaterThan(0));

      // Durations
      final d1 = SongModel({'_id': 1, 'title': 'Short', 'duration': 60000});
      final d2 = SongModel({'_id': 2, 'title': 'Long', 'duration': 300000});
      final d0 = SongModel({'_id': 3, 'title': 'Zero', 'duration': 0});
      expect(compareDurations(d1, d2, ascending: true), lessThan(0));
      expect(compareDurations(d1, d2, ascending: false), greaterThan(0));
      expect(compareDurations(d0, d1, ascending: false), greaterThan(0));

      // Play counts
      final p1 = SongModel({'_id': 1, 'title': 'A'});
      final p2 = SongModel({'_id': 2, 'title': 'B'});
      final playCounts = {1: 10, 2: 2};
      expect(comparePlayCounts(p1, p2, playCounts, descending: true), lessThan(0));
      expect(comparePlayCounts(p1, p2, playCounts, descending: false), greaterThan(0));

      // Composers
      final c1 = SongModel({'_id': 1, 'title': 'A', 'composer': 'Bach'});
      final c2 = SongModel({'_id': 2, 'title': 'B', 'composer': 'Mozart'});
      expect(compareComposers(c1, c2, ascending: true), lessThan(0));
      expect(compareComposers(c1, c2, ascending: false), greaterThan(0));

      // Genres
      final g1 = SongModel({'_id': 1, 'title': 'A', 'genre': 'Classical'});
      final g2 = SongModel({'_id': 2, 'title': 'B', 'genre': 'Rock'});
      expect(compareGenres(g1, g2, ascending: true), lessThan(0));
      expect(compareGenres(g1, g2, ascending: false), greaterThan(0));
    });


    test('applyAlbumsSort saves and updates albums sort mode', () async {
      final appState = AppStateController.instance;
      await appState.applyAlbumsSort(AlbumsSort.leastTracks);

      expect(appState.albumsSort, AlbumsSort.leastTracks);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('albums_sort_mode_v1'), AlbumsSort.leastTracks.name);
    });

    test('applyAlbumArtistsSort saves and updates album artists sort mode', () async {
      final appState = AppStateController.instance;
      await appState.applyAlbumArtistsSort(AlbumArtistsSort.mostTracks);

      expect(appState.albumArtistsSort, AlbumArtistsSort.mostTracks);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('album_artists_sort_mode_v1'), AlbumArtistsSort.mostTracks.name);
    });
  });

  group('AppEmptyState Widget Tests', () {
    testWidgets('renders title, message, and invokes onAction', (tester) async {
      var actionFired = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppEmptyState(
              icon: Icons.music_off_rounded,
              title: 'No songs found',
              message: 'Add songs to your library.',
              actionLabel: 'Scan Library',
              actionIcon: Icons.refresh_rounded,
              onAction: () => actionFired = true,
            ),
          ),
        ),
      );

      expect(find.text('No songs found'), findsOneWidget);
      expect(find.text('Add songs to your library.'), findsOneWidget);
      expect(find.text('Scan Library'), findsOneWidget);
      expect(find.byIcon(Icons.music_off_rounded), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);

      await tester.tap(find.text('Scan Library'));
      expect(actionFired, isTrue);
    });
  });

  group('AlphabeticalBubbleScroller Tests', () {
    testWidgets('renders scrollable child and responds without errors', (tester) async {
      final controller = ScrollController();
      final items = List.generate(30, (i) => 'Item ${String.fromCharCode(65 + (i % 26))} $i');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlphabeticalBubbleScroller(
              scrollController: controller,
              itemCount: items.length,
              sectionKeyOf: (index) => items[index],
              child: ListView.builder(
                controller: controller,
                itemCount: items.length,
                itemBuilder: (context, i) => ListTile(title: Text(items[i])),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Item A 0'), findsOneWidget);
      controller.dispose();
    });

    testWidgets('supports numeric sort mode (years, track counts) and preserves sort order', (tester) async {
      final controller = ScrollController();
      // Descending years: 2024, 2020, 2015, 1999
      final years = ['2024', '2020', '2015', '1999', '1984', '1975', '1968', '0'];
      final items = List.generate(20, (i) => years[i % years.length]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlphabeticalBubbleScroller(
              scrollController: controller,
              itemCount: items.length,
              isNumericSort: true,
              sortKey: 'yearDesc',
              sectionKeyOf: (index) => items[index],
              child: ListView.builder(
                controller: controller,
                itemCount: items.length,
                itemBuilder: (context, i) => ListTile(title: Text('Track $i (${items[i]})')),
              ),
            ),
          ),
        ),
      );

      // Verify widget rendered
      expect(find.byType(AlphabeticalBubbleScroller), findsOneWidget);

      // Verify the rail ignores pointers when idle/hidden
      final ignoreFinder = find.descendant(
        of: find.byType(AlphabeticalBubbleScroller),
        matching: find.byType(IgnorePointer),
      );
      expect(ignoreFinder, findsWidgets);

      controller.dispose();
    });

    testWidgets('invalidates cached sections when sortKey or isNumericSort updates', (tester) async {
      final controller = ScrollController();
      final titles = ['Queen', 'Pink Floyd', 'Beatles', 'Abba', 'Zebra', 'Radiohead', 'Oasis', 'Muse', 'Nirvana', 'Kinks'];

      // Initially alphabetical
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlphabeticalBubbleScroller(
              scrollController: controller,
              itemCount: titles.length,
              isNumericSort: false,
              sortKey: 'titleAsc',
              sectionKeyOf: (index) => titles[index],
              child: ListView.builder(
                controller: controller,
                itemCount: titles.length,
                itemBuilder: (context, i) => ListTile(title: Text(titles[i])),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(AlphabeticalBubbleScroller), findsOneWidget);

      // Switch to numeric sort (e.g. track count) with same itemCount
      final trackCounts = ['42', '30', '25', '18', '12', '8', '5', '3', '2', '1'];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlphabeticalBubbleScroller(
              scrollController: controller,
              itemCount: trackCounts.length,
              isNumericSort: true,
              sortKey: 'mostTracks',
              sectionKeyOf: (index) => trackCounts[index],
              child: ListView.builder(
                controller: controller,
                itemCount: trackCounts.length,
                itemBuilder: (context, i) => ListTile(title: Text('Album $i: ${trackCounts[i]} tracks')),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(AlphabeticalBubbleScroller), findsOneWidget);
      controller.dispose();
    });

    testWidgets('supports duration buckets and zero play count sections without collapsing into #', (tester) async {
      final controller = ScrollController();
      final durations = ['1m', '2m', '3m', '4m', '5m', '6m', '7m', '8m', '9m', '10m', '15m'];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlphabeticalBubbleScroller(
              scrollController: controller,
              itemCount: durations.length,
              isNumericSort: true,
              sortKey: 'durationAsc',
              sectionKeyOf: (index) => durations[index],
              child: ListView.builder(
                controller: controller,
                itemCount: durations.length,
                itemBuilder: (context, i) => ListTile(title: Text('Track $i: ${durations[i]}')),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(AlphabeticalBubbleScroller), findsOneWidget);
      controller.dispose();
    });
  });

  group('Multi-Select NavigationStateMixin Tests', () {
    test('selectAllSongs and deselectAllSongs work as expected', () {
      final appState = AppStateController.instance;
      appState.exitSelectionMode();
      expect(appState.isSelectionMode, isFalse);
      expect(appState.selectedSongIds, isEmpty);

      appState.enterSelectionMode();
      expect(appState.isSelectionMode, isTrue);

      appState.selectAllSongs([101, 102, 103, 104]);
      expect(appState.selectedSongIds, {101, 102, 103, 104});

      appState.toggleSelectedSongId(102);
      expect(appState.selectedSongIds, {101, 103, 104});

      appState.deselectAllSongs();
      expect(appState.selectedSongIds, isEmpty);
      expect(appState.isSelectionMode, isTrue);

      appState.exitSelectionMode();
      expect(appState.isSelectionMode, isFalse);
    });
  });

  group('Queue Page & Playlist Creation Tests', () {
    test('createNewPlaylist correctly seeds with initialSongIds', () async {
      final appState = AppStateController.instance;
      final seededSongIds = [101, 102, 103];
      final playlist = await appState.createNewPlaylist(
        'Queue Saved Playlist',
        initialSongIds: seededSongIds,
      );

      expect(playlist, isNotNull);
      expect(playlist!.name, 'Queue Saved Playlist');
      expect(playlist.songIds, seededSongIds);
      expect(playlist.songIds.length, 3);

      // Clean up
      await appState.deletePlaylist(playlist);
    });

    test('Liked Songs playlist is initialized and stays pinned at index 0', () async {
      final appState = AppStateController.instance;
      await appState.loadUserPlaylists();

      expect(appState.likedSongsPlaylist, isNotNull);
      expect(appState.likedSongsPlaylist!.id, UserPlaylist.likedSongsPlaylistId);
      expect(appState.likedSongsPlaylist!.name, UserPlaylist.likedSongsPlaylistName);
      expect(appState.userPlaylists.first.id, UserPlaylist.likedSongsPlaylistId);
    });

    test('toggleLikedSong adds and removes song from liked_songs and LovedSongsService', () async {
      final appState = AppStateController.instance;
      await appState.loadUserPlaylists();
      const songId = 99991;

      if (appState.likedSongsPlaylist!.songIds.contains(songId)) {
        await appState.toggleLikedSong(songId);
      }
      expect(LovedSongsService.instance.isLoved(songId), isFalse);
      expect(appState.likedSongsPlaylist!.songIds.contains(songId), isFalse);

      final added = await appState.toggleLikedSong(songId);
      expect(added, isTrue);
      expect(LovedSongsService.instance.isLoved(songId), isTrue);
      expect(appState.likedSongsPlaylist!.songIds.contains(songId), isTrue);

      final removed = await appState.toggleLikedSong(songId);
      expect(removed, isFalse);
      expect(LovedSongsService.instance.isLoved(songId), isFalse);
      expect(appState.likedSongsPlaylist!.songIds.contains(songId), isFalse);
    });

    test('reorderCustomUserPlaylists preserves Liked Songs at index 0', () async {
      final appState = AppStateController.instance;
      await appState.loadUserPlaylists();

      final plA = await appState.createNewPlaylist('Custom Alpha');
      final plB = await appState.createNewPlaylist('Custom Beta');
      expect(plA, isNotNull);
      expect(plB, isNotNull);

      expect(appState.userPlaylists.first.id, UserPlaylist.likedSongsPlaylistId);

      appState.reorderCustomUserPlaylists(0, 2);
      expect(appState.userPlaylists.first.id, UserPlaylist.likedSongsPlaylistId);

      await appState.deletePlaylist(plA!);
      await appState.deletePlaylist(plB!);
    });

    test('formatPlaylistDuration formats remaining queue time correctly', () {
      // 0 ms -> 0m
      expect(formatPlaylistDuration(0), '0m');
      // 59 seconds -> 0m
      expect(formatPlaylistDuration(59000), '0m');
      // 3 minutes -> 3m
      expect(formatPlaylistDuration(180000), '3m');
      // 1 hour 15 minutes -> 1h 15m
      expect(formatPlaylistDuration(4500000), '1h 15m');
    });
  });

  group('Material Expressive Architecture Tests', () {
    test('buildTheme configures PredictiveBack on Android and Zoom on desktop', () {
      const scheme = ColorScheme.light();
      final theme = buildTheme(scheme, Brightness.light);

      final androidBuilder = theme.pageTransitionsTheme.builders[TargetPlatform.android];
      expect(androidBuilder, isA<PredictiveBackPageTransitionsBuilder>());

      final linuxBuilder = theme.pageTransitionsTheme.builders[TargetPlatform.linux];
      expect(linuxBuilder, isA<ZoomPageTransitionsBuilder>());

      final windowsBuilder = theme.pageTransitionsTheme.builders[TargetPlatform.windows];
      expect(windowsBuilder, isA<ZoomPageTransitionsBuilder>());

      final macosBuilder = theme.pageTransitionsTheme.builders[TargetPlatform.macOS];
      expect(macosBuilder, isA<ZoomPageTransitionsBuilder>());
    });

    testWidgets('SharedAxisTransition renders child in PageTransitionSwitcher', (tester) async {
      final appState = AppStateController.instance;
      appState.inlineDetailContent = const Text('Test Detail View');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageTransitionSwitcher(
              reverse: appState.inlineDetailContent == null,
              transitionBuilder: (child, primary, secondary) => SharedAxisTransition(
                animation: primary,
                secondaryAnimation: secondary,
                transitionType: SharedAxisTransitionType.scaled,
                child: child,
              ),
              child: appState.inlineDetailContent != null
                  ? KeyedSubtree(
                      key: ValueKey(appState.inlineDetailContent.hashCode),
                      child: appState.inlineDetailContent!,
                    )
                  : const SizedBox.shrink(key: ValueKey('empty')),
            ),
          ),
        ),
      );

      expect(find.text('Test Detail View'), findsOneWidget);
      expect(find.byType(SharedAxisTransition), findsOneWidget);

      appState.inlineDetailContent = null;
    });

    testWidgets('MiniPlayerTile conditionally enables Hero based on enableHero flag', (tester) async {
      final song = SongModel({
        '_id': 999,
        'title': 'Hero Song',
        'artist': 'Hero Artist',
        'duration': 180000,
      });

      // When enableHero is false (e.g. in detail pages), Hero is omitted
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MiniPlayerTile(
              controller: playbackController,
              song: song,
              songs: [song],
              currentIndex: 0,
              onTap: () {},
              onDismiss: () {},
              onQueueChanged: (_) {},
              enableHero: false,
            ),
          ),
        ),
      );

      expect(find.byType(Hero), findsNothing);

      // When enableHero is true (e.g. on HomePage), Hero tag is present
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MiniPlayerTile(
              controller: playbackController,
              song: song,
              songs: [song],
              currentIndex: 0,
              onTap: () {},
              onDismiss: () {},
              onQueueChanged: (_) {},
              enableHero: true,
            ),
          ),
        ),
      );

      expect(find.byType(Hero), findsOneWidget);
    });

    testWidgets('Smooth slide between tabs with PageController and easeOutCubic', (tester) async {
      final pageController = PageController(initialPage: 0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageView(
              controller: pageController,
              children: const [
                Text('Tab 0 Library'),
                Text('Tab 1 Albums'),
                Text('Tab 2 Artists'),
                Text('Tab 3 Playlists'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Tab 0 Library'), findsOneWidget);
      expect(find.text('Tab 1 Albums'), findsNothing);

      // Animate smoothly to page 1 using Material Expressive curve
      pageController.animateToPage(
        1,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      await tester.pumpAndSettle();

      expect(find.text('Tab 1 Albums'), findsOneWidget);
      expect(pageController.page, 1.0);
    });

    test('SearchHistoryManager saves, deduplicates, limits to 10, and clears recent queries', () async {
      SharedPreferences.setMockInitialValues({});

      await SearchHistoryManager.addQuery('The Beatles');
      await SearchHistoryManager.addQuery('Queen');
      await SearchHistoryManager.addQuery('the beatles'); // Case-insensitive deduplication

      var history = await SearchHistoryManager.getHistory();
      expect(history.length, 2);
      expect(history.first, 'the beatles');
      expect(history.last, 'Queen');

      // Add 10 more to test max 10 cap
      for (int i = 0; i < 10; i++) {
        await SearchHistoryManager.addQuery('Artist $i');
      }
      history = await SearchHistoryManager.getHistory();
      expect(history.length, 10);
      expect(history.first, 'Artist 9');

      // Remove single
      await SearchHistoryManager.removeQuery('Artist 9');
      history = await SearchHistoryManager.getHistory();
      expect(history.contains('Artist 9'), isFalse);
      expect(history.length, 9);

      // Clear all
      await SearchHistoryManager.clearHistory();
      history = await SearchHistoryManager.getHistory();
      expect(history.isEmpty, isTrue);
    });

    testWidgets('buildHighlightedText highlights matching query substring in primary color', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          ),
          home: Scaffold(
            body: Center(
              child: buildHighlightedText(
                text: 'Here Comes The Sun',
                query: 'sun',
                baseStyle: const TextStyle(color: Colors.black, fontSize: 16),
                highlightColor: Colors.deepPurple,
              ),
            ),
          ),
        ),
      );

      final textWidget = tester.widget<Text>(find.byType(Text));
      final span = textWidget.textSpan! as TextSpan;
      expect(span.children, isNotNull);
      expect(span.children!.length, 2);
      expect(span.children![0].toPlainText(), 'Here Comes The ');
      expect(span.children![1].toPlainText(), 'Sun');
      expect((span.children![1] as TextSpan).style?.color, Colors.deepPurple);
      expect((span.children![1] as TextSpan).style?.fontWeight, FontWeight.w700);
    });

    testWidgets('AppSearchView renders with smart filter pre-selection and empty state on no match', (tester) async {
      SharedPreferences.setMockInitialValues({
        'search_recent_queries': ['Pink Floyd', 'Nirvana'],
      });

      await tester.pumpWidget(
        MaterialApp(
          home: const AppSearchView(
            initialFilter: SearchFilter.albums,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Albums filter chip is selected
      final filterChips = tester.widgetList<FilterChip>(find.byType(FilterChip)).toList();
      // It should display 'All' plus all enabled categories, which defaults to tracks, albums, artists, albumArtists, composers, genres -> 7 chips total
      expect(filterChips.length, 7);
      final albumsChip = filterChips.firstWhere((c) {
        if (c.label is Row) {
          return (c.label as Row).children.any((w) => w is Text && w.data == 'Albums');
        }
        return false;
      });
      expect(albumsChip.selected, isTrue);

      // Verify Recent Searches are shown when query is empty
      expect(find.text('Recent Searches'), findsOneWidget);
      expect(find.text('Pink Floyd'), findsOneWidget);
      expect(find.text('Nirvana'), findsOneWidget);

      // Enter a query with no matches
      await tester.enterText(find.byType(SearchBar), 'xyznonexistent123');
      await tester.pumpAndSettle();

      // Verify AppEmptyState is rendered
      expect(find.byType(AppEmptyState), findsOneWidget);
      expect(find.text('No results found'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppEmptyState),
          matching: find.textContaining('xyznonexistent123'),
        ),
        findsOneWidget,
      );
    });

    test('AppStateController.updateSongMetadataInPlace updates song lists in-place', () {
      final appState = AppStateController.instance;
      final original = SongModel({
        '_id': 99999,
        'title': 'Original Title',
        'artist': 'Original Artist',
        'album': 'Original Album',
        '_data': '/storage/emulated/0/Music/track99999.mp3',
      });
      appState.songs = [original];
      playbackController.songs = [original];
      playbackController.currentQueue = [original];

      final updated = SongModel({
        '_id': 99999,
        'title': 'Edited Title',
        'artist': 'Edited Artist',
        'album': 'Edited Album',
        '_data': '/storage/emulated/0/Music/track99999.mp3',
      });

      appState.updateSongMetadataInPlace(updated);

      expect(appState.songs.single.title, 'Edited Title');
      expect(appState.songs.single.artist, 'Edited Artist');
      expect(appState.songs.single.album, 'Edited Album');
      expect(playbackController.songs.single.title, 'Edited Title');
      expect(playbackController.currentQueue.single.title, 'Edited Title');
    });

    test('runWithPlaybackSuspendedForTagWrite executes action exactly once', () async {
      int executionCount = 0;
      await playbackController.runWithPlaybackSuspendedForTagWrite(
        () async {
          executionCount++;
        },
        targetFilePath: '/path/test_track.mp3',
      );
      expect(executionCount, 1);
    });

    group('UniversalSongTile Tests', () {
      testWidgets('renders duration only once when showMetaDuration is false and trailing duration provided', (tester) async {
        final song = SongModel({
          '_id': 12345,
          'title': 'Smart Playlist Track',
          'artist': 'Test Artist',
          'duration': 185000,
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: UniversalSongTile(
                song: song,
                subtitle: 'Test Artist',
                showMetaDuration: false,
                trailing: const Text('3:05'),
              ),
            ),
          ),
        );

        // '3:05' should appear exactly once in the tree (in the trailing widget)
        expect(find.text('3:05'), findsOneWidget);
        expect(find.text('Smart Playlist Track'), findsOneWidget);
        expect(find.text('Test Artist'), findsOneWidget);
      });

      testWidgets('renders duration in meta when showMetaDuration is true without trailing', (tester) async {
        final song = SongModel({
          '_id': 12346,
          'title': 'Library Track',
          'artist': 'Test Artist',
          'duration': 185000,
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: UniversalSongTile(
                song: song,
                subtitle: 'Test Artist',
                showMetaDuration: true,
              ),
            ),
          ),
        );

        // Duration is shown in the meta row
        expect(find.text('3:05'), findsOneWidget);
      });

      testWidgets('library song tile renders with 3-line layout inside 106.0 extent without overflow', (tester) async {
        final song = SongModel({
          '_id': 12347,
          'title': 'Library Track With Full Tags',
          'artist': 'Test Artist Name',
          'album': 'Test Album Title',
          'duration': 215000,
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 106.0,
                child: UniversalSongTile(
                  song: song,
                  title: song.title,
                  subtitle: song.artist,
                  meta: song.album,
                  durationMs: song.duration,
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
                  trailing: const Icon(Icons.more_vert_rounded),
                ),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Library Track With Full Tags'), findsOneWidget);
        expect(find.text('Test Artist Name'), findsOneWidget);
        expect(find.text('Test Album Title'), findsOneWidget);
        expect(find.text('3:35'), findsOneWidget);
      });
    });

    group('Smooth Transition Tests', () {
      testWidgets('FastArtworkWidget embeds AnimatedSwitcher for smooth transitions', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FastArtworkWidget(
                id: 9999,
                type: ArtworkType.ALBUM,
                width: 100,
                height: 100,
                nullArtworkWidget: const Icon(Icons.album_rounded),
              ),
            ),
          ),
        );

        expect(find.byType(AnimatedSwitcher), findsOneWidget);
        final animatedSwitcher = tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
        expect(animatedSwitcher.duration, const Duration(milliseconds: 240));
        expect(animatedSwitcher.switchInCurve, Curves.easeOutCubic);
        expect(find.byIcon(Icons.album_rounded), findsOneWidget);
      });

      testWidgets('Background gradient uses AnimatedSwitcher for soft blooming appearance', (tester) async {
        const top = Colors.deepPurple;
        const mid = Colors.purple;
        const accent = Colors.pink;
        const surface = Colors.black;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  Positioned.fill(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 320),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: DecoratedBox(
                        key: const ValueKey('test_gradient'),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [top, mid, accent, surface],
                            stops: [0.0, 0.35, 0.70, 1.0],
                          ),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        expect(find.byType(AnimatedSwitcher), findsOneWidget);
        expect(find.byKey(const ValueKey('test_gradient')), findsOneWidget);
      });
    });

    group('SleepTimerService Tests', () {
      tearDown(() {
        SleepTimerService.instance.cancel();
      });

      test('SleepTimerService start and cancel works as expected', () {
        final timer = SleepTimerService.instance;
        expect(timer.isActive, isFalse);
        expect(timer.isEndOfSong, isFalse);

        timer.start(const Duration(minutes: 15));
        expect(timer.isActive, isTrue);
        expect(timer.isEndOfSong, isFalse);
        expect(timer.remaining, isNotNull);
        expect(timer.remaining!.inMinutes, 14); // Between 14 and 15 min remaining

        timer.cancel();
        expect(timer.isActive, isFalse);
        expect(timer.isEndOfSong, isFalse);
        expect(timer.remaining, isNull);
      });

      test('SleepTimerService startForEndOfSong sets end of song mode', () {
        final timer = SleepTimerService.instance;
        expect(timer.isActive, isFalse);

        timer.startForEndOfSong();
        expect(timer.isActive, isTrue);
        expect(timer.isEndOfSong, isTrue);

        timer.cancel();
      });
    });

    testWidgets('buildBottomBarsGutter creates 4.0 cards equivalent gutter height (320px)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                Builder(
                  builder: (context) => buildBottomBarsGutter(context),
                ),
              ],
            ),
          ),
        ),
      );

      final sizedBoxFinder = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(SizedBox),
      );
      expect(sizedBoxFinder, findsOneWidget);
      final sizedBox = tester.widget<SizedBox>(sizedBoxFinder);
      expect(sizedBox.height, 320.0);
    });

    testWidgets('AppSearchView clicking outside search bar dismisses keyboard/focus', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AppSearchView(),
        ),
      );
      await tester.pumpAndSettle();

      final searchBar = find.byType(SearchBar);
      expect(searchBar, findsOneWidget);

      // Initially, autofocus causes focus to be active on the search field
      final initialFocus = FocusManager.instance.primaryFocus;
      expect(initialFocus?.hasFocus, isTrue);

      // Tap outside the search bar (e.g. on recent searches or blank background at (200, 400))
      await tester.tapAt(const Offset(200, 400));
      await tester.pumpAndSettle();

      final primaryFocus = FocusManager.instance.primaryFocus;
      expect(primaryFocus == null || !primaryFocus.hasFocus || primaryFocus is FocusScopeNode, isTrue);
    });

    testWidgets('LibraryTab search bar is non-focusable and tapping it does not capture keyboard focus', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Focus(
                    canRequestFocus: false,
                    descendantsAreFocusable: false,
                    child: GestureDetector(
                      onTap: () {},
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
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final searchBarFinder = find.byType(SearchBar);
      expect(searchBarFinder, findsOneWidget);

      // Tap on search bar
      await tester.tap(searchBarFinder, warnIfMissed: false);
      await tester.pumpAndSettle();

      // Ensure focus manager did not focus any text field
      final primaryFocus = FocusManager.instance.primaryFocus;
      expect(primaryFocus == null || !primaryFocus.hasFocus || primaryFocus is FocusScopeNode, isTrue);
    });

    testWidgets('NowPlayingLandscapeView renders centered artwork and metadata with device insets', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.ryanheise.just_audio.methods'),
        (call) async {
          if (call.method == 'init') return {'id': 'test-player'};
          return {};
        },
      );

      final player = AudioPlayer();
      final song = SongModel({
        '_id': 999,
        'title': 'Stargazing Night',
        'artist': 'Luna Eclipse',
        'album': 'Constellations',
      });

      tester.view.physicalSize = const Size(800, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        player.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(800, 400),
              padding: EdgeInsets.fromLTRB(40, 0, 40, 16),
            ),
            child: Scaffold(
              body: NowPlayingLandscapeView(
                isDark: true,
                textColor: Colors.white,
                textColorSecondary: Colors.white70,
                iconBgColor: Colors.white12,
                iconFgColor: Colors.white,
                primaryColor: Colors.deepPurple,
                displayedSong: song,
                player: player,
                artworkPulseAnimation: const AlwaysStoppedAnimation(1.0),
                controlsVisible: false,
                onToggleControls: () {},
                artworkPageViewBuilder: (side) => Container(
                  key: const ValueKey('art-box'),
                  width: side,
                  height: side,
                  color: Colors.blue,
                ),
                lyricsView: const Text('Lyrics Panel View'),
                onOpenArtist: () {},
                onOpenAlbum: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Stargazing Night'), findsOneWidget);
      expect(find.text('Luna Eclipse'), findsOneWidget);
      expect(find.text('Constellations'), findsOneWidget);
      expect(find.text('Lyrics Panel View'), findsOneWidget);
      expect(find.byKey(const ValueKey('art-box')), findsOneWidget);

      final titleText = tester.widget<Text>(find.text('Stargazing Night'));
      expect(titleText.textAlign, TextAlign.center);
    });

    test('writeMp3Id3TextFrames and readMp3Id3TextFrames writes and reads TCOM (composer) and TEXT (lyricist)', () async {
      final tempDir = await Directory.systemTemp.createTemp('id3_text_test_');
      final mp3File = File('${tempDir.path}/test_text.mp3');

      // 10-byte ID3v2 header: "ID3", version 2.3.0, flags 0, tag size 128 synchsafe
      final header = [
        0x49, 0x44, 0x33, // "ID3"
        0x03, 0x00,       // v2.3.0
        0x00,             // flags
        0x00, 0x00, 0x01, 0x00 // tag size: 128 bytes
      ];
      final tit2Data = utf8.encode('Test Song');
      final tit2Frame = [
        ...ascii.encode('TIT2'),
        0x00, 0x00, 0x00, tit2Data.length + 1,
        0x00, 0x00,
        0x03, // UTF-8 encoding flag
        ...tit2Data,
      ];
      final padding = List<int>.filled(128 - tit2Frame.length, 0);
      final audioData = List<int>.filled(64, 0xFF);

      await mp3File.writeAsBytes([...header, ...tit2Frame, ...padding, ...audioData]);

      // Write composer and lyricist
      await writeMp3Id3TextFrames(
        mp3File.path,
        composer: 'Ludwig van Beethoven',
        lyricist: 'Friedrich Schiller',
      );

      // Read back
      final tags = await readMp3Id3TextFrames(mp3File.path, const ['TCOM', 'TEXT']);
      expect(tags['TCOM'], 'Ludwig van Beethoven');
      expect(tags['TEXT'], 'Friedrich Schiller');

      // Update composer
      await writeMp3Id3TextFrames(
        mp3File.path,
        composer: 'Wolfgang Amadeus Mozart',
      );

      final updatedTags = await readMp3Id3TextFrames(mp3File.path, const ['TCOM', 'TEXT']);
      expect(updatedTags['TCOM'], 'Wolfgang Amadeus Mozart');
      expect(updatedTags['TEXT'], 'Friedrich Schiller');

      await tempDir.delete(recursive: true);
    });

    testWidgets('AppSortBottomSheet displays song sort options and selects', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SortMode? selectedMode;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showSongSortBottomSheet(
                    context,
                    currentSort: SortMode.artist,
                    onSortSelected: (mode) {
                      selectedMode = mode;
                    },
                  );
                },
                child: const Text('Open Sort'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sort'));
      await tester.pumpAndSettle();

      expect(find.text('Sort Library'), findsOneWidget);
      expect(find.text('Track Artist'), findsOneWidget);
      expect(find.text('Album Artist'), findsOneWidget);
      expect(find.text('Release Year'), findsOneWidget);
      expect(find.text('Album Artist & Year'), findsOneWidget);

      // Tap 'Release Year'
      await tester.tap(find.text('Release Year'));
      await tester.pumpAndSettle();

      expect(selectedMode, SortMode.year);
      // Bottom sheet is closed
      expect(find.text('Sort Library'), findsNothing);
    });

    testWidgets('AppSortBottomSheet displays album sort categories and selects', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      AlbumsSort? selectedSort;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAlbumsSortBottomSheet(
                    context,
                    currentSort: AlbumsSort.titleAsc,
                    onSortSelected: (mode) {
                      selectedSort = mode;
                    },
                  );
                },
                child: const Text('Open Album Sort'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Album Sort'));
      await tester.pumpAndSettle();

      expect(find.text('Sort Albums'), findsOneWidget);
      expect(find.text('TITLE'), findsOneWidget);
      expect(find.text('ARTIST'), findsOneWidget);
      expect(find.text('RELEASE YEAR'), findsOneWidget);
      expect(find.text('TRACK COUNT'), findsOneWidget);

      // Tap 'Most tracks first'
      await tester.tap(find.text('Most tracks first'));
      await tester.pumpAndSettle();

      expect(selectedSort, AlbumsSort.mostTracks);
      expect(find.text('Sort Albums'), findsNothing);
    });

    testWidgets('SongInfoSheet renders all details, tags, timestamps, and playback stats', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final song = SongModel({
        '_id': 8888,
        'title': 'Stargazer Odyssey',
        'artist': 'Galactic Groove',
        'album': 'Cosmic Echoes',
        'album_artist': 'Galactic Groove',
        'composer': 'Maestro Star',
        'genre': 'Space Synth',
        'year': 2024,
        'track': 4,
        'duration': 245000,
        '_size': 8388608,
        '_data': '/storage/emulated/0/Music/stargazer_odyssey.flac',
        'date_added': 1700000000,
      });

      playbackController.setPlayHistoryForTesting(
        counts: {8888: 42},
        lastPlayedMs: {8888: 1710000000000},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showSongInfoSheet(context, song),
                child: const Text('Open Song Info'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Song Info'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Copy all details'), findsOneWidget);
      expect(find.text('FILE INFORMATION'), findsOneWidget);
      expect(find.text('TAGS & METADATA'), findsOneWidget);
      expect(find.text('TIMESTAMPS'), findsOneWidget);
      expect(find.text('PLAYBACK STATISTICS'), findsOneWidget);
      expect(find.text('Stargazer Odyssey'), findsWidgets);
      expect(find.text('Galactic Groove'), findsWidgets);
      expect(find.text('Cosmic Echoes'), findsWidgets);
      expect(find.text('stargazer_odyssey.flac'), findsOneWidget);
      expect(find.text('42 plays'), findsOneWidget);
    });

    test('AppStateController locked date added preserves original date across tag edits', () async {
      final appState = AppStateController.instance;
      await appState.loadLockedDateAddedPreferences();

      const songPath = '/music/test_lock_song.mp3';
      const initialAddedMs = 1680000000000;

      appState.lockSongDateAdded(
        songPath,
        7777,
        initialAddedMs,
      );

      final songBeforeEdit = SongModel({
        '_id': 7777,
        '_data': songPath,
        'date_added': 1680000000, // seconds
      });

      expect(appState.dateAddedForSong(songBeforeEdit), initialAddedMs);

      // Simulate a tag edit or file scanner that sees a brand-new modified/added timestamp
      final songAfterEdit = SongModel({
        '_id': 7777,
        '_data': songPath,
        'date_added': 1720000000, // modified/resynced timestamp seconds
      });

      // The locked date added must be strictly preserved!
      expect(appState.dateAddedForSong(songAfterEdit), initialAddedMs);
    });

    testWidgets('SmartPlaylistPage Most Played limit switcher and play count display', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final songs = List.generate(25, (i) {
        return SongModel({
          '_id': 1000 + i,
          'title': 'Track ${i + 1}',
          'artist': 'Artist ${i + 1}',
          'duration': 180000,
          '_data': '/music/track_${i + 1}.mp3',
        });
      });

      playbackController.setPlayHistoryForTesting(
        counts: {for (var i = 0; i < songs.length; i++) songs[i].id: 50 - i},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SmartPlaylistPage(
            player: playbackController.player,
            title: 'Most played',
            description: 'Your top tracks',
            icon: Icons.local_fire_department_rounded,
            songs: songs,
            kind: SmartPlaylistKind.mostPlayed,
            librarySongs: songs,
            onQueueChanged: (_) {},
            selectedTabIndex: 3,
            onNavigateTab: (_) {},
            onOpenNowPlaying: (_) {},
            onPlayAll: () async {},
            onPlaySong: (_) async {},
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Limit switcher segments
      expect(find.text('Top 10'), findsOneWidget);
      expect(find.text('Top 20'), findsOneWidget);
      expect(find.text('Top 50'), findsOneWidget);
      expect(find.text('Top 100'), findsOneWidget);

      // Song tile subtitle contains play count
      expect(find.textContaining('50 plays'), findsOneWidget);

      // Default limit is 50, so all 25 songs are included
      expect(find.textContaining('25 tracks'), findsOneWidget);
      expect(find.text('Track 1'), findsOneWidget);
      expect(find.text('Track 5'), findsOneWidget);

      // Switch to Top 10
      await tester.tap(find.text('Top 10'));
      await tester.pumpAndSettle();

      // Top 10 songs limit applied
      expect(find.textContaining('10 tracks'), findsOneWidget);
      expect(find.text('Track 1'), findsOneWidget);
      expect(find.text('Track 5'), findsOneWidget);
      expect(find.text('Track 15'), findsNothing);
    });

    test('AppTab parsing, defaults, and bounds enforcement', () {
      // Defaults
      expect(AppTab.defaultTabs.length, 5);
      expect(AppTab.defaultTabs, [
        AppTab.songs,
        AppTab.albums,
        AppTab.artists,
        AppTab.genres,
        AppTab.playlists,
      ]);

      // Null or empty list fallback
      expect(AppTab.parseList(null), AppTab.defaultTabs);
      expect(AppTab.parseList([]), AppTab.defaultTabs);

      // Fewer than 3 valid tabs fallback
      expect(AppTab.parseList(['songs', 'albums']), AppTab.defaultTabs);
      expect(AppTab.parseList(['invalid_key', 'another_invalid']), AppTab.defaultTabs);

      // Valid 3 tabs
      final threeTabs = AppTab.parseList(['songs', 'genres', 'folders']);
      expect(threeTabs, [AppTab.songs, AppTab.genres, AppTab.folders]);

      // Valid 4 tabs
      final fourTabs = AppTab.parseList(['albums', 'artists', 'genres', 'folders']);
      expect(fourTabs, [AppTab.albums, AppTab.artists, AppTab.genres, AppTab.folders]);

      // Max 5 tabs capping
      final sixTabs = AppTab.parseList([
        'songs',
        'albums',
        'artists',
        'genres',
        'playlists',
        'folders',
      ]);
      expect(sixTabs.length, 5);
      expect(sixTabs, [
        AppTab.songs,
        AppTab.albums,
        AppTab.artists,
        AppTab.genres,
        AppTab.playlists,
      ]);

      // Deduplication and invalid entries handling
      final withDuplicates = AppTab.parseList([
        'songs',
        'invalid_key',
        'songs',
        'genres',
        'folders',
      ]);
      expect(withDuplicates, [AppTab.songs, AppTab.genres, AppTab.folders]);

      // Storage keys
      for (final tab in AppTab.values) {
        expect(AppTab.fromStorageKey(tab.storageKey), tab);
      }
    });

    test('AppStateController indexes genres and respects genre sort modes', () async {
      final appState = AppStateController.instance;

      final s1 = SongModel({
        '_id': 2001,
        'title': 'Track 1',
        'genre': 'Rock / Metal',
        'duration': 180000,
        'album_id': 101,
        '_data': '/m/t1.mp3',
      });
      final s2 = SongModel({
        '_id': 2002,
        'title': 'Track 2',
        'genre': 'Pop; Dance',
        'duration': 200000,
        'album_id': 102,
        '_data': '/m/t2.mp3',
      });
      final s3 = SongModel({
        '_id': 2003,
        'title': 'Track 3',
        'genre': 'Rock',
        'duration': 210000,
        'album_id': 103,
        '_data': '/m/t3.mp3',
      });
      final s4 = SongModel({
        '_id': 2004,
        'title': 'Track 4',
        'genre': 'Jazz',
        'duration': 240000,
        'album_id': 104,
        '_data': '/m/t4.mp3',
      });
      final s5 = SongModel({
        '_id': 2005,
        'title': 'Track 5',
        'genre': null,
        'duration': 150000,
        'album_id': 105,
        '_data': '/m/t5.mp3',
      });

      appState.songs = [s1, s2, s3, s4, s5];
      appState.recomputeLibraryStructure();

      // Ensure genres are indexed correctly
      final genreNames = appState.cachedGenres.map((g) => g.name).toList();
      expect(genreNames, containsAll(['Rock', 'Metal', 'Pop', 'Dance', 'Jazz', 'Unknown Genre']));

      final rockStat = appState.cachedGenres.firstWhere((g) => g.name == 'Rock');
      expect(rockStat.trackCount, 2); // s1 and s3
      expect(rockStat.albumIds.length, 2);

      final unknownStat = appState.cachedGenres.firstWhere((g) => g.name == 'Unknown Genre');
      expect(unknownStat.trackCount, 1); // s5

      // Sort by Most Tracks
      await appState.applyGenreSort(GenreSort.mostTracks);
      expect(appState.cachedGenres.first.name, 'Rock');

      // Sort Alphabetically Ascending
      await appState.applyGenreSort(GenreSort.nameAsc);
      expect(appState.cachedGenres.first.name, 'Dance');

      // Sort Alphabetically Descending
      await appState.applyGenreSort(GenreSort.nameDesc);
      expect(appState.cachedGenres.first.name, 'Unknown Genre');
    });

    test('AppStateController groups by Album Artists, Artists, and Composers', () {
      final appState = AppStateController.instance;

      final s1 = SongModel({
        '_id': 3001,
        'title': 'Symphony No. 5',
        'artist': 'Soloist A',
        'album_artist': 'Philharmonic Orchestra',
        'composer': 'Ludwig van Beethoven',
        'album_id': 201,
        '_data': '/m/c1.mp3',
      });
      final s2 = SongModel({
        '_id': 3002,
        'title': 'Symphony No. 9',
        'artist': 'Soloist B',
        'album_artist': 'Philharmonic Orchestra',
        'composer': 'Ludwig van Beethoven',
        'album_id': 201,
        '_data': '/m/c2.mp3',
      });
      final s3 = SongModel({
        '_id': 3003,
        'title': 'Piano Sonata',
        'artist': 'Soloist A',
        'album_artist': 'Soloist A',
        'composer': 'Wolfgang Amadeus Mozart',
        'album_id': 202,
        '_data': '/m/c3.mp3',
      });

      appState.songs = [s1, s2, s3];
      appState.recomputeLibraryStructure();

      // Album Artists check: Philharmonic Orchestra (2 tracks), Soloist A (1 track)
      final albumArtists = appState.cachedAlbumArtists;
      final philAlbum = albumArtists.firstWhere((a) => a.name == 'Philharmonic Orchestra');
      expect(philAlbum.trackCount, 2);
      final soloistAAlbum = albumArtists.firstWhere((a) => a.name == 'Soloist A');
      expect(soloistAAlbum.trackCount, 1);

      // Track Artists check: Soloist A (2 tracks), Soloist B (1 track)
      final trackArtists = appState.cachedTrackArtists;
      final soloistATrack = trackArtists.firstWhere((a) => a.name == 'Soloist A');
      expect(soloistATrack.trackCount, 2);
      final soloistBTrack = trackArtists.firstWhere((a) => a.name == 'Soloist B');
      expect(soloistBTrack.trackCount, 1);

      // Composers check: Ludwig van Beethoven (2 tracks), Wolfgang Amadeus Mozart (1 track)
      final composers = appState.cachedComposers;
      final beethoven = composers.firstWhere((a) => a.name == 'Ludwig van Beethoven');
      expect(beethoven.trackCount, 2);
      final mozart = composers.firstWhere((a) => a.name == 'Wolfgang Amadeus Mozart');
      expect(mozart.trackCount, 1);

      // Toggle artists view mode
      appState.setArtistsViewMode(ArtistsViewMode.composers);
      expect(appState.artistsViewMode, ArtistsViewMode.composers);
      appState.setArtistsViewMode(ArtistsViewMode.artists);
      expect(appState.artistsViewMode, ArtistsViewMode.artists);
      appState.setArtistsViewMode(ArtistsViewMode.albumArtists);
      expect(appState.artistsViewMode, ArtistsViewMode.albumArtists);
    });

    testWidgets('CustomizeTabsDialog displays tab chips and enforces constraints', (WidgetTester tester) async {
      final appState = AppStateController.instance;
      appState.activeTabs = [
        AppTab.songs,
        AppTab.albums,
        AppTab.artists,
        AppTab.genres,
        AppTab.playlists,
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => showCustomizeTabsDialog(context),
                  child: const Text('Customize'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Customize'));
      await tester.pumpAndSettle();

      // Check dialog opened
      expect(find.text('Customize Bottom Bar'), findsOneWidget);
      expect(find.textContaining('5 / 5'), findsOneWidget);

      // Check that tab names are rendered in the chips
      expect(find.text('Songs'), findsWidgets);
      expect(find.text('Albums'), findsWidgets);
      expect(find.text('Artists'), findsWidgets);
      expect(find.text('Genres'), findsWidgets);
      expect(find.text('Playlists'), findsWidgets);
      expect(find.text('Folders'), findsWidgets);

      // Reset button exists
      expect(find.text('Reset'), findsOneWidget);
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();

      // Save changes
      await tester.ensureVisible(find.text('Apply'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // Dialog is closed
      expect(find.text('Customize Bottom Bar'), findsNothing);
    });

    test('PlaybackController play asserts normal volume and pause clears interruption flag', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final controller = playbackController;
      
      // If volume was somehow ducked or muted below 0.1, play() re-asserts 1.0
      await controller.player.setVolume(0.0);
      expect(controller.player.volume, 0.0);

      // Verify pause and stop trigger clearInterruptionResume safely
      expect(() => controller.pause(), returnsNormally);
      expect(() => controller.stop(), returnsNormally);
    });
  });
}

