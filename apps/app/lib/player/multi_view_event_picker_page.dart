import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fvcksubs_core/fvcksubs_core.dart';

import '../app_scope.dart';
import '../catalog/live_timeline_cubit.dart';
import '../theme/tokens.dart';

class MultiViewEventPickerPage extends StatefulWidget {
  const MultiViewEventPickerPage({super.key, required this.excludedRefs});

  final Set<MediaRef> excludedRefs;

  @override
  State<MultiViewEventPickerPage> createState() =>
      _MultiViewEventPickerPageState();
}

class _MultiViewEventPickerPageState extends State<MultiViewEventPickerPage> {
  late final CatalogTimelineCubit _cubit;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final scope = AppScope.of(context);
    _cubit = CatalogTimelineCubit(
      catalogCache: scope.catalogCache,
      registry: scope.registry,
    );
    unawaited(_load(scope));
  }

  Future<void> _load(AppScope scope, {bool refresh = false}) async {
    final category = scope.registry.categories.firstWhere(
      (value) => value.toLowerCase() == 'sport',
      orElse: () => 'sport',
    );
    final plugins = scope.registry.pluginsFor(category);
    final pluginId = scope.pluginController.resolve([
      for (final plugin in plugins) plugin.id,
    ]);
    final bindings = [
      for (final binding in scope.registry.catalogsFor(category))
        if (pluginId == null || binding.extensionId == pluginId) binding,
    ];
    await _cubit.load(bindings, category: category, refresh: refresh);
  }

  @override
  void dispose() {
    unawaited(_cubit.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Choose live event')),
      body: BlocProvider<CatalogTimelineCubit>.value(
        value: _cubit,
        child: BlocBuilder<CatalogTimelineCubit, CatalogTimelineState>(
          builder: (context, state) {
            final events = [
              for (final event in state.events)
                if (!widget.excludedRefs.contains(event.ref) &&
                    !isMultiViewEventEnded(event))
                  event,
            ];
            if (state.isLoading && events.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (events.isEmpty) {
              return RefreshIndicator(
                onRefresh: () => _load(scope, refresh: true),
                child: ListView(
                  children: const [
                    SizedBox(height: 240),
                    Center(child: Text('No other live events available.')),
                  ],
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: () => _load(scope, refresh: true),
              child: ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: events.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.xs),
                itemBuilder: (context, index) {
                  final event = events[index];
                  return ListTile(
                    tileColor: AppColors.surfaceDark,
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
                    title: Text(multiViewEventTitle(event)),
                    subtitle: Text(multiViewEventStatus(event)),
                    trailing: const Icon(Icons.add_circle_outline),
                    onTap: () => Navigator.of(context).pop(event),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

bool isMultiViewEventEnded(EventItemV2 event) {
  if (event.schedule.state == ScheduleState.ended) return true;
  final endsAt = event.schedule.endsAt?.toLocal();
  return endsAt != null && !DateTime.now().isBefore(endsAt);
}

String multiViewEventTitle(EventItemV2 event) {
  final participants = event.participants
      .take(2)
      .map((participant) => participant.name)
      .where((name) => name.trim().isNotEmpty)
      .toList();
  return participants.length == 2 ? participants.join(' vs ') : event.title;
}

String multiViewEventStatus(EventItemV2 event) {
  if (!isMultiViewEventEnded(event) &&
      !DateTime.now().isBefore(event.schedule.startsAt.toLocal())) {
    return 'LIVE';
  }
  return 'Starts ${_formatEventTime(event.schedule.startsAt.toLocal())}';
}

String _formatEventTime(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
