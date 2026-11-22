import Cocoa
import FlutterMacOS
import ObjectiveC.runtime

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Deliver the first click to Flutter even when the window is inactive,
    // instead of AppKit swallowing that click just to activate the window. For
    // a click-driven culler a single click on a background Cullimingo window
    // should select a thumbnail straight away (Finder / Photo Mechanic behave
    // this way). AppKit asks the hit NSView — the FlutterView — for
    // acceptsFirstMouse(for:), which defaults to NO; override it to YES scoped
    // to that class only, never on NSView globally.
    Self.enableAcceptsFirstMouse(on: flutterViewController.view)

    // Native directory picker that allows creating folders (file_selector's
    // directory panel disables that) and opens at a given directory.
    let dialogs = FlutterMethodChannel(
      name: "cullimingo/dialogs",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    dialogs.setMethodCallHandler { (call, result) in
      if call.method == "appIcon" {
        // The Finder icon of an app bundle as PNG bytes, for the toolbar's
        // "Send to" button. Nil when the path is gone.
        let args = call.arguments as? [String: Any]
        guard let path = args?["path"] as? String,
          FileManager.default.fileExists(atPath: path)
        else {
          result(nil)
          return
        }
        let size = (args?["size"] as? Int) ?? 64
        result(Self.pngIcon(forFile: path, size: size))
        return
      }
      guard call.method == "pickDirectory" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let args = call.arguments as? [String: Any]
      let panel = NSOpenPanel()
      panel.canChooseFiles = false
      panel.canChooseDirectories = true
      panel.canCreateDirectories = true
      panel.allowsMultipleSelection = false
      if let initial = args?["initialDirectory"] as? String, !initial.isEmpty {
        panel.directoryURL = URL(fileURLWithPath: initial)
      }
      panel.begin { response in
        if response == .OK, let url = panel.url {
          result(url.path)
        } else {
          result(nil)
        }
      }
    }

    super.awakeFromNib()
  }

  /// Renders the workspace icon of [path] into a [size]×[size]-pixel PNG.
  private static func pngIcon(forFile path: String, size: Int) -> FlutterStandardTypedData? {
    let icon = NSWorkspace.shared.icon(forFile: path)
    guard
      let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return nil }
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    icon.draw(
      in: NSRect(x: 0, y: 0, width: size, height: size),
      from: .zero, operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else {
      return nil
    }
    return FlutterStandardTypedData(bytes: png)
  }

  /// Overrides `acceptsFirstMouse(for:)` to return true on [view]'s concrete
  /// class (the private FlutterView subclass). Uses `class_replaceMethod` so
  /// the override is added to that class alone — every other NSView keeps the
  /// default behaviour.
  private static func enableAcceptsFirstMouse(on view: NSView) {
    let selector = #selector(NSView.acceptsFirstMouse(for:))
    guard let template = class_getInstanceMethod(NSView.self, selector) else {
      return
    }
    let block: @convention(block) (AnyObject, NSEvent?) -> Bool = { _, _ in true }
    class_replaceMethod(
      type(of: view),
      selector,
      imp_implementationWithBlock(block),
      method_getTypeEncoding(template))
  }
}
