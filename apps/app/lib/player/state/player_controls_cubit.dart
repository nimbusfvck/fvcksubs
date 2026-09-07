import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/app_player_controller.dart';

class PlayerControlsState {
  const PlayerControlsState({
    this.value = const AppPlayerValue(),
    this.controlsVisible = true,
    this.isBuffering = true,
    this.liveEdge = Duration.zero,
    this.dragValueMs,
    this.activeSubtitleLabel,
    this.activeQualityLabel,
    this.skipIntroLabel,
  });

  final AppPlayerValue value;
  final bool controlsVisible;
  final bool isBuffering;
  final Duration liveEdge;
  final double? dragValueMs;
  final String? activeSubtitleLabel;
  final String? activeQualityLabel;
  final String? skipIntroLabel;

  PlayerControlsState copyWith({
    AppPlayerValue? value,
    bool? controlsVisible,
    bool? isBuffering,
    Duration? liveEdge,
    Object? dragValueMs = _unchanged,
    Object? activeSubtitleLabel = _unchanged,
    Object? activeQualityLabel = _unchanged,
    Object? skipIntroLabel = _unchanged,
  }) => PlayerControlsState(
    value: value ?? this.value,
    controlsVisible: controlsVisible ?? this.controlsVisible,
    isBuffering: isBuffering ?? this.isBuffering,
    liveEdge: liveEdge ?? this.liveEdge,
    dragValueMs: identical(dragValueMs, _unchanged)
        ? this.dragValueMs
        : dragValueMs as double?,
    activeSubtitleLabel: identical(activeSubtitleLabel, _unchanged)
        ? this.activeSubtitleLabel
        : activeSubtitleLabel as String?,
    activeQualityLabel: identical(activeQualityLabel, _unchanged)
        ? this.activeQualityLabel
        : activeQualityLabel as String?,
    skipIntroLabel: identical(skipIntroLabel, _unchanged)
        ? this.skipIntroLabel
        : skipIntroLabel as String?,
  );
}

const _unchanged = Object();

class PlayerControlsCubit extends Cubit<PlayerControlsState> {
  PlayerControlsCubit({
    PlayerControlsState initial = const PlayerControlsState(),
  }) : super(initial);

  void update({
    required AppPlayerValue value,
    required bool controlsVisible,
    required bool isBuffering,
    required Duration liveEdge,
    required double? dragValueMs,
    required String? activeSubtitleLabel,
    required String? activeQualityLabel,
    required String? skipIntroLabel,
  }) => emit(
    PlayerControlsState(
      value: value,
      controlsVisible: controlsVisible,
      isBuffering: isBuffering,
      liveEdge: liveEdge,
      dragValueMs: dragValueMs,
      activeSubtitleLabel: activeSubtitleLabel,
      activeQualityLabel: activeQualityLabel,
      skipIntroLabel: skipIntroLabel,
    ),
  );

  void setControlsVisible(bool visible) {
    if (state.controlsVisible == visible) return;
    emit(state.copyWith(controlsVisible: visible));
  }

  void setDragValue(double? value) {
    if (state.dragValueMs == value) return;
    emit(state.copyWith(dragValueMs: value));
  }

  void setLiveEdge(Duration edge) {
    if (state.liveEdge == edge) return;
    emit(state.copyWith(liveEdge: edge));
  }

  void setLabels({String? subtitle, String? quality}) => emit(
    state.copyWith(activeSubtitleLabel: subtitle, activeQualityLabel: quality),
  );
}
