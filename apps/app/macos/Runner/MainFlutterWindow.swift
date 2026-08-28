import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.setFrame(initialFrame(), display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  // Opens wide enough on launch to show the desktop nav rail (>=840pt) right
  // away, instead of the 800x600 storyboard default that only fits the
  // narrow, bottom-nav layout. Clamped to the screen so it still fits on
  // smaller displays.
  private func initialFrame() -> NSRect {
    let preferredSize = NSSize(width: 1280, height: 800)
    guard let screenFrame = self.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
    else {
      return NSRect(origin: self.frame.origin, size: preferredSize)
    }
    let size = NSSize(
      width: min(preferredSize.width, screenFrame.width),
      height: min(preferredSize.height, screenFrame.height)
    )
    let origin = NSPoint(
      x: screenFrame.midX - size.width / 2,
      y: screenFrame.midY - size.height / 2
    )
    return NSRect(origin: origin, size: size)
  }
}
