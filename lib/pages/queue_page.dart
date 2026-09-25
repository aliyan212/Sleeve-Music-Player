import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import '../ui/shared/app_empty_state.dart';
import '../utils/format_utils.dart';
import '../widgets/universal_song_tile.dart';
import '../services/app_state_controller.dart';
import '../dialogs/playlist_dialogs.dart';






class QueuePage extends StatefulWidget {
  final AudioPlayer player;
  final List<SongModel> songs;
  final int currentIndex;
  final void Function(int) onPlayIndex;
  final void Function(List<SongModel>) onQueueChanged;

  const QueuePage({
    super.key,
    required this.player,
    required this.songs,
    required this.currentIndex,
    required this.onPlayIndex,
    required this.onQueueChanged,
  });

  @override
  State<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends State<QueuePage> {
  late List<SongModel> _queue;
  late int _currentIndex;
  late final Map<int, SongModel> _songById;
  StreamSubscription<SequenceState?>? _sequenceSub;
  StreamSubscription<bool>? _shuffleSub;
  StreamSubscription<List<int>>? _shuffleIndicesSub;
  bool _isReordering = false;
  bool _ignoreSequenceUpdates = false;
  bool _shuffleEnabled = false;
  List<int> _shuffleIndices = [];

  bool _sameQueueById(List<SongModel> a, List<SongModel> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  bool _sameIntList(List<int> a, List<int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  List<SongModel> _queueFromSequence(List<IndexedAudioSource> sequence) {
    final out = <SongModel>[];
    for (final src in sequence) {
      final tag = src.tag;
      if (tag is SongModel) {
        out.add(tag);
        continue;
      }
      if (tag is MediaItem) {
        final songId = int.tryParse(tag.id);
        if (songId != null) {
          final song = _songById[songId];
          if (song != null) out.add(song);
        }
      }
    }
    return out;
  }

  /// Returns the queue indices for the "up next" songs in actual playback order.
  /// When shuffle is enabled, uses [_shuffleIndices]; otherwise linear order.
  List<int> _computeUpNext() {
    if (_shuffleEnabled && _shuffleIndices.isNotEmpty) {
      final posInShuffle = _shuffleIndices.indexOf(_currentIndex);
      if (posInShuffle >= 0) {
        return [
          for (var i = posInShuffle + 1; i < _shuffleIndices.length; i++)
            _shuffleIndices[i],
        ];
      }
    }
    // Fallback: linear order after _currentIndex
    return [
      for (var i = _currentIndex + 1; i < _queue.length; i++) i,
    ];
  }

  @override
  void initState() {
    super.initState();
    _songById = {for (final s in widget.songs) s.id: s};

    _shuffleEnabled = widget.player.shuffleModeEnabled;
    _shuffleIndices = widget.player.shuffleIndices;

    final initialSequence = widget.player.sequence;
    if (initialSequence.isNotEmpty) {
      _queue = _queueFromSequence(initialSequence);
    } else {
      _queue = List.from(widget.songs);
    }

    if (initialSequence.isNotEmpty) {
      final sameLength = widget.songs.length == _queue.length;
      if (sameLength && !_sameQueueById(widget.songs, _queue) && _queue.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          widget.onQueueChanged(_queue);
        });
      }
    }

    _currentIndex = widget.player.currentIndex ?? widget.currentIndex;
    if (_currentIndex < 0) _currentIndex = 0;
    if (_queue.isNotEmpty && _currentIndex >= _queue.length) {
      _currentIndex = _queue.length - 1;
    }

    _sequenceSub = widget.player.sequenceStateStream.listen((state) {
      if (!mounted) return;
      if (_isReordering || _ignoreSequenceUpdates) return;

      final seq = state.sequence;
      if (seq.isEmpty) return;

      final mappedQueue = _queueFromSequence(seq);
      final nextQueue = mappedQueue.isNotEmpty ? mappedQueue : _queue;
      final nextIndex = widget.player.currentIndex ?? _currentIndex;
      final nextShuffleIndices = state.shuffleIndices;

      final orderChanged = !_sameQueueById(_queue, nextQueue);
      final indexChanged = nextIndex != _currentIndex;
      final shuffleChanged = !_sameIntList(_shuffleIndices, nextShuffleIndices);
      if (!orderChanged && !indexChanged && !shuffleChanged) return;

      setState(() {
        if (orderChanged) _queue = nextQueue;
        _currentIndex = nextIndex.clamp(0, _queue.isEmpty ? 0 : _queue.length - 1);
        if (shuffleChanged) _shuffleIndices = nextShuffleIndices;
      });
      if (orderChanged) widget.onQueueChanged(_queue);
    });

    _shuffleSub = widget.player.shuffleModeEnabledStream.listen((enabled) {
      if (!mounted) return;
      setState(() {
        _shuffleEnabled = enabled;
        _shuffleIndices = widget.player.shuffleIndices;
      });
    });

    _shuffleIndicesSub = widget.player.shuffleIndicesStream.listen((indices) {
      if (!mounted) return;
      if (!_sameIntList(_shuffleIndices, indices)) {
        setState(() {
          _shuffleIndices = indices;
        });
      }
    });

  }

  @override
  void dispose() {
    _sequenceSub?.cancel();
    _shuffleSub?.cancel();
    _shuffleIndicesSub?.cancel();
    super.dispose();
  }

  Future<void> _moveItem(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || newIndex < 0) return;
    if (oldIndex >= _queue.length || newIndex >= _queue.length) return;

    final prevQueue = List<SongModel>.from(_queue);
    final prevCurrentIndex = _currentIndex;

    setState(() {
      final item = _queue.removeAt(oldIndex);
      _queue.insert(newIndex, item);

      if (oldIndex == _currentIndex) {
        _currentIndex = newIndex;
      } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
        _currentIndex--;
      } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
        _currentIndex++;
      }
    });
    widget.onQueueChanged(_queue);

    _ignoreSequenceUpdates = true;
    try {
      await widget.player.moveAudioSource(oldIndex, newIndex);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _queue = prevQueue;
        _currentIndex = prevCurrentIndex.clamp(0, _queue.isEmpty ? 0 : _queue.length - 1);
      });
      widget.onQueueChanged(_queue);
    } finally {
      _ignoreSequenceUpdates = false;
    }
  }

  Future<void> _removeItem(int index, {int? songId}) async {
    final resolvedIndex = songId == null ? index : _queue.indexWhere((s) => s.id == songId);
    if (resolvedIndex < 0 || resolvedIndex >= _queue.length) return;

    if (resolvedIndex == _currentIndex) {
      final cs = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: cs.onTertiaryContainer,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Cannot remove currently playing song',
                  style: TextStyle(color: cs.onTertiaryContainer),
                ),
              ),
            ],
          ),
          backgroundColor: cs.tertiaryContainer,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final prevQueue = List<SongModel>.from(_queue);
    final prevCurrentIndex = _currentIndex;

    _ignoreSequenceUpdates = true;
    try {
      if (resolvedIndex < widget.player.audioSources.length) {
        await widget.player.removeAudioSourceAt(resolvedIndex);
      }

      if (!mounted) return;
      setState(() {
        if (resolvedIndex >= 0 && resolvedIndex < _queue.length) {
          _queue.removeAt(resolvedIndex);
          if (resolvedIndex < _currentIndex) {
            _currentIndex--;
          }
        }

        final nextIndex = widget.player.currentIndex ?? _currentIndex;
        _currentIndex = nextIndex.clamp(0, _queue.isEmpty ? 0 : _queue.length - 1);
      });

      widget.onQueueChanged(_queue);
      HapticFeedback.lightImpact();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _queue = prevQueue;
        _currentIndex = prevCurrentIndex.clamp(0, _queue.isEmpty ? 0 : _queue.length - 1);
      });
      widget.onQueueChanged(_queue);
    } finally {
      _ignoreSequenceUpdates = false;
    }
  }

  Future<void> _saveAsPlaylist() async {
    final appState = AppStateController.instance;
    final queueSongIds = _queue.map((s) => s.id).toList();
    final created = await promptCreatePlaylist(
      context,
      onPlaylistCreated: (name) => appState.createNewPlaylist(
        name,
        initialSongIds: queueSongIds,
      ),
    );
    if (!mounted) return;
    if (created != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved "${created.name}" (${created.songIds.length} songs)'),
        ),
      );
    }
  }

  Future<void> _confirmClearQueue() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Queue'),
        content: const Text(
          'Remove all upcoming songs from the queue? Current song will continue playing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _clearUpcomingQueue();
    }
  }

  Future<void> _clearUpcomingQueue() async {
    if (_queue.isEmpty) return;
    HapticFeedback.mediumImpact();
    final currentSong = (_currentIndex >= 0 && _currentIndex < _queue.length)
        ? _queue[_currentIndex]
        : null;

    _ignoreSequenceUpdates = true;
    try {
      final totalSources = widget.player.audioSources.length;
      for (int i = totalSources - 1; i >= 0; i--) {
        if (i != _currentIndex) {
          try {
            await widget.player.removeAudioSourceAt(i);
          } catch (_) {}
        }
      }

      if (!mounted) return;
      setState(() {
        if (currentSong != null) {
          _queue = [currentSong];
          _currentIndex = 0;
        } else {
          _queue = [];
          _currentIndex = 0;
        }
        _shuffleIndices = [];
      });
      widget.onQueueChanged(_queue);
    } finally {
      _ignoreSequenceUpdates = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bgColor = cs.surface;
    final textColor = cs.onSurface;
    final textColorSecondary = cs.onSurfaceVariant;
    final dividerColor = cs.outlineVariant.withValues(alpha: 0.45);
    final surfaceColor = Color.alphaBlend(cs.primary.withValues(alpha: 0.04), cs.surface);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton.filledTonal(
          icon: Icon(Icons.close_rounded, color: cs.onSecondaryContainer),
          style: IconButton.styleFrom(
            backgroundColor: cs.secondaryContainer,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Play Queue',
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: cs.tertiaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${_queue.length} songs',
                style: TextStyle(
                  color: cs.onTertiaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Text(
              'Now Playing',
              style: TextStyle(
                color: textColorSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          if (_currentIndex >= 0 && _currentIndex < _queue.length)
            _buildCurrentSongTile(_queue[_currentIndex]),
          Divider(color: dividerColor, height: 28),
          Expanded(
            child: Builder(
              builder: (context) {
                final upNextIndices = _computeUpNext();
                int totalRemainingMs = 0;
                for (final idx in upNextIndices) {
                  if (idx >= 0 && idx < _queue.length) {
                    totalRemainingMs += (_queue[idx].duration ?? 0);
                  }
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeaderToolbar(upNextIndices, totalRemainingMs, cs),
                    const SizedBox(height: 8),
                    Expanded(
                      child: upNextIndices.isEmpty
                          ? const Center(
                              child: AppEmptyState(
                                icon: Icons.queue_music_rounded,
                                title: 'Nothing up next',
                                message: 'Add songs to your queue or turn on autoplay.',
                              ),
                            )
                          : ReorderableListView.builder(
                              padding: const EdgeInsets.only(bottom: 100),
                              itemCount: upNextIndices.length,
                              buildDefaultDragHandles: false,
                              onReorderStart: (index) {
                                HapticFeedback.mediumImpact();
                                if (!_shuffleEnabled) {
                                  setState(() => _isReordering = true);
                                }
                              },
                              onReorderEnd: _shuffleEnabled
                                  ? null
                                  : (_) => setState(() => _isReordering = false),
                              proxyDecorator: (child, index, animation) {
                                return AnimatedBuilder(
                                  animation: animation,
                                  builder: (context, child) {
                                    final elevation = lerpDouble(2, 10, animation.value) ?? 6;
                                    final scale = lerpDouble(1.0, 1.02, animation.value) ?? 1.0;
                                    return Transform.scale(
                                      scale: scale,
                                      alignment: Alignment.centerLeft,
                                      child: Material(
                                        elevation: elevation,
                                        color: surfaceColor,
                                        shadowColor: Colors.black54,
                                        borderRadius: BorderRadius.circular(14),
                                        clipBehavior: Clip.antiAlias,
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: child,
                                );
                              },
                              onReorder: (oldIndex, newIndex) {
                                if (_shuffleEnabled) return;
                                if (oldIndex == newIndex) return;
                                final actualOld = upNextIndices[oldIndex];
                                var adjustedNew = newIndex > oldIndex ? newIndex - 1 : newIndex;
                                adjustedNew = adjustedNew.clamp(0, upNextIndices.length - 1);
                                final actualNew = upNextIndices[adjustedNew];
                                _moveItem(actualOld, actualNew);
                              },
                              itemBuilder: (context, index) {
                                final queueIndex = upNextIndices[index];
                                final song = _queue[queueIndex];
                                return _buildQueueTile(song, queueIndex, index);
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderToolbar(List<int> upNextIndices, int totalRemainingMs, ColorScheme cs) {
    final textColorSecondary = cs.onSurfaceVariant;
    final textColorTertiary = cs.onSurfaceVariant.withValues(alpha: 0.78);

    final durationStr = totalRemainingMs > 0 ? formatPlaylistDuration(totalRemainingMs) : null;
    final subtitleStr = upNextIndices.isEmpty
        ? 'No songs'
        : (durationStr != null ? '${upNextIndices.length} songs • $durationStr' : '${upNextIndices.length} songs');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Up Next',
                  style: TextStyle(
                    color: textColorSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitleStr,
                  style: TextStyle(
                    color: textColorTertiary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.playlist_add_rounded, size: 18),
            label: const Text('Save'),
            onPressed: _queue.isEmpty ? null : _saveAsPlaylist,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            icon: const Icon(Icons.clear_all_rounded, size: 20),
            tooltip: 'Clear upcoming',
            onPressed: upNextIndices.isEmpty ? null : _confirmClearQueue,
            style: IconButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentSongTile(SongModel song) {
    final cs = Theme.of(context).colorScheme;
    
    return StreamBuilder<PlayerState>(
      stream: widget.player.playerStateStream,
      builder: (context, snapshot) {
        final isPlaying = widget.player.playing;
        
        return UniversalSongTile(
          song: song,
          isCurrent: true,
          isPlaying: isPlaying,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          showMetaDuration: false,
          trailing: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.tertiaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              isPlaying ? Icons.graphic_eq_rounded : Icons.pause_rounded,
              color: cs.onTertiaryContainer,
              size: 20,
            ),
          ),
          onTap: () async {
            HapticFeedback.lightImpact();
            if (widget.player.playing) {
              await widget.player.pause();
            } else {
              unawaited(widget.player.play());
            }
          },
        );
      },
    );
  }

  Widget _buildQueueTile(SongModel song, int queueIndex, int displayIndex) {
    final cs = Theme.of(context).colorScheme;
    final textColorSecondary = cs.onSurfaceVariant;
    final textColorTertiary = cs.onSurfaceVariant.withValues(alpha: 0.78);
    final deleteBg = cs.errorContainer;
    final deleteFg = cs.onErrorContainer;

    return Dismissible(
      key: ValueKey('queue_song_${song.id}_$displayIndex'),
      direction: DismissDirection.endToStart,
      dismissThresholds: const {DismissDirection.endToStart: 0.35},
      movementDuration: const Duration(milliseconds: 220),
      resizeDuration: const Duration(milliseconds: 180),
      confirmDismiss: (_) async => true,
      onDismissed: (_) {
        HapticFeedback.mediumImpact();
        _removeItem(queueIndex, songId: song.id);
      },
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: deleteBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Remove',
              style: TextStyle(color: deleteFg, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            Icon(Icons.delete_rounded, color: deleteFg),
          ],
        ),
      ),
      child: UniversalSongTile(
        song: song,
        showMetaDuration: false,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        prefixLeading: Container(
          width: 24,
          alignment: Alignment.center,
          margin: const EdgeInsets.only(right: 6),
          child: Text(
            '${displayIndex + 1}',
            style: TextStyle(
              color: textColorSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              formatTime(song.duration),
              style: TextStyle(
                color: textColorTertiary,
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
            ReorderableDragStartListener(
              index: displayIndex,
              enabled: !_shuffleEnabled,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Icon(
                  Icons.drag_handle_rounded,
                  color: _shuffleEnabled
                      ? cs.outline.withValues(alpha: 0.3)
                      : cs.onSurfaceVariant.withValues(alpha: 0.7),
                  size: 20,
                ),
              ),
            ),
          ],
        ),
        onTap: () {
          widget.onPlayIndex(queueIndex);
          setState(() => _currentIndex = queueIndex);
        },
      ),
    );
  }
}
