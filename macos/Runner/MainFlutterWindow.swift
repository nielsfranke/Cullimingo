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
