import AppKit

struct Session: Codable {
    var isBreak = false
    var remaining: TimeInterval = 25 * 60
    var deadline: Date?
    var completed = false
    var customDuration: TimeInterval?
    var duration: TimeInterval { customDuration ?? (isBreak ? 5 * 60 : 25 * 60) }
    static func parseTime(_ input: String) -> TimeInterval? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              let minutes = Double(parts[0]), minutes <= 180 else { return nil }
        let seconds: Double
        if parts.count == 2 {
            guard let value = Double(parts[1]), value < 60 else { return nil }
            seconds = value
        } else { seconds = 0 }
        let total = minutes * 60 + seconds
        return total >= 1 && total <= 10800 ? total : nil
    }
    mutating func setCustom(_ seconds: TimeInterval) {
        customDuration = seconds; reset()
    }
    var running: Bool { deadline != nil }
    var label: String { isBreak ? "Break" : "Focus" }
    var clock: String {
        let seconds = max(0, Int(ceil(remaining)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    @discardableResult mutating func update(now: Date = Date()) -> Bool {
        guard let end = deadline else { return false }
        remaining = max(0, end.timeIntervalSince(now))
        if remaining == 0 { deadline = nil; completed = true; return true }
        return false
    }
    mutating func toggle(now: Date = Date()) {
        if update(now: now) { return }
        if running { deadline = nil; return }
        if completed { next() }
        deadline = now.addingTimeInterval(remaining)
    }
    mutating func reset() { deadline = nil; completed = false; remaining = duration }
    mutating func next() { isBreak.toggle(); customDuration = nil; reset() }
}

enum Dial {
    // Measured directly from the black seam pixels in Assets/tomato.png.
    static let radius = 81.0
    private static let seamSamples: [Double] = [
        108.4608, 105.6346, 103.6159, 102.1355, 100.7897, 99.8476, 98.2326, 97.4251, 96.6176, 96.4831, 95.2718, 94.5989, 94.0606, 93.5223, 93.1185, 92.7148, 92.3111, 91.9073, 91.6381, 91.2344, 91.0998, 90.8307, 90.5615, 90.4269, 90.2923, 90.0232, 89.8886, 89.8886, 89.7540, 89.7540, 89.6194, 89.6194, 89.6194, 89.6194, 89.6194, 89.7540, 89.7540, 89.8886, 90.0232, 90.1578, 90.2923, 90.4269, 90.5615, 90.8307, 91.0998, 91.2344, 91.6381, 91.9073, 92.3111, 92.7148, 93.1185, 93.5223, 94.0606, 94.5989, 95.8102, 96.4831, 96.6176, 97.9635, 98.9055, 99.8476, 101.0588, 102.4046, 103.8850, 106.0383, 109.6720
    ]
    static func seamAtX(_ x: Double) -> Double {
        let t = min(Double(seamSamples.count - 1), max(0, (x - 15) / 2.5))
        let i = min(seamSamples.count - 2, Int(t))
        let f = t - Double(i)
        return seamSamples[i] * (1 - f) + seamSamples[i + 1] * f
    }
    static func seamY(_ angle: Double) -> Double { seamAtX(95 + radius * sin(angle)) }
    static func seamSlope(_ x: Double) -> Double { (seamAtX(x + 1) - seamAtX(x - 1)) / 2 }
    static func opacity(_ angle: Double) -> Double {
        min(1, max(0, (1.48 - abs(angle)) / 0.14))
    }
    static func angle(minute: Int, remainingMinutes: Double) -> Double {
        let raw = (remainingMinutes - Double(minute)) * 2 * Double.pi / 60
        return atan2(sin(raw), cos(raw))
    }
}

final class CompanionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class TomatoView: NSView {
    var session = Session() {
        didSet {
            let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            if !reducedMotion && session.completed && !oldValue.completed {
                ringStarted = ProcessInfo.processInfo.systemUptime
                startAnimation()
            }
            if !reducedMotion && session.running && !oldValue.running &&
                (oldValue.completed || abs(session.remaining - session.duration) < 1) {
                windFrom = 0
                windStarted = ProcessInfo.processInfo.systemUptime
                startAnimation()
            } else if !session.running && oldValue.running && !session.completed {
                windFrom = nil
            } else if !reducedMotion && !session.running && !session.completed &&
                        abs(session.remaining - oldValue.remaining) > 2 {
                windFrom = oldValue.remaining / 60
                windStarted = ProcessInfo.processInfo.systemUptime
                startAnimation()
            }
        }
    }
    private var animationTimer: Timer?
    private var windFrom: Double?
    private var windStarted = 0.0
    private var ringStarted: Double?
    private func startAnimation() {
        guard animationTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let now = ProcessInfo.processInfo.systemUptime
            if now - self.windStarted >= 0.75 { self.windFrom = nil }
            if let start = self.ringStarted, now - start >= 1.0 { self.ringStarted = nil }
            self.needsDisplay = true
            if self.windFrom == nil && self.ringStarted == nil {
                timer.invalidate(); self.animationTimer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }
    private var dialMinutes: Double {
        let actual = session.deadline.map { max(0, $0.timeIntervalSinceNow) } ?? session.remaining
        guard let from = windFrom else { return actual / 60 }
        let t = min(1, max(0, (ProcessInfo.processInfo.systemUptime - windStarted) / 0.75))
        let eased = 1 - pow(1 - t, 3)
        return from + (actual / 60 - from) * eased
    }
    var onDoubleClick: (() -> Void)?
    var onMenu: ((NSEvent) -> Void)?
    var onMove: (() -> Void)?
    private var startMouse = NSPoint.zero
    private var startOrigin = NSPoint.zero
    private var dragged = false
    private var contextClick = false
    private let artwork: NSImage = {
        guard let url = Bundle.main.url(forResource: "tomato", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { fatalError("Missing tomato artwork") }
        return image
    }()
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        contextClick = event.modifierFlags.contains(.control)
        if contextClick { onMenu?(event); return }
        startMouse = NSEvent.mouseLocation
        startOrigin = window?.frame.origin ?? .zero
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard !contextClick else { return }
        let p = NSEvent.mouseLocation
        let dx = p.x - startMouse.x, dy = p.y - startMouse.y
        if hypot(dx, dy) > 3 { dragged = true }
        if dragged { window?.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy)) }
    }
    override func mouseUp(with event: NSEvent) {
        guard !contextClick else { return }
        if dragged { onMove?() } else if event.clickCount == 2 { onDoubleClick?() }
    }
    override func rightMouseDown(with event: NSEvent) { onMenu?(event) }
    private func centered(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = 1; shadow.shadowOffset = NSSize(width: 0, height: -1)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .shadow: shadow]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: (190 - size.width) / 2, y: y), withAttributes: attrs)
    }
    private var dialLabels: [Int: NSImage] = [:]
    private func drawDialLabel(_ minute: Int, angle: Double) {
        let label: NSImage
        if let cached = dialLabels[minute] { label = cached }
        else {
            let text = String(minute) as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            let measured = text.size(withAttributes: attrs)
            let size = NSSize(width: ceil(measured.width) + 2, height: ceil(measured.height) + 2)
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: Int(size.width * 3), pixelsHigh: Int(size.height * 3),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            bitmap.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            text.draw(at: NSPoint(x: 1, y: 1), withAttributes: attrs)
            NSGraphicsContext.restoreGraphicsState()
            label = NSImage(size: size); label.addRepresentation(bitmap)
            dialLabels[minute] = label
        }
        // Each strip follows the measured seam, including its steeper outer edges.
        let radius = Dial.radius
        let stripWidth = 0.5
        for u in stride(from: 0.0, to: Double(label.size.width), by: stripWidth) {
            let a = angle + (u - Double(label.size.width) / 2) / radius
            guard abs(a) < 1.46 else { continue }
            let c = cos(a), sn = sin(a)
            let transform = NSAffineTransform()
            transform.transformStruct = NSAffineTransformStruct(
                m11: c, m12: Dial.seamSlope(95 + radius * sn) * c,
                m21: 0, m22: 1,
                tX: 95 + radius * sn, tY: Dial.seamY(a) - 20)
            NSGraphicsContext.saveGraphicsState()
            transform.concat()
            label.draw(in: NSRect(x: 0, y: 0, width: stripWidth + 0.04, height: label.size.height),
                       from: NSRect(x: u, y: 0, width: stripWidth + 0.04, height: label.size.height),
                       operation: .sourceOver, fraction: 0.95 * Dial.opacity(a))
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); dirtyRect.fill(using: .copy)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSGraphicsContext.saveGraphicsState()
        if let started = ringStarted {
            let t = ProcessInfo.processInfo.systemUptime - started
            let rotation = NSAffineTransform()
            rotation.translateX(by: 95, yBy: 65)
            rotation.rotate(byDegrees: CGFloat(sin(t * 48) * 3.5 * max(0, 1 - t)))
            rotation.translateX(by: -95, yBy: -65)
            rotation.concat()
        }
        artwork.draw(in: NSRect(x: 0, y: 30, width: 190, height: 151), from: .zero, operation: .sourceOver, fraction: 1)
        // Project a rotating 60-minute scale around the curved lower shell.
        // The remaining minute is always centered below the fixed white pointer.
        let minutes = dialMinutes
        for minute in 0..<60 {
            let angle = Dial.angle(minute: minute, remainingMinutes: minutes)
            guard abs(angle) < 1.38 else { continue }
            let perspective = cos(angle)
            let x = 95 + Dial.radius * sin(angle)
            let y = Dial.seamY(angle) - 4
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: x, y: y))
            let length = minute % 5 == 0 ? 5.0 : 2.7
            tick.line(to: NSPoint(x: x, y: y - length))
            NSColor.white.withAlphaComponent(0.88 * Dial.opacity(angle)).setStroke()
            tick.lineWidth = max(0.4, perspective * 0.85); tick.stroke()
            if minute % 5 == 0 { drawDialLabel(minute, angle: angle) }
        }
        centered(session.clock, y: 47, font: .monospacedDigitSystemFont(ofSize: 14, weight: .semibold), color: .white)
        NSGraphicsContext.restoreGraphicsState()

    }
}

final class TimerApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var panel: CompanionPanel!
    var tomato: TomatoView!
    var status: NSStatusItem!
    var ticker: Timer?
    var session = Session()
    var desktop = UserDefaults.standard.bool(forKey: "desktop")
    var sound = !UserDefaults.standard.bool(forKey: "muted")
    var alarmVolume: Float = UserDefaults.standard.object(forKey: "alarmVolume") == nil ? 0.9 : min(1, max(0, UserDefaults.standard.float(forKey: "alarmVolume")))
    private var alarmKind = UserDefaults.standard.string(forKey: "alarmKind") == "spaceship" ? "spaceship" : "bell"
    private var alarmPlayer: NSSound?
    private var volumeLabel: NSTextField?

    func playAlarm(preview: Bool = false) {
        guard preview || sound else { return }
        alarmPlayer?.stop()
        if let url = Bundle.main.url(forResource: alarmKind, withExtension: "wav") {
            alarmPlayer = NSSound(contentsOf: url, byReference: false)
        }
        alarmPlayer?.volume = alarmVolume
        alarmPlayer?.play()
    }
    @objc func previewAlarm() { playAlarm(preview: true) }
    @objc func changeVolume(_ slider: NSSlider) {
        alarmVolume = slider.floatValue
        UserDefaults.standard.set(alarmVolume, forKey: "alarmVolume")
        alarmPlayer?.volume = alarmVolume
        volumeLabel?.stringValue = "Volume: \(Int((alarmVolume * 100).rounded()))%"
    }
    @objc func changeAlarmKind(_ popup: NSPopUpButton) {
        alarmKind = popup.indexOfSelectedItem == 1 ? "spaceship" : "bell"
        UserDefaults.standard.set(alarmKind, forKey: "alarmKind")
        alarmPlayer?.stop()
    }
    @objc func soundSettings() {
        let alert = NSAlert()
        alert.messageText = "Timer sound"
        alert.informativeText = "Choose an alarm bell or a synthesized Jetsons-inspired spaceship sound. Adjust volume and preview below. Changes save automatically."
        alert.addButton(withTitle: "Done")
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 132))
        let choice = NSPopUpButton(frame: NSRect(x: 0, y: 100, width: 300, height: 26))
        choice.addItems(withTitles: ["Mechanical alarm", "Retro spaceship (Jetsons-inspired)"])
        choice.selectItem(at: alarmKind == "spaceship" ? 1 : 0)
        choice.target = self; choice.action = #selector(changeAlarmKind(_:))
        choice.setAccessibilityLabel("Completion sound")
        content.addSubview(choice)
        let label = NSTextField(labelWithString: "Volume: \(Int((alarmVolume * 100).rounded()))%")
        label.frame = NSRect(x: 0, y: 75, width: 300, height: 20)
        volumeLabel = label; content.addSubview(label)
        let slider = NSSlider(value: Double(alarmVolume), minValue: 0, maxValue: 1, target: self, action: #selector(changeVolume(_:)))
        slider.frame = NSRect(x: 0, y: 46, width: 300, height: 25)
        slider.isContinuous = true
        slider.setAccessibilityLabel("Alarm volume")
        content.addSubview(slider)
        let preview = NSButton(title: "Preview sound", target: self, action: #selector(previewAlarm))
        preview.frame = NSRect(x: 0, y: 2, width: 145, height: 30)
        content.addSubview(preview)
        alert.accessoryView = content
        alert.window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        alarmPlayer?.stop(); volumeLabel = nil
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let data = UserDefaults.standard.data(forKey: "session"),
           let saved = try? JSONDecoder().decode(Session.self, from: data),
           saved.remaining.isFinite, saved.remaining >= 0, saved.remaining <= saved.duration {
            session = saved
        }
        panel = CompanionPanel(contentRect: NSRect(x: 0, y: 0, width: 190, height: 185), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        tomato = TomatoView(frame: NSRect(x: 0, y: 0, width: 190, height: 185))
        tomato.toolTip = "Double-click to start/pause/resume · Drag to move · Right-click for controls"
        tomato.onDoubleClick = { [weak self] in self?.toggle() }
        tomato.onMove = { [weak self] in self?.savePosition() }
        tomato.onMenu = { [weak self] event in
            guard let self else { return }
            NSMenu.popUpContextMenu(self.makeMenu(), with: event, for: self.tomato)
        }
        panel.contentView = tomato
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Tomato Timer")
        status.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let menu = NSMenu(); menu.delegate = self; status.menu = menu
        restorePosition(); applyLevel()
        tick(); manageTicker()
        if !UserDefaults.standard.bool(forKey: "hasSeenQuickGuide") {
            DispatchQueue.main.async { [weak self] in self?.quickGuide() }
        }
    }
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        for item in makeMenu().items { item.menu?.removeItem(item); menu.addItem(item) }
    }
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Tomato Timer · \(session.label) \(session.clock)", action: nil, keyEquivalent: ""))
        add(menu, session.running ? "Pause" : session.completed ? "Start \(session.isBreak ? "focus" : "break")" : "Start / Resume", #selector(toggle))
        add(menu, "Set custom time…", #selector(customTime))
        add(menu, "Reset current timer", #selector(reset))
        add(menu, session.isBreak ? "Switch to focus (25 min)" : "Switch to break (5 min)", #selector(next))
        menu.addItem(.separator())
        add(menu, "Bring timer forward", #selector(bringForward))
        add(menu, "Send to desktop", #selector(sendBack))
        add(menu, "Bring timer here", #selector(bringHere))
        menu.addItem(.separator())
        add(menu, "Sound settings…", #selector(soundSettings))
        add(menu, sound ? "Mute completion sound" : "Enable completion sound", #selector(toggleSound))
        add(menu, "Quick guide…", #selector(quickGuide))
        add(menu, "Quit Tomato Timer", #selector(quit))
        return menu
    }
    func add(_ menu: NSMenu, _ title: String, _ action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; menu.addItem(item)
    }
    func persist() {
        if let data = try? JSONEncoder().encode(session) { UserDefaults.standard.set(data, forKey: "session") }
    }
    func updateDisplay() {
        tomato.session = session; tomato.needsDisplay = true
        status.button?.title = session.completed ? " ✓" : session.running ? " \(session.clock)" : ""
        status.button?.toolTip = "Tomato Timer · \(session.label) \(session.clock)"
    }
    func tick() {
        if session.update() {
            playAlarm()
            persist(); manageTicker()
        }
        updateDisplay()
    }
    func manageTicker() {
        ticker?.invalidate(); ticker = nil
        if session.running {
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common); ticker = timer
        }
    }
    @objc func toggle() {
        // Show completion first if the click arrived just after the deadline.
        if session.update() {
            playAlarm()
        } else { session.toggle() }
        persist(); manageTicker(); updateDisplay()
    }
    @objc func customTime() {
        let alert = NSAlert()
        alert.messageText = "Set custom time"
        alert.informativeText = "Enter minutes (e.g. 15) or minutes:seconds (e.g. 2:30). From 1 second to 180 minutes. The new timer starts paused."
        alert.addButton(withTitle: "Set time")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
        input.stringValue = String(format: "%d:%02d", Int(session.duration) / 60, Int(session.duration) % 60)
        input.placeholderString = "25 or 25:00"
        input.setAccessibilityLabel("Custom time in minutes or minutes and seconds")
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        alert.window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        while alert.runModal() == .alertFirstButtonReturn {
            guard let seconds = Session.parseTime(input.stringValue) else {
                alert.informativeText = "Please enter a time from 0:01 to 180:00, such as 15 or 2:30. Seconds must be below 60."
                input.selectText(nil)
                continue
            }
            session.setCustom(seconds)
            persist(); manageTicker(); updateDisplay()
            return
        }
    }
    @objc func reset() { session.reset(); persist(); manageTicker(); updateDisplay() }
    @objc func next() { session.next(); persist(); manageTicker(); updateDisplay() }
    @objc func toggleSound() { sound.toggle(); UserDefaults.standard.set(!sound, forKey: "muted"); if !sound { alarmPlayer?.stop() } }
    func applyLevel() {
        panel.level = desktop ? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1) : .floating
        panel.ignoresMouseEvents = false; panel.orderFrontRegardless()
    }
    func setDesktop(_ value: Bool) { desktop = value; UserDefaults.standard.set(value, forKey: "desktop"); applyLevel() }
    @objc func bringForward() { setDesktop(false) }
    @objc func sendBack() { setDesktop(true) }
    @objc func bringHere() { placeOnScreen(); bringForward(); savePosition() }
    func placeOnScreen() {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: frame.maxX - 440, y: frame.minY + 35))
    }
    func restorePosition() {
        let d = UserDefaults.standard
        if d.object(forKey: "x") != nil {
            let point = NSPoint(x: d.double(forKey: "x"), y: d.double(forKey: "y"))
            if NSScreen.screens.contains(where: { $0.visibleFrame.contains(NSRect(x: point.x + 25, y: point.y + 30, width: 140, height: 125)) }) {
                panel.setFrameOrigin(point); return
            }
        }
        placeOnScreen()
    }
    func savePosition() { UserDefaults.standard.set(panel.frame.minX, forKey: "x"); UserDefaults.standard.set(panel.frame.minY, forKey: "y") }
    @objc func quickGuide() {
        let alert = NSAlert()
        alert.messageText = "Meet your Tomato Timer"
        alert.informativeText = "Double-click the tomato to start, pause, or resume.\n\nDrag it anywhere on your desktop.\n\nRight-click for custom time, sounds, and desktop placement.\n\nFocus for 25 minutes, then double-click to start a 5-minute break when the alarm rings.\n\nUse the timer icon in the menu bar to bring it forward or quit."
        alert.addButton(withTitle: "Got it")
        if let url = Bundle.main.url(forResource: "tomato", withExtension: "png") {
            alert.icon = NSImage(contentsOf: url)
        }
        alert.window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            UserDefaults.standard.set(true, forKey: "hasSeenQuickGuide")
        }
    }
    @objc func quit() { NSApplication.shared.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { persist(); savePosition() }
}

@main enum Main {
    static func main() throws {
        if CommandLine.arguments.contains("--self-test") {
            let now = Date(timeIntervalSince1970: 1000)
            var s = Session()
            s.toggle(now: now)
            assert(s.running && s.clock == "25:00")
            s.toggle(now: now.addingTimeInterval(61))
            assert(!s.running && s.remaining == 1439 && s.clock == "23:59")
            s.toggle(now: now.addingTimeInterval(300))
            assert(!s.update(now: now.addingTimeInterval(301)))
            let data = try JSONEncoder().encode(s)
            s = try JSONDecoder().decode(Session.self, from: data)
            assert(s.update(now: now.addingTimeInterval(5000)))
            assert(s.completed && !s.running && s.clock == "00:00")
            assert(!s.update(now: now.addingTimeInterval(5001)))
            s.toggle(now: now.addingTimeInterval(5002))
            assert(s.isBreak && s.running && s.remaining == 300)
            s.reset(); assert(s.isBreak && !s.running && s.remaining == 300)
            s.next(); assert(!s.isBreak && s.remaining == 1500)
            assert(abs(Dial.angle(minute: 25, remainingMinutes: 25)) < 0.00001)
            assert(Dial.angle(minute: 30, remainingMinutes: 25) < 0)
            assert(Dial.angle(minute: 20, remainingMinutes: 25) > 0)
            assert(abs(Dial.angle(minute: 0, remainingMinutes: 0)) < 0.00001)
            assert(abs(Dial.angle(minute: 25, remainingMinutes: 24.5) + Double.pi / 60) < 0.00001)
            assert(Session.parseTime("15") == 900)
            assert(Session.parseTime(" 2:30 ") == 150)
            assert(Session.parseTime("0:01") == 1)
            assert(Session.parseTime("180:00") == 10800)
            for invalid in ["0", "-1", "1:60", "181", "abc", "2:", "1:2:3"] {
                assert(Session.parseTime(invalid) == nil)
            }
            s.setCustom(90); assert(!s.running && s.remaining == 90 && s.duration == 90)
            s.toggle(now: now); s.reset(); assert(!s.running && s.remaining == 90)
            let customData = try JSONEncoder().encode(s)
            s = try JSONDecoder().decode(Session.self, from: customData)
            assert(s.duration == 90)
            s.next(); assert(s.customDuration == nil && s.duration == 300)
            print("PASS: custom input validation, reset, persistence, next session")
            print("PASS: dial alignment, direction, fractional motion, zero alignment")
            print("PASS: start, pause, resume, elapsed-time accuracy, persistence, completion once, break transition, reset, switch")
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        if let index = CommandLine.arguments.firstIndex(of: "--preview"), CommandLine.arguments.count > index + 1 {
            let view = TomatoView(frame: NSRect(x: 0, y: 0, width: 190, height: 185))
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 380, pixelsHigh: 370, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            bitmap.size = view.bounds.size
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            view.draw(view.bounds); NSGraphicsContext.restoreGraphicsState()
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            return
        }
        let delegate = TimerApp(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
