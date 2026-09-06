import Cocoa

/// Black pad that shows the token count of whatever was last pasted into it.
/// Nothing else is displayed: the text view behind the number is fully transparent.
class AppDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate {

    private static let frameKey = "TokenCounterWindowFrame"

    /// The content view runs the full window height (fullSizeContentView), so the
    /// top strip is reserved by hand for the traffic lights.
    private static let titlebarHeight: CGFloat = 28

    private var window: NSWindow!
    private var textView: PasteSink!
    private var countLabel: NSTextField!
    private let tokenizer = Tokenizer()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        buildWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
    }

    // MARK: - UI

    private func buildWindow() {
        let size = NSSize(width: 200, height: 128)
        let frame = NSRect(origin: defaultOrigin(for: size), size: size)

        window = NSWindow(contentRect: frame,
                          styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                          backing: .buffered,
                          defer: false)
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = true
        window.backgroundColor = .black
        window.appearance = NSAppearance(named: .darkAqua)
        window.hasShadow = true
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.setFrameAutosaveName(Self.frameKey)

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = content

        // Visible titlebar strip: a lighter shade than the pad, with a hairline
        // divider, so the traffic-light band reads as its own band.
        let titlebar = NSView(frame: NSRect(x: 0,
                                            y: size.height - Self.titlebarHeight,
                                            width: size.width,
                                            height: Self.titlebarHeight))
        titlebar.wantsLayer = true
        titlebar.layer?.backgroundColor = NSColor(white: 0.16, alpha: 1.0).cgColor
        titlebar.autoresizingMask = [.width, .minYMargin]
        content.addSubview(titlebar)

        let divider = NSView(frame: NSRect(x: 0, y: 0, width: size.width, height: 1))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(white: 0.28, alpha: 1.0).cgColor
        divider.autoresizingMask = [.width, .maxYMargin]
        titlebar.addSubview(divider)

        // Invisible sink that receives the paste. It spans the black area only —
        // stopping short of the titlebar strip so the pointer stays an arrow over
        // the traffic lights and turns into an I-beam over the pad itself.
        textView = PasteSink(frame: NSRect(x: 0,
                                           y: 0,
                                           width: size.width,
                                           height: size.height - Self.titlebarHeight))
        textView.onPaste = { [weak self] text in self?.update(with: text) }
        textView.delegate = self
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textColor = .clear
        textView.insertionPointColor = .clear
        textView.font = .systemFont(ofSize: 1)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.autoresizingMask = [.width, .height]
        content.addSubview(textView)

        countLabel = NSTextField(labelWithString: "0")
        countLabel.font = .monospacedDigitSystemFont(ofSize: 34, weight: .bold)
        countLabel.textColor = NSColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1.0)
        countLabel.alignment = .center
        countLabel.backgroundColor = .clear
        countLabel.isBezeled = false
        // Centred in the black pad, i.e. below the reserved titlebar strip.
        countLabel.frame = NSRect(x: 0,
                                  y: (size.height - Self.titlebarHeight - 40) / 2,
                                  width: size.width,
                                  height: 40)
        countLabel.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        content.addSubview(countLabel)
        countLabel.isEnabled = false
    }

    private func defaultOrigin(for size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else { return NSPoint(x: 100, y: 100) }
        let visible = screen.visibleFrame
        return NSPoint(x: visible.maxX - size.width - 24,
                       y: visible.minY + 24)
    }

    // MARK: - Counting

    private func update(with text: String) {
        let count = tokenizer.countTokens(text)
        countLabel.stringValue = formatted(count)
    }

    private func formatted(_ n: Int) -> String {
        // Keep long numbers readable inside a 200pt window.
        let s = String(n)
        guard s.count > 3 else { return s }
        var out = ""
        for (i, ch) in s.enumerated() {
            if i > 0 && (s.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return out
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}

// MARK: - Paste sink

/// A text view that exists only to catch ⌘V. It clears itself before each paste so
/// the reported number always describes the clipboard, never an accumulation.
private final class PasteSink: NSTextView {

    var onPaste: ((String) -> Void)?

    override func paste(_ sender: Any?) {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        // Never build up an ever-growing buffer: the storage is replaced, not appended.
        textStorage?.setAttributedString(NSAttributedString(string: ""))
        onPaste?(text)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        paste(sender)
    }

    override var acceptsFirstResponder: Bool { true }

    /// The sink is keyboard-only. Letting it swallow clicks would block both the
    /// traffic lights and background-dragging; it keeps focus regardless because
    /// nothing else in the window can take it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "v" {
            paste(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
