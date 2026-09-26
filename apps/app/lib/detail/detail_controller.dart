import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';
import 'package:fvcksubs_extension_host/fvcksubs_extension_host.dart';

import 'detail_state.dart';

class DetailController extends Cubit<DetailState> {
  DetailController({required this.registry, required MediaItemV2 item})
    : super(DetailState(item: item));

  final ExtensionRegistry registry;

  int _detailRequest = 0;

  Future<void> load() async {
    final request = ++_detailRequest;
    emit(state.copyWith(status: DetailStatus.loading));
    try {
      final detail = await registry.meta(state.item.ref);
      if (isClosed || request != _detailRequest) return;
      emit(state.copyWith(status: DetailStatus.ready, detail: detail));
    } catch (_) {
      if (isClosed || request != _detailRequest) return;
      emit(
        state.copyWith(
          status: DetailStatus.ready,
          detail: MediaDetailV2(item: state.item),
        ),
      );
    }
  }

  Future<void> loadGroup(String groupId) async {
    if (state.isGroupLoading(groupId)) return;
    final loading = {...state.loadingGroupIds, groupId};
    final errors = {...state.groupErrors}..remove(groupId);
    emit(state.copyWith(loadingGroupIds: loading, groupErrors: errors));

    try {
      final loaded = await registry.meta(state.item.ref, groupId: groupId);
      if (isClosed) return;
      final loadedGroup = loaded.episodeGuide?.groups
          .where((group) => group.id == groupId)
          .firstOrNull;
      final current = state.detail;
      final currentGuide = current?.episodeGuide;
      if (loadedGroup == null ||
          !loadedGroup.loaded ||
          current == null ||
          currentGuide == null) {
        throw StateError('Detail group $groupId was not loaded');
      }

      final guide = EpisodeGuide(
        groups: [
          for (final group in currentGuide.groups)
            group.id == groupId ? loadedGroup : group,
        ],
        defaultEpisodeRef:
            currentGuide.defaultEpisodeRef ??
            loaded.episodeGuide?.defaultEpisodeRef,
      );
      emit(
        state.copyWith(
          detail: MediaDetailV2(
            item: current.item,
            description: current.description,
            tags: current.tags,
            facts: current.facts,
            credits: current.credits,
            trailers: current.trailers,
            collection: current.collection,
            recommendations: current.recommendations,
            episodeGuide: guide,
            channelGuide: current.channelGuide,
          ),
        ),
      );
    } catch (error) {
      if (!isClosed) {
        emit(
          state.copyWith(groupErrors: {...state.groupErrors, groupId: error}),
        );
      }
    } finally {
      if (!isClosed) {
        emit(
          state.copyWith(
            loadingGroupIds: {...state.loadingGroupIds}..remove(groupId),
          ),
        );
      }
    }
  }
}
