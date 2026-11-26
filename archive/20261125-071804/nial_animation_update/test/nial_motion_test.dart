import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nial_diary/services/nial_motion.dart';

void main() {
  testWidgets('entrance settles with one child', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: NialEntrance(child: Text('entry')))));
    await tester.pumpAndSettle();
    expect(find.text('entry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('reduced motion skips entrance', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: NialEntrance(child: Text('reduced')))));
    final fade = tester.widget<FadeTransition>(find.descendant(
      of: find.byType(NialEntrance), matching: find.byType(FadeTransition)));
    expect(fade.opacity.value, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('press feedback preserves tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: NialPressFeedback(child: GestureDetector(
        onTap: () => taps++,
        child: const SizedBox(width: 80, height: 80, child: Text('tap')))))));
    await tester.tap(find.text('tap'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
}
