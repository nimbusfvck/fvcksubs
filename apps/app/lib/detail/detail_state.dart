import 'package:fvcksubs_core/fvcksubs_core.dart';

enum DetailStatus { initial, loading, ready }

class DetailState {
  const DetailState({
    required this.item,
    this.status = DetailStatus.initial,
    this.detail,
    this.loadingGroupIds = const {},
    this.groupErrors = const {},
  });

  final MediaItemV2 item;
  final DetailStatus status;
  final MediaDetailV2? detail;
  final Set<String> loadingGroupIds;
  final Map<String, Object> groupErrors;

  bool get metadataLoading => status != DetailStatus.ready;

  bool isGroupLoading(String groupId) => loadingGroupIds.contains(groupId);

  Object? groupErrorFor(String groupId) => groupErrors[groupId];

  DetailState copyWith({
    DetailStatus? status,
    MediaDetailV2? detail,
    Set<String>? loadingGroupIds,
    Map<String, Object>? groupErrors,
  }) => DetailState(
    item: item,
    status: status ?? this.status,
    detail: detail ?? this.detail,
    loadingGroupIds: loadingGroupIds ?? this.loadingGroupIds,
    groupErrors: groupErrors ?? this.groupErrors,
  );
}
