

enum SortMode {
  // Title
  titleAsc,
  titleDesc,
  // Album
  albumAsc,
  albumDesc,
  // Track Artist (strictly song artist, not confused with album artist)
  artistAsc,
  artistDesc,
  // Album Artist
  albumArtistAsc,
  albumArtistDesc,
  // Album Artist & Year
  albumArtistYearAsc,
  albumArtistYearDesc,
  // Composer
  composerAsc,
  composerDesc,
  // Genre
  genreAsc,
  genreDesc,
  // Release Year
  yearAsc,
  yearDesc,
  // Duration
  durationAsc,
  durationDesc,
  // Track Number
  trackAsc,
  trackDesc,
  // Most Played / Play Count
  mostPlayed,
  leastPlayed;

  // Backwards-compatible aliases for existing code and test suites
  static const SortMode artist = SortMode.artistAsc;
  static const SortMode albumArtist = SortMode.albumArtistAsc;
  static const SortMode year = SortMode.yearAsc;
  static const SortMode albumArtistYear = SortMode.albumArtistYearAsc;

  bool get isNumeric {
    switch (this) {
      case SortMode.yearAsc:
      case SortMode.yearDesc:
      case SortMode.durationAsc:
      case SortMode.durationDesc:
      case SortMode.trackAsc:
      case SortMode.trackDesc:
      case SortMode.mostPlayed:
      case SortMode.leastPlayed:
        return true;
      default:
        return false;
    }
  }
}