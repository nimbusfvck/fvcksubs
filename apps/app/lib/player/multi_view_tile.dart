part of 'multi_view_page.dart';

class _MultiViewTile extends StatefulWidget {
  const _MultiViewTile({
    super.key,
    required this.entry,
    required this.muted,
    required this.controller,
    required this.playerBuilder,
    required this.onControllerCreated,
    required this.error,
    required this.retrying,
    required this.onTogglePlayback,
    required this.onSelectAudio,
    required this.onRemove,
    required this.onRetry,
    required this.onChangeSource,
    required this.sourceLoading,
    required this.onTogglePinned,
    required this.pinned,
    required this.onOpenSinglePlayer,
    required this.audioActive,
  });

  final _MultiViewEntry entry;
  final bool muted;
  final AppPlayerController? controller;
  final PlayerBuilder playerBuilder;
  final void Function(Object? controller) onControllerCreated;
  final String? error;
  final bool retrying;
  final VoidCallback onTogglePlayback;
  final VoidCallback onSelectAudio;
  final VoidCallback onRemove;
  final VoidCallback onRetry;
  final VoidCallback onChangeSource;
  final bool sourceLoading;
  final VoidCallback onTogglePinned;
  final bool pinned;
  final VoidCallback? onOpenSinglePlayer;
  final bool audioActive;

  @override
  State<_MultiViewTile> createState() => _MultiViewTileState();
}

class _MultiViewTileState extends State<_MultiViewTile> {
  static const _controlsHideDelay = Duration(seconds: 3);

  Timer? _hideTimer;
  AppPlayerController? _listenedController;
  bool _controlsVisible = true;
  bool _wasPlaying = false;
  bool _wasBuffering = true;

  @override
  void initState() {
    super.initState();
    _attachController(widget.controller);
  }

  @override
  void didUpdateWidget(covariant _MultiViewTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _attachController(widget.controller);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _listenedController?.value.removeListener(_onValueChanged);
    super.dispose();
  }

  void _attachController(AppPlayerController? controller) {
    _listenedController?.value.removeListener(_onValueChanged);
    _listenedController = controller;
    _wasPlaying = false;
    _wasBuffering = true;
    controller?.value.addListener(_onValueChanged);
    _syncVisibilityWithPlayback();
  }

  void _onValueChanged() {
    if (!mounted) return;
    _syncVisibilityWithPlayback();
  }

  void _syncVisibilityWithPlayback() {
    final value = widget.controller?.value.value;
    final initialized = value?.initialized ?? false;
    final buffering = value?.isBuffering ?? true;
    final playing = value?.isPlaying ?? false;
    if (!initialized || buffering) {
      _hideTimer?.cancel();
      _setControlsVisible(true);
    } else if (!playing) {
      _hideTimer?.cancel();
      _setControlsVisible(true);
    } else if (!_wasPlaying || _wasBuffering) {
      _armHideTimer();
    }
    _wasPlaying = playing;
    _wasBuffering = buffering || !initialized;
  }

  void _armHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_controlsHideDelay, () {
      _hideTimer = null;
      _setControlsVisible(false);
    });
  }

  void _setControlsVisible(bool visible) {
    if (!mounted || _controlsVisible == visible) return;
    setState(() => _controlsVisible = visible);
  }

  void _revealControls() {
    _setControlsVisible(true);
    final value = widget.controller?.value.value;
    if (value?.initialized == true &&
        value?.isPlaying == true &&
        value?.isBuffering == false) {
      _armHideTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ClipRRect(
      borderRadius: AppRadius.md,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Colors.black),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => _revealControls(),
          child: MouseRegion(
            onHover: (_) => _revealControls(),
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.playerBuilder(
                  context,
                  widget.entry.source.stream,
                  isLive: true,
                  muted: widget.muted,
                  mixWithOthers: true,
                  playing: true,
                  wakelock: false,
                  fit: BoxFit.contain,
                  preferredSubtitleLanguage: null,
                  preferredQualityMaxHeight:
                      scope.qualityPreferenceController.maxHeight,
                  subtitleAppearance:
                      scope.subtitlePreferenceController.appearance,
                  onControllerCreated: widget.onControllerCreated,
                  key: ValueKey('${widget.entry.key}/player'),
                ),
                Positioned(
                  left: AppSpacing.md,
                  right: AppSpacing.md,
                  top: 56,
                  bottom: 56,
                  child: widget.error == null
                      ? const SizedBox.shrink()
                      : DecoratedBox(
                          decoration: const BoxDecoration(
                            color: Color(0xCC000000),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.error!,
                                  style: const TextStyle(color: Colors.white),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                FilledButton.icon(
                                  onPressed: widget.retrying
                                      ? null
                                      : widget.onRetry,
                                  icon: widget.retrying
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.refresh),
                                  label: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: AnimatedOpacity(
                      opacity: _controlsVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            child: DecoratedBox(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0xE6000000),
                                    Color(0x7A000000),
                                    Colors.transparent,
                                  ],
                                  stops: [0, 0.55, 1],
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.sm,
                                  AppSpacing.xs,
                                  AppSpacing.sm,
                                  AppSpacing.md,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        multiViewEventTitle(widget.entry.event),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTypography.bodySm.copyWith(
                                          color: AppColors.onDark,
                                          shadows: const [
                                            Shadow(
                                              color: Colors.black54,
                                              blurRadius: 4,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: widget.sourceLoading
                                          ? null
                                          : widget.onChangeSource,
                                      icon: widget.sourceLoading
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(Icons.tune_rounded),
                                      color: Colors.white,
                                      tooltip: 'Change source',
                                    ),
                                    IconButton(
                                      onPressed: widget.onTogglePinned,
                                      icon: Icon(
                                        widget.pinned
                                            ? Icons.push_pin_rounded
                                            : Icons.push_pin_outlined,
                                      ),
                                      color: Colors.white,
                                      tooltip: widget.pinned
                                          ? 'Unpin player'
                                          : 'Pin player',
                                    ),
                                    if (widget.onOpenSinglePlayer != null)
                                      IconButton(
                                        onPressed: widget.onOpenSinglePlayer,
                                        icon: const Icon(
                                          Icons.fullscreen_rounded,
                                        ),
                                        color: Colors.white,
                                        tooltip: 'Single player',
                                      ),
                                    IconButton(
                                      onPressed: widget.onRemove,
                                      icon: const Icon(Icons.close),
                                      color: Colors.white,
                                      tooltip: 'Remove event',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (widget.error == null && widget.retrying)
                            const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            )
                          else if (widget.error == null)
                            Center(
                              child: ValueListenableBuilder<AppPlayerValue>(
                                valueListenable:
                                    widget.controller?.value ??
                                    _emptyPlayerValue,
                                builder: (context, value, _) => DecoratedBox(
                                  decoration: const BoxDecoration(
                                    color: Color(0x99000000),
                                    shape: BoxShape.circle,
                                  ),
                                  child: IconButton(
                                    onPressed:
                                        value.isBuffering || !value.initialized
                                        ? null
                                        : widget.onTogglePlayback,
                                    icon:
                                        value.isBuffering || !value.initialized
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Icon(
                                            value.isPlaying
                                                ? Icons.pause_rounded
                                                : Icons.play_arrow_rounded,
                                          ),
                                    color: Colors.white,
                                    tooltip:
                                        value.isBuffering || !value.initialized
                                        ? 'Loading'
                                        : value.isPlaying
                                        ? 'Pause'
                                        : 'Play',
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            right: AppSpacing.sm,
                            bottom: AppSpacing.sm,
                            child: DecoratedBox(
                              decoration: const BoxDecoration(
                                color: Color(0x99000000),
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                onPressed: widget.onSelectAudio,
                                icon: Icon(
                                  widget.audioActive
                                      ? Icons.volume_up_rounded
                                      : Icons.volume_off,
                                ),
                                color: Colors.white,
                                tooltip: widget.audioActive
                                    ? 'Audio aktif'
                                    : 'Pilih audio',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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

class _AddEventTile extends StatelessWidget {
  const _AddEventTile({
    required this.loading,
    required this.onTap,
    required this.maxSlots,
  });

  final bool loading;
  final VoidCallback onTap;
  final int maxSlots;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceDark,
    borderRadius: AppRadius.md,
    child: InkWell(
      onTap: loading ? null : onTap,
      borderRadius: AppRadius.md,
      child: Center(
        child: loading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_circle_outline, size: 36),
                  const SizedBox(height: AppSpacing.sm),
                  const Text('Add live event'),
                  const SizedBox(height: AppSpacing.xs),
                  Text('Up to $maxSlots live events'),
                ],
              ),
      ),
    ),
  );
}
