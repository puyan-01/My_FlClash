import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/ippure.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NodePurityState {
  const NodePurityState({
    this.byNode = const {},
    this.testingGroups = const {},
  });

  final Map<String, IpPurity> byNode;
  final Set<String> testingGroups;

  NodePurityState copyWith({
    Map<String, IpPurity>? byNode,
    Set<String>? testingGroups,
  }) {
    return NodePurityState(
      byNode: byNode ?? this.byNode,
      testingGroups: testingGroups ?? this.testingGroups,
    );
  }
}

final nodePurityProvider =
    NotifierProvider<NodePurityNotifier, NodePurityState>(
      NodePurityNotifier.new,
    );

class NodePurityNotifier extends Notifier<NodePurityState> {
  /// 判定节点是否合格的上限，对应 IPPure 的 fraudScore。
  static const threshold = 40;

  static const _settle = Duration(milliseconds: 350);

  @override
  NodePurityState build() => const NodePurityState();

  bool isTesting(String groupName) =>
      state.testingGroups.contains(groupName);

  /// 逐个切到组内节点并查询出口 IP 的纯净度。切换期间会断开现有连接。
  Future<void> scanGroup(String groupName) async {
    if (state.testingGroups.contains(groupName)) {
      return;
    }
    final group = ref.read(groupsProvider).getGroup(groupName);
    if (group == null || group.all.isEmpty) {
      return;
    }
    final members = group.all.toList();
    final action = ref.read(proxiesActionProvider.notifier);
    final previous = ref.read(proxyNameProvider(groupName));
    state = state.copyWith(
      testingGroups: {...state.testingGroups, groupName},
    );
    try {
      for (final proxy in members) {
        await action.changeProxy(groupName: groupName, proxyName: proxy.name);
        await Future<void>.delayed(_settle);
        final purity = await fetchIpPurity(request.dio);
        if (purity != null) {
          state = state.copyWith(
            byNode: {...state.byNode, proxy.name: purity},
          );
        }
      }
    } finally {
      if (previous != null &&
          previous.isNotEmpty &&
          previous != groupName) {
        await action.changeProxy(groupName: groupName, proxyName: previous);
      }
      state = state.copyWith(
        testingGroups: state.testingGroups
            .where((name) => name != groupName)
            .toSet(),
      );
    }
  }
}
