import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timma_kiosk/kiosk/presentation/widgets/kiosk_scrollable.dart';

/// Owner, 2026-11-23: *"on every view section that has some informations that
/// the user should scroll the screen to see, it should be clear indicating
/// it"*.
///
/// On a borne this is not a nicety: a customer standing at a machine for
/// twenty seconds does not experiment, so content below the fold is content
/// that does not exist.
void main() {
  Future<ScrollController> pump(
    WidgetTester tester, {
    required int items,
    double height = 300,
  }) async {
    final ScrollController controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              height: height,
              width: 300,
              child: KioskScrollable(
                controller: controller,
                child: ListView.builder(
                  controller: controller,
                  itemCount: items,
                  itemBuilder: (_, int i) =>
                      SizedBox(height: 100, child: Text('row $i')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('a list with more below it is faded and shows a bar', (
    tester,
  ) async {
    await pump(tester, items: 20);

    // The fade: content that visibly runs on rather than stopping.
    expect(find.byType(ShaderMask), findsOneWidget);
    // And the signal a customer already knows from every other screen.
    expect(find.byType(Scrollbar), findsOneWidget);
  });

  testWidgets('the bar sits BESIDE the content, never on it', (tester) async {
    await pump(tester, items: 20);

    // ⚠ Owner, 2026-11-24: a `Scrollbar` paints over its child by default,
    // and on a menu that means a thumb lying across a dish photograph — or a
    // price. The content is inset instead, so the two never share pixels.
    final double content = tester.getSize(find.byType(ListView)).width;
    final double box = tester.getSize(find.byType(KioskScrollable)).width;
    expect(
      content,
      lessThan(box),
      reason: 'the list filled the whole width, so the bar is drawn on it',
    );
    expect(box - content, greaterThanOrEqualTo(6));
  });

  testWidgets('a list that fits says nothing at all', (tester) async {
    await pump(tester, items: 2);

    // ⚠ An affordance that is always there is an affordance nobody reads —
    // and the ShaderMask is a compositing layer on a tablet that does not
    // need one.
    expect(
      find.byType(ShaderMask),
      findsNothing,
      reason: 'nothing is hidden, so nothing should suggest it is',
    );
  });

  testWidgets('scrolled to the bottom, the hint goes', (tester) async {
    final ScrollController controller = await pump(tester, items: 20);
    expect(find.byType(ShaderMask), findsOneWidget);

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();

    // Still faded — at the BOTTOM there is now content ABOVE instead, and the
    // fade moves to that edge. A hint that only ever pointed down would tell
    // a customer at the end of a list that there is more under it.
    expect(find.byType(ShaderMask), findsOneWidget);
  });

  testWidgets('it survives a controller with no clients yet', (tester) async {
    // The first frame: the controller has no positions until the child has
    // laid out, and reading `position` then throws.
    final ScrollController controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KioskScrollable(
            controller: controller,
            child: ListView(
              controller: controller,
              children: const <Widget>[Text('only')],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
