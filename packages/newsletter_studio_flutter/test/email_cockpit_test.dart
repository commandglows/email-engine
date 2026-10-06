import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newsletter_studio_flutter/newsletter_studio_flutter.dart';

void main() {
  testWidgets('loads sections lazily and retains state when switching', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final built = <EmailSection>{};
    await tester.pumpWidget(
      MaterialApp(
        home: EmailCockpit(
          builder: (_, section) {
            built.add(section);
            return section == EmailSection.support
                ? const _DraftProbe()
                : Text('Page ${section.label}');
          },
        ),
      ),
    );
    expect(built, isEmpty);
    await tester.tap(find.text('Service client').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Brouillon conservé');
    await tester.tap(find.text('Sources').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Service client').first);
    await tester.pumpAndSettle();
    expect(find.text('Brouillon conservé'), findsOneWidget);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.text('Brouillon conservé'), findsOneWidget);
    expect(built, {EmailSection.support, EmailSection.sources});
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile cockpit opens diffusion from its drawer', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: EmailCockpit(
          builder: (_, section) => Text('Page ${section.label}'),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diffusion').last);
    await tester.pumpAndSettle();
    expect(find.text('Page Diffusion'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _DraftProbe extends StatefulWidget {
  const _DraftProbe();
  @override
  State<_DraftProbe> createState() => _DraftProbeState();
}

class _DraftProbeState extends State<_DraftProbe> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(controller: controller);
}
