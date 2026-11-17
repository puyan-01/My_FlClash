import 'dart:math' as math;

import 'package:fl_clash/common/ippure.dart';
import 'package:fl_clash/common/task_pool.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'config.dart';
import 'core.dart';
import 'route_state.dart';

class NodePurityState {
  const NodePurityState({
    this.byNode = const {},
    this.testingGroups = const {},
    this.failedNodes = const {},
  });

  final Map<String, IpPurity> byNode;
  final Set<String> testingGroups;
  final Set<String> failedNodes;

  NodePurityState copyWith({
    Map<String, IpPurity>? byNode,
    Set<String>? testingGroups,
    Set<String>? failedNodes,
  }) {
    return NodePurityState(
      byNode: byNode ?? this.byNode,
      testingGroups: testingGroups ?? this.testingGroups,
      failedNodes: failedNodes ?? this.failedNodes,
    );
  }
}

final nodePurityProvider =
    NotifierProvider<NodePurityNotifier, NodePurityState>(
      NodePurityNotifier.new,
    );

class NodePurityNotifier extends Notifier<NodePurityState> {
  static const _nonNodeTypes = {
    'compatible',
    'direct',
    'dns',
    'pass',
    'passrule',
    'reject',
    'rejectdrop',
    'rematch',
  };

  final _pool = TaskPool(4);
  final _latestScan = <String, Object>{};
  int _generation = 0;

  @override
  NodePurityState build() {
    ref.onDispose(() {
      _generation++;
      _latestScan.clear();
    });
    ref.listen(currentProfileIdProvider, (_, _) => _reset());
    ref.listen(coreStatusProvider, (_, status) {
      if (status != CoreStatus.connected) _reset();
    });
    ref.listen(
      routeTrackerProvider.select(
        (route) => route.synced ? route.coreEpoch : null,
      ),
      (previous, next) {
        if (previous != null && next != null) _reset();
      },
    );
    return const NodePurityState();
  }

  void _reset() {
    _generation++;
    _latestScan.clear();
    state = const NodePurityState();
  }

  Future<void> scanGroup(String groupName) async {
    if (state.testingGroups.contains(groupName)) {
      return;
    }
    final groups = ref.read(groupsProvider);
    final group = groups.getGroup(groupName);
    if (group == null) {
      return;
    }
    final members = {
      for (final proxy in group.all)
        if (proxy.name.isNotEmpty &&
            !_nonNodeTypes.contains(proxy.type.toLowerCase()) &&
            groups.getGroup(proxy.name) == null)
          proxy.name,
    };
    if (members.isEmpty) {
      return;
    }

    final core = ref.read(coreHandlerProvider);
    final generation = _generation;
    final scan = Object();
    for (final name in members) {
      _latestScan[name] = scan;
    }
    state = state.copyWith(
      testingGroups: Set.unmodifiable({...state.testingGroups, groupName}),
    );

    bool isCurrent() => ref.mounted && generation == _generation;

    final nodes = members.iterator;
    Future<void> runWorker() async {
      while (isCurrent() && nodes.moveNext()) {
        final node = nodes.current;
        await _pool.run(() async {
          if (!isCurrent() || _latestScan[node] != scan) return;
          final purity = await fetchIpPurity(core, proxyName: node);
          if (!isCurrent() || _latestScan[node] != scan) return;
          _latestScan.remove(node);
          _recordResult(node, purity);
        });
      }
    }

    try {
      await Future.wait([
        for (var i = 0; i < math.min(members.length, _pool.concurrency); i++)
          runWorker(),
      ]);
    } finally {
      if (isCurrent()) {
        state = state.copyWith(
          testingGroups: Set.unmodifiable(
            {...state.testingGroups}..remove(groupName),
          ),
        );
      }
    }
  }

  void _recordResult(String node, IpPurity? purity) {
    if (purity == null) {
      state = state.copyWith(
        byNode: Map.unmodifiable({...state.byNode}..remove(node)),
        failedNodes: Set.unmodifiable({...state.failedNodes, node}),
      );
      return;
    }
    state = state.copyWith(
      byNode: Map.unmodifiable({...state.byNode, node: purity}),
      failedNodes: Set.unmodifiable({...state.failedNodes}..remove(node)),
    );
  }
}
