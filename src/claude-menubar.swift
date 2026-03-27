import Cocoa
import Foundation

// MARK: - Preferences

struct Prefs: Codable {
    var showSession: Bool = true
    var showWeek: Bool = false
    var showSonnet: Bool = false
    var showTimeToReset: Bool = true
    var displayFormat: DisplayFormat = .both

    enum DisplayFormat: String, Codable {
        case percentage, bar, both
    }

    static let path = NSString(string: "~/.claude-gauge/prefs.json").expandingTildeInPath

    static func load() -> Prefs {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let prefs = try? JSONDecoder().decode(Prefs.self, from: data) else {
            return Prefs()
        }
        return prefs
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(self) {
            try? data.write(to: URL(fileURLWithPath: Prefs.path))
        }
    }
}

// MARK: - Data

struct QuotaEntry {
    let label: String
    let symbol: String
    let percentage: Int
    let resetDate: Date?
}

// MARK: - Bar Rendering

func miniBar(_ pct: Int, width: Int = 8) -> String {
    let filled = Int((Double(pct) / 100.0 * Double(width)).rounded())
    return String(repeating: "▰", count: filled) + String(repeating: "▱", count: width - filled)
}

// MARK: - Time

func formatDelta(_ secs: TimeInterval) -> String {
    if secs < 0 { return "now" }
    let totalMins = (Int(secs) + 59) / 60
    let hours = totalMins / 60
    let mins = totalMins % 60
    if hours >= 24 {
        let days = hours / 24
        let h = hours % 24
        return "\(days)d\u{00b7}\(h)h"
    } else if hours > 0 {
        return "\(hours)h\u{00b7}\(mins)m"
    } else {
        return "\(mins)m"
    }
}

// MARK: - Controller

class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var tickTimer: Timer?
    private var dataTimer: Timer?
    private var prefs = Prefs.load()
    private var quotas: [QuotaEntry] = []
    private var lastDataModTime: Date?
    private var lastUpdateTime: Date?

    private let dataFile = NSString(string: "~/.claude-gauge/data.json").expandingTildeInPath
    private let iconPath = NSString(string: "~/.claude-gauge/assets/claude-menubar-icon.png").expandingTildeInPath

    override init() {
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        if let icon = NSImage(contentsOfFile: iconPath) {
            icon.isTemplate = true
            icon.size = NSSize(width: 18, height: 18)
            statusItem.button?.image = icon
            statusItem.button?.imagePosition = .imageLeft
        }
        statusItem.button?.title = " ..."

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        readData()

        // Check for new data every 5s (just a file stat, very cheap)
        dataTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.readDataIfChanged()
        }

        // Tick countdown every 60s
        tickTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.updateDisplay()
        }
    }

    // MARK: - Data

    func readDataIfChanged() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: dataFile),
              let modTime = attrs[.modificationDate] as? Date else { return }
        if let last = lastDataModTime, modTime <= last { return }
        readData()
    }

    func readData() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: dataFile)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rl = json["rate_limits"] as? [String: Any] else { return }

        var entries: [QuotaEntry] = []

        if let fiveHour = rl["five_hour"] as? [String: Any],
           let pct = fiveHour["used_percentage"] as? Double {
            var resetDate: Date?
            if let ts = fiveHour["resets_at"] as? Double {
                resetDate = Date(timeIntervalSince1970: ts)
            }
            entries.append(QuotaEntry(label: "session", symbol: "◷", percentage: Int(pct), resetDate: resetDate))
        }

        if let sevenDay = rl["seven_day"] as? [String: Any],
           let pct = sevenDay["used_percentage"] as? Double {
            var resetDate: Date?
            if let ts = sevenDay["resets_at"] as? Double {
                resetDate = Date(timeIntervalSince1970: ts)
            }
            entries.append(QuotaEntry(label: "week", symbol: "◫", percentage: Int(pct), resetDate: resetDate))
        }

        if !entries.isEmpty {
            quotas = entries
            lastUpdateTime = Date()
            if let attrs = try? FileManager.default.attributesOfItem(atPath: dataFile),
               let modTime = attrs[.modificationDate] as? Date {
                lastDataModTime = modTime
            }
        }
        updateDisplay()
    }

    // MARK: - Display

    func effectivePercentage(_ q: QuotaEntry) -> Int {
        // If reset happened after our last data update → stale data → show 0%
        guard let resetDate = q.resetDate, let lastUpdate = lastUpdateTime else { return q.percentage }
        if resetDate > lastUpdate && resetDate <= Date() { return 0 }
        return q.percentage
    }

    func formatBarTitle(_ q: QuotaEntry) -> String {
        let pct = effectivePercentage(q)
        switch prefs.displayFormat {
        case .percentage: return "\(pct)%"
        case .bar: return miniBar(pct, width: 8)
        case .both: return "\(miniBar(pct, width: 8)) \(pct)%"
        }
    }

    func countdownFor(_ q: QuotaEntry) -> String {
        guard let resetDate = q.resetDate else { return "" }
        let remaining = resetDate.timeIntervalSince(Date())
        if remaining <= 0 { return "reset" }
        return formatDelta(remaining)
    }

    func updateDisplay() {
        guard !quotas.isEmpty else {
            statusItem.button?.title = " --"
            return
        }

        var parts: [String] = []
        for q in quotas {
            let show = (q.label == "session" && prefs.showSession) ||
                       (q.label == "week" && prefs.showWeek)
            if show {
                var part = "\(q.symbol)\u{2009}\(formatBarTitle(q))"
                if prefs.showTimeToReset {
                    let tl = countdownFor(q)
                    if !tl.isEmpty { part += " \(tl)" }
                }
                parts.append(part)
            }
        }

        statusItem.button?.title = parts.isEmpty ? " --" : " " + parts.joined(separator: "  ")
    }

    // MARK: - Menu

    func menuWillOpen(_ menu: NSMenu) {
        buildMenu()
    }

    func buildMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()
        menu.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        if !quotas.isEmpty {
            let labelWidth = 10
            for q in quotas {
                let paddedLabel = q.label.padding(toLength: labelWidth, withPad: " ", startingAt: 0)
                let pct = effectivePercentage(q)
                let bar = miniBar(pct, width: 10)
                let pctStr = String(format: "%3d%%", pct)
                let tl = countdownFor(q)
                let timeStr = tl.isEmpty ? "" : "  \(tl)"
                let title = "\(q.symbol)  \(paddedLabel) \(bar)  \(pctStr)\(timeStr)"
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
            menu.addItem(NSMenuItem.separator())
        }

        addHeader(menu, "Show in bar:")
        addToggle(menu, "  ◷ Session (5h)", #selector(toggleSession), prefs.showSession)
        addToggle(menu, "  ◫ Week (7d)", #selector(toggleWeek), prefs.showWeek)
        menu.addItem(NSMenuItem.separator())

        addHeader(menu, "Display:")
        addToggle(menu, "  Percentage", #selector(setPercentage), prefs.displayFormat == .percentage)
        addToggle(menu, "  Bar", #selector(setBar), prefs.displayFormat == .bar)
        addToggle(menu, "  Both", #selector(setBoth), prefs.displayFormat == .both)
        menu.addItem(NSMenuItem.separator())
        addToggle(menu, "  Show time to reset", #selector(toggleTime), prefs.showTimeToReset)
        menu.addItem(NSMenuItem.separator())

        var refreshTitle = "Data from statusline"
        if let lastUpdate = lastUpdateTime {
            let ago = Int(Date().timeIntervalSince(lastUpdate))
            if ago < 60 {
                refreshTitle += "  ·  \(ago)s ago"
            } else if ago < 3600 {
                refreshTitle += "  ·  \(ago / 60)m ago"
            } else {
                refreshTitle += "  ·  \(ago / 3600)h ago"
            }
        }
        let refreshItem = NSMenuItem(title: refreshTitle, action: nil, keyEquivalent: "")
        refreshItem.isEnabled = false
        menu.addItem(refreshItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    func addHeader(_ menu: NSMenu, _ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    func addToggle(_ menu: NSMenu, _ title: String, _ action: Selector, _ isOn: Bool) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.state = isOn ? .on : .off
        item.target = self
        menu.addItem(item)
    }

    // MARK: - Actions

    @objc func toggleSession() { prefs.showSession.toggle(); prefs.save(); updateDisplay() }
    @objc func toggleWeek() { prefs.showWeek.toggle(); prefs.save(); updateDisplay() }
    @objc func toggleTime() { prefs.showTimeToReset.toggle(); prefs.save(); updateDisplay() }

    @objc func setPercentage() { prefs.displayFormat = .percentage; prefs.save(); updateDisplay() }
    @objc func setBar() { prefs.displayFormat = .bar; prefs.save(); updateDisplay() }
    @objc func setBoth() { prefs.displayFormat = .both; prefs.save(); updateDisplay() }

    @objc func quit() { NSApp.terminate(nil) }
}

// MARK: - Main

class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: StatusBarController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = StatusBarController()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.run()
