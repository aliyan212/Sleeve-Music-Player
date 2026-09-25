import 'dart:async';
import 'dart:math' as math;
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/now_playing/now_playing_header.dart';
import '../widgets/now_playing/now_playing_artwork_carousel.dart';
import '../widgets/now_playing_lyrics_view.dart';

import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audiotags/audiotags.dart';
import 'package:audio_service/audio_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../android_notifications.dart';
import '../utils/palette_compute.dart';
import '../ui/shared/fast_artwork_widget.dart';
import '../ui/shared/squiggly_seek_bar.dart';
import '../widgets/now_playing_transport.dart';
import '../utils/lyrics.dart';
import '../utils/format_utils.dart';
import '../main.dart';
import '../services/loved_songs_service.dart';
import '../services/app_state_controller.dart';
import '../widgets/now_playing/now_playing_mesh_background.dart';
import '../widgets/now_playing/now_playing_landscape_view.dart';
import '../ui/shared/bouncy_pressable.dart';

class NowPlayingPage extends StatefulWidget {
  final AudioPlayer player;
  final SongModel song;
  final List<SongModel> songs;
  final Function(List<SongModel>)? onQueueChanged;
  final void Function(SongModel song) onOpenAlbum;
  final void Function(SongModel song) onOpenArtist;
  final ValueChanged<SongModel>? onSongUpdated;

  static final LinkedHashMap<
    int,
    ({Color primary, Color secondary, Color tertiary})
  >
  paletteCache =
      LinkedHashMap<int, ({Color primary, Color secondary, Color tertiary})>();
  static const int paletteCacheMax = 30;

  const NowPlayingPage({
    super.key,
    required this.player,
    required this.song,
    required this.songs,
    this.onQueueChanged,
    required this.onOpenAlbum,
    required this.onOpenArtist,
    this.onSongUpdated,
  });
  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage>
    with TickerProviderStateMixin {

  final ItemScrollController _lyricItemScrollController =
      ItemScrollController();
  final ItemPositionsListener _lyricItemPositionsListener =
      ItemPositionsListener.create();
  Color? _primaryColor;
  Color? _secondaryColor;
  Color? _tertiaryColor;
  late SongModel _displayedSong;
  bool _showLyrics = false;
  String? _rawLyrics;
  List<LyricLine> _lrcLines = [];
  List<int> _lrcTimesMs = const <int>[];
  bool _isSynced = false;
  int _currentLyricIndex = -1;
  final ValueNotifier<int> _activeLyricIndex = ValueNotifier<int>(0);
  StreamSubscription<int?>? _indexSub;
  bool _autoScrollEnabled = true;
  Timer? _resumeAutoScrollTimer;

  Timer? _paletteDebounceTimer;
  Timer? _paletteLockTimer;
  Timer? _artworkBytesDebounceTimer;
  int _paletteToken = 0;
  int _artworkBytesToken = 0;
  Uint8List? _displayedArtworkBytes;
  DateTime? _lastPaletteAppliedAt;
  static const Duration _paletteMinDisplayWindow = Duration(milliseconds: 440);
  ({int songId, int token, Color? primary, Color? secondary, Color? tertiary})?
  _pendingPalette;

  late final AnimationController _bgGradientController;
  late final AnimationController _artworkPulseController;
  late PageController _portraitPageController;
  late PageController _fullscreenPageController;
  StreamSubscription<PlayerState>? _nowPlayingPlayerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _shuffleSub;
  StreamSubscription<List<int>>? _shuffleIndicesSub;
  bool _isProgrammaticPageChange = false;
  int? _userSwipedToPage;

  bool _disableMotion = false;
  bool _fullscreenLandscape = false;
  bool _fullscreenControlsVisible = false;
  double _dragOffset = 0.0;

  List<int> _getEffectiveIndices() {
    if (widget.player.shuffleModeEnabled) {
      final sh = widget.player.shuffleIndices;
      if (sh.isNotEmpty) return sh;
    }
    final seqLen = widget.player.sequence.length;
    return List.generate(seqLen, (i) => i);
  }

  int _pageForSequenceIndex(int seqIndex, List<int> effectiveIndices) {
    if (effectiveIndices.isEmpty) return 0;
    final pos = effectiveIndices.indexOf(seqIndex);
    return pos >= 0 ? pos : seqIndex.clamp(0, effectiveIndices.length - 1);
  }

  void _syncSpecificController(
    PageController controller,
    void Function(PageController) onRecreated,
    int targetPage,
  ) {
    if (controller.hasClients) {
      final page = controller.page;
      if (page != null && (page - targetPage).abs() < 0.05) {
        return;
      }
      final currentPage = page?.round() ?? -1;
      if (currentPage != targetPage) {
        _isProgrammaticPageChange = true;
        final isAdjacent = (currentPage - targetPage).abs() == 1;
        if (isAdjacent) {
          controller
              .animateToPage(
                targetPage,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
              )
              .whenComplete(() {
                _isProgrammaticPageChange = false;
              });
        } else {
          controller.jumpToPage(targetPage);
          _isProgrammaticPageChange = false;
        }
      }
    } else {
      controller.dispose();
      onRecreated(PageController(initialPage: targetPage, keepPage: false));
    }
  }

  void _syncPageController(int targetPage) {
    _syncSpecificController(
      _portraitPageController,
      (c) => _portraitPageController = c,
      targetPage,
    );
    _syncSpecificController(
      _fullscreenPageController,
      (c) => _fullscreenPageController = c,
      targetPage,
    );
  }

  @override
  void initState() {
    super.initState();
    _displayedSong = widget.song;
    final cachedPalette = NowPlayingPage.paletteCache[_displayedSong.id];
    if (cachedPalette != null) {
      _primaryColor = cachedPalette.primary;
      _secondaryColor = cachedPalette.secondary;
      _tertiaryColor = cachedPalette.tertiary;
    }

    final initialEffective = _getEffectiveIndices();
    final initialPage = _pageForSequenceIndex(
      widget.player.currentIndex ?? 0,
      initialEffective,
    );
    _portraitPageController = PageController(
      initialPage: initialPage,
      keepPage: false,
    );
    _fullscreenPageController = PageController(
      initialPage: initialPage,
      keepPage: false,
    );
    if (hasCachedArtworkBytes(_displayedSong.id, size: 900)) {
      _displayedArtworkBytes = peekCachedArtworkBytes(
        _displayedSong.id,
        size: 900,
      );
    } else if (hasCachedArtworkBytes(_displayedSong.id, size: 200)) {
      _displayedArtworkBytes = peekCachedArtworkBytes(
        _displayedSong.id,
        size: 200,
      );
    }

    _bgGradientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );

    _artworkPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );

    appIsForeground.addListener(_handleForegroundChanged);

    _nowPlayingPlayerStateSub = widget.player.playerStateStream.listen((state) {
      // Keep pulse only while playing.
      if (_disableMotion) {
        if (_artworkPulseController.isAnimating) _artworkPulseController.stop();
        return;
      }
      if (!appIsForeground.value) {
        if (_artworkPulseController.isAnimating) _artworkPulseController.stop();
        return;
      }
      final isPlaying =
          state.playing && state.processingState != ProcessingState.completed;
      if (isPlaying) {
        if (!_artworkPulseController.isAnimating) {
          _artworkPulseController.repeat(reverse: true);
        }
      } else {
        if (_artworkPulseController.isAnimating) {
          _artworkPulseController.stop();
        }
      }
    });

    if (widget.player.playing &&
        widget.player.processingState != ProcessingState.completed &&
        appIsForeground.value &&
        !_disableMotion) {
      _artworkPulseController.repeat(reverse: true);
    }

    _loadLyrics();
    _scheduleArtworkBytesUpdate(_displayedSong.id, delay: Duration.zero);
    if (cachedPalette == null) {
      _schedulePaletteUpdate(
        _displayedSong.id,
        delay: Duration.zero,
      );
    }

    _indexSub = widget.player.currentIndexStream.listen((index) {
      if (!mounted) return;
      if (index == null || index < 0) return;

      // Get the current song from the player's sequence to handle queue changes correctly
      final sequence = widget.player.sequence;
      if (index >= sequence.length) return;

      final currentSource = sequence[index];
      final tag = currentSource.tag;

      // Find the song by matching the tag (which contains song id or MediaItem)
      SongModel? newSong;
      if (tag is MediaItem) {
        final songId = int.tryParse(tag.id);
        if (songId != null) {
          newSong = widget.songs.cast<SongModel?>().firstWhere(
            (s) => s?.id == songId,
            orElse: () => null,
          );
        }
      } else if (tag is SongModel) {
        newSong = tag;
      }

      if (newSong == null || newSong.id == _displayedSong.id) return;

      final effective = _getEffectiveIndices();
      final targetPage = _pageForSequenceIndex(index, effective);
      if (_userSwipedToPage == targetPage) {
        // Handled smoothly by active PageView's ongoing drag/ballistic scroll;
        // avoid launching a competing programmatic animation on it,
        // but ensure any inactive controller is updated.
        _userSwipedToPage = null;
        if (!_portraitPageController.hasClients) {
          _portraitPageController.dispose();
          _portraitPageController = PageController(
            initialPage: targetPage,
            keepPage: false,
          );
        }
        if (!_fullscreenPageController.hasClients) {
          _fullscreenPageController.dispose();
          _fullscreenPageController = PageController(
            initialPage: targetPage,
            keepPage: false,
          );
        }
      } else {
        _userSwipedToPage = null;
        _syncPageController(targetPage);
      }

      final hasHighRes = hasCachedArtworkBytes(newSong.id, size: 900);
      final hasLowRes = hasCachedArtworkBytes(newSong.id, size: 200);

      HapticFeedback.mediumImpact();
      setState(() {
        _displayedSong = newSong!;
        if (hasHighRes) {
          _displayedArtworkBytes = peekCachedArtworkBytes(
            newSong.id,
            size: 900,
          );
        } else if (hasLowRes) {
          _displayedArtworkBytes = peekCachedArtworkBytes(
            newSong.id,
            size: 200,
          );
        } else {
          _displayedArtworkBytes = null;
        }
        _showLyrics = false;
        _currentLyricIndex = -1;
      });
      WakelockPlus.disable();
      _scheduleArtworkBytesUpdate(newSong.id);
      _schedulePaletteUpdate(newSong.id);
      _loadLyrics();
    });

    _shuffleSub = widget.player.shuffleModeEnabledStream.listen((_) {
      if (!mounted || _userSwipedToPage != null) return;
      final effective = _getEffectiveIndices();
      final targetPage = _pageForSequenceIndex(
        widget.player.currentIndex ?? 0,
        effective,
      );
      _syncPageController(targetPage);
      setState(() {});
    });

    _shuffleIndicesSub = widget.player.shuffleIndicesStream.listen((_) {
      if (!mounted || _userSwipedToPage != null) return;
      final effective = _getEffectiveIndices();
      final targetPage = _pageForSequenceIndex(
        widget.player.currentIndex ?? 0,
        effective,
      );
      _syncPageController(targetPage);
      setState(() {});
    });

    _positionSub = widget.player.positionStream.listen((position) {
      if (!mounted || !_isSynced || _lrcLines.isEmpty || !_showLyrics) return;
      if (!appIsForeground.value) return;

      final activeIndex = _activeLyricIndexForPosition(position);
      if (activeIndex != _currentLyricIndex) {
        _currentLyricIndex = activeIndex;
        _activeLyricIndex.value = activeIndex;

        if (_autoScrollEnabled) {
          _scrollToActiveLine(activeIndex);
        }
      }
    });
    if (!appIsForeground.value) {
      _positionSub?.pause();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disable = MediaQuery.of(context).disableAnimations;
    _disableMotion = disable;
    _syncMotionControllers();
  }

  void _syncMotionControllers() {
    if (!mounted) return;
    final shouldAnimate = appIsForeground.value && !_disableMotion;
    if (shouldAnimate) {
      final route = ModalRoute.of(context);
      if (route != null &&
          route.animation != null &&
          !route.animation!.isCompleted) {
        route.animation!.addStatusListener((status) {
          if (status == AnimationStatus.completed &&
              mounted &&
              appIsForeground.value &&
              !_disableMotion) {
            if (!_bgGradientController.isAnimating) {
              _bgGradientController.repeat();
            }
          } else if (status == AnimationStatus.reverse && mounted) {
            if (_bgGradientController.isAnimating) _bgGradientController.stop();
          }
        });
      } else {
        if (!_bgGradientController.isAnimating) _bgGradientController.repeat();
      }
    } else {
      if (_bgGradientController.isAnimating) _bgGradientController.stop();
    }

    // Artwork pulse depends on player state; if we can't animate, stop.
    if (!shouldAnimate) {
      if (_artworkPulseController.isAnimating) _artworkPulseController.stop();
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _positionSub = null;

    _indexSub?.cancel();
    _shuffleSub?.cancel();
    _shuffleIndicesSub?.cancel();
    _resumeAutoScrollTimer?.cancel();
    _paletteDebounceTimer?.cancel();
    _paletteDebounceTimer = null;
    _paletteLockTimer?.cancel();
    _paletteLockTimer = null;
    _artworkBytesDebounceTimer?.cancel();
    _artworkBytesDebounceTimer = null;

    if (_fullscreenLandscape) {
      try {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
        ]);
      } catch (_) {
        // Ignore platform-specific failures.
      }
    }

    _activeLyricIndex.dispose();
    _portraitPageController.dispose();
    _fullscreenPageController.dispose();

    appIsForeground.removeListener(_handleForegroundChanged);
    _bgGradientController.dispose();

    _nowPlayingPlayerStateSub?.cancel();
    _nowPlayingPlayerStateSub = null;
    _artworkPulseController.dispose();

    WakelockPlus.disable();
    super.dispose();
  }

  void _scheduleArtworkBytesUpdate(
    int songId, {
    Duration delay = const Duration(milliseconds: 80),
  }) {
    _artworkBytesDebounceTimer?.cancel();
    final token = ++_artworkBytesToken;
    _artworkBytesDebounceTimer = Timer(delay, () {
      _updateArtworkBytes(songId, token);
    });
  }

  Future<void> _updateArtworkBytes(int songId, int token) async {
    try {
      final bytes = await queryArtworkBytesCached(
        songId,
        type: ArtworkType.AUDIO,
        size: 900,
        quality: 100,
      );
      if (!mounted) return;
      if (token != _artworkBytesToken) return;
      if (songId != _displayedSong.id) return;
      if (identical(_displayedArtworkBytes, bytes)) return;
      setState(() => _displayedArtworkBytes = bytes);
    } catch (_) {
      // Keep previously rendered artwork if fetch fails.
    }
  }


  void _queueOrApplyPalette({
    required int songId,
    required int token,
    required Color? primary,
    required Color? secondary,
    required Color? tertiary,
  }) {
    if (!mounted) return;
    if (token != _paletteToken) return;
    if (songId != _displayedSong.id) return;

    final now = DateTime.now();
    final last = _lastPaletteAppliedAt;
    final remaining = last == null
        ? Duration.zero
        : _paletteMinDisplayWindow - now.difference(last);

    if (remaining <= Duration.zero) {
      _paletteLockTimer?.cancel();
      _paletteLockTimer = null;
      _pendingPalette = null;
      setState(() {
        _primaryColor = primary;
        _secondaryColor = secondary;
        _tertiaryColor = tertiary;
      });
      _lastPaletteAppliedAt = now;
      return;
    }

    _pendingPalette = (
      songId: songId,
      token: token,
      primary: primary,
      secondary: secondary,
      tertiary: tertiary,
    );

    _paletteLockTimer?.cancel();
    _paletteLockTimer = Timer(remaining, () {
      if (!mounted) return;
      final pending = _pendingPalette;
      if (pending == null) return;
      if (pending.token != _paletteToken) {
        _pendingPalette = null;
        return;
      }
      if (pending.songId != _displayedSong.id) {
        _pendingPalette = null;
        return;
      }
      setState(() {
        _primaryColor = pending.primary;
        _secondaryColor = pending.secondary;
        _tertiaryColor = pending.tertiary;
      });
      _lastPaletteAppliedAt = DateTime.now();
      _pendingPalette = null;
    });
  }

  Future<void> _setFullscreenLandscape(bool enabled) async {
    if (_fullscreenLandscape == enabled) return;
    final effective = _getEffectiveIndices();
    final currentSeqIndex = widget.player.currentIndex ?? 0;
    final targetPage = _pageForSequenceIndex(currentSeqIndex, effective);

    if (enabled) {
      if (!_fullscreenPageController.hasClients) {
        _fullscreenPageController.dispose();
        _fullscreenPageController = PageController(
          initialPage: targetPage,
          keepPage: false,
        );
      }
    } else {
      if (!_portraitPageController.hasClients) {
        _portraitPageController.dispose();
        _portraitPageController = PageController(
          initialPage: targetPage,
          keepPage: false,
        );
      }
    }

    setState(() {
      _fullscreenLandscape = enabled;
      if (enabled) {
        _showLyrics = true;
        _autoScrollEnabled = true;
        _currentLyricIndex = -1;
      }
    });

    try {
      if (enabled) {
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
        ]);
      }
    } catch (_) {
      // Ignore platform-specific failures.
    }

    if (!mounted) return;
    if (enabled && _isSynced && _lrcLines.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final idx = _activeLyricIndexForPosition(widget.player.position);
        _scrollToActiveLine(idx);
      });
    }
  }

  void _handleForegroundChanged() {
    if (!mounted) return;
    if (appIsForeground.value) {
      // 1. RESUME: Instant Catch-Up
      if (_showLyrics && _isSynced) {
        _primeLyricsScroll();
      }
      if (_positionSub?.isPaused == true) {
        _positionSub?.resume();
      }
      _syncMotionControllers();
      if (_showLyrics) {
        _setLyricsVisible(true, force: true);
      }
    } else {
      // 2. PAUSE: Deep Sleep Mode
      _positionSub?.pause();
      WakelockPlus.disable();
      if (_bgGradientController.isAnimating) _bgGradientController.stop();
      if (_artworkPulseController.isAnimating) _artworkPulseController.stop();
    }
  }

  void _openArtistDetail() {
    widget.onOpenArtist(_displayedSong);
  }

  void _openAlbumDetail() {
    widget.onOpenAlbum(_displayedSong);
  }

  void _setLyricsVisible(bool show, {bool force = false}) {
    if (!force && _showLyrics == show) return;
    if (!show) {
      final effective = _getEffectiveIndices();
      final currentSeqIndex = widget.player.currentIndex ?? 0;
      final targetPage = _pageForSequenceIndex(currentSeqIndex, effective);
      if (!_portraitPageController.hasClients) {
        _portraitPageController.dispose();
        _portraitPageController = PageController(
          initialPage: targetPage,
          keepPage: false,
        );
      }
    }
    setState(() {
      _showLyrics = show;
      if (show) {
        _autoScrollEnabled = true;
        _currentLyricIndex = -1;
      }
    });
    if (show) {
      WakelockPlus.enable();
      if (_rawLyrics == null) {
        _loadLyrics();
      } else {
        _primeLyricsScroll();
      }
    } else {
      WakelockPlus.disable();
    }
  }

  void _primeLyricsScroll() {
    if (!_isSynced || _lrcLines.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final idx = _activeLyricIndexForPosition(widget.player.position);
      if (_lyricItemScrollController.isAttached) {
        _lyricItemScrollController.jumpTo(
          index: idx.clamp(0, _lrcLines.length - 1),
          alignment: _alignmentForLine(idx),
        );
      }
    });
  }

  Future<void> _loadLyrics() async {
    setState(() {
      _rawLyrics = null;
      _lrcLines = [];
      _lrcTimesMs = const <int>[];
      _isSynced = false;
      _currentLyricIndex = -1;
    });
    String? lyrics = await LyricsHelper.getLyrics(_displayedSong.data);
    if (lyrics != null && lyrics.isNotEmpty) {
      bool isSynced = LyricsHelper.isLRC(lyrics);
      if (isSynced && mounted) {
        final parsed = LyricsHelper.parseLRC(lyrics);
        setState(() {
          _lrcLines = parsed;
          _lrcTimesMs = parsed
              .map((e) => e.time.inMilliseconds)
              .toList(growable: false);
          _isSynced = true;
          _rawLyrics = lyrics;
        });

        // Seed the active index so long lyric files don't rebuild the whole UI.
        final idx = _activeLyricIndexForPosition(widget.player.position);
        _currentLyricIndex = idx;
        _activeLyricIndex.value = idx;
      } else if (mounted) {
        setState(() {
          _rawLyrics = lyrics;
          _isSynced = false;
          _lrcLines = [];
          _lrcTimesMs = const <int>[];
        });
        _currentLyricIndex = -1;
        _activeLyricIndex.value = 0;
      }
    }
  }

  Future<void> _reloadDisplayedSongMetadata() async {
    try {
      final tag = await AudioTags.read(_displayedSong.data);
      if (!mounted || tag == null) return;

      final updatedMap = Map<dynamic, dynamic>.from(_displayedSong.getMap);
      updatedMap['title'] = tag.title ?? _displayedSong.title;
      updatedMap['artist'] = tag.trackArtist ?? _displayedSong.artist;
      updatedMap['album'] = tag.album ?? _displayedSong.album;
      updatedMap['album_artist'] =
          tag.albumArtist ?? updatedMap['album_artist'];
      updatedMap['genre'] = tag.genre ?? updatedMap['genre'];
      updatedMap['year'] = tag.year ?? updatedMap['year'];
      updatedMap['track'] = tag.trackNumber ?? updatedMap['track'];
      updatedMap['disc_number'] = tag.discNumber ?? updatedMap['disc_number'];
      updatedMap['track_total'] = tag.trackTotal ?? updatedMap['track_total'];
      updatedMap['disc_total'] = tag.discTotal ?? updatedMap['disc_total'];

      setState(() {
        _displayedSong = SongModel(updatedMap);
      });
    } catch (_) {}
  }

  int _activeLyricIndexForPosition(Duration position) {
    final times = _lrcTimesMs;
    if (times.isEmpty) return 0;

    final ms = position.inMilliseconds;
    if (ms <= times.first) return 0;
    if (ms >= times.last) return times.length - 1;

    // Find the last timestamp <= current position.
    int lo = 0;
    int hi = times.length - 1;
    int best = 0;
    while (lo <= hi) {
      final mid = lo + ((hi - lo) >> 1);
      final t = times[mid];
      if (t <= ms) {
        best = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return best;
  }

  void _schedulePaletteUpdate(
    int songId, {
    Duration delay = const Duration(milliseconds: 320),
  }) {
    _paletteDebounceTimer?.cancel();
    final token = ++_paletteToken;
    _paletteDebounceTimer = Timer(delay, () {
      _updatePalette(songId, token);
    });
  }

  Future<void> _updatePalette(int songId, int token) async {
    try {
      final cached = NowPlayingPage.paletteCache.remove(songId);
      if (cached != null) {
        // LRU: re-insert as most recently used.
        NowPlayingPage.paletteCache[songId] = cached;
        if (!mounted) return;
        if (token != _paletteToken) return;
        if (songId != _displayedSong.id) return;
        _queueOrApplyPalette(
          songId: songId,
          token: token,
          primary: cached.primary,
          secondary: cached.secondary,
          tertiary: cached.tertiary,
        );
        return;
      }

      Uint8List? bytes = await queryArtworkBytesCached(
        songId,
        type: ArtworkType.AUDIO,
        size: 200,
      );
      if (!mounted) return;
      if (token != _paletteToken) return;
      if (songId != _displayedSong.id) return;
      if (bytes == null) {
        _queueOrApplyPalette(
          songId: songId,
          token: token,
          primary: null,
          secondary: null,
          tertiary: null,
        );
        return;
      }
      try {
        // Compute a lightweight palette from artwork bytes.
        final Map<String, int> result = await computePaletteFromBytes(bytes);
        if (!mounted) return;
        if (token != _paletteToken) return;
        if (songId != _displayedSong.id) return;

        final primaryColorInt = result['primary'] ?? 0xFF000000;
        final secondaryColorInt = result['secondary'] ?? primaryColorInt;
        final tertiaryColorInt = result['tertiary'] ?? secondaryColorInt;
        final primary = boostVibrance(
          Color(primaryColorInt),
          extraSaturation: 0.5,
          extraLightness: 0.08,
        );
        final secondary = boostVibrance(
          Color(secondaryColorInt),
          extraSaturation: 0.42,
          extraLightness: -0.02,
        );
        final tertiary = boostVibrance(
          Color(tertiaryColorInt),
          extraSaturation: 0.46,
          extraLightness: 0.03,
        );

        _queueOrApplyPalette(
          songId: songId,
          token: token,
          primary: primary,
          secondary: secondary,
          tertiary: tertiary,
        );

        NowPlayingPage.paletteCache.remove(songId);
        NowPlayingPage.paletteCache[songId] = (
          primary: primary,
          secondary: secondary,
          tertiary: tertiary,
        );
        while (NowPlayingPage.paletteCache.length >
            NowPlayingPage.paletteCacheMax) {
          NowPlayingPage.paletteCache.remove(
            NowPlayingPage.paletteCache.keys.first,
          );
        }
      } catch (_) {
        // Swallow errors; palette is a nicety, not critical.
      }
    } catch (_) {}
  }

  double _alignmentForLine(int index) {
    if (index < 0 || index >= _lrcLines.length) return 0.36;
    final len = _lrcLines[index].content.trim().length;
    if (len <= 36) return 0.36;
    if (len <= 75) return 0.30;
    if (len <= 120) return 0.25;
    return 0.20;
  }

  void _scrollToActiveLine(int index) {
    if (!_lyricItemScrollController.isAttached) return;
    if (index < 0 || index >= _lrcLines.length) return;

    // Smooth physics-based gliding scroll with gentle easing curve
    _lyricItemScrollController.scrollTo(
      index: index,
      alignment: _alignmentForLine(index),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeInOutCubic,
    );
  }

  void _pauseAutoScroll() {
    _autoScrollEnabled = false;
    _resumeAutoScrollTimer?.cancel();
    _resumeAutoScrollTimer = Timer(const Duration(milliseconds: 4500), () {
      if (mounted) setState(() => _autoScrollEnabled = true);
    });
  }

  Widget _buildFullscreenLandscapeView({
    required bool isDark,
    required Color textColor,
    required Color textColorSecondary,
    required Color iconBgColor,
    required Color iconFgColor,
  }) {
    return NowPlayingLandscapeView(
      isDark: isDark,
      textColor: textColor,
      textColorSecondary: textColorSecondary,
      iconBgColor: iconBgColor,
      iconFgColor: iconFgColor,
      primaryColor: _primaryColor,
      displayedSong: _displayedSong,
      player: widget.player,
      artworkPulseAnimation: _artworkPulseController,
      controlsVisible: _fullscreenControlsVisible,
      onToggleControls: () => setState(
        () => _fullscreenControlsVisible = !_fullscreenControlsVisible,
      ),
      artworkPageViewBuilder: (side) => NowPlayingArtworkCarousel(
                                        player: widget.player,
                                        isFullscreen: true,
                                        sequence: widget.player.sequence,
                                        effectiveIndices: _getEffectiveIndices(),
                                        pageController: _fullscreenPageController,
                                        isProgrammaticPageChange: _isProgrammaticPageChange,
                                        onUserSwipedToPage: (p) => _userSwipedToPage = p,
                                        displayedSong: _displayedSong,
                                        artworkPulseController: _artworkPulseController,
                                        primaryColor: _primaryColor,
                                        alignment: Alignment.center,
                                      ),
      lyricsView: NowPlayingLyricsView(
                                        rawLyrics: _rawLyrics,
                                        isSynced: _isSynced,
                                        lrcLines: _lrcLines,
                                        activeLyricIndex: _activeLyricIndex,
                                        itemScrollController: _lyricItemScrollController,
                                        itemPositionsListener: _lyricItemPositionsListener,
                                        displayedArtworkBytes: _displayedArtworkBytes,
                                        currentLyricIndex: _currentLyricIndex,
                                        player: widget.player,
                                        onPauseAutoScroll: _pauseAutoScroll,
                                        alignmentForLine: _alignmentForLine,
                                      ),
      onOpenArtist: _openArtistDetail,
      onOpenAlbum: _openAlbumDetail,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    // Adjust colors based on theme - lighter in light mode, darker in dark mode
    Color adjustColorForTheme(Color color) {
      final hsl = HSLColor.fromColor(color);
      if (isDark) {
        // Deep, rich colors for dark mode.
        return hsl
            .withSaturation((hsl.saturation * 0.95).clamp(0.0, 1.0))
            .withLightness((hsl.lightness * 0.5).clamp(0.25, 0.45))
            .toColor();
      } else {
        // Lighter colors for light mode
        return hsl
            .withLightness((hsl.lightness * 0.5 + 0.5).clamp(0.6, 0.9))
            .toColor();
      }
    }

    // Deep, elegant fallback colors if artwork colors aren't available yet
    final defaultTopColor = isDark
        ? Color.alphaBlend(
            cs.primary.withValues(alpha: 0.08),
            const Color(0xFF141519),
          )
        : cs.surfaceContainerHighest;
    final defaultMidColor = isDark
        ? const Color(0xFF0F1014)
        : cs.surfaceContainer;
    final defaultAccentColor = cs.primary;

    final targetTopColor = _primaryColor != null
        ? adjustColorForTheme(_primaryColor!)
        : defaultTopColor;
    final targetMidColor = _secondaryColor != null
        ? adjustColorForTheme(_secondaryColor!)
        : defaultMidColor;
    final targetAccentColor = _tertiaryColor != null
        ? adjustColorForTheme(_tertiaryColor!)
        : Color.lerp(targetTopColor, targetMidColor, 0.45) ??
              defaultAccentColor;

    final textColor = isDark ? Colors.white : Colors.black87;
    final textColorSecondary = isDark ? Colors.white70 : Colors.black54;
    final iconBgColor = isDark
        ? Colors.white10
        : Colors.black.withValues(alpha: 0.08);
    final iconFgColor = isDark ? Colors.white : Colors.black87;

    return GestureDetector(
      onVerticalDragUpdate: (details) {
        if (_fullscreenLandscape) return;
        if (details.primaryDelta! > 0 || _dragOffset > 0) {
          setState(() {
            _dragOffset += details.primaryDelta!;
            if (_dragOffset < 0) _dragOffset = 0;
          });
        }
      },
      onVerticalDragEnd: (details) {
        if (_fullscreenLandscape) return;
        if (_dragOffset > 150 || (details.primaryVelocity ?? 0) > 400) {
          HapticFeedback.lightImpact();
          Navigator.pop(context);
        } else {
          setState(() => _dragOffset = 0.0);
        }
      },
      child: Transform.translate(
        offset: Offset(0, _dragOffset),
        child: Scaffold(
          backgroundColor: isDark ? const Color(0xFF101116) : cs.surface,
          body: NowPlayingMeshBackground(
            targetTopColor: targetTopColor,
            targetMidColor: targetMidColor,
            targetAccentColor: targetAccentColor,
            animation: _bgGradientController,
            isDark: isDark,
            child: Column(
              children: [
                SizedBox(
                  height: MediaQuery.of(context).viewPadding.top > 0
                      ? MediaQuery.of(context).viewPadding.top
                      : (MediaQueryData.fromView(
                                  View.of(context),
                                ).viewPadding.top >
                                0
                            ? MediaQueryData.fromView(
                                View.of(context),
                              ).viewPadding.top
                            : 42.0), // Safe fallback for S10+ and similar devices
                ),
                NowPlayingHeader(
                  player: widget.player,
                  songs: widget.songs,
                  displayedSong: _displayedSong,
                  rawLyrics: _rawLyrics,
                  isFullscreenLandscape: _fullscreenLandscape,
                  showLyrics: _showLyrics,
                  isDark: isDark,
                  textColorSecondary: textColorSecondary,
                  iconBgColor: iconBgColor,
                  iconFgColor: iconFgColor,
                  onPop: () => Navigator.pop(context),
                  onQueueChanged: widget.onQueueChanged,
                  onSetLyricsVisible: _setLyricsVisible,
                  onSetFullscreenLandscape: (val) async {
                    await _setFullscreenLandscape(val);
                  },
                  onSongUpdated: (updatedSong) {
                    setState(() {
                      _displayedSong = updatedSong;
                    });
                    widget.onSongUpdated?.call(updatedSong);
                  },
                  onReloadDisplayedSongMetadata: _reloadDisplayedSongMetadata,
                  onLoadLyrics: _loadLyrics,
                ),
                Expanded(
                  child: _fullscreenLandscape
                      ? _buildFullscreenLandscapeView(
                          isDark: isDark,
                          textColor: textColor,
                          textColorSecondary: textColorSecondary,
                          iconBgColor: iconBgColor,
                          iconFgColor: iconFgColor,
                        )
                      : OrientationBuilder(
                          builder: (context, orientation) {
                            final isLandscape =
                                orientation == Orientation.landscape;

                            Widget artworkOrLyrics() {
                              return GestureDetector(
                                onTap: () => _setLyricsVisible(!_showLyrics),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 400),
                                  child: _showLyrics
                                      ? NowPlayingLyricsView(
                                        rawLyrics: _rawLyrics,
                                        isSynced: _isSynced,
                                        lrcLines: _lrcLines,
                                        activeLyricIndex: _activeLyricIndex,
                                        itemScrollController: _lyricItemScrollController,
                                        itemPositionsListener: _lyricItemPositionsListener,
                                        displayedArtworkBytes: _displayedArtworkBytes,
                                        currentLyricIndex: _currentLyricIndex,
                                        player: widget.player,
                                        onPauseAutoScroll: _pauseAutoScroll,
                                        alignmentForLine: _alignmentForLine,
                                      )
                                      : NowPlayingArtworkCarousel(
                                        player: widget.player,
                                        isFullscreen: false,
                                        sequence: widget.player.sequence,
                                        effectiveIndices: _getEffectiveIndices(),
                                        pageController: _portraitPageController,
                                        isProgrammaticPageChange: _isProgrammaticPageChange,
                                        onUserSwipedToPage: (p) => _userSwipedToPage = p,
                                        displayedSong: _displayedSong,
                                        artworkPulseController: _artworkPulseController,
                                        primaryColor: _primaryColor,
                                        alignment: Alignment.center,
                                      ),
                                ),
                              );
                            }

                            Widget songMeta({double titleSize = 22}) {
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _displayedSong.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w900,
                                          color: textColor,
                                          letterSpacing: -0.8,
                                          fontSize: titleSize,
                                        ),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 6),
                                  BouncyPressable(
                                    onPressed: () {
                                      HapticFeedback.selectionClick();
                                      _openArtistDetail();
                                    },
                                    child: Text(
                                      _displayedSong.artist ?? "Unknown Artist",
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: textColor.withValues(
                                              alpha: 0.8,
                                            ),
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: -0.3,
                                          ),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  BouncyPressable(
                                    onPressed: () {
                                      HapticFeedback.selectionClick();
                                      _openAlbumDetail();
                                    },
                                    child: Text(
                                      _displayedSong.album ?? "Unknown Album",
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: textColorSecondary,
                                            fontWeight: FontWeight.w500,
                                          ),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              );
                            }

                            Widget seekAndTime() {
                              return ValueListenableBuilder<bool>(
                                valueListenable: appIsForeground,
                                builder: (context, isFg, _) {
                                  if (!isFg) {
                                    final position = widget.player.position;
                                    final total =
                                        widget.player.duration ?? Duration.zero;
                                    final isPlaying = widget.player.playing &&
                                        widget.player.processingState !=
                                            ProcessingState.completed;
                                    return Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SquigglySeekBar(
                                          position: position,
                                          duration: total,
                                          isPlaying: isPlaying,
                                          onChanged: (val) =>
                                              widget.player.seek(val),
                                          isDark: isDark,
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                formatTime(
                                                  position.inMilliseconds,
                                                ),
                                                style: TextStyle(
                                                  color: textColorSecondary,
                                                ),
                                              ),
                                              Text(
                                                formatTime(
                                                  total.inMilliseconds,
                                                ),
                                                style: TextStyle(
                                                  color: textColorSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  }

                                  return StreamBuilder<PlayerState>(
                                    stream: widget.player.playerStateStream,
                                    builder: (context, playerSnapshot) {
                                      final isPlaying =
                                          (playerSnapshot.data?.playing ??
                                                  false) &&
                                              playerSnapshot
                                                      .data?.processingState !=
                                                  ProcessingState.completed;
                                      return StreamBuilder<Duration>(
                                        stream: widget.player.positionStream,
                                        builder: (context, snapshot) {
                                          final position =
                                              snapshot.data ?? Duration.zero;
                                          final total =
                                              widget.player.duration ??
                                              Duration.zero;
                                          return Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SquigglySeekBar(
                                                position: position,
                                                duration: total,
                                                isPlaying: isPlaying,
                                                onChanged: (val) =>
                                                    widget.player.seek(val),
                                                isDark: isDark,
                                              ),
                                              Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                    ),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Text(
                                                      formatTime(
                                                        position.inMilliseconds,
                                                      ),
                                                      style: TextStyle(
                                                        color:
                                                            textColorSecondary,
                                                      ),
                                                    ),
                                                    Text(
                                                      formatTime(
                                                        total.inMilliseconds,
                                                      ),
                                                      style: TextStyle(
                                                        color:
                                                            textColorSecondary,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      );
                                    },
                                  );
                                },
                              );
                            }

                            Widget songMetaWithActions({double titleSize = 22}) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  ListenableBuilder(
                                    listenable: LovedSongsService.instance,
                                    builder: (context, _) {
                                      final isLoved = LovedSongsService.instance.isLoved(_displayedSong.id);
                                      return IconButton.filledTonal(
                                        tooltip: isLoved ? 'Remove from loved' : 'Love song',
                                        icon: Icon(
                                          isLoved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                          color: isLoved ? Colors.redAccent : iconFgColor,
                                          size: 22,
                                        ),
                                        onPressed: () {
                                          HapticFeedback.selectionClick();
                                          AppStateController.instance.toggleLikedSong(_displayedSong.id);
                                        },
                                        style: IconButton.styleFrom(
                                          backgroundColor: isLoved
                                              ? Colors.redAccent.withValues(alpha: 0.15)
                                              : iconBgColor,
                                          foregroundColor: isLoved ? Colors.redAccent : iconFgColor,
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: songMeta(titleSize: titleSize),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton.filledTonal(
                                    tooltip: 'Add to playlist',
                                    icon: const Icon(Icons.playlist_add_rounded, size: 24),
                                    onPressed: () {
                                      HapticFeedback.selectionClick();
                                      AppStateController.instance.addSongsToPlaylistFlow(context, [_displayedSong.id]);
                                    },
                                    style: IconButton.styleFrom(
                                      backgroundColor: iconBgColor,
                                      foregroundColor: iconFgColor,
                                    ),
                                  ),
                                ],
                              );
                            }

                            if (!isLandscape) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24.0,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Expanded(child: artworkOrLyrics()),
                                    const SizedBox(height: 28),
                                    songMetaWithActions(titleSize: 22),
                                    const SizedBox(height: 24),
                                    seekAndTime(),
                                    const SizedBox(height: 20),
                                    NowPlayingTransport(
                                      player: widget.player,
                                      isDark: isDark,
                                      iconFgColor: iconFgColor,
                                      accentColor:
                                          _primaryColor ?? _secondaryColor,
                                      onPlayPressed: () async {
                                        final ok =
                                            await ensureNotificationPermissionIfNeeded();
                                        if (!ok && context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: const Text(
                                                'Notifications are blocked, so the player notification can\'t be shown.',
                                              ),
                                              behavior:
                                                  SnackBarBehavior.floating,
                                              action: SnackBarAction(
                                                label: 'Settings',
                                                onPressed: () =>
                                                    AndroidNotifications.openAppNotificationSettings(),
                                              ),
                                            ),
                                          );
                                        }
                                        widget.player.play();
                                      },
                                    ),
                                    const SizedBox(height: 36),
                                  ],
                                ),
                              );
                            }

                            // Landscape: use two columns and allow the right side to scroll if needed.
                            final mediaPadding = MediaQuery.paddingOf(context);
                            return Padding(
                              padding: EdgeInsets.fromLTRB(
                                math.max(16.0, mediaPadding.left),
                                4,
                                math.max(16.0, mediaPadding.right),
                                math.max(12.0, mediaPadding.bottom),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 5,
                                    child: Center(child: artworkOrLyrics()),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    flex: 6,
                                    child: SingleChildScrollView(
                                      physics: const BouncingScrollPhysics(),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const SizedBox(height: 8),
                                          songMetaWithActions(titleSize: 20),
                                          const SizedBox(height: 16),
                                          seekAndTime(),
                                          const SizedBox(height: 14),
                                          NowPlayingTransport(
                                            player: widget.player,
                                            isDark: isDark,
                                            iconFgColor: iconFgColor,
                                            accentColor:
                                                _primaryColor ??
                                                _secondaryColor,
                                            onPlayPressed: () async {
                                              final ok =
                                                  await ensureNotificationPermissionIfNeeded();
                                              if (!ok && context.mounted) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: const Text(
                                                      'Notifications are blocked, so the player notification can\'t be shown.',
                                                    ),
                                                    behavior: SnackBarBehavior
                                                        .floating,
                                                    action: SnackBarAction(
                                                      label: 'Settings',
                                                      onPressed: () =>
                                                          AndroidNotifications.openAppNotificationSettings(),
                                                    ),
                                                  ),
                                                );
                                              }
                                              widget.player.play();
                                            },
                                          ),
                                          const SizedBox(height: 16),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
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

