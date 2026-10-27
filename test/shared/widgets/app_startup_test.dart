import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediagrab/shared/widgets/app_startup.dart';

void main() {
  testWidgets('flushes on background and detachment, unregisters on disposal', (
    tester,
  ) async {
    var flushes = 0;
    await tester.pumpWidget(
      AppStartup(onBackground: () => flushes++, child: const SizedBox()),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(flushes, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(flushes, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    expect(flushes, 2);
    // A paused test binding does not render the replacement/dispose its child.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(flushes, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('renders destination immediately and runs ready work once', (
    tester,
  ) async {
    var calls = 0;
    var destinationWasMounted = false;
    Widget app() => MaterialApp(
      home: AppStartup(
        onReady: () {
          calls++;
          destinationWasMounted = find.text('Ready').evaluate().isNotEmpty;
        },
        child: const Scaffold(body: Text('Ready')),
      ),
    );
    await tester.pumpWidget(app());
    expect(find.text('Ready'), findsOneWidget);
    expect(destinationWasMounted, isTrue);
    expect(calls, 1);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(app());
    await tester.pump(const Duration(seconds: 2));
    expect(calls, 1);
    expect(find.text('Ready'), findsOneWidget);
  });
}
