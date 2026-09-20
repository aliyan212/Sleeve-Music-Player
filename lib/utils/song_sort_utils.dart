import 'package:on_audio_query/on_audio_query.dart';
import '../services/playback_controller.dart';

final _yearRegex = RegExp(r'\b(19|20)\d{2}\b');

String normalizeSortText(String v) {
  final t = v.trim();
  if (t.isEmpty) return '';
  final lower = t.toLowerCase();
  if (lower == 'unknown' ||
      lower == 'unknown artist' ||
      lower == 'unknown album') {
    return '';
  }
  return t;
}

int compareSortStrings(String a, String b) {
  final aNorm = normalizeSortText(a);
  final bNorm = normalizeSortText(b);
  final aEmpty = aNorm.isEmpty;
  final bEmpty = bNorm.isEmpty;
  if (aEmpty != bEmpty) return aEmpty ? 1 : -1;

  final aLower = aNorm.toLowerCase();
  final bLower = bNorm.toLowerCase();
  final comp = aLower.compareTo(bLower);
  if (comp != 0) return comp;
  return aNorm.compareTo(bNorm);
}

int compareSortStringsDesc(String a, String b) {
  final aNorm = normalizeSortText(a);
  final bNorm = normalizeSortText(b);
  final aEmpty = aNorm.isEmpty;
  final bEmpty = bNorm.isEmpty;
  if (aEmpty != bEmpty) return aEmpty ? 1 : -1;

  final aLower = aNorm.toLowerCase();
  final bLower = bNorm.toLowerCase();
  final comp = bLower.compareTo(aLower);
  if (comp != 0) return comp;
  return bNorm.compareTo(aNorm);
}

int compareStrings(String a, String b) {
  final aTrim = a.trim();
  final bTrim = b.trim();
  final aLower = aTrim.toLowerCase();
  final bLower = bTrim.toLowerCase();
  final comp = aLower.compareTo(bLower);
  if (comp != 0) return comp;
  return aTrim.compareTo(bTrim);
}


int yearFromSong(SongModel s) {
  final map = s.getMap;
  dynamic v = map["year"];
  if (v == null || v == 0 || v == '0') {
    v = map["date"] ?? map["recording_time"];
  }
  if (v == null) return 0;
  if (v is int && v > 0) return v;
  final raw = v.toString();
  final direct = int.tryParse(raw);
  if (direct != null && direct > 0) return direct;
  final match = _yearRegex.firstMatch(raw);
  if (match == null) return 0;
  return int.tryParse(match.group(0)!) ?? 0;
}

int discFromSong(SongModel s) {
  final v = s.getMap['disc_number'];
  if (v is int && v > 0) return v;
  if (v != null) {
    final str = v.toString().trim();
    final slash = str.indexOf('/');
    final discStr = slash != -1 ? str.substring(0, slash).trim() : str;
    final parsed = int.tryParse(discStr);
    if (parsed != null && parsed > 0) return parsed;
  }
  // Fallback: Check if track has disc encoded (e.g. 1001 for disc 1, track 1)
  final t = s.track ?? 0;
  if (t >= 1000) return t ~/ 1000;
  return 0;
}

int trackFromSong(SongModel s) {
  int t = s.track ?? 0;
  if (t == 0) {
    final v = s.getMap['track'];
    if (v is int && v > 0) {
      t = v;
    } else if (v != null) {
      final str = v.toString().trim();
      final slash = str.indexOf('/');
      final trackStr = slash != -1 ? str.substring(0, slash).trim() : str;
      t = int.tryParse(trackStr) ?? 0;
    }
  }
  if (t >= 1000) return t % 1000;
  return t;
}

int compareDiscAndTrack(SongModel a, SongModel b) {
  var ad = discFromSong(a);
  var bd = discFromSong(b);
  if (ad == 0) ad = 1;
  if (bd == 0) bd = 1;
  if (ad != bd) return ad.compareTo(bd);

  final at = trackFromSong(a);
  final bt = trackFromSong(b);
  final finalAt = at == 0 ? 99999 : at;
  final finalBt = bt == 0 ? 99999 : bt;
  final tc = finalAt.compareTo(finalBt);
  if (tc != 0) return tc;

  final titleComp = compareSortStrings(a.title, b.title);
  if (titleComp != 0) return titleComp;
  return a.id.compareTo(b.id);
}

String albumArtistFor(SongModel s) {
  final raw = (s.getMap["album_artist"] ?? s.getMap["albumArtist"])?.toString();
  final fromSong = normalizeSortText(raw ?? '');
  if (fromSong.isNotEmpty) return fromSong;
  final fromSongArtist = normalizeSortText(s.artist ?? '');
  if (fromSongArtist.isNotEmpty) return fromSongArtist;
  final fromAlbum = normalizeSortText(playbackController.albumMap[s.albumId]?.artist ?? '');
  if (fromAlbum.isNotEmpty) return fromAlbum;
  return '';
}

String albumIdentityKey(SongModel s) {
  final artist = albumArtistFor(s).toLowerCase();
  final album = normalizeSortText(s.album ?? playbackController.albumMap[s.albumId]?.album ?? '').toLowerCase();
  if (album.isNotEmpty) {
    return '$artist\u0000$album';
  }
  final aid = s.albumId;
  if (aid != null && aid > 0) return 'album_id_$aid';
  return 'song_id_${s.id}';
}

/// Computes the representative release year for an album from the years of its songs.
///
/// The year assigned is the one associated with the most songs in the album.
/// If all tracks have different years (or if there is a tie between most frequent years),
/// the latest (highest) year is chosen. Returns 0 if no track has a valid year (> 0).
int computeAlbumYearFromYears(Iterable<int> songYears) {
  final valid = songYears.where((y) => y > 0).toList(growable: false);
  if (valid.isEmpty) return 0;

  final counts = <int, int>{};
  for (final y in valid) {
    counts[y] = (counts[y] ?? 0) + 1;
  }

  int maxCount = 0;
  for (final c in counts.values) {
    if (c > maxCount) maxCount = c;
  }

  int latestYear = 0;
  for (final entry in counts.entries) {
    if (entry.value == maxCount) {
      if (entry.key > latestYear) latestYear = entry.key;
    }
  }

  return latestYear;
}

/// Precomputes the representative album release year for every album among [songs],
/// keyed by [albumIdentityKey].
Map<String, int> computeAlbumYearMap(Iterable<SongModel> songs) {
  final yearsByAlbumKey = <String, List<int>>{};
  for (final s in songs) {
    final key = albumIdentityKey(s);
    final y = yearFromSong(s);
    if (y > 0) {
      (yearsByAlbumKey[key] ??= []).add(y);
    }
  }

  final out = <String, int>{};
  for (final entry in yearsByAlbumKey.entries) {
    out[entry.key] = computeAlbumYearFromYears(entry.value);
  }
  return out;
}

String composerFromSong(SongModel s) =>
    (s.composer ?? (s.getMap['composer'] as String?))?.trim() ?? '';

String genreFromSong(SongModel s) => s.genre?.trim() ?? '';

String albumFromSong(SongModel s) =>
    s.album ?? playbackController.albumMap[s.albumId]?.album ?? '';

int compareYears(int ya, int yb, {required bool ascending}) {
  final aValid = ya > 0;
  final bValid = yb > 0;
  if (!aValid && !bValid) return 0;
  if (!aValid) return 1;
  if (!bValid) return -1;
  return ascending ? ya.compareTo(yb) : yb.compareTo(ya);
}

int compareTracks(SongModel a, SongModel b, {required bool ascending}) {
  final ta = trackFromSong(a);
  final tb = trackFromSong(b);
  final aValid = ta > 0;
  final bValid = tb > 0;
  if (!aValid && !bValid) return 0;
  if (!aValid) return 1;
  if (!bValid) return -1;
  final comp = ascending ? ta.compareTo(tb) : tb.compareTo(ta);
  if (comp != 0) return comp;
  final tc = compareSortStrings(a.title, b.title);
  if (tc != 0) return tc;
  return a.id.compareTo(b.id);
}

int compareDurations(SongModel a, SongModel b, {required bool ascending}) {
  final da = a.duration ?? 0;
  final db = b.duration ?? 0;
  final aValid = da > 0;
  final bValid = db > 0;
  if (!aValid && !bValid) return 0;
  if (!aValid) return 1;
  if (!bValid) return -1;
  final comp = ascending ? da.compareTo(db) : db.compareTo(da);
  if (comp != 0) return comp;
  final tc = compareSortStrings(a.title, b.title);
  if (tc != 0) return tc;
  return a.id.compareTo(b.id);
}

int comparePlayCounts(
  SongModel a,
  SongModel b,
  Map<int, int> playCounts, {
  required bool descending,
}) {
  final ca = playCounts[a.id] ?? 0;
  final cb = playCounts[b.id] ?? 0;
  final comp = descending ? cb.compareTo(ca) : ca.compareTo(cb);
  if (comp != 0) return comp;
  final tc = compareSortStrings(a.title, b.title);
  if (tc != 0) return tc;
  return a.id.compareTo(b.id);
}

int compareComposers(SongModel a, SongModel b, {required bool ascending}) {
  final ca = composerFromSong(a);
  final cb = composerFromSong(b);
  final comp = ascending
      ? compareSortStrings(ca, cb)
      : compareSortStringsDesc(ca, cb);
  if (comp != 0) return comp;
  final tc = compareSortStrings(a.title, b.title);
  if (tc != 0) return tc;
  return a.id.compareTo(b.id);
}

int compareGenres(SongModel a, SongModel b, {required bool ascending}) {
  final ga = genreFromSong(a);
  final gb = genreFromSong(b);
  final comp = ascending
      ? compareSortStrings(ga, gb)
      : compareSortStringsDesc(ga, gb);
  if (comp != 0) return comp;
  final ac = compareSortStrings(a.artist ?? '', b.artist ?? '');
  if (ac != 0) return ac;
  final tc = compareSortStrings(a.title, b.title);
  if (tc != 0) return tc;
  return a.id.compareTo(b.id);
}

int compareAlbums(SongModel a, SongModel b, {required bool ascending}) {
  final albA = albumFromSong(a);
  final albB = albumFromSong(b);
  final comp = ascending
      ? compareSortStrings(albA, albB)
      : compareSortStringsDesc(albA, albB);
  if (comp != 0) return comp;
  final tc = compareDiscAndTrack(a, b);
  if (tc != 0) return tc;
  final tComp = compareSortStrings(a.title, b.title);
  if (tComp != 0) return tComp;
  return a.id.compareTo(b.id);
}

int compareTrackArtists(SongModel a, SongModel b, {required bool ascending}) {
  final artA = a.artist ?? '';
  final artB = b.artist ?? '';
  final comp = ascending
      ? compareSortStrings(artA, artB)
      : compareSortStringsDesc(artA, artB);
  if (comp != 0) return comp;
  final albComp = compareAlbums(a, b, ascending: true);
  if (albComp != 0) return albComp;
  final tc = compareDiscAndTrack(a, b);
  if (tc != 0) return tc;
  return compareSortStrings(a.title, b.title);
}

int compareAlbumArtists(SongModel a, SongModel b, {required bool ascending}) {
  final aaA = albumArtistFor(a);
  final aaB = albumArtistFor(b);
  final comp = ascending
      ? compareSortStrings(aaA, aaB)
      : compareSortStringsDesc(aaA, aaB);
  if (comp != 0) return comp;
  final albComp = compareAlbums(a, b, ascending: true);
  if (albComp != 0) return albComp;
  final tc = compareDiscAndTrack(a, b);
  if (tc != 0) return tc;
  return compareSortStrings(a.title, b.title);
}

int compareTitles(SongModel a, SongModel b, {required bool ascending}) {
  final comp = ascending
      ? compareSortStrings(a.title, b.title)
      : compareSortStringsDesc(a.title, b.title);
  if (comp != 0) return comp;
  final ac = compareSortStrings(a.artist ?? '', b.artist ?? '');
  if (ac != 0) return ac;
  return a.id.compareTo(b.id);
}


