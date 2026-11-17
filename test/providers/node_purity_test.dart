import 'dart:async';

import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/node_purity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod/riverpod.dart';

class _MockCore extends Mock implements CoreHandlerInterface {}

const _groupName = 'Main';
const _node = Proxy(name: 'node-a', type: 'Trojan');

OutboundIpResult _answer(int score) => OutboundIpResult(
  body: '{"ip":"1.1.1.1","fraudScore":$score,"countryCode":"JP"}',
);

void main() {
  setUpAll(() => registerFallbackValue(const OutboundIpParams(timeout: 0)));

  late _MockCore core;
  setUp(() => core = _MockCore());

  ProviderContainer containerFor(List<Proxy> members) {
    final container = ProviderContainer(
      overrides: [
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        currentProfileIdProvider.overrideWithBuild((_, _) => 1),
        groupsProvider.overrideWithBuild(
          (_, _) => [
            Group(name: _groupName, type: GroupType.Selector, all: members),
            const Group(name: 'Auto', type: GroupType.URLTest, all: [_node]),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test(
    'pins each refresh to the node and clears failed risk results',
    () async {
      final results = [
        _answer(40),
        const OutboundIpResult(error: 'timeout'),
        _answer(71),
      ].iterator;
      when(() => core.outboundIp(any())).thenAnswer((_) async {
        results.moveNext();
        return results.current;
      });
      final container = containerFor(const [
        _node,
        Proxy(name: 'DIRECT', type: 'Direct'),
        Proxy(name: 'REJECT', type: 'Reject'),
        Proxy(name: 'Auto', type: 'URLTest'),
      ]);
      final notifier = container.read(nodePurityProvider.notifier);

      await notifier.scanGroup(_groupName);
      expect(container.read(nodePurityProvider).byNode[_node.name]?.score, 40);

      await notifier.scanGroup(_groupName);
      expect(container.read(nodePurityProvider).byNode, isEmpty);
      expect(container.read(nodePurityProvider).failedNodes, {_node.name});

      await notifier.scanGroup(_groupName);
      expect(container.read(nodePurityProvider).byNode[_node.name]?.score, 71);
      expect(container.read(nodePurityProvider).failedNodes, isEmpty);
      final calls = verify(() => core.outboundIp(captureAny())).captured;
      expect(calls, hasLength(3));
      expect(
        calls,
        everyElement(
          isA<OutboundIpParams>()
              .having((params) => params.proxyName, 'proxyName', _node.name)
              .having((params) => params.urls, 'urls', [
                'https://my.ippure.com/v1/info',
              ]),
        ),
      );
      verifyNoMoreInteractions(core);
    },
  );

  test(
    'bounds requests and discards pending results on profile change',
    () async {
      final pending = <Completer<OutboundIpResult>>[];
      when(() => core.outboundIp(any())).thenAnswer((_) {
        final completer = Completer<OutboundIpResult>();
        pending.add(completer);
        return completer.future;
      });
      final container = containerFor([
        for (var i = 0; i < 8; i++) Proxy(name: 'node-$i', type: 'Trojan'),
      ]);
      final scan = container
          .read(nodePurityProvider.notifier)
          .scanGroup(_groupName);
      expect(container.read(nodePurityProvider).testingGroups, {_groupName});
      await pumpEventQueue();
      expect(pending, hasLength(4));

      container.read(currentProfileIdProvider.notifier).value = 2;
      for (final completer in pending) {
        completer.complete(_answer(10));
      }
      await scan;

      expect(pending, hasLength(4));
      final state = container.read(nodePurityProvider);
      expect(state.byNode, isEmpty);
      expect(state.failedNodes, isEmpty);
      expect(state.testingGroups, isEmpty);
    },
  );
}
