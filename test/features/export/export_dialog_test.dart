import 'dart:convert';
import 'dart:io';

import 'package:cullimingo/features/delivery/domain/delivery_server.dart';
import 'package:cullimingo/features/export/domain/export_plan.dart';
import 'package:cullimingo/features/export/domain/export_preset.dart';
import 'package:cullimingo/features/export/presentation/export_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// Test-only transitive deps (via path_provider) for mocking the platform.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// Test-only transitive dep (via path_provider) for the mock mixin.
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

ExportSource _src(String path) => ExportSource(
  path: path,
  capturedAt: DateTime(2026, 6, 1, 10),
  originalName: path.split('/').last,
);

/// Feeds a fixed app-support dir so the dialog's AppSettings can read a
/// remembered destination (which enables the Export button).
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.supportDir);
  final String supportDir;
  @override
  Future<String?> getApplicationSupportPath() async => supportDir;
}

void main() {
  late Directory tempDir;
  const dest = '/exports/out';

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cm_export_dialog');
    File(
      p.join(tempDir.path, 'settings.json'),
    ).writeAsStringSync('{"lastDestination":"$dest"}');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  Future<ExportRequest?> openAndAct(
    WidgetTester tester,
    List<ExportSource> sources, {
    required String tap,
  }) async {
    ExportRequest? result;
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showExportDialog(context, sources: sources);
                done = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tap));
    await tester.pumpAndSettle();
    expect(done, isTrue, reason: 'dialog should have closed');
    return result;
  }

  testWidgets('shows the form with a live output-name preview', (tester) async {
    final sources = [_src('/s/DSC_0001.ARW'), _src('/s/DSC_0002.JPG')];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showExportDialog(context, sources: sources),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Title reflects the count, and the form is shown.
    expect(find.text('Export 2 photos'), findsOneWidget);
    expect(find.text('Long edge'), findsOneWidget);
    expect(find.text('2048 px'), findsOneWidget);

    // The live preview runs the real planner: keep-names forces .jpg.
    expect(find.textContaining('DSC_0001.jpg'), findsOneWidget);

    // The honest expectations note is present.
    expect(find.textContaining('not a Capture One'), findsOneWidget);

    // The dialog only configures — it never runs the export inline anymore.
    expect(find.textContaining('Exporting'), findsNothing);
  });

  testWidgets('Export returns a request with the resolved plan + destination', (
    tester,
  ) async {
    final sources = [_src('/s/DSC_0001.ARW'), _src('/s/DSC_0002.JPG')];
    final request = await openAndAct(tester, sources, tap: 'Export 2');

    expect(request, isNotNull);
    expect(request!.destinationRoot, dest);
    expect(request.plan.length, 2);
    // Ordered by capture time then path, keep-names forces .jpg.
    expect(request.plan.first.relPath, 'DSC_0001.jpg');
    expect(request.preset.longEdge, 2048);
  });

  testWidgets(
    '"Same folder as originals" returns a next-to-originals request',
    (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final sources = [_src('/s/DSC_0001.ARW')];
      ExportRequest? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showExportDialog(context, sources: sources);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Switch the destination mode to beside-the-originals.
      await tester.tap(find.text('Choose a folder…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Same folder as originals').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Export 1'));
      await tester.pumpAndSettle();

      expect(result!.nextToOriginals, isTrue);
      expect(result!.destinationRoot, isNull);
      expect(result!.subfolder, 'Exports'); // the default subfolder
    },
  );

  testWidgets('Cancel returns null (no export)', (tester) async {
    final request = await openAndAct(tester, [_src('/s/a.JPG')], tap: 'Cancel');
    expect(request, isNull);
  });

  testWidgets('format dropdown (with libvips): WebP lands in the preset '
      'and the preview extension follows', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ExportRequest? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showExportDialog(
                  context,
                  sources: [_src('/s/a.JPG')],
                  altFormats: true,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Format'), findsOneWidget);
    await tester.tap(find.text('JPEG'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WebP'));
    await tester.pumpAndSettle();
    expect(find.textContaining('a.webp'), findsOneWidget);

    await tester.tap(find.text('Export 1'));
    await tester.pumpAndSettle();
    expect(result!.preset.format, ExportFormat.webp);
    expect(result!.plan.single.relPath, 'a.webp');
  });

  testWidgets('no format dropdown without libvips', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showExportDialog(
                context,
                sources: [_src('/s/a.JPG')],
                altFormats: false,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Format'), findsNothing);
  });

  group('with a configured delivery server', () {
    const server = DeliveryServer(
      id: 'srv-1',
      name: 'AP wire',
      protocol: DeliveryProtocol.ftps,
      host: 'ftp.example.com',
      port: 21,
      username: 'niels',
      remoteDir: 'incoming',
    );

    setUp(() {
      File(p.join(tempDir.path, 'settings.json')).writeAsStringSync(
        jsonEncode({
          'lastDestination': dest,
          'deliveryServers': [server.toJson()],
        }),
      );
    });

    testWidgets('no server selected → plain local request', (tester) async {
      final request = await openAndAct(tester, [
        _src('/s/a.JPG'),
      ], tap: 'Export 1');
      expect(request!.server, isNull);
      expect(request.destinationRoot, dest);
    });

    testWidgets('server target returns server + null destination', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final sources = [_src('/s/a.JPG')];
      ExportRequest? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showExportDialog(context, sources: sources);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Local folder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload to AP wire (FTPS (explicit TLS))'));
      await tester.pumpAndSettle();

      // Uploading only: no folder fields, button says upload.
      expect(find.text('Choose a folder…'), findsNothing);
      expect(find.text('Open folder when done'), findsNothing);

      await tester.tap(find.text('Export & upload 1'));
      await tester.pumpAndSettle();

      expect(result!.server, server);
      expect(result!.destinationRoot, isNull);
      expect(result!.openWhenDone, isFalse);

      // 'Also keep a local copy' brings the folder back next time; the
      // remembered destination re-enables the button.
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Local folder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload to AP wire (FTPS (explicit TLS))'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Also keep a local copy'));
      await tester.pumpAndSettle();
      expect(find.text('Open folder when done'), findsOneWidget);
      await tester.tap(find.text('Export & upload 1'));
      await tester.pumpAndSettle();
      expect(result!.server, server);
      expect(result!.destinationRoot, dest);
    });
  });
}
