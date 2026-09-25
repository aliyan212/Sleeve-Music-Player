
import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/app_state_controller.dart';
import '../services/playback_controller.dart';
import '../ui/shared/bottom_bars_gutter.dart';
import '../data/models/app_tab.dart';
import 'tabs/album_artists_tab.dart';
import 'tabs/albums_tab.dart';
import 'tabs/folders_tab.dart';
import 'tabs/genres_tab.dart';
import 'tabs/library_tab.dart';
import 'tabs/playlists_tab.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, this.initialTabIndex = 0});
  final int initialTabIndex;
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final AppStateController _appState = AppStateController.instance;
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _showSearchInAppBar = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isVerticalDragActive = ValueNotifier<bool>(false);
  Offset? _pointerDownPos;
  late final PageController _pageController;
  late int _lastRenderedTabIndex;

  @override
  void initState() {
    super.initState();
    playbackController.attachStreamListeners();
    _lastRenderedTabIndex = widget.initialTabIndex;
    _pageController = PageController(initialPage: widget.initialTabIndex);
    _appState.selectedTabIndex = widget.initialTabIndex;
    _appState.ensureLibraryPermissionAndLoad(fromUserAction: false);
    _appState.loadUserPlaylists();
    _appState.addListener(_onAppStateChanged);
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _appState.removeListener(_onAppStateChanged);
    _pageController.dispose();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _showSearchInAppBar.dispose();
    _isVerticalDragActive.dispose();
    super.dispose();
  }

  void _onAppStateChanged() {
    if (!mounted) return;
    final maxIndex = _appState.activeTabs.isEmpty ? 0 : _appState.activeTabs.length - 1;
    final currentTarget = _appState.selectedTabIndex.clamp(0, maxIndex);
    if (_appState.selectedTabIndex != currentTarget) {
      _appState.selectedTabIndex = currentTarget;
    }
    if (_lastRenderedTabIndex != currentTarget) {
      _lastRenderedTabIndex = currentTarget;
      FocusManager.instance.primaryFocus?.unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
      if (_pageController.hasClients && _pageController.page?.round() != currentTarget) {
        _pageController.animateToPage(
          currentTarget,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      }
    }
    setState(() {});
  }

  Widget _buildTabChild(AppTab tab) {
    switch (tab) {
      case AppTab.songs:
        return _KeepAlivePage(
          key: const PageStorageKey<String>('tab_library'),
          child: LibraryTab(
            scrollController: _scrollController,
            showSearchInAppBar: _showSearchInAppBar,
          ),
        );
      case AppTab.albums:
        return const _KeepAlivePage(
          key: PageStorageKey<String>('tab_albums'),
          child: AlbumsTab(),
        );
      case AppTab.artists:
        return const _KeepAlivePage(
          key: PageStorageKey<String>('tab_artists'),
          child: AlbumArtistsTab(),
        );
      case AppTab.genres:
        return const _KeepAlivePage(
          key: PageStorageKey<String>('tab_genres'),
          child: GenresTab(),
        );
      case AppTab.playlists:
        return const _KeepAlivePage(
          key: PageStorageKey<String>('tab_playlists'),
          child: PlaylistsTab(),
        );
      case AppTab.folders:
        return const _KeepAlivePage(
          key: PageStorageKey<String>('tab_folders'),
          child: FoldersTab(),
        );
    }
  }

  void _handleScroll() {
    final shouldShow = _scrollController.hasClients && _scrollController.offset > 50;
    if (_showSearchInAppBar.value != shouldShow) {
      _showSearchInAppBar.value = shouldShow;
    }
  }

  Widget _animatedBottomBars() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: AnimatedSlide(
          offset: _appState.isSelectionMode ? const Offset(0, 1) : Offset.zero,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: _appState.isSelectionMode ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: buildDetailBottomBars(
              context: context,
              player: playbackController.player,
              songs: _appState.songs,
              currentIndex: playbackController.currentIndex,
              onQueueChanged: (_) {},
              onOpenNowPlaying: (song) => _appState.openNowPlaying(context, song),
              selectedTabIndex: _appState.selectedTabIndex,
              onNavigateTab: _appState.selectTab,
              enableHero: true,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_appState.isSelectionMode && _appState.inlineDetailContent == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_appState.isSelectionMode) {
          HapticFeedback.selectionClick();
          FocusManager.instance.primaryFocus?.unfocus();
          SystemChannels.textInput.invokeMethod('TextInput.hide');
          _appState.exitSelectionMode();
          return;
        }
        if (_appState.inlineDetailContent != null) {
          HapticFeedback.selectionClick();
          FocusManager.instance.primaryFocus?.unfocus();
          SystemChannels.textInput.invokeMethod('TextInput.hide');
          _appState.closeInlineDetail();
        }
      },
      child: Scaffold(
        extendBody: true,
        bottomNavigationBar: _animatedBottomBars(),
        body: _appState.permissionState != LibraryPermissionState.granted
            ? (_appState.permissionState == LibraryPermissionState.unknown
                  ? const Center(child: CircularProgressIndicator())
                  : _LibraryPermissionGate(
                      state: _appState.permissionState,
                      onGrant: () => _appState.ensureLibraryPermissionAndLoad(
                        fromUserAction: true,
                      ),
                      onOpenSettings: openAppSettings,
                    ))
            : _appState.isLoading
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                    IgnorePointer(
                      ignoring: _appState.inlineDetailContent != null,
                      child: Listener(
                        onPointerDown: (e) {
                          _pointerDownPos = e.position;
                          if (FocusManager.instance.primaryFocus?.hasFocus ?? false) {
                            FocusManager.instance.primaryFocus?.unfocus();
                            SystemChannels.textInput.invokeMethod('TextInput.hide');
                          }
                        },
                        onPointerMove: (e) {
                          if (_pointerDownPos != null && !_isVerticalDragActive.value) {
                            final dx = (e.position.dx - _pointerDownPos!.dx).abs();
                            final dy = (e.position.dy - _pointerDownPos!.dy).abs();
                            // When dragging vertically or diagonally, lock horizontal swipe
                            // so vertical lists scroll smoothly without accidental tab switches.
                            if (dy > 6.0 && dy >= dx) {
                              _isVerticalDragActive.value = true;
                            }
                          }
                        },
                        onPointerUp: (_) {
                          _pointerDownPos = null;
                          if (_isVerticalDragActive.value) {
                            _isVerticalDragActive.value = false;
                          }
                        },
                        onPointerCancel: (_) {
                          _pointerDownPos = null;
                          if (_isVerticalDragActive.value) {
                            _isVerticalDragActive.value = false;
                          }
                        },
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (notification.metrics.axis == Axis.vertical) {
                              if (notification is ScrollStartNotification &&
                                  notification.dragDetails != null) {
                                if (!_isVerticalDragActive.value) {
                                  _isVerticalDragActive.value = true;
                                }
                              } else if (notification is ScrollEndNotification) {
                                if (_isVerticalDragActive.value) {
                                  _isVerticalDragActive.value = false;
                                }
                              }
                            }
                            return false;
                          },
                          child: ValueListenableBuilder<bool>(
                            valueListenable: _isVerticalDragActive,
                            builder: (context, isVerticalDrag, _) {
                              return PageView(
                                controller: _pageController,
                                physics: (_appState.isSelectionMode || isVerticalDrag)
                                    ? const NeverScrollableScrollPhysics()
                                    : const PageScrollPhysics(),
                                onPageChanged: (index) {
                                  _lastRenderedTabIndex = index;
                                  FocusManager.instance.primaryFocus?.unfocus();
                                  SystemChannels.textInput.invokeMethod('TextInput.hide');
                                  if (_appState.selectedTabIndex != index) {
                                    _appState.selectTab(index);
                                  }
                                },
                                children: _appState.activeTabs.map(_buildTabChild).toList(),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    PageTransitionSwitcher(
                      reverse: _appState.inlineDetailContent == null,
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (
                        Widget child,
                        Animation<double> primaryAnimation,
                        Animation<double> secondaryAnimation,
                      ) {
                        return SharedAxisTransition(
                          animation: primaryAnimation,
                          secondaryAnimation: secondaryAnimation,
                          transitionType: SharedAxisTransitionType.scaled,
                          fillColor: Colors.transparent,
                          child: child,
                        );
                      },
                      child: _appState.inlineDetailContent != null
                          ? KeyedSubtree(
                              key: ValueKey<int>(_appState.inlineDetailContent.hashCode),
                              child: _appState.inlineDetailContent!,
                            )
                          : const SizedBox.shrink(key: ValueKey<String>('empty_detail')),
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
  }
}

class _LibraryPermissionGate extends StatelessWidget {
  final LibraryPermissionState state;
  final VoidCallback onGrant;
  final VoidCallback onOpenSettings;

  const _LibraryPermissionGate({
    required this.state,
    required this.onGrant,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = switch (state) {
      LibraryPermissionState.permanentlyDenied => 'Music access blocked',
      LibraryPermissionState.denied => 'Allow access to your music',
      LibraryPermissionState.unknown => 'Preparing your library',
      LibraryPermissionState.granted => 'Ready',
    };

    final body = switch (state) {
      LibraryPermissionState.permanentlyDenied =>
        'Permission was denied permanently. Open Settings and enable Music/Audio access to scan your library.',
      LibraryPermissionState.denied =>
        'To show your on-device songs, the app needs permission to read your audio library. Nothing is uploaded.',
      LibraryPermissionState.unknown =>
        'We’ll ask for access only when you’re ready.',
      LibraryPermissionState.granted => 'All set!',
    };

    final buttonLabel =
        state == LibraryPermissionState.permanentlyDenied
            ? 'Open Settings'
            : 'Allow Access';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.library_music, size: 64, color: cs.primary),
            const SizedBox(height: 24),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              body,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            if (state != LibraryPermissionState.unknown)
              FilledButton.icon(
                onPressed:
                    state == LibraryPermissionState.permanentlyDenied
                        ? onOpenSettings
                        : onGrant,
                icon: const Icon(Icons.check),
                label: Text(buttonLabel),
              ),
          ],
        ),
      ),
    );
  }
}

class _KeepAlivePage extends StatefulWidget {
  final Widget child;
  const _KeepAlivePage({super.key, required this.child});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
