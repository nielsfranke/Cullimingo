import 'package:cullimingo/features/inspector/data/exif_detail.dart';
import 'package:cullimingo/features/inspector/presentation/inspector_panel.dart';
import 'package:cullimingo/features/metadata/domain/iptc_core.dart';
import 'package:cullimingo/features/metadata/domain/iptc_structured.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: Row(children: [child])),
  );

  testWidgets('empty state when no photo is focused', (tester) async {
    await tester.pumpWidget(
      host(InspectorPanelBody(data: null, onClose: () {})),
    );
    expect(find.text('No photo selected'), findsOneWidget);
  });

  testWidgets('renders marks and formatted EXIF for the focused photo', (
    tester,
  ) async {
    // Tall surface so the lazily-built ListView lays out every section (the
    // added IPTC section pushes Image below the default 600px fold).
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const data = InspectorData(
      filename: '_AIV1234.ARW',
      isRaw: true,
      rating: 4,
      color: ColorLabel.green,
      flag: PickFlag.pick,
      keywords: ['portrait', 'studio'],
      camera: 'Sony ILCE-7M4',
      fallbackWidth: 7008,
      fallbackHeight: 4672,
      exif: ExifDetail(
        lens: 'FE 85mm F1.4 GM',
        aperture: 1.4,
        shutterSeconds: 0.004,
        iso: 400,
        focalLength: 85,
        exposureBias: 0.3,
        width: 7008,
        height: 4672,
      ),
    );

    await tester.pumpWidget(
      host(InspectorPanelBody(data: data, onClose: () {})),
    );

    expect(find.text('_AIV1234.ARW'), findsOneWidget);
    expect(find.text('RAW'), findsOneWidget);
    // Marks: colour + flag labels.
    expect(find.text('Green'), findsOneWidget);
    expect(find.text('Pick'), findsOneWidget);
    expect(find.text('portrait'), findsOneWidget);
    // EXIF formatted via the pure formatters.
    expect(find.text('Sony ILCE-7M4'), findsOneWidget);
    expect(find.text('FE 85mm F1.4 GM'), findsOneWidget);
    expect(find.text('1/250 s'), findsOneWidget);
    expect(find.text('f/1.4'), findsOneWidget);
    expect(find.text('ISO 400'), findsOneWidget);
    expect(find.text('85 mm'), findsOneWidget);
    expect(find.text('+0.3 EV'), findsOneWidget);
    expect(find.text('7008 × 4672'), findsOneWidget);
    expect(find.text('32.7 MP'), findsOneWidget);
  });

  testWidgets('shows the structured IPTC tables read-only', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const data = InspectorData(
      filename: 'x.jpg',
      isRaw: false,
      rating: 0,
      color: ColorLabel.none,
      flag: PickFlag.none,
      keywords: [],
      iptc: IptcCore(
        locationsShown: [IptcLocation(city: 'Munich', country: 'Germany')],
        imageCreators: [IptcEntity(name: 'Jane Doe')],
      ),
    );

    await tester.pumpWidget(
      host(InspectorPanelBody(data: data, onClose: () {})),
    );

    expect(find.text('Locations shown'), findsOneWidget);
    expect(find.text('Munich · Germany'), findsOneWidget);
    expect(find.text('Image creators'), findsOneWidget);
    expect(find.text('Jane Doe'), findsOneWidget);
  });

  testWidgets('absent EXIF fields show an em dash', (tester) async {
    const data = InspectorData(
      filename: 'plain.jpg',
      isRaw: false,
      rating: 0,
      color: ColorLabel.none,
      flag: PickFlag.none,
      keywords: [],
    );

    await tester.pumpWidget(
      host(InspectorPanelBody(data: data, onClose: () {})),
    );

    expect(find.text('No marks'), findsOneWidget);
    expect(find.text('RAW'), findsNothing);
    // Lens/exposure/etc. all absent → em dashes present.
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('shows IPTC fields and an Edit button that fires', (
    tester,
  ) async {
    var edited = false;
    const data = InspectorData(
      filename: 'wire.jpg',
      isRaw: false,
      rating: 0,
      color: ColorLabel.none,
      flag: PickFlag.none,
      keywords: [],
      iptc: IptcCore(caption: 'On the wire', credit: 'Reuters'),
    );

    await tester.pumpWidget(
      host(
        InspectorPanelBody(
          data: data,
          onClose: () {},
          onEditMetadata: () => edited = true,
        ),
      ),
    );

    expect(find.text('IPTC'), findsOneWidget);
    expect(find.text('On the wire'), findsOneWidget);
    expect(find.text('Reuters'), findsOneWidget);

    await tester.tap(find.text('Edit'));
    expect(edited, isTrue);
  });

  testWidgets('IPTC section shows a hint when there is no metadata', (
    tester,
  ) async {
    const data = InspectorData(
      filename: 'plain.jpg',
      isRaw: false,
      rating: 0,
      color: ColorLabel.none,
      flag: PickFlag.none,
      keywords: [],
    );

    await tester.pumpWidget(
      host(InspectorPanelBody(data: data, onClose: () {})),
    );

    expect(find.text('No caption or credit'), findsOneWidget);
    // No Edit button when no callback is wired.
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('close button fires the callback', (tester) async {
    var closed = false;
    await tester.pumpWidget(
      host(InspectorPanelBody(data: null, onClose: () => closed = true)),
    );
    await tester.tap(find.byIcon(Icons.chevron_right));
    expect(closed, isTrue);
  });

  group('inline IPTC editing', () {
    const data = InspectorData(
      filename: 'w.jpg',
      isRaw: false,
      rating: 0,
      color: ColorLabel.none,
      flag: PickFlag.none,
      keywords: [],
      iptc: IptcCore(caption: 'On the wire', credit: 'Reuters'),
    );

    Future<List<(IptcField, String)>> pump(
      WidgetTester tester, {
      InspectorData shown = data,
    }) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final saves = <(IptcField, String)>[];
      await tester.pumpWidget(
        host(
          InspectorPanelBody(
            data: shown,
            onClose: () {},
            onSaveIptc: (field, value) async => saves.add((field, value)),
          ),
        ),
      );
      return saves;
    }

    testWidgets('click a value, type, Enter → saves that field', (
      tester,
    ) async {
      final saves = await pump(tester);
      await tester.tap(find.text('Reuters'));
      await tester.pump();

      await tester.enterText(
        find.byType(TextField),
        'AP',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(saves, [(IptcField.credit, 'AP')]);
    });

    testWidgets('Escape cancels without saving', (tester) async {
      final saves = await pump(tester);
      await tester.tap(find.text('Reuters'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'AP');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(saves, isEmpty);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Reuters'), findsOneWidget);
    });

    testWidgets('an unchanged commit does not save', (tester) async {
      final saves = await pump(tester);
      await tester.tap(find.text('Reuters'));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(saves, isEmpty);
    });

    testWidgets('Add field menu opens an editor for an empty field', (
      tester,
    ) async {
      final saves = await pump(tester);
      await tester.tap(find.text('+ Add field'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Headline'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'March downtown');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(saves, [(IptcField.headline, 'March downtown')]);
    });

    testWidgets('read-only without onSaveIptc: tapping opens no editor', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        host(InspectorPanelBody(data: data, onClose: () {})),
      );
      await tester.tap(find.text('Reuters'));
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('+ Add field'), findsNothing);
    });
  });
}
