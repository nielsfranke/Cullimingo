import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cullimingo/app/theme/tokens.dart';
import 'package:cullimingo/core/cache/preview_cache.dart';
import 'package:cullimingo/core/db/database.dart';
import 'package:cullimingo/core/files/open_external.dart';
import 'package:cullimingo/core/files/supported_files.dart';
import 'package:cullimingo/core/raw/preview_extractor.dart';
import 'package:cullimingo/features/cull/domain/loupe_analysis.dart';
import 'package:cullimingo/features/cull/domain/loupe_zoom.dart';
import 'package:cullimingo/features/cull/presentation/cull_providers.dart';
import 'package:cullimingo/features/cull/presentation/loupe_analysis_decode.dart';
import 'package:cullimingo/features/cull/presentation/widgets/cull_toolbar.dart';
import 'package:cullimingo/features/cull/presentation/widgets/loupe_filmstrip.dart';
import 'package:cullimingo/features/cull/presentation/widgets/thumbnail_context_menu.dart';
import 'package:cullimingo/features/filter/presentation/filter_providers.dart';
import 'package:cullimingo/features/handoff/data/transfer_service.dart';
import 'package:cullimingo/features/handoff/domain/external_editor.dart';
import 'package:cullimingo/features/handoff/presentation/send_to_providers.dart';
import 'package:cullimingo/features/inspector/presentation/inspector_panel.dart';
import 'package:cullimingo/features/inspector/presentation/inspector_providers.dart';
import 'package:cullimingo/features/metadata/domain/crop_rect.dart';
import 'package:cullimingo/features/metadata/presentation/iptc_editor_dialog.dart';
import 'package:cullimingo/features/metadata/presentation/keyword_dialog.dart';
import 'package:cullimingo/shared/models/cull_marks.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// Fullscreen loupe preview (`BUILD_PLAN.md` §7): a single photo at screen
/// resolution ([PreviewTier.loupe], scaled to the display's pixel long edge)
/// with its cull marks. Opened from the grid on double-click or `Enter`/`F`;
/// `[`/`]` blit between photos.
///
/// Zoomable: `Fit` (the whole frame) and `100%` (1 image-pixel : 1 logical-px,
/// for checking focus) presets plus a slider; drag to pan when magnified. Zoom
/// resets on each photo change.
///
/// Keyboard is owned by the cull page (one focus node, no fighting) — this is
/// a pure visual overlay driven by the focused photo over the filtered set.
class LoupeView extends ConsumerStatefulWidget {
  /// Creates the loupe overlay.
  const LoupeView({
    required this.onClose,
    required this.onTransfer,
    required this.onSendTo,
    this.onEditMetadata,
    this.onRename,
    this.onApplyTemplate,
    this.onGeocode,
    this.onExport,
    this.onContactSheet,
    super.key,
  });

  /// Called when the close button is tapped.
  final VoidCallback onClose;

  /// Copies/moves the shown photo to a folder (right-click menu).
  final ValueChanged<TransferMode> onTransfer;

  /// Opens the shown photo in a configured external editor (right-click menu).
  final ValueChanged<ExternalEditor> onSendTo;

  /// Opens the metadata editor (right-click menu). Null disables it.
  final VoidCallback? onEditMetadata;

  /// Renames the shown photo (right-click menu). Null disables it.
  final VoidCallback? onRename;

  /// Stamps the metadata template (right-click menu). Null disables it.
  final VoidCallback? onApplyTemplate;

  /// Fills IPTC location from GPS (right-click menu). Null disables it.
  final VoidCallback? onGeocode;

  /// Exports the shown photo (right-click menu). Null disables it.
  final VoidCallback? onExport;

  /// Opens the ContactSheet dialog for the shown photo; the bool is pull mode
  /// (true = fetch marks, false = send). Only offered when configured (§7b).
  final ValueChanged<bool>? onContactSheet;

  @override
  ConsumerState<LoupeView> createState() => _LoupeViewState();
}

class _LoupeViewState extends ConsumerState<LoupeView> {
  /// Pan/zoom transform for the [InteractiveViewer]; scale 1.0 == Fit.
  final TransformationController _tc = TransformationController();

  /// Native pixel size of the decoded preview, once resolved.
  Size? _intrinsic;

  /// Bytes whose [_intrinsic] we resolved, to skip redundant decodes.
  Uint8List? _resolvedBytes;

  /// Current viewport (loupe image area) size in logical pixels.
  Size _viewport = Size.zero;

  /// The focused photo we're showing — changing it refreshes the native size.
  int? _photoId;

  /// Whether we've restored the persisted zoom for this loupe session yet.
  bool _restored = false;

  /// Latched true once the user zooms in on the current photo, so we pull the
  /// full-resolution source (original / embedded JPEG) for true 100% pixel-
  /// peeping. Reset on each photo change so a blit stays on the fast preview.
  bool _wantFull = false;

  /// Zoom (relative to Fit) past which we fetch the full-resolution source. A
  /// modest magnification, so the sharp bytes are usually in before 100%.
  static const double _fullZoomTrigger = 1.5;

  /// Whether the read-only Lightroom/Camera-Raw crop outline is shown (only has
  /// an effect on photos that carry a crop).
  bool _showCrop = true;

  /// The source bytes the current histogram/clipping/peaking results were
  /// computed from, and which of the three were requested — so a rebuild that
  /// changes neither skips the (isolate) recompute.
  Uint8List? _analyzedSource;
  ({bool histogram, bool clipping, bool peaking})? _analyzedFlags;

  /// Decoded straight-RGBA pixels of [_analyzedSource] (downscaled to
  /// [_analysisMaxLongEdge]), cached so toggling an overlay on the same photo
  /// re-runs only the cheap pixel loop, not the decode.
  Uint8List? _analysisRgba;
  int _analysisWidth = 0;
  int _analysisHeight = 0;

  /// Long-edge cap for the analysis decode. The overlays stretch over the
  /// photo anyway, so analysing more pixels than roughly a screen's worth
  /// costs seconds (on a 45-MP original) for no visible gain. Close to the
  /// loupe preview's own resolution so the peaking threshold keeps meaning
  /// what it was tuned to mean.
  static const int _analysisMaxLongEdge = 2048;

  /// Guards against a stale analysis (superseded by a newer photo/toggle)
  /// landing after the fact.
  int _analysisGen = 0;

  /// The current photo's RGB histogram, once computed.
  RgbHistogram? _histogram;

  /// Decoded clipping-warning / focus-peaking overlays, once computed. Same
  /// pixel dimensions as the analysed source; painted over the photo aligned
  /// via `_letterboxedImageRect`.
  ui.Image? _clippingImage;
  ui.Image? _peakingImage;

  /// Ephemeral mark-confirmation HUD: the current flash, whether it's visible
  /// (drives the fade), and the one-shot hide timer. Null when nothing to show.
  _MarkFlash? _flash;
  bool _flashVisible = false;
  Timer? _flashTimer;

  /// The last mark-signal sequence we flashed, so a rebuild doesn't re-show it.
  int _shownFlashSeq = 0;

  static const Duration _flashHold = Duration(milliseconds: 600);
  static const Duration _flashFadeOut = Duration(milliseconds: 150);

  @override
  void initState() {
    super.initState();
    _tc.addListener(_onTransform);
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _disposeAnalysisImages();
    _tc
      ..removeListener(_onTransform)
      ..dispose();
    super.dispose();
  }

  // Releases the decoded overlay images' native memory. Safe to call
  // repeatedly (e.g. once per toggle-off and again in dispose()).
  void _disposeAnalysisImages() {
    _clippingImage?.dispose();
    _peakingImage?.dispose();
    _clippingImage = null;
    _peakingImage = null;
  }

  // Handles a mark signal from the keyboard/toolbar: show the HUD for the
  // applied mark, then start the hide timer. Event-driven (not derived from the
  // shown photo), so it still fires when auto-advance has already blitted on.
  void _onMarkSignal(LoupeMarkSignal? signal) {
    if (signal == null || signal.seq == _shownFlashSeq) return;
    _shownFlashSeq = signal.seq;
    if (!ref.read(markConfirmationEnabledProvider)) return;
    // With auto-advance on, the mark blits to the next photo — flashing the
    // confirmation over *that* photo is confusing, and the advance already
    // confirms the action, so skip it.
    if (ref.read(autoAdvanceAfterMarkProvider)) return;

    final flash = signal.rating != null
        ? _MarkFlash.rating(signal.rating!)
        : signal.flag != null
        ? _MarkFlash.flag(signal.flag!)
        : _MarkFlash.color(signal.color!);

    _flashTimer?.cancel();
    setState(() {
      _flash = flash;
      _flashVisible = true;
    });
    _flashTimer = Timer(_flashHold, () {
      if (mounted) setState(() => _flashVisible = false);
    });
  }

  // Rebuild so the zoom slider/percent reflect a pinch or drag-zoom, and
  // persist the *mode* (Fit / 100% / custom) so it carries to the next loupe
  // session — a raw scale wouldn't mean 100% on the next photo.
  void _onTransform() {
    final scale = _scale;
    setState(() {
      // Past a modest zoom-in, pull the full-resolution source so 100% renders
      // true 1:1 instead of an upscaled preview.
      if (scale > _fullZoomTrigger) _wantFull = true;
    });
    ref
        .read(loupeZoomLevelProvider.notifier)
        .set(_zoom.modeForScale(scale), scale);
  }

  double get _scale => _tc.value.getMaxScaleOnAxis();

  LoupeZoom get _zoom => LoupeZoom(intrinsic: _intrinsic, viewport: _viewport);

  // Sets an absolute zoom [target] (relative to Fit), centred in the viewport.
  // Drives the Fit/100% presets and the slider.
  void _applyScale(double target) {
    final clamped = target.clamp(_zoom.minScale, _zoom.maxScale);
    final cx = _viewport.width / 2;
    final cy = _viewport.height / 2;
    _tc.value = Matrix4.identity()
      ..translateByDouble(cx, cy, 0, 1)
      ..scaleByDouble(clamped, clamped, clamped, 1)
      ..translateByDouble(-cx, -cy, 0, 1);
  }

  // Resolve the decoded preview's native size (for the 100% preset). Reuses the
  // image cache, so this rides along with the Image.memory decode.
  void _resolveIntrinsic(Uint8List bytes) {
    _resolvedBytes = bytes;
    final stream = MemoryImage(bytes).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        final size = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
        stream.removeListener(listener);
        if (mounted && _intrinsic != size) setState(() => _intrinsic = size);
      },
      // Corrupt/undecodable bytes: drop the listener quietly (the image area
      // shows a broken-file placeholder via errorBuilder) rather than letting
      // the error bubble to the global image handler.
      onError: (_, _) => stream.removeListener(listener),
    );
    stream.addListener(listener);
  }

  // Computes whichever of histogram/clipping/peaking are requested for
  // [source]: a native decode on the engine's IO thread (downscaled to
  // [_analysisMaxLongEdge] — the pure-Dart decode this replaced took seconds
  // on a big preview), then the pixel loop off the UI isolate
  // (`BUILD_PLAN.md` §0.6 — a multi-megapixel convolution has no business
  // running on the frame thread). Skips the recompute when neither the bytes
  // nor the requested set changed since the last run, reuses the decoded
  // pixels when only the set changed, and drops a result that a newer call
  // (photo blit, toggle) has already superseded.
  Future<void> _scheduleAnalysis(
    Uint8List? source, {
    required bool histogram,
    required bool clipping,
    required bool peaking,
  }) async {
    final anyOn = histogram || clipping || peaking;
    if (!anyOn || source == null) {
      if (_analyzedSource != null) {
        _analyzedSource = null;
        _analyzedFlags = null;
        _analysisRgba = null;
        _disposeAnalysisImages();
        setState(() => _histogram = null);
      }
      return;
    }
    final flags = (histogram: histogram, clipping: clipping, peaking: peaking);
    if (identical(source, _analyzedSource) && _analyzedFlags == flags) return;
    final sameSource = identical(source, _analyzedSource);
    _analyzedSource = source;
    _analyzedFlags = flags;
    final gen = ++_analysisGen;

    LoupeAnalysis? result;
    var rgba = sameSource ? _analysisRgba : null;
    var width = _analysisWidth;
    var height = _analysisHeight;
    if (rgba == null) {
      final decoded = await decodeRgbaForAnalysis(
        source,
        maxLongEdge: _analysisMaxLongEdge,
      );
      if (!mounted || gen != _analysisGen) return;
      if (decoded != null) {
        rgba = decoded.rgba;
        width = decoded.width;
        height = decoded.height;
        _analysisRgba = rgba;
        _analysisWidth = width;
        _analysisHeight = height;
      } else {
        // Native decode/readback failed (already logged) — fall back to the
        // slow pure-Dart decode so the overlays degrade to slow, not broken.
        result = await computeLoupeAnalysisOffThread(
          source,
          wantHistogram: histogram,
          wantClipping: clipping,
          wantPeaking: peaking,
        );
        if (!mounted || gen != _analysisGen) return;
        if (result == null) {
          // Genuinely undecodable bytes — show nothing, same as before.
          _analysisRgba = null;
          _disposeAnalysisImages();
          setState(() => _histogram = null);
          return;
        }
      }
    }

    final analysis =
        result ??
        await computeLoupeAnalysisFromRgbaOffThread(
          rgba!,
          width: width,
          height: height,
          wantHistogram: histogram,
          wantClipping: clipping,
          wantPeaking: peaking,
        );
    if (!mounted || gen != _analysisGen) return;

    ui.Image? clipImage;
    if (analysis.clippingOverlayRgba != null) {
      clipImage = await _decodeRgba(
        analysis.clippingOverlayRgba!,
        analysis.width,
        analysis.height,
      );
    }
    if (!mounted || gen != _analysisGen) {
      clipImage?.dispose();
      return;
    }

    ui.Image? peakImage;
    if (analysis.peakingOverlayRgba != null) {
      peakImage = await _decodeRgba(
        analysis.peakingOverlayRgba!,
        analysis.width,
        analysis.height,
      );
    }
    if (!mounted || gen != _analysisGen) {
      clipImage?.dispose();
      peakImage?.dispose();
      return;
    }

    _disposeAnalysisImages();
    setState(() {
      _histogram = analysis.histogram;
      _clippingImage = clipImage;
      _peakingImage = peakImage;
    });
  }

  Future<ui.Image> _decodeRgba(Uint8List rgba, int width, int height) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  Widget _brokenImage() => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.broken_image_outlined,
          color: AppColors.textSecondary,
          size: 56,
        ),
        SizedBox(height: AppSpacing.sm),
        Text(
          'Can’t display this file',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final photos = ref.watch(filteredPhotosProvider);
    final focusedId = ref.watch(
      cullControllerProvider.select((s) => s.focusedId),
    );
    if (photos.isEmpty) return const SizedBox.shrink();

    final index = photos
        .indexWhere((ph) => ph.id == focusedId)
        .clamp(
          0,
          photos.length - 1,
        );
    final photo = photos[index];
    final controller = ref.read(cullControllerProvider.notifier);

    // A new photo (blit) leaves the transform untouched so zoom *and* pan
    // carry over seamlessly — no jump, and you can compare the same crop across
    // frames (focus checking). We keep the previous native size until the loupe
    // bytes resolve, so the slider range and 100% button don't flicker.
    if (photo.id != _photoId) {
      _photoId = photo.id;
      _resolvedBytes = null;
      _wantFull = false; // a blit starts on the fast preview again
      // A blit's analysis is the new photo's, not a rescale of the old one —
      // drop it so `_scheduleAnalysis` recomputes instead of skipping (its
      // dedup only keys off the byte reference, not the photo id).
      _analyzedSource = null;
      _analyzedFlags = null;
      _analysisRgba = null;
      _histogram = null;
      _disposeAnalysisImages();
    }

    // Once, on open, restore the persisted zoom mode (centred) after layout
    // gives us a viewport. For 100% we must wait until the native size resolves
    // so scaleForMode can compute it; Fit/custom can restore immediately.
    // Navigation thereafter keeps the live transform.
    if (!_restored && _viewport != Size.zero) {
      final saved = ref.read(loupeZoomLevelProvider);
      final target = _zoom.scaleForMode(
        saved.mode,
        custom: saved.customScale,
      );
      if (target != null) {
        _restored = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _applyScale(target);
        });
      }
    }

    // Warm the neighbours so `[`/`]` blits without a decode wait.
    _prefetchNeighbours(ref, photos, index);

    final inspectorOpen = ref.watch(inspectorOpenProvider);
    final filmstripOpen = ref.watch(filmstripVisibleProvider);
    final histogramOn = ref.watch(loupeHistogramVisibleProvider);
    final clippingOn = ref.watch(loupeClippingVisibleProvider);
    final peakingOn = ref.watch(loupeFocusPeakingVisibleProvider);
    final loupe = ref.watch(loupePreviewProvider(photo.path)).value;
    final thumb = ref.watch(thumbnailProvider(photo.path)).value;
    // Once zoomed in, prefer the full-resolution source (loaded lazily); it
    // sharpens in over the preview via gaplessPlayback, no flicker or jump.
    final full = _wantFull
        ? ref.watch(loupeFullPreviewProvider(photo.path)).value
        : null;
    final bytes = full ?? loupe ?? thumb;
    // Resolve the native size from the best *real* source (full when present,
    // else loupe) so hundredScale — and thus the 100% preset — is true 1:1 of
    // the original once it loads. The thumb is a wrong-size placeholder.
    final source = full ?? loupe;
    if (source != null && !identical(source, _resolvedBytes)) {
      _resolveIntrinsic(source);
    }
    // Analyse the screen-res preview when it's there: histogram/clipping/
    // peaking don't gain from full-res pixels (the decode is capped anyway),
    // and preferring the loupe bytes keeps the overlays stable — they don't
    // recompute when zooming past the full-res trigger swaps the source.
    unawaited(
      _scheduleAnalysis(
        loupe ?? full,
        histogram: histogramOn,
        clipping: clippingOn,
        peaking: peakingOn,
      ),
    );

    // Flash an ephemeral confirmation when a mark is applied in the loupe.
    ref.listen(loupeMarkFlashProvider, (_, signal) => _onMarkSignal(signal));

    // ExcludeFocus: the on-screen controls stay clickable but never steal
    // keyboard focus from the grid, so `[`/`]` and cull keys keep working.
    //
    // Layout: image area on top, a solid docked toolbar below (Lightroom-style)
    // so the controls never sit over the photo.
    return ExcludeFocus(
      child: ColoredBox(
        color: Colors.black,
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          // Listener (not GestureDetector) so the right-click
                          // wins over the InteractiveViewer's pan/zoom arena;
                          // primary presses fall through to pan as before.
                          child: Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: (e) {
                              if (e.buttons & kSecondaryButton != 0) {
                                unawaited(_showLoupeMenu(photo, e.position));
                              }
                            },
                            child: _imageArea(
                              photo,
                              bytes,
                              clippingImage: clippingOn ? _clippingImage : null,
                              peakingImage: peakingOn ? _peakingImage : null,
                            ),
                          ),
                        ),
                        if (histogramOn && _histogram != null)
                          Positioned(
                            left: AppSpacing.md,
                            bottom: AppSpacing.md,
                            child: IgnorePointer(
                              child: _HistogramPanel(histogram: _histogram!),
                            ),
                          ),
                        // Videos never decode into the loupe (only a poster
                        // frame, or nothing on Linux) — this is the play
                        // affordance, mirroring the grid's play badge.
                        if (isVideoPath(photo.path))
                          Center(
                            child: IconButton(
                              iconSize: 64,
                              onPressed: () =>
                                  unawaited(openExternally(photo.path)),
                              tooltip: 'Open in system player',
                              icon: const Icon(Icons.play_circle_fill_rounded),
                              color: Colors.white70,
                            ),
                          ),
                        // Ephemeral mark-confirmation HUD, centred over the
                        // photo. IgnorePointer so it never blocks pan/zoom.
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Center(
                              child: AnimatedOpacity(
                                opacity: _flashVisible ? 1 : 0,
                                // Appear instantly on keypress; fade out after.
                                duration: _flashVisible
                                    ? Duration.zero
                                    : _flashFadeOut,
                                child: _flash == null
                                    ? const SizedBox.shrink()
                                    : _MarkFlashContent(flash: _flash!),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: AppSpacing.md,
                          right: AppSpacing.md,
                          child: Row(
                            children: [
                              if (photo.hasCrop)
                                IconButton(
                                  onPressed: () =>
                                      setState(() => _showCrop = !_showCrop),
                                  tooltip: _showCrop
                                      ? 'Hide crop outline'
                                      : 'Show crop outline',
                                  icon: Icon(
                                    _showCrop
                                        ? Icons.crop_rounded
                                        : Icons.crop_free_rounded,
                                  ),
                                  color: AppColors.textPrimary,
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.black.withValues(
                                      alpha: 0.4,
                                    ),
                                  ),
                                ),
                              IconButton(
                                onPressed: widget.onClose,
                                tooltip: 'Close loupe (Esc)',
                                icon: const Icon(Icons.close_rounded),
                                color: AppColors.textPrimary,
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (inspectorOpen) const InspectorPanel(),
                ],
              ),
            ),
            _LoupeToolbar(
              photo: photo,
              position: index + 1,
              total: photos.length,
              scale: _scale,
              minScale: _zoom.minScale,
              maxScale: _zoom.maxScale,
              hundredScale: _zoom.hundredScale,
              inspectorOpen: inspectorOpen,
              onToggleInspector: () =>
                  ref.read(inspectorOpenProvider.notifier).toggle(),
              filmstripOpen: filmstripOpen,
              onToggleFilmstrip: () => ref
                  .read(filmstripVisibleProvider.notifier)
                  .set(!filmstripOpen),
              histogramOpen: histogramOn,
              onToggleHistogram: () =>
                  ref.read(loupeHistogramVisibleProvider.notifier).toggle(),
              clippingOpen: clippingOn,
              onToggleClipping: () =>
                  ref.read(loupeClippingVisibleProvider.notifier).toggle(),
              peakingOpen: peakingOn,
              onTogglePeaking: () =>
                  ref.read(loupeFocusPeakingVisibleProvider.notifier).toggle(),
              onZoom: _applyScale,
              onFit: () => _applyScale(1),
              onRating: (r) {
                ref.read(loupeMarkFlashProvider.notifier).rating(r);
                unawaited(controller.setRating(photo.id, r));
              },
              onFlag: (f) {
                ref.read(loupeMarkFlashProvider.notifier).flag(f);
                unawaited(controller.setFlag(photo.id, f));
              },
              onColor: (c) {
                ref.read(loupeMarkFlashProvider.notifier).color(c);
                unawaited(controller.setColor(photo.id, c));
              },
              onKeywords: () => showKeywordEditor(context, ref),
              onRotateLeft: () => unawaited(controller.rotate(photo.id, -1)),
              onRotateRight: () => unawaited(controller.rotate(photo.id, 1)),
              onEditMetadata: () => unawaited(showIptcEditor(context, ref)),
            ),
            if (filmstripOpen) const LoupeFilmstrip(),
          ],
        ),
      ),
    );
  }

  Widget _imageArea(
    Photo photo,
    Uint8List? bytes, {
    required ui.Image? clippingImage,
    required ui.Image? peakingImage,
  }) {
    if (bytes == null) {
      return Center(
        child: Icon(
          photo.isRaw ? Icons.raw_on_rounded : Icons.image_outlined,
          color: AppColors.textSecondary,
          size: 64,
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        _viewport = Size(c.maxWidth, c.maxHeight);
        final crop = _showCrop ? _cropOf(photo) : null;
        return InteractiveViewer(
          transformationController: _tc,
          minScale: _zoom.minScale,
          maxScale: _zoom.maxScale,
          // The preview is upright per the file's EXIF; apply only the user's
          // extra quarter-turns (§ rotate). The crop outline and analysis
          // overlays are siblings of the image inside the same RotatedBox, so
          // they track zoom, pan and rotation with the photo.
          child: RotatedBox(
            quarterTurns: photo.userRotation,
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stack) => _brokenImage(),
                ),
                if (clippingImage != null)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _AnalysisOverlayPainter(
                        image: clippingImage,
                        imageAspect: _intrinsic,
                      ),
                    ),
                  ),
                if (peakingImage != null)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _AnalysisOverlayPainter(
                        image: peakingImage,
                        imageAspect: _intrinsic,
                      ),
                    ),
                  ),
                if (crop != null)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _CropOverlayPainter(
                        crop: crop,
                        imageAspect: _intrinsic,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // The photo's read-only crop, or null when it has none or the crop is
  // effectively full-frame (nothing worth outlining).
  CropRect? _cropOf(Photo photo) {
    if (!photo.hasCrop || photo.cropLeft == null) return null;
    final crop = CropRect(
      left: photo.cropLeft!,
      top: photo.cropTop ?? 0,
      right: photo.cropRight ?? 1,
      bottom: photo.cropBottom ?? 1,
      angle: photo.cropAngle ?? 0,
    );
    return crop.isMeaningful ? crop : null;
  }

  // Opens the same context menu as a grid thumbnail, acting on the shown photo.
  Future<void> _showLoupeMenu(Photo photo, Offset position) async {
    // The shown photo is the focus target, so mark actions land on it.
    ref.read(cullControllerProvider.notifier).focus(photo.id);
    await showThumbnailContextMenu(
      context: context,
      ref: ref,
      photo: photo,
      globalPosition: position,
      onTransfer: widget.onTransfer,
      onSendTo: widget.onSendTo,
      onEditMetadata: widget.onEditMetadata,
      onRename: widget.onRename,
      onApplyTemplate: widget.onApplyTemplate,
      onGeocode: widget.onGeocode,
      onExport: widget.onExport,
      onContactSheet: (ref.read(contactSheetConfiguredProvider).value ?? false)
          ? widget.onContactSheet
          : null,
    );
  }

  void _prefetchNeighbours(WidgetRef ref, List<Photo> photos, int index) {
    final cache = ref.read(previewCacheProvider);
    for (final i in [index - 1, index + 1]) {
      if (i >= 0 && i < photos.length) {
        cache
            .get(
              photos[i].path,
              PreviewTier.loupe,
              priority: JobPriority.prefetch,
            )
            .ignore();
      }
    }
  }
}

/// Docked bottom toolbar: an interactive cull row (stars / pick-reject /
/// colours), the zoom controls, and the filename + `i / n` position. Solid
/// surface so it never overlaps the photo (Lightroom-style chrome).
class _LoupeToolbar extends StatelessWidget {
  const _LoupeToolbar({
    required this.photo,
    required this.position,
    required this.total,
    required this.scale,
    required this.minScale,
    required this.maxScale,
    required this.hundredScale,
    required this.inspectorOpen,
    required this.onToggleInspector,
    required this.filmstripOpen,
    required this.onToggleFilmstrip,
    required this.histogramOpen,
    required this.onToggleHistogram,
    required this.clippingOpen,
    required this.onToggleClipping,
    required this.peakingOpen,
    required this.onTogglePeaking,
    required this.onZoom,
    required this.onFit,
    required this.onRating,
    required this.onFlag,
    required this.onColor,
    required this.onKeywords,
    required this.onRotateLeft,
    required this.onRotateRight,
    required this.onEditMetadata,
  });

  final Photo photo;
  final int position;
  final int total;
  final double scale;
  final double minScale;
  final double maxScale;
  final double? hundredScale;

  /// Whether the metadata inspector panel is open.
  final bool inspectorOpen;

  /// Toggles the metadata inspector panel.
  final VoidCallback onToggleInspector;

  /// Whether the bottom thumbnail filmstrip is shown.
  final bool filmstripOpen;

  /// Toggles the bottom thumbnail filmstrip.
  final VoidCallback onToggleFilmstrip;

  /// Whether the RGB histogram panel is shown.
  final bool histogramOpen;

  /// Toggles the histogram panel.
  final VoidCallback onToggleHistogram;

  /// Whether blown-highlight/crushed-shadow tinting is shown over the photo.
  final bool clippingOpen;

  /// Toggles the clipping-warning overlay.
  final VoidCallback onToggleClipping;

  /// Whether the focus-peaking edge overlay is shown over the photo.
  final bool peakingOpen;

  /// Toggles the focus-peaking overlay.
  final VoidCallback onTogglePeaking;

  final ValueChanged<double> onZoom;
  final VoidCallback onFit;
  final ValueChanged<int> onRating;
  final ValueChanged<PickFlag> onFlag;
  final ValueChanged<ColorLabel> onColor;
  final VoidCallback onKeywords;
  final VoidCallback onRotateLeft;
  final VoidCallback onRotateRight;
  final VoidCallback onEditMetadata;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      // One level: zoom on the left, the photo's name + cull controls centred,
      // the position on the right.
      child: Row(
        children: [
          _ZoomControls(
            scale: scale,
            minScale: minScale,
            maxScale: maxScale,
            hundredScale: hundredScale,
            onZoom: onZoom,
            onFit: onFit,
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  p.basename(photo.path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                CullToolbar(
                  photo: photo,
                  onRating: onRating,
                  onFlag: onFlag,
                  onColor: onColor,
                  onKeywords: onKeywords,
                  onRotateLeft: onRotateLeft,
                  onRotateRight: onRotateRight,
                  onEditMetadata: onEditMetadata,
                ),
              ],
            ),
          ),
          _AnalysisMenuButton(
            histogramOpen: histogramOpen,
            onToggleHistogram: onToggleHistogram,
            clippingOpen: clippingOpen,
            onToggleClipping: onToggleClipping,
            peakingOpen: peakingOpen,
            onTogglePeaking: onTogglePeaking,
          ),
          IconButton(
            onPressed: onToggleFilmstrip,
            tooltip: filmstripOpen ? 'Hide filmstrip' : 'Show filmstrip',
            icon: Icon(
              Icons.view_carousel_outlined,
              size: 18,
              color: filmstripOpen ? AppColors.accent : AppColors.textSecondary,
            ),
          ),
          IconButton(
            onPressed: onToggleInspector,
            tooltip: inspectorOpen ? 'Hide info (I)' : 'Show info (I)',
            icon: Icon(
              Icons.info_outline,
              size: 18,
              color: inspectorOpen ? AppColors.accent : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '$position / $total',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Which analysis overlay a [_AnalysisMenuButton] menu item toggles.
enum _AnalysisToggle { histogram, clipping, peaking }

/// A single overflow menu for the loupe's DSP overlays (RGB histogram,
/// clipping warnings, focus peaking) — grouping them behind one icon keeps
/// the toolbar from growing a new button per analysis tool (three separate
/// `IconButton`s overflowed the row); the trigger accents when any is on, and
/// each item shows its own checkmark.
class _AnalysisMenuButton extends StatelessWidget {
  const _AnalysisMenuButton({
    required this.histogramOpen,
    required this.onToggleHistogram,
    required this.clippingOpen,
    required this.onToggleClipping,
    required this.peakingOpen,
    required this.onTogglePeaking,
  });

  final bool histogramOpen;
  final VoidCallback onToggleHistogram;
  final bool clippingOpen;
  final VoidCallback onToggleClipping;
  final bool peakingOpen;
  final VoidCallback onTogglePeaking;

  @override
  Widget build(BuildContext context) {
    final anyOpen = histogramOpen || clippingOpen || peakingOpen;
    return PopupMenuButton<_AnalysisToggle>(
      tooltip: 'Analysis overlays',
      popUpAnimationStyle: kMenuAnimationStyle,
      icon: Icon(
        Icons.insights_rounded,
        size: 18,
        color: anyOpen ? AppColors.accent : AppColors.textSecondary,
      ),
      onSelected: (value) {
        switch (value) {
          case _AnalysisToggle.histogram:
            onToggleHistogram();
          case _AnalysisToggle.clipping:
            onToggleClipping();
          case _AnalysisToggle.peaking:
            onTogglePeaking();
        }
      },
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: _AnalysisToggle.histogram,
          checked: histogramOpen,
          child: const Text('Histogram'),
        ),
        CheckedPopupMenuItem(
          value: _AnalysisToggle.clipping,
          checked: clippingOpen,
          child: const Text('Clipping warnings'),
        ),
        CheckedPopupMenuItem(
          value: _AnalysisToggle.peaking,
          checked: peakingOpen,
          child: const Text('Focus peaking'),
        ),
      ],
    );
  }
}

/// Fit / 100% presets, a zoom slider, and the current percentage.
class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.scale,
    required this.minScale,
    required this.maxScale,
    required this.hundredScale,
    required this.onZoom,
    required this.onFit,
  });

  final double scale;
  final double minScale;
  final double maxScale;
  final double? hundredScale;
  final ValueChanged<double> onZoom;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    final atFit = (scale - 1).abs() < 0.01;
    final hundred = hundredScale;
    // Percentage relative to 1:1 (100%). Falls back to Fit-relative if the
    // native size isn't known yet.
    final percent = hundred != null
        ? (scale / hundred * 100).round()
        : (scale * 100).round();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PresetButton(label: 'Fit', active: atFit, onTap: onFit),
        const SizedBox(width: AppSpacing.xs),
        SizedBox(
          width: 100,
          child: Slider(
            value: scale.clamp(minScale, maxScale),
            min: minScale,
            max: maxScale,
            onChanged: onZoom,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        _PresetButton(
          label: '100%',
          active: hundred != null && (scale - hundred).abs() < 0.01,
          onTap: hundred == null ? null : () => onZoom(hundred),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 40,
          child: Text(
            '$percent%',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// A zoom preset rendered as a clear chip button: filled when active, outlined
/// (so it still reads as tappable) otherwise, muted when disabled.
class _PresetButton extends StatelessWidget {
  const _PresetButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final border = active ? AppColors.accent : AppColors.border;
    final fg = !enabled
        ? AppColors.textSecondary
        : active
        ? Colors.white
        : AppColors.textPrimary;

    return Material(
      color: active ? AppColors.accent : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        side: BorderSide(color: border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// A one-shot loupe mark confirmation — exactly one of rating/flag/colour is
/// set, describing the mark that was just applied.
class _MarkFlash {
  const _MarkFlash.rating(int this.rating) : flag = null, color = null;
  const _MarkFlash.flag(PickFlag this.flag) : rating = null, color = null;
  const _MarkFlash.color(ColorLabel this.color) : rating = null, flag = null;

  /// New star rating (0 = cleared), or null when this isn't a rating flash.
  final int? rating;

  /// New pick/reject flag, or null when this isn't a flag flash.
  final PickFlag? flag;

  /// New colour label, or null when this isn't a colour flash.
  final ColorLabel? color;
}

/// The centred HUD content for a [_MarkFlash]: big stars, a pick/reject chip,
/// or a colour swatch, in a translucent rounded pill.
class _MarkFlashContent extends StatelessWidget {
  const _MarkFlashContent({required this.flash});

  final _MarkFlash flash;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        child: _body(),
      ),
    );
  }

  Widget _body() {
    final rating = flash.rating;
    if (rating != null) {
      if (rating == 0) return const _FlashLabel('No rating');
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rating; i++)
            const Icon(
              Icons.star_rounded,
              color: AppColors.ratingGold,
              size: 44,
            ),
        ],
      );
    }
    final flag = flash.flag;
    if (flag != null) {
      return switch (flag) {
        PickFlag.pick => const _FlashLabel(
          'Pick',
          icon: Icons.check_circle_rounded,
          color: AppColors.labelGreen,
        ),
        PickFlag.reject => const _FlashLabel(
          'Rejected',
          icon: Icons.cancel_rounded,
          color: AppColors.labelRed,
        ),
        PickFlag.none => const _FlashLabel('Flag cleared'),
      };
    }
    final color = flash.color!;
    if (color == ColorLabel.none) return const _FlashLabel('Colour cleared');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: color.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.sm),
        _FlashLabel(color.displayName),
      ],
    );
  }
}

/// A big label (optional leading icon) for the mark-confirmation HUD.
class _FlashLabel extends StatelessWidget {
  const _FlashLabel(this.text, {this.icon, this.color});

  final String text;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppColors.textPrimary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, color: tint, size: 32),
          const SizedBox(width: AppSpacing.sm),
        ],
        Text(
          text,
          style: TextStyle(
            color: tint,
            fontSize: 26,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Paints the read-only Lightroom/Camera-Raw crop over the loupe image: dims'
/// the cropped-away border and outlines the kept rectangle. Lives inside the
/// image's RotatedBox, so it inherits the same zoom/pan/rotation transform.
class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter({required this.crop, required this.imageAspect});

  final CropRect crop;

  /// The image's native pixel size, used to place the letterboxed image rect
  /// within the (contain-fitted) canvas. Null while it is still resolving.
  final Size? imageAspect;

  @override
  void paint(Canvas canvas, Size size) {
    final aspect = imageAspect;
    if (aspect == null || aspect.width <= 0 || aspect.height <= 0) return;
    final image = _letterboxedImageRect(size, aspect);

    // The kept rectangle's four corners, rotated about its centre by the
    // straighten angle — Camera Raw stores the crop axis-aligned in the
    // *straightened* frame, so on the original image it appears tilted. Falls
    // out to an axis-aligned box when the angle is 0 (see [CropRect.corners]).
    final pts = crop.corners(
      offX: image.left,
      offY: image.top,
      w: image.width,
      h: image.height,
    );
    final keep = Path()..moveTo(pts.first.$1, pts.first.$2);
    for (final (x, y) in pts.skip(1)) {
      keep.lineTo(x, y);
    }
    keep.close();

    // Dim everything outside the kept crop (even-odd = image minus keep).
    final mask = Path()
      ..addRect(image)
      ..addPath(keep, Offset.zero)
      ..fillType = PathFillType.evenOdd;
    canvas
      ..drawPath(mask, Paint()..color = Colors.black.withValues(alpha: 0.45))
      ..drawPath(
        keep,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: 0.9),
      );
  }

  @override
  bool shouldRepaint(_CropOverlayPainter oldDelegate) => true;
}

/// The rect [image] occupies inside a [canvas] area under `BoxFit.contain` —
/// shared by every overlay painted over the loupe photo (crop outline,
/// clipping/peaking analysis) so they all line up with the displayed image.
Rect _letterboxedImageRect(Size canvas, Size image) {
  final scale = math.min(
    canvas.width / image.width,
    canvas.height / image.height,
  );
  final dispW = image.width * scale;
  final dispH = image.height * scale;
  final offX = (canvas.width - dispW) / 2;
  final offY = (canvas.height - dispH) / 2;
  return Rect.fromLTWH(offX, offY, dispW, dispH);
}

/// Paints a decoded analysis overlay (clipping-warning or focus-peaking RGBA
/// image) over the loupe photo, aligned to the same `BoxFit.contain` rect as
/// the base image. Lives inside the same `RotatedBox`, so it inherits zoom,
/// pan and rotation.
class _AnalysisOverlayPainter extends CustomPainter {
  const _AnalysisOverlayPainter({
    required this.image,
    required this.imageAspect,
  });

  /// The overlay to paint — same pixel dimensions as [imageAspect].
  final ui.Image image;

  /// The base image's native pixel size, once resolved.
  final Size? imageAspect;

  @override
  void paint(Canvas canvas, Size size) {
    final aspect = imageAspect;
    if (aspect == null || aspect.width <= 0 || aspect.height <= 0) return;
    final dest = _letterboxedImageRect(size, aspect);
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    canvas.drawImageRect(
      image,
      src,
      dest,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(_AnalysisOverlayPainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.imageAspect != imageAspect;
}

/// A small floating panel drawing the RGB histogram as three overlaid channel
/// curves (sqrt-scaled so a strong single peak doesn't flatten the rest).
/// Fixed over the image (not part of the zoom/pan transform) since it
/// describes the whole photo's tonal distribution, not the current viewport.
class _HistogramPanel extends StatelessWidget {
  const _HistogramPanel({required this.histogram});

  final RgbHistogram histogram;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: SizedBox(
          width: 192,
          height: 84,
          child: CustomPaint(painter: _HistogramPainter(histogram: histogram)),
        ),
      ),
    );
  }
}

/// Draws the three channel curves for [_HistogramPanel].
class _HistogramPainter extends CustomPainter {
  const _HistogramPainter({required this.histogram});

  final RgbHistogram histogram;

  @override
  void paint(Canvas canvas, Size size) {
    final maxCount = histogram.maxCount;
    if (maxCount == 0) return;
    final maxSqrt = math.sqrt(maxCount.toDouble());

    void drawChannel(List<int> bins, Color color) {
      final path = Path();
      for (var i = 0; i < bins.length; i++) {
        final x = size.width * i / (bins.length - 1);
        final h = size.height * (math.sqrt(bins[i].toDouble()) / maxSqrt);
        final y = size.height - h;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }

    drawChannel(histogram.red, Colors.redAccent);
    drawChannel(histogram.green, Colors.greenAccent);
    drawChannel(histogram.blue, Colors.lightBlueAccent);
  }

  @override
  bool shouldRepaint(_HistogramPainter oldDelegate) =>
      oldDelegate.histogram != histogram;
}
