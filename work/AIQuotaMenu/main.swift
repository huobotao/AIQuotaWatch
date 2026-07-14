import AppKit
import Foundation

private struct AccountTileData {
    let title: String
    let shortTitle: String
    let iconLabel: String
    let remainingText: String
    let subtitle: String
    let usedPercent: Double?
    let remainingPercent: Double?
    let timePercent: Double?
    let bottomLeft: String
    let bottomRight: String
    let tint: NSColor
}

/// 按用户约定给账号标主次：霍波桃 hotmail 是主账号，带 -1 的 UTS 学生号是副账号
private func accountRole(email: String?) -> String? {
    guard let email = email?.lowercased() else { return nil }
    if email.contains("hotmail.com") { return "主账号" }
    if email.contains("-1@") || email.contains("student.uts") { return "副账号" }
    return nil
}

private struct WindowCandidate {
    let lineTitle: String
    let remainingPercent: Double?
    let usedPercent: Double?
    let timePercent: Double?
    let countdown: String?
    let pace: String
    let tint: NSColor
}

private final class AccountTileView: NSView {
    private let data: AccountTileData

    init(data: AccountTileData) {
        self.data = data
        super.init(frame: NSRect(x: 0, y: 0, width: 420, height: 108))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 420).isActive = true
        heightAnchor.constraint(equalToConstant: 108).isActive = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let card = bounds.insetBy(dx: 10, dy: 5)
        let cardPath = NSBezierPath(roundedRect: card, xRadius: 8, yRadius: 8)
        NSColor.controlBackgroundColor.withAlphaComponent(0.72).setFill()
        cardPath.fill()
        NSColor.separatorColor.withAlphaComponent(0.75).setStroke()
        cardPath.lineWidth = 1
        cardPath.stroke()

        let titleAttrs = textAttributes(size: 15, weight: .semibold, color: .labelColor)
        let valueAttrs = textAttributes(size: 15, weight: .bold, color: .labelColor, alignment: .right)
        let secondaryAttrs = textAttributes(size: 11, weight: .regular, color: .secondaryLabelColor)
        let bottomAttrs = textAttributes(size: 10, weight: .medium, color: .secondaryLabelColor)
        let bottomRightAttrs = textAttributes(size: 10, weight: .medium, color: .secondaryLabelColor, alignment: .right)

        let content = card.insetBy(dx: 14, dy: 10)
        (data.title as NSString).draw(
            in: NSRect(x: content.minX, y: content.minY, width: content.width * 0.62, height: 20),
            withAttributes: titleAttrs
        )
        (data.remainingText as NSString).draw(
            in: NSRect(x: content.midX, y: content.minY, width: content.width / 2, height: 20),
            withAttributes: valueAttrs
        )
        (data.subtitle as NSString).draw(
            in: NSRect(x: content.minX, y: content.minY + 23, width: content.width, height: 16),
            withAttributes: secondaryAttrs
        )

        drawBar(in: NSRect(x: content.minX, y: content.minY + 50, width: content.width, height: 8))

        (data.bottomLeft as NSString).draw(
            in: NSRect(x: content.minX, y: content.minY + 64, width: content.width / 2, height: 14),
            withAttributes: bottomAttrs
        )
        (data.bottomRight as NSString).draw(
            in: NSRect(x: content.midX, y: content.minY + 64, width: content.width / 2, height: 14),
            withAttributes: bottomRightAttrs
        )
    }

    private func drawBar(in rect: NSRect) {
        let trackPath = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        NSColor.separatorColor.withAlphaComponent(0.55).setFill()
        trackPath.fill()

        if let used = data.usedPercent {
            let width = rect.width * CGFloat(clamp(used) / 100)
            if width > 1 {
                let fillRect = NSRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
                let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: rect.height / 2, yRadius: rect.height / 2)
                data.tint.setFill()
                fillPath.fill()
            }
        }

        if let time = data.timePercent {
            let markerX = rect.minX + rect.width * CGFloat(clamp(time) / 100)
            let markerRect = NSRect(x: markerX - 1.5, y: rect.minY - 6, width: 3, height: rect.height + 12)
            let markerPath = NSBezierPath(roundedRect: markerRect, xRadius: 1.5, yRadius: 1.5)
            NSColor.labelColor.setFill()
            markerPath.fill()
        }
    }

    private func textAttributes(
        size: CGFloat,
        weight: NSFont.Weight,
        color: NSColor,
        alignment: NSTextAlignment = .left
    ) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        return [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
    }

    private func clamp(_ value: Double) -> Double {
        min(100, max(0, value))
    }
}

final class MenuDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private let statusURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/AIQuotaWatch/status.json")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: 132)
        item.autosaveName = NSStatusItem.AutosaveName("com.codex.aiquotamenu.status")
        item.isVisible = true
        item.button?.title = ""
        item.button?.imagePosition = .imageOnly
        item.button?.imageScaling = .scaleNone
        item.button?.image = placeholderStatusImage()
        item.button?.toolTip = "AI 额度观察"
        item.menu = buildMenu(status: [:])
        statusItem = item
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.update()
        }
    }

    private func buildMenu(status: [String: Any]) -> NSMenu {
        let menu = NSMenu()
        let accounts = accountTiles(from: status)
        if accounts.isEmpty {
            menu.addItem(disabledItem("AI 额度读取中"))
        } else {
            for account in accounts {
                let item = NSMenuItem()
                item.view = AccountTileView(data: account)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let openItem = NSMenuItem(title: "打开窗口", action: #selector(openWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let refreshItem = NSMenuItem(title: "刷新主程序", action: #selector(refreshWatcher), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())
        let maker = NSMenuItem(title: "由 Codex（GPT-5）为 Richard 制作", action: nil, keyEquivalent: "")
        maker.isEnabled = false
        menu.addItem(maker)

        let quitItem = NSMenuItem(title: "退出菜单栏", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    private func update() {
        let status = readStatus()
        let accounts = accountTiles(from: status)
        statusItem?.isVisible = true
        statusItem?.length = 132
        statusItem?.button?.title = ""
        statusItem?.button?.imagePosition = .imageOnly
        statusItem?.button?.imageScaling = .scaleNone
        statusItem?.button?.image = statusImage(from: accounts)
        statusItem?.button?.toolTip = tooltip(from: status)
        statusItem?.menu = buildMenu(status: status)
    }

    private func readStatus() -> [String: Any] {
        guard let data = try? Data(contentsOf: statusURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return object
    }

    private func menuTitle(from status: [String: Any]) -> String {
        let accounts = accountTiles(from: status)
        guard !accounts.isEmpty else { return "AI 额度读取中" }
        return "AI " + accounts
            .map { "\($0.shortTitle) \($0.remainingText.replacingOccurrences(of: "剩 ", with: ""))" }
            .joined(separator: " · ")
    }

    private func placeholderStatusImage() -> NSImage {
        statusImage(from: [])
    }

    private func statusImage(from accounts: [AccountTileData]) -> NSImage {
        let size = NSSize(width: 126, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        NSGraphicsContext.current?.imageInterpolation = .high
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 7.5, weight: .bold),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.9)
        ]
        let rows = accounts.prefix(3)
        let rowHeight: CGFloat = 6
        let labelWidth: CGFloat = 10
        let barX: CGFloat = 14
        let barWidth: CGFloat = size.width - barX - 4
        let barHeight: CGFloat = 3.4

        if rows.isEmpty {
            drawMiniBar(
                in: NSRect(x: barX, y: 7.2, width: barWidth, height: barHeight),
                usedPercent: nil,
                timePercent: nil,
                tint: .systemBlue
            )
            ("AI" as NSString).draw(
                in: NSRect(x: 1, y: 4, width: labelWidth + 4, height: 10),
                withAttributes: labelAttributes
            )
        } else {
            for (index, account) in rows.enumerated() {
                let y = size.height - CGFloat(index + 1) * rowHeight + 1.1
                (account.iconLabel as NSString).draw(
                    in: NSRect(x: 3, y: y - 2.1, width: labelWidth, height: rowHeight + 3),
                    withAttributes: labelAttributes
                )
                drawMiniBar(
                    in: NSRect(x: barX, y: y, width: barWidth, height: barHeight),
                    usedPercent: account.usedPercent,
                    timePercent: account.timePercent,
                    tint: account.tint
                )
            }
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func drawMiniBar(
        in rect: NSRect,
        usedPercent: Double?,
        timePercent: Double?,
        tint: NSColor
    ) {
        let track = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        NSColor.labelColor.withAlphaComponent(0.22).setFill()
        track.fill()

        if let usedPercent {
            let fillWidth = max(1.5, rect.width * CGFloat(clamp(usedPercent) / 100))
            let fill = NSBezierPath(
                roundedRect: NSRect(x: rect.minX, y: rect.minY, width: fillWidth, height: rect.height),
                xRadius: rect.height / 2,
                yRadius: rect.height / 2
            )
            tint.setFill()
            fill.fill()
        }

        if let timePercent {
            let markerX = rect.minX + rect.width * CGFloat(clamp(timePercent) / 100)
            let marker = NSBezierPath(
                roundedRect: NSRect(x: markerX - 0.8, y: rect.minY - 2.2, width: 1.6, height: rect.height + 4.4),
                xRadius: 0.8,
                yRadius: 0.8
            )
            NSColor.labelColor.setFill()
            marker.fill()
        }
    }

    private func clamp(_ value: Double) -> Double {
        min(100, max(0, value))
    }

    private func tooltip(from status: [String: Any]) -> String {
        let accounts = accountTiles(from: status)
        guard !accounts.isEmpty else { return "AI 额度观察" }
        return accounts.map { "\($0.title)：\($0.remainingText)，\($0.subtitle)" }.joined(separator: "\n")
    }

    private func accountTiles(from status: [String: Any]) -> [AccountTileData] {
        let providers = status["providers"] as? [[String: Any]] ?? []
        guard !providers.isEmpty else { return [] }

        let codexProvider = providers.first { providerName($0).localizedCaseInsensitiveContains("Codex") }
        let claudeProviders = providers
            .filter { providerName($0).localizedCaseInsensitiveContains("Claude Code") }
            .sorted { (accountNumber(providerName($0)) ?? 0) < (accountNumber(providerName($1)) ?? 0) }
        let fableProviders = providers.filter { providerName($0).localizedCaseInsensitiveContains("Fable") }

        var accounts: [AccountTileData] = []
        if let codexProvider {
            if let candidate = tightestCandidate(from: windowCandidates(for: codexProvider, labelPrefix: "", tint: .systemBlue)) {
                accounts.append(tile(
                    title: "Codex",
                    shortTitle: "Codex",
                    iconLabel: "C",
                    candidate: candidate,
                    fallbackRemaining: percentText(codexProvider["remaining"])
                ))
            } else {
                // 账号在监控范围内但暂无窗口数据时保留占位行，保证三条横杠不缺席
                accounts.append(placeholderTile(
                    title: "Codex",
                    shortTitle: "Codex",
                    iconLabel: "C",
                    mode: codexProvider["mode"] as? String,
                    fallbackRemaining: percentText(codexProvider["remaining"]),
                    tint: .systemBlue
                ))
            }
        }

        for claudeProvider in claudeProviders.prefix(2) {
            let name = providerName(claudeProvider)
            let number = accountNumber(name)
            let matchingFable = fableProviders.first { accountNumber(providerName($0)) == number }
            // 用户只关心 Fable：有 Fable 钱包数据时只显示 Fable 周额度，缺失时才回退 Code 窗口
            var candidates: [WindowCandidate] = []
            if let matchingFable {
                candidates = windowCandidates(for: matchingFable, labelPrefix: "", tint: .systemPurple)
            }
            if candidates.isEmpty {
                candidates = windowCandidates(for: claudeProvider, labelPrefix: "Code", tint: .systemOrange)
            }
            let iconLabel = number.map(String.init) ?? "L"
            let email = claudeProvider["email"] as? String
            let role = accountRole(email: email)
            let title: String
            if let role {
                title = number.map { "Claude \($0) · \(role)" } ?? "Claude · \(role)"
            } else {
                title = name
            }
            if let candidate = tightestCandidate(from: candidates) {
                accounts.append(tile(
                    title: title,
                    shortTitle: number.map { "Claude \($0)" } ?? "Claude",
                    iconLabel: iconLabel,
                    email: email,
                    candidate: candidate,
                    fallbackRemaining: percentText(claudeProvider["remaining"])
                ))
            } else {
                accounts.append(placeholderTile(
                    title: title,
                    shortTitle: number.map { "Claude \($0)" } ?? "Claude",
                    iconLabel: iconLabel,
                    email: email,
                    mode: claudeProvider["mode"] as? String,
                    fallbackRemaining: percentText(claudeProvider["remaining"]),
                    tint: .systemOrange
                ))
            }
        }

        return accounts
    }

    private func windowCandidates(
        for provider: [String: Any],
        labelPrefix: String,
        tint: NSColor
    ) -> [WindowCandidate] {
        let windows = provider["windows"] as? [[String: Any]] ?? []
        return windows.compactMap { window in
            let title = window["title"] as? String ?? "窗口"
            let prefixedTitle = labelPrefix.isEmpty ? title : "\(labelPrefix) · \(title)"
            let remaining = doublePercent(window["remainingPercent"])
            let used = doublePercent(window["usedPercent"]) ?? remaining.map { 100 - $0 }
            let time = doublePercent(window["timePercent"])
            let countdown = window["countdown"] as? String
            let pace = window["pace"] as? String ?? "暂无判断"
            return WindowCandidate(
                lineTitle: prefixedTitle,
                remainingPercent: remaining,
                usedPercent: used,
                timePercent: time,
                countdown: countdown,
                pace: pace,
                tint: riskColor(remaining: remaining, fallback: tint)
            )
        }
    }

    private func tightestCandidate(from candidates: [WindowCandidate]) -> WindowCandidate? {
        candidates.min { lhs, rhs in
            switch (lhs.remainingPercent, rhs.remainingPercent) {
            case let (l?, r?):
                if l == r {
                    return (lhs.timePercent ?? 0) > (rhs.timePercent ?? 0)
                }
                return l < r
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.lineTitle < rhs.lineTitle
            }
        }
    }

    private func tile(
        title: String,
        shortTitle: String,
        iconLabel: String,
        email: String? = nil,
        candidate: WindowCandidate,
        fallbackRemaining: String?
    ) -> AccountTileData {
        let remainingText = candidate.remainingPercent.map { "剩 \(formatPercent($0))" } ?? "剩 \(fallbackRemaining ?? "--")"
        let countdown = cleanCountdown(candidate.countdown) ?? "重置时间未知"
        let usedText = candidate.usedPercent.map { "额度已用 \(formatPercent($0))" } ?? "额度未知"
        let timeText = candidate.timePercent.map { "时间 \(formatPercent($0))" } ?? "时间未知"
        // 有邮箱时优先展示身份，省掉节奏文案避免截断
        let subtitle: String
        if let email {
            subtitle = "\(email) · \(candidate.lineTitle) · \(countdown)"
        } else {
            subtitle = "\(candidate.lineTitle) · \(countdown) · \(candidate.pace)"
        }
        return AccountTileData(
            title: title,
            shortTitle: shortTitle,
            iconLabel: iconLabel,
            remainingText: remainingText,
            subtitle: subtitle,
            usedPercent: candidate.usedPercent,
            remainingPercent: candidate.remainingPercent,
            timePercent: candidate.timePercent,
            bottomLeft: usedText,
            bottomRight: timeText,
            tint: candidate.tint
        )
    }

    private func placeholderTile(
        title: String,
        shortTitle: String,
        iconLabel: String,
        email: String? = nil,
        mode: String?,
        fallbackRemaining: String?,
        tint: NSColor
    ) -> AccountTileData {
        // provider 级 remaining 可用时反推条形图，避免"剩 0%"却画空条的矛盾
        let remaining = doublePercent(fallbackRemaining)
        let used = remaining.map { 100 - $0 }
        let base = mode.map { "\($0) · 暂无窗口数据" } ?? "暂无窗口数据"
        return AccountTileData(
            title: title,
            shortTitle: shortTitle,
            iconLabel: iconLabel,
            remainingText: "剩 \(fallbackRemaining ?? "--")",
            subtitle: email.map { "\($0) · \(base)" } ?? base,
            usedPercent: used,
            remainingPercent: remaining,
            timePercent: nil,
            bottomLeft: used.map { "额度已用 \(formatPercent($0))" } ?? "额度未知",
            bottomRight: "时间未知",
            tint: riskColor(remaining: remaining, fallback: tint)
        )
    }

    private func percent(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return "\(Int(number.doubleValue.rounded()))%" }
        if let double = value as? Double { return "\(Int(double.rounded()))%" }
        if let int = value as? Int { return "\(int)%" }
        return nil
    }

    private func providerName(_ provider: [String: Any]) -> String {
        provider["name"] as? String ?? provider["shortName"] as? String ?? "未知项目"
    }

    private func accountNumber(_ name: String) -> Int? {
        let digits = name.filter { $0.isNumber }
        return digits.isEmpty ? nil : Int(String(digits))
    }

    private func percentText(_ value: Any?) -> String? {
        percent(value)
    }

    private func doublePercent(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String {
            let stripped = string.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(stripped)
        }
        return nil
    }

    private func formatPercent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private func cleanCountdown(_ value: String?) -> String? {
        guard let value, !value.isEmpty, !value.contains("--") else { return nil }
        return value
    }

    private func riskColor(remaining: Double?, fallback: NSColor) -> NSColor {
        guard let remaining else { return fallback }
        if remaining <= 20 { return .systemRed }
        if remaining <= 45 { return .systemOrange }
        return fallback
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func openWindow() {
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications/AI 额度观察.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    @objc private func refreshWatcher() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["kickstart", "-k", "gui/\(getuid())/com.richardhuo.aiquotawatch"]
        try? task.run()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = MenuDelegate()
app.delegate = delegate
app.run()
