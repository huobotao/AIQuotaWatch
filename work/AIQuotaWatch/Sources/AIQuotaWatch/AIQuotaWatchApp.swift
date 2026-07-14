import AppKit
import CryptoKit
import Darwin
import Foundation
import Network
import SwiftUI

@main
struct AIQuotaWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: QuotaModel

    init() {
        _model = StateObject(wrappedValue: SharedQuotaModel.model)
    }

    var body: some Scene {
        WindowGroup("AI 额度观察", id: "quota-dashboard") {
            DetailView(model: model)
                .frame(minWidth: 840, minHeight: 620)
                .background(AppPalette.windowBackground)
        }
        .defaultSize(width: 840, height: 620)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var httpServer: QuotaHTTPServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        httpServer = QuotaHTTPServer()
        httpServer?.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            DashboardWindowCoordinator.shared.configureOpenWindowsForFullscreen()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showDashboardWindow(nil)
        }
        return true
    }

    @objc func showDashboardWindow(_ sender: Any?) {
        DashboardWindowCoordinator.shared.show(model: SharedQuotaModel.model)
    }

    @objc func refreshQuota(_ sender: Any?) {
        SharedQuotaModel.model.refresh()
    }

    @objc func quitApp(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let summaryItem = NSMenuItem(title: "正在读取额度...", action: nil, keyEquivalent: "")
    private let sourceItem = NSMenuItem(title: "由 Codex（GPT-5）制作", action: nil, keyEquivalent: "")
    private weak var appDelegate: AppDelegate?
    private let model: QuotaModel
    private var timer: Timer?

    init(model: QuotaModel, appDelegate: AppDelegate) {
        self.model = model
        self.appDelegate = appDelegate
        self.statusItem = NSStatusBar.system.statusItem(withLength: 108)
        self.statusItem.autosaveName = NSStatusItem.AutosaveName("com.codex.aiquotawatch.status")
        self.statusItem.isVisible = true
        configureButton()
        configureMenu()
        updateTitle()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateTitle()
            }
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent", accessibilityDescription: "AI 额度观察")
        button.image?.isTemplate = true
        button.imagePosition = .imageLeft
        button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        button.toolTip = "AI 额度观察"
        button.title = " AI"
    }

    private func configureMenu() {
        let menu = NSMenu()
        summaryItem.isEnabled = false
        sourceItem.isEnabled = false
        menu.addItem(summaryItem)
        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "打开窗口", action: #selector(AppDelegate.showDashboardWindow(_:)), keyEquivalent: "")
        openItem.target = appDelegate
        menu.addItem(openItem)

        let refreshItem = NSMenuItem(title: "刷新", action: #selector(AppDelegate.refreshQuota(_:)), keyEquivalent: "r")
        refreshItem.target = appDelegate
        menu.addItem(refreshItem)

        menu.addItem(.separator())
        menu.addItem(sourceItem)

        let quitItem = NSMenuItem(title: "退出", action: #selector(AppDelegate.quitApp(_:)), keyEquivalent: "q")
        quitItem.target = appDelegate
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func updateTitle() {
        let snapshot = model.snapshot
        statusItem.isVisible = true
        statusItem.length = 108
        statusItem.button?.title = " " + snapshot.compactMenuTitle
        statusItem.button?.toolTip = snapshot.statusMenuSummary
        summaryItem.title = snapshot.statusMenuSummary
    }
}

@MainActor
final class DashboardWindowCoordinator {
    static let shared = DashboardWindowCoordinator()
    private var window: NSWindow?

    func configureOpenWindowsForFullscreen() {
        for window in NSApp.windows where window.title == "AI 额度观察" {
            configureForFullscreen(window)
        }
    }

    func show(model: QuotaModel) {
        if let existing = window {
            configureForFullscreen(existing)
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        if let existing = NSApp.windows.first(where: { $0.title == "AI 额度观察" }) {
            window = existing
            configureForFullscreen(existing)
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = DetailView(model: model)
            .frame(minWidth: 840, minHeight: 620)
            .background(AppPalette.windowBackground)
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "AI 额度观察"
        newWindow.center()
        newWindow.contentView = NSHostingView(rootView: view)
        newWindow.isReleasedWhenClosed = false
        configureForFullscreen(newWindow)
        newWindow.makeKeyAndOrderFront(nil)
        window = newWindow
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureForFullscreen(_ window: NSWindow) {
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.standardWindowButton(.zoomButton)?.isEnabled = true
    }
}

@MainActor
enum SharedQuotaModel {
    static let model = QuotaModel()
}

@MainActor
final class QuotaModel: ObservableObject {
    @Published var snapshot = DashboardSnapshot.empty
    @Published var isRefreshing = false
    @Published var zoomScale: CGFloat = 1.0
    private var timer: Timer?
    private let minZoom: CGFloat = 0.8
    private let maxZoom: CGFloat = 2.2

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task.detached(priority: .utility) {
            let next = QuotaScanner.scan(now: Date())
            await MainActor.run {
                self.snapshot = next
                StatusFileWriter.write(snapshot: next)
                self.isRefreshing = false
            }
        }
    }

    func setZoom(_ scale: CGFloat) {
        let next = min(max(scale, minZoom), maxZoom)
        guard abs(next - zoomScale) > 0.001 else { return }
        zoomScale = next
    }

    func nudgeZoom(_ delta: CGFloat) {
        setZoom(zoomScale + delta)
    }

    func magnifyZoom(_ magnification: CGFloat) {
        let factor = max(0.2, 1 + magnification)
        setZoom(zoomScale * factor)
    }

    func resetZoom() {
        setZoom(1.0)
    }

    func openCodexFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: QuotaConfig.expandedPath("~/.codex/sessions")))
    }

    func openClaudeFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: QuotaConfig.expandedPath("~/.claude/projects")))
    }
}

struct QuotaConfig {
    static func expandedPath(_ path: String) -> String {
        if path == "~" { return NSHomeDirectory() }
        if path.hasPrefix("~/") {
            return NSHomeDirectory() + "/" + path.dropFirst(2)
        }
        return path
    }
}

enum StatusFileWriter {
    static let statusURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/AIQuotaWatch/status.json")

    static func write(snapshot: DashboardSnapshot) {
        do {
            let payload = StatusPayloadBuilder.payload(from: snapshot)
            try FileManager.default.createDirectory(
                at: statusURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: statusURL, options: .atomic)
        } catch {
            NSLog("AIQuotaWatch failed to write status.json: %@", String(describing: error))
        }
    }
}

struct DashboardSnapshot {
    var scannedAt: Date
    var codex: ProviderSnapshot
    var claudes: [ProviderSnapshot]
    var tokenReport: TokenUsageReport

    static let empty = DashboardSnapshot(
        scannedAt: Date(),
        codex: ProviderSnapshot(
            name: "GPT Codex",
            shortName: "Cdx",
            mode: "读取 Codex 本地 rate_limits",
            windows: [],
            latestAt: nil,
            source: "~/.codex/sessions"
        ),
        claudes: [
            ProviderSnapshot(
                name: "Claude Code",
                shortName: "Cl",
                mode: "读取官方 usage 接口",
                windows: [],
                latestAt: nil,
                source: "api.anthropic.com/api/oauth/usage"
            )
        ],
        tokenReport: .empty
    )

    var menuTitle: String {
        let codexRemain = codex.tightestRemainingText
        let normalClaude = claudes.filter { !$0.isFableWallet }
        let fable = claudes.filter { $0.isFableWallet }
        let claudeText: String
        if normalClaude.count <= 1 {
            claudeText = "L\(normalClaude.first?.tightestRemainingText ?? "--")"
        } else {
            claudeText = normalClaude.enumerated()
                .map { "L\($0.offset + 1)\($0.element.tightestRemainingText)" }
                .joined(separator: " ")
        }
        let fableText = fable.isEmpty ? "" : " F\(fable.map { $0.tightestRemainingText }.minByPercent() ?? "--")"
        return "AI C\(codexRemain) \(claudeText)\(fableText)"
    }

    var compactMenuTitle: String {
        let codexText = compactPercent(codex.tightestRemainingText)
        let normalClaude = claudes.filter { !$0.isFableWallet }
        let fable = claudes.filter { $0.isFableWallet }
        let claudeValues = normalClaude.map { $0.tightestRemainingText }.filter { $0 != "--" }
        let claudeText = compactPercent(claudeValues.minByPercent() ?? "--")
        let fableValues = fable.map { $0.tightestRemainingText }.filter { $0 != "--" }
        if !fableValues.isEmpty {
            let fableText = compactPercent(fableValues.minByPercent() ?? "--")
            return "AI C\(codexText) L\(claudeText) F\(fableText)"
        }
        return "AI C\(codexText) L\(claudeText)"
    }

    var statusMenuSummary: String {
        let normalClaude = claudes.filter { !$0.isFableWallet }
        let fable = claudes.filter { $0.isFableWallet }
        let claudeText = normalClaude.map { $0.tightestRemainingText }.minByPercent() ?? "--"
        if fable.isEmpty {
            return "Codex \(codex.tightestRemainingText) · Claude \(claudeText)"
        }
        let fableText = fable.map { $0.tightestRemainingText }.minByPercent() ?? "--"
        return "Codex \(codex.tightestRemainingText) · Claude \(claudeText) · Fable \(fableText)"
    }

    private func compactPercent(_ text: String) -> String {
        text.replacingOccurrences(of: "%", with: "")
    }

    var providers: [ProviderSnapshot] {
        [codex] + claudes
    }
}

extension Array where Element == String {
    func minByPercent() -> String? {
        let pairs = compactMap { text -> (String, Int)? in
            guard text != "--" else { return nil }
            let number = text.replacingOccurrences(of: "%", with: "")
            guard let value = Int(number) else { return nil }
            return (text, value)
        }
        return pairs.min(by: { $0.1 < $1.1 })?.0
    }
}

struct ProviderSnapshot: Identifiable {
    var id: String { shortName }
    var name: String
    var shortName: String
    var mode: String
    var windows: [QuotaWindow]
    var latestAt: Date?
    var source: String
    /// 账号邮箱（Claude 官方 profile 接口），用于区分「账号 1 / 账号 2」
    var email: String? = nil

    var tightestRemainingText: String {
        let values = windows.compactMap { $0.remainingPercent }
        guard let value = values.min() else { return "--" }
        return "\(Int(value.rounded()))%"
    }

    var primaryWindow: QuotaWindow? {
        windows.first
    }

    var isFableWallet: Bool {
        name.localizedCaseInsensitiveContains("Fable") || shortName.localizedCaseInsensitiveContains("Fb")
    }
}

struct QuotaWindow: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let usedPercent: Double?
    let timePercent: Double?
    let resetAt: Date?
    let windowMinutes: Int
    let latestAt: Date?
    let official: Bool
    let basis: String
    let tokenSummary: TokenSummary?
    let isExpired: Bool

    var remainingPercent: Double? {
        guard !isExpired else { return nil }
        guard let usedPercent else { return nil }
        return max(0, min(100, 100 - usedPercent))
    }

    var activeUsedPercent: Double? {
        isExpired ? nil : usedPercent
    }

    var pace: Pace {
        if isExpired { return .stale }
        guard let usedPercent, let timePercent else { return .unknown }
        let delta = usedPercent - timePercent
        if delta > 8 { return .balanceFaster }
        if delta < -8 { return .timeFaster }
        return .matched
    }

    func isExpired(at date: Date) -> Bool {
        guard let resetAt else { return isExpired }
        return resetAt.timeIntervalSince(date) < -120
    }

    func remainingPercent(at date: Date) -> Double? {
        guard !isExpired(at: date), let usedPercent else { return nil }
        return max(0, min(100, 100 - usedPercent))
    }

    func activeUsedPercent(at date: Date) -> Double? {
        isExpired(at: date) ? nil : usedPercent
    }

    func timePercent(at date: Date) -> Double? {
        guard let resetAt else { return timePercent }
        let duration = Double(windowMinutes) * 60
        guard duration > 0 else { return timePercent }
        let remaining = max(0, resetAt.timeIntervalSince(date))
        let elapsed = max(0, min(duration, duration - remaining))
        return elapsed / duration * 100
    }

    func pace(at date: Date) -> Pace {
        if isExpired(at: date) { return .stale }
        guard let usedPercent, let timePercent = timePercent(at: date) else { return .unknown }
        let delta = usedPercent - timePercent
        if delta > 8 { return .balanceFaster }
        if delta < -8 { return .timeFaster }
        return .matched
    }
}

struct TokenSummary {
    let total: Double
    let entries: Int
}

struct TokenUsageReport {
    var codexEvents: [TokenUsageEvent]
    var codexConversations: [TokenConversationUsage]
    var scannedFiles: Int
    var source: String
    var claudeConversations: [TokenConversationUsage] = []
    var claudeScannedFiles: Int = 0
    var claudeSource: String = "~/.claude/projects"

    static let empty = TokenUsageReport(
        codexEvents: [],
        codexConversations: [],
        scannedFiles: 0,
        source: "~/.codex/sessions"
    )

    var totalTokens: Double {
        codexEvents.reduce(0) { $0 + Double($1.tokens) }
    }

    var claudeTotalTokens: Double {
        claudeConversations.reduce(0) { $0 + Double($1.tokens) }
    }

    var peakEvent: TokenUsageEvent? {
        codexEvents.max { $0.tokens < $1.tokens }
    }

    var latestEvent: TokenUsageEvent? {
        codexEvents.max { $0.timestamp < $1.timestamp }
    }
}

struct TokenUsageEvent: Identifiable {
    let id: String
    let timestamp: Date
    let sessionID: String
    let conversationTitle: String
    let tokens: Int
    let inputTokens: Int?
    let cachedInputTokens: Int?
    let outputTokens: Int?
    let reasoningTokens: Int?
    let cumulativeTokens: Int?
    let sourceFile: String
}

struct TokenConversationUsage: Identifiable {
    let id: String
    let title: String
    let tokens: Int
    let events: Int
    let latestAt: Date
    let sourceFile: String
}

enum Pace {
    case balanceFaster
    case timeFaster
    case matched
    case stale
    case unknown

    var text: String {
        switch self {
        case .balanceFaster: return "额度跑得更快"
        case .timeFaster: return "时间跑得更快"
        case .matched: return "节奏接近"
        case .stale: return "等新记录"
        case .unknown: return "暂无判断"
        }
    }

    var symbolName: String {
        switch self {
        case .balanceFaster: return "exclamationmark.triangle.fill"
        case .timeFaster: return "clock.fill"
        case .matched: return "equal.circle.fill"
        case .stale: return "arrow.clockwise.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .balanceFaster: return AppPalette.warning
        case .timeFaster: return AppPalette.good
        case .matched: return AppPalette.steady
        case .stale: return AppPalette.muted
        case .unknown: return AppPalette.muted
        }
    }
}

enum AppPalette {
    static let windowBackground = Color(nsColor: NSColor.windowBackgroundColor)
    static let panel = Color(nsColor: NSColor.controlBackgroundColor)
    static let border = Color(nsColor: NSColor.separatorColor).opacity(0.55)
    static let text = Color(nsColor: NSColor.labelColor)
    static let secondaryText = Color(nsColor: NSColor.secondaryLabelColor)
    static let muted = Color.gray
    static let codex = Color(red: 0.12, green: 0.44, blue: 0.82)
    static let claude = Color(red: 0.75, green: 0.33, blue: 0.16)
    static let good = Color(red: 0.18, green: 0.55, blue: 0.28)
    static let warning = Color(red: 0.88, green: 0.58, blue: 0.13)
    static let danger = Color(red: 0.78, green: 0.16, blue: 0.19)
    static let steady = Color(red: 0.24, green: 0.46, blue: 0.64)
}

struct MenuPanel: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: QuotaModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("AI 额度观察")
                    .font(.headline)
                Spacer()
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("刷新")
            }

            CompactProviderView(provider: model.snapshot.codex, tint: AppPalette.codex)
            ForEach(model.snapshot.claudes) { provider in
                CompactProviderView(provider: provider, tint: AppPalette.claude)
            }

            Divider()

            HStack {
                Button("打开窗口") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "quota-dashboard")
                }
                    .keyboardShortcut(.defaultAction)
                Spacer()
                Button("退出") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}

struct CompactProviderView: View {
    let provider: ProviderSnapshot
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(provider.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(provider.tightestRemainingText)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
            }

            if provider.windows.isEmpty {
                Text("暂无本地用量记录")
                    .font(.caption)
                    .foregroundStyle(AppPalette.secondaryText)
            } else {
                ForEach(provider.windows.prefix(2)) { window in
                    HStack(spacing: 8) {
                        Text(window.title)
                            .font(.caption)
                            .foregroundStyle(AppPalette.secondaryText)
                            .frame(width: 64, alignment: .leading)
                        MiniProgress(
                            value: window.activeUsedPercent ?? 0,
                            tint: progressColor(window.remainingPercent),
                            marker: window.isExpired ? nil : window.timePercent
                        )
                        Text(Format.percent(window.remainingPercent))
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func progressColor(_ remaining: Double?) -> Color {
        guard let remaining else { return AppPalette.muted }
        if remaining < 15 { return AppPalette.danger }
        if remaining < 35 { return AppPalette.warning }
        return tint
    }
}

struct DetailView: View {
    @ObservedObject var model: QuotaModel
    @State private var contentHeight: CGFloat = 0
    @State private var claudeTokenDraft = ""
    @State private var claudeTokenMessage: String?
    @State private var claudeTokenSaved = false
    private let columns = [
        GridItem(.adaptive(minimum: 360), spacing: 16, alignment: .top)
    ]

    var body: some View {
        GeometryReader { proxy in
            let zoom = model.zoomScale
            let contentWidth = max(420, proxy.size.width / zoom)

            ScrollView {
                dashboardContent
                    .frame(width: contentWidth, alignment: .topLeading)
                    .background(
                        GeometryReader { contentProxy in
                            Color.clear.preference(
                                key: ContentHeightPreferenceKey.self,
                                value: contentProxy.size.height
                            )
                        }
                    )
                    .scaleEffect(zoom, anchor: .topLeading)
                    .frame(
                        width: proxy.size.width,
                        height: max(proxy.size.height, contentHeight * zoom),
                        alignment: .topLeading
                    )
            }
            .background(
                MagnificationEventBridge { magnification in
                    model.magnifyZoom(magnification)
                }
            )
            .onPreferenceChange(ContentHeightPreferenceKey.self) { height in
                contentHeight = height
            }
        }
    }

    private var dashboardContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            providerOverview

            TokenUsageSection(report: model.snapshot.tokenReport)

            ClaudeTokenSection(report: model.snapshot.tokenReport)

            settings

            footer
        }
        .padding(22)
    }

    private struct AccountGroup: Identifiable {
        let id: String
        let cards: [ProviderSnapshot]
        let isCodex: Bool
    }

    // 严格按账号分组：Codex 一组；每个 Claude 账号一组（Code 卡 + 该账号的 Fable 钱包卡）
    private var accountGroups: [AccountGroup] {
        let claudeAccounts = model.snapshot.claudes.filter { !$0.isFableWallet }
        let fableWallets = model.snapshot.claudes.filter { $0.isFableWallet }

        var groups: [AccountGroup] = [
            AccountGroup(id: "codex-group", cards: [model.snapshot.codex], isCodex: true)
        ]
        var pairedWalletIDs = Set<String>()
        for account in claudeAccounts {
            var cards = [account]
            if let wallet = fableWallets.first(where: { accountDigits($0.name) == accountDigits(account.name) }) {
                cards.append(wallet)
                pairedWalletIDs.insert(wallet.id)
            }
            groups.append(AccountGroup(id: "claude-\(account.id)", cards: cards, isCodex: false))
        }
        // 配不上账号的 Fable 钱包单独成组，保证卡片不丢
        for wallet in fableWallets where !pairedWalletIDs.contains(wallet.id) {
            groups.append(AccountGroup(id: "fable-\(wallet.id)", cards: [wallet], isCodex: false))
        }
        return groups
    }

    private func accountDigits(_ name: String) -> String {
        name.filter(\.isNumber)
    }

    @ViewBuilder
    private var providerOverview: some View {
        let groups = accountGroups

        ViewThatFits(in: .horizontal) {
            // 宽窗口：每个账号一列（Codex｜Claude 1｜Claude 2），列内是该账号全部卡片
            HStack(alignment: .top, spacing: 16) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(group.cards) { provider in
                            ProviderDetailCard(
                                provider: provider,
                                tint: group.isCodex ? AppPalette.codex : AppPalette.claude
                            )
                        }
                    }
                    .frame(minWidth: 320, maxWidth: .infinity, alignment: .topLeading)
                }
            }

            // 窄窗口：每个账号一行区块，顺序不变
            VStack(alignment: .leading, spacing: 26) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(group.cards) { provider in
                            ProviderDetailCard(
                                provider: provider,
                                tint: group.isCodex ? AppPalette.codex : AppPalette.claude
                            )
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("AI 额度观察")
                    .font(.system(size: 28, weight: .semibold))
                Text("扫描时间 \(Format.time(model.snapshot.scannedAt))")
                    .font(.callout)
                    .foregroundStyle(AppPalette.secondaryText)
            }

            Spacer()

            HStack(spacing: 6) {
                Button {
                    model.nudgeZoom(-0.1)
                } label: {
                    Image(systemName: "minus")
                }
                .help("缩小")

                Button {
                    model.resetZoom()
                } label: {
                    Text("\(Int((model.zoomScale * 100).rounded()))%")
                        .font(.system(.callout, design: .monospaced).weight(.semibold))
                        .frame(minWidth: 48)
                }
                .help("重置缩放")

                Button {
                    model.nudgeZoom(0.1)
                } label: {
                    Image(systemName: "plus")
                }
                .help("放大")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Button {
                model.refresh()
            } label: {
                Label(model.isRefreshing ? "刷新中" : "刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("数据来源原则")
                .font(.headline)

            Label("只显示官方结构化额度字段；不把本地 token 用量换算成余额。", systemImage: "checkmark.shield")
                .foregroundStyle(AppPalette.good)
            Label("Codex 使用本地 session 里的官方 rate_limits。Claude Code 逐个读取正在运行的账号令牌，分别调用官方 usage 接口；没有官方字段就显示不可用。", systemImage: "info.circle")
                .foregroundStyle(AppPalette.secondaryText)

            claudeAccountImport

            HStack(spacing: 10) {
                Button {
                    model.openCodexFolder()
                } label: {
                    Label("Codex 记录", systemImage: "folder")
                }
                Button {
                    model.openClaudeFolder()
                } label: {
                    Label("Claude 记录", systemImage: "folder")
                }
            }
        }
        .padding(16)
        .background(AppPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppPalette.border, lineWidth: 1)
        )
    }

    private var claudeAccountImport: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            HStack(alignment: .firstTextBaseline) {
                Label("Claude 多账号", systemImage: "person.2")
                    .font(.headline)
                Spacer()
                Text("本机保存 · 官方接口")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppPalette.secondaryText)
            }

            Text("第二个 Claude Code 账号可以粘贴 OAuth token；应用只把它用于官方 usage 接口，不读取密码，也不本地估算余额。")
                .font(.callout)
                .foregroundStyle(AppPalette.secondaryText)

            let accounts = ClaudeUsageClient.accountSummaries()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("当前识别 \(accounts.count) 个 Claude 账号")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text(accounts.count >= 2 ? "可同时监测" : "还需要第二个账号")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accounts.count >= 2 ? AppPalette.good : AppPalette.warning)
                }

                if accounts.isEmpty {
                    Label("没有找到 Claude Code 账号 token。先打开 Claude Code，或在下面粘贴账号 token。", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(AppPalette.warning)
                } else {
                    ForEach(accounts) { account in
                        HStack(spacing: 8) {
                            Image(systemName: account.live ? "bolt.circle.fill" : "externaldrive.fill")
                                .foregroundStyle(account.live ? AppPalette.good : AppPalette.secondaryText)
                            Text(account.id)
                                .font(.system(.callout, design: .monospaced).weight(.semibold))
                            Text(account.subscription ?? "Claude")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppPalette.secondaryText)
                            Spacer()
                            Text(account.live ? "运行中" : "已保存")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(account.live ? AppPalette.good : AppPalette.secondaryText)
                        }
                    }
                }
            }
            .padding(12)
            .background(AppPalette.panel.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppPalette.border.opacity(0.8), lineWidth: 1)
            )

            HStack(spacing: 10) {
                SecureField("粘贴 Claude Code OAuth token", text: $claudeTokenDraft)
                    .textFieldStyle(.roundedBorder)

                Button {
                    let result = ClaudeUsageClient.importManualToken(claudeTokenDraft)
                    claudeTokenMessage = result.message
                    claudeTokenSaved = result.saved
                    if result.saved {
                        claudeTokenDraft = ""
                        model.refresh()
                    }
                } label: {
                    Label("保存账号", systemImage: "key")
                }
                .disabled(claudeTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let claudeTokenMessage {
                Label(claudeTokenMessage, systemImage: claudeTokenSaved ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(claudeTokenSaved ? AppPalette.good : AppPalette.warning)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("余额只来自官方结构化额度字段；没有官方字段就显示不可用。")
                .foregroundStyle(AppPalette.secondaryText)
            Spacer()
            Text("由 Codex（GPT-5）为 Richard 制作 · 2026-07-02")
                .font(.callout.weight(.semibold))
        }
        .font(.callout)
        .padding(.top, 2)
    }
}

struct FieldBox<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppPalette.secondaryText)
            HStack(spacing: 6) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct MagnificationEventBridge: NSViewRepresentable {
    let onMagnify: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMagnify: onMagnify)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onMagnify = onMagnify
        context.coordinator.attach(to: nsView)
    }

    @MainActor
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        var onMagnify: (CGFloat) -> Void
        private var monitor: Any?
        private weak var window: NSWindow?

        init(onMagnify: @escaping (CGFloat) -> Void) {
            self.onMagnify = onMagnify
        }

        func attach(to view: NSView) {
            window = view.window
            if view.window == nil {
                Task { @MainActor [weak self, weak view] in
                    self?.window = view?.window
                }
            }
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let window = self.window, event.window === window {
                        self.onMagnify(event.magnification)
                    }
                }
                return event
            }
        }

        func detach() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
            window = nil
        }
    }
}

struct ProviderDetailCard: View {
    let provider: ProviderSnapshot
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(tint)
                    .frame(width: 10, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.name)
                        .font(.title3.weight(.semibold))
                    Text(provider.mode)
                        .font(.caption)
                        .foregroundStyle(AppPalette.secondaryText)
                }
                if let email = provider.email {
                    Text(email)
                        .font(.system(.callout, design: .monospaced).weight(.medium))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(tint.opacity(0.12))
                        .clipShape(Capsule())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.leading, 6)
                }
                Spacer()
                Text(provider.tightestRemainingText)
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
            }

            if provider.windows.isEmpty {
            EmptyStateView(source: provider.source, message: provider.mode)
            } else {
                ForEach(provider.windows) { window in
                    WindowDetailView(window: window, tint: tint)
                }
            }

            Divider()

            HStack {
                Label(provider.source, systemImage: "externaldrive")
                    .foregroundStyle(AppPalette.secondaryText)
                Spacer()
                Text("最近 \(Format.relative(provider.latestAt))")
                    .foregroundStyle(AppPalette.secondaryText)
            }
            .font(.caption)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppPalette.border, lineWidth: 1)
        )
    }
}

struct EmptyStateView: View {
    let source: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("暂无可用记录", systemImage: "doc.text.magnifyingglass")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(AppPalette.secondaryText)
            Text(source)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(AppPalette.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
    }
}

struct TokenUsageSection: View {
    let report: TokenUsageReport

    private var recentEvents: [TokenUsageEvent] {
        Array(report.codexEvents.suffix(8).reversed())
    }

    private var chartEvents: [TokenUsageEvent] {
        Array(report.codexEvents.suffix(120))
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 280), spacing: 14, alignment: .top)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Token 消耗")
                        .font(.title3.weight(.semibold))
                    Text("Codex 结构化 last_token_usage · \(report.scannedFiles) 个 session 文件")
                        .font(.caption)
                        .foregroundStyle(AppPalette.secondaryText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.compact(report.totalTokens))
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    Text("最近 9 天")
                        .font(.caption)
                        .foregroundStyle(AppPalette.secondaryText)
                }
            }

            if report.codexEvents.isEmpty {
                EmptyStateView(source: report.source, message: "没有找到 Codex last_token_usage 记录")
            } else {
                TokenTimelineChart(events: chartEvents)
                    .frame(height: 165)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    TokenListPanel(title: "最近什么时候用掉") {
                        ForEach(recentEvents) { event in
                            TokenEventRow(event: event)
                        }
                    }

                    TokenListPanel(title: "用在哪个对话上") {
                        ForEach(report.codexConversations.prefix(8)) { conversation in
                            TokenConversationRow(conversation: conversation)
                        }
                    }
                }
            }

            Label("Claude 逐对话 token 明细见下方卡片，取自转录 message.usage 的官方计量。", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(AppPalette.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppPalette.border, lineWidth: 1)
        )
    }
}

struct ClaudeTokenSection: View {
    let report: TokenUsageReport

    private struct RankedConversation: Identifiable {
        let conversation: TokenConversationUsage
        let isCodex: Bool
        var id: String { (isCodex ? "codex-" : "claude-") + conversation.id }
    }

    private var codexTotalTokens: Double {
        report.codexConversations.reduce(0) { $0 + Double($1.tokens) }
    }

    private var combinedTotalTokens: Double {
        report.claudeTotalTokens + codexTotalTokens
    }

    // Claude 与 Codex 的对话统一按 token 消耗排行
    private var topConversations: [RankedConversation] {
        let claude = report.claudeConversations.map { RankedConversation(conversation: $0, isCodex: false) }
        let codex = report.codexConversations.map { RankedConversation(conversation: $0, isCodex: true) }
        return Array((claude + codex).sorted { $0.conversation.tokens > $1.conversation.tokens }.prefix(10))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(AppPalette.claude)
                    .frame(width: 10, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude + Codex · Token 用量明细")
                        .font(.title3.weight(.semibold))
                    Text("按对话精确聚合 · Claude 近 7 天 \(report.claudeScannedFiles) 个转录 + Codex 近 9 天 \(report.scannedFiles) 个 session")
                        .font(.caption)
                        .foregroundStyle(AppPalette.secondaryText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.compact(combinedTotalTokens))
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    HStack(spacing: 6) {
                        Text("Claude \(Format.compact(report.claudeTotalTokens))")
                            .foregroundStyle(AppPalette.claude)
                        Text("Codex \(Format.compact(codexTotalTokens))")
                            .foregroundStyle(AppPalette.codex)
                    }
                    .font(.caption)
                }
            }

            if topConversations.isEmpty {
                EmptyStateView(
                    source: "\(report.claudeSource) · \(report.source)",
                    message: "最近 7 天没有找到任何对话级 token 用量记录"
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("消耗最高的对话")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(topConversations) { ranked in
                            TokenConversationRow(
                                conversation: ranked.conversation,
                                badge: ranked.isCodex ? "Codex" : "Claude",
                                badgeTint: ranked.isCodex ? AppPalette.codex : AppPalette.claude
                            )
                        }
                    }
                }
            }

            Divider()

            HStack {
                Label("\(report.claudeSource) · \(report.source)", systemImage: "externaldrive")
                    .foregroundStyle(AppPalette.secondaryText)
                Spacer()
                Text("Claude 取自 message.usage、Codex 取自 last_token_usage，均为官方计量，未做本地估算")
                    .foregroundStyle(AppPalette.secondaryText)
            }
            .font(.caption)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppPalette.border, lineWidth: 1)
        )
    }
}

struct TokenTimelineChart: View {
    let events: [TokenUsageEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let maxTokens = max(1, events.map(\.tokens).max() ?? 1)
                let slotWidth = width / Double(max(events.count, 1))
                let barWidth = max(2, min(14, slotWidth * 0.72))

                ZStack(alignment: .bottomLeading) {
                    VStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { _ in
                            Divider()
                            Spacer()
                        }
                        Divider()
                    }
                    .opacity(0.35)

                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        let barHeight = max(2, (Double(event.tokens) / Double(maxTokens)) * (height - 10))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppPalette.codex)
                            .frame(width: barWidth, height: barHeight)
                            .position(
                                x: min(width - barWidth / 2, Double(index) * slotWidth + slotWidth / 2),
                                y: height - barHeight / 2
                            )
                            .help("\(Format.dateTime(event.timestamp)) · \(Format.compact(Double(event.tokens))) tokens · \(event.conversationTitle)")
                    }
                }
            }

            HStack {
                Text(Format.dateTime(events.first?.timestamp))
                Spacer()
                if let peak = events.max(by: { $0.tokens < $1.tokens }) {
                    Text("峰值 \(Format.compact(Double(peak.tokens)))")
                }
                Spacer()
                Text(Format.dateTime(events.last?.timestamp))
            }
            .font(.caption2)
            .foregroundStyle(AppPalette.secondaryText)
        }
    }
}

struct TokenListPanel<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct TokenEventRow: View {
    let event: TokenUsageEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.dateTime(event.timestamp))
                    .font(.caption.weight(.semibold))
                Text(event.conversationTitle)
                    .font(.caption2)
                    .foregroundStyle(AppPalette.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.compact(Double(event.tokens)))
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                Text(Format.tokenParts(event))
                    .font(.caption2)
                    .foregroundStyle(AppPalette.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

struct TokenConversationRow: View {
    let conversation: TokenConversationUsage
    var badge: String? = nil
    var badgeTint: Color = AppPalette.codex

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let badge {
                Text(badge)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(badgeTint.opacity(0.16))
                    .foregroundStyle(badgeTint)
                    .clipShape(Capsule())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text("\(conversation.events) 次 · 最近 \(Format.relative(conversation.latestAt))")
                    .font(.caption2)
                    .foregroundStyle(AppPalette.secondaryText)
            }
            Spacer()
            Text(Format.compact(Double(conversation.tokens)))
                .font(.system(.caption, design: .monospaced).weight(.semibold))
        }
        .padding(.vertical, 3)
    }
}

struct WindowDetailView: View {
    let window: QuotaWindow
    let tint: Color

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { timeline in
            let now = timeline.date
            let expired = window.isExpired(at: now)
            let timePercent = window.timePercent(at: now)
            let remainingPercent = window.remainingPercent(at: now)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(window.title)
                            .font(.headline)
                        Text(window.subtitle)
                            .font(.caption)
                            .foregroundStyle(AppPalette.secondaryText)
                    }
                    Spacer()
                    PaceBadge(pace: window.pace(at: now))
                }

                MetricBar(
                    title: "额度",
                    value: window.activeUsedPercent(at: now),
                    markerValue: expired ? nil : timePercent,
                    trailing: expired ? "等官方更新" : "剩 \(Format.percent(remainingPercent))",
                    tint: progressColor(remainingPercent)
                )

                MetricBar(
                    title: "时间",
                    value: timePercent,
                    trailing: Format.countdown(to: window.resetAt, now: now),
                    tint: AppPalette.steady
                )

                HStack {
                    Text(window.basis)
                        .foregroundStyle(AppPalette.secondaryText)
                    Spacer()
                    if let tokenSummary = window.tokenSummary {
                        Text("\(Format.compact(tokenSummary.total)) tokens / \(tokenSummary.entries) 条")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(AppPalette.secondaryText)
                    }
                }
                .font(.caption)
            }
            .padding(12)
            .background(AppPalette.windowBackground.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppPalette.border, lineWidth: 1)
            )
        }
    }

    private func progressColor(_ remaining: Double?) -> Color {
        guard let remaining else { return AppPalette.muted }
        if remaining < 15 { return AppPalette.danger }
        if remaining < 35 { return AppPalette.warning }
        return tint
    }
}

struct MetricBar: View {
    let title: String
    let value: Double?
    var markerValue: Double? = nil
    let trailing: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(AppPalette.secondaryText)
                    .frame(width: 42, alignment: .leading)
                Text(Format.percent(value))
                    .font(.system(.caption, design: .monospaced))
                Spacer()
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(AppPalette.secondaryText)
            }
            MiniProgress(value: value ?? 0, tint: tint, marker: markerValue)
                .frame(height: markerValue == nil ? 8 : 24)
        }
    }
}

struct MiniProgress: View {
    let value: Double
    let tint: Color
    var marker: Double? = nil

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: NSColor.quaternaryLabelColor).opacity(0.45))
                    .frame(height: 7)
                RoundedRectangle(cornerRadius: 4)
                    .fill(tint)
                    .frame(width: max(0, min(1, value / 100)) * geometry.size.width)
                    .frame(height: 7)

                if let marker {
                    let markerX = max(0, min(1, marker / 100)) * geometry.size.width
                    TimePointer()
                        .offset(x: min(max(0, markerX - 9), max(0, geometry.size.width - 18)))
                        .help("时间进度")
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: marker == nil ? 7 : 24)
    }
}

struct TimePointer: View {
    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: "clock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white, AppPalette.steady)
                .frame(width: 18, height: 12)
            ZStack {
                Capsule()
                    .fill(Color(nsColor: NSColor.windowBackgroundColor).opacity(0.9))
                    .frame(width: 5, height: 11)
                Capsule()
                    .fill(AppPalette.steady)
                    .frame(width: 3, height: 11)
            }
        }
        .shadow(color: Color.black.opacity(0.18), radius: 1, y: 1)
    }
}

struct PaceBadge: View {
    let pace: Pace

    var body: some View {
        Label(pace.text, systemImage: pace.symbolName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(pace.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(pace.color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

enum QuotaScanner {
    static func scan(now: Date) -> DashboardSnapshot {
        let codex = scanCodex(now: now)
        let claudes = scanClaudeOfficial(now: now)
        var tokenReport = scanCodexTokenReport(now: now)
        let claudeToken = scanClaudeTokenReport(now: now)
        tokenReport.claudeConversations = claudeToken.conversations
        tokenReport.claudeScannedFiles = claudeToken.scannedFiles
        tokenReport.claudeSource = claudeToken.source
        return DashboardSnapshot(scannedAt: now, codex: codex, claudes: claudes, tokenReport: tokenReport)
    }

    private static func scanCodex(now: Date) -> ProviderSnapshot {
        let root = URL(fileURLWithPath: QuotaConfig.expandedPath("~/.codex/sessions"))
        let cutoff = now.addingTimeInterval(-9 * 24 * 3600)
        var latest: CodexRateEvent?

        for file in jsonlFiles(under: root, modifiedAfter: cutoff).prefix(80) {
            parseLines(in: file, matching: "\"rate_limits\"", maxBytes: 8 * 1024 * 1024) { line in
                guard let object = parseJSON(line),
                      let payload = object["payload"] as? [String: Any],
                      let rateLimits = (object["rate_limits"] as? [String: Any]) ?? (payload["rate_limits"] as? [String: Any]),
                      let timestamp = parseDate(object["timestamp"] as? String) else {
                    return
                }

                let event = CodexRateEvent(
                    timestamp: timestamp,
                    limitName: rateLimits["limit_name"] as? String,
                    primary: rateLimits["primary"] as? [String: Any],
                    secondary: rateLimits["secondary"] as? [String: Any],
                    planType: rateLimits["plan_type"] as? String,
                    tokenTotal: ((payload["info"] as? [String: Any])?["total_token_usage"] as? [String: Any])?["total_tokens"] as? Int
                )
                // limit_id 为 premium 的限流事件 primary/secondary 恒为 null，
                // 不能让它按时间戳顶掉真正带窗口数据的 codex 限额事件；
                // 同时要求窗口字段齐全，防止空字典同样顶掉可渲染的事件
                guard renderableWindow(event.primary) || renderableWindow(event.secondary) else { return }
                if latest == nil || event.timestamp > latest!.timestamp {
                    latest = event
                }
            }
        }

        guard let latest else {
            return ProviderSnapshot(
                name: "GPT Codex",
                shortName: "Cdx",
                mode: "未找到 rate_limits",
                windows: [],
                latestAt: nil,
                source: "~/.codex/sessions"
            )
        }

        var windows: [QuotaWindow] = []
        if let primary = latest.primary,
           let window = codexWindow(from: primary, label: "短窗口", event: latest, now: now) {
            windows.append(window)
        }
        if let secondary = latest.secondary,
           let window = codexWindow(from: secondary, label: "长窗口", event: latest, now: now) {
            windows.append(window)
        }

        let modelName = latest.limitName ?? "Codex rate limit"
        let mode = latest.planType.map { "\(modelName) · \($0)" } ?? modelName
        return ProviderSnapshot(
            name: "GPT Codex",
            shortName: "Cdx",
            mode: mode,
            windows: windows,
            latestAt: latest.timestamp,
            source: "~/.codex/sessions"
        )
    }

    private static func renderableWindow(_ dictionary: [String: Any]?) -> Bool {
        guard let dictionary else { return false }
        return number(dictionary["used_percent"]) != nil
            && int(dictionary["window_minutes"]) != nil
            && number(dictionary["resets_at"]) != nil
    }

    private static func scanCodexTokenReport(now: Date) -> TokenUsageReport {
        let root = URL(fileURLWithPath: QuotaConfig.expandedPath("~/.codex/sessions"))
        let cutoff = now.addingTimeInterval(-9 * 24 * 3600)
        let files = Array(jsonlFiles(under: root, modifiedAfter: cutoff).prefix(80))
        var events: [TokenUsageEvent] = []
        var summaries: [String: (title: String, tokens: Int, events: Int, latestAt: Date, sourceFile: String)] = [:]

        for file in files {
            guard let text = readTailText(from: file, maxBytes: 4 * 1024 * 1024) else { continue }

            let metadata = codexSessionMetadata(file: file)
            var sessionID = metadata.sessionID ?? sessionIDFromFilename(file)
            var cwd = metadata.cwd
            var startedAt = metadata.startedAt
            var eventIndex = 0

            text.enumerateLines { line, _ in
                guard let object = parseJSON(line),
                      let payload = object["payload"] as? [String: Any] else {
                    return
                }

                if object["type"] as? String == "session_meta" || payload["type"] as? String == "session_meta" {
                    if let value = (payload["session_id"] as? String) ?? (payload["id"] as? String) {
                        sessionID = value
                    }
                    cwd = payload["cwd"] as? String
                    startedAt = parseDate(payload["timestamp"] as? String) ?? startedAt
                    return
                }

                guard let timestamp = parseDate(object["timestamp"] as? String),
                      let info = payload["info"] as? [String: Any],
                      let lastUsage = info["last_token_usage"] as? [String: Any],
                      let tokens = int(lastUsage["total_tokens"]),
                      tokens > 0 else {
                    return
                }

                let title = tokenConversationTitle(cwd: cwd, startedAt: startedAt, file: file)
                let totalUsage = info["total_token_usage"] as? [String: Any]
                let event = TokenUsageEvent(
                    id: "\(sessionID)-\(Int(timestamp.timeIntervalSince1970 * 1000))-\(eventIndex)",
                    timestamp: timestamp,
                    sessionID: sessionID,
                    conversationTitle: title,
                    tokens: tokens,
                    inputTokens: int(lastUsage["input_tokens"]),
                    cachedInputTokens: int(lastUsage["cached_input_tokens"]),
                    outputTokens: int(lastUsage["output_tokens"]),
                    reasoningTokens: int(lastUsage["reasoning_output_tokens"]),
                    cumulativeTokens: int(totalUsage?["total_tokens"]),
                    sourceFile: file.lastPathComponent
                )
                events.append(event)
                eventIndex += 1

                if let existing = summaries[sessionID] {
                    summaries[sessionID] = (
                        title: existing.title,
                        tokens: existing.tokens + tokens,
                        events: existing.events + 1,
                        latestAt: max(existing.latestAt, timestamp),
                        sourceFile: existing.sourceFile
                    )
                } else {
                    summaries[sessionID] = (
                        title: title,
                        tokens: tokens,
                        events: 1,
                        latestAt: timestamp,
                        sourceFile: file.lastPathComponent
                    )
                }
            }
        }

        let sortedEvents = events.sorted { $0.timestamp < $1.timestamp }
        let conversations = summaries.map { key, value in
            TokenConversationUsage(
                id: key,
                title: value.title,
                tokens: value.tokens,
                events: value.events,
                latestAt: value.latestAt,
                sourceFile: value.sourceFile
            )
        }
        .sorted {
            if $0.tokens == $1.tokens { return $0.latestAt > $1.latestAt }
            return $0.tokens > $1.tokens
        }

        return TokenUsageReport(
            codexEvents: sortedEvents,
            codexConversations: conversations,
            scannedFiles: files.count,
            source: "~/.codex/sessions"
        )
    }

    /// 按 sessionId 精确聚合最近 7 天 Claude Code 的 token 消耗。
    /// 数据来自 ~/.claude/projects/**/*.jsonl 里每条 assistant 消息的 message.usage
    /// （input/output/cache_creation/cache_read 均为 API 返回的官方计量），不做任何本地估算。
    private static func scanClaudeTokenReport(
        now: Date
    ) -> (conversations: [TokenConversationUsage], scannedFiles: Int, source: String) {
        let source = "~/.claude/projects"
        let root = URL(fileURLWithPath: QuotaConfig.expandedPath(source))
        let cutoff = now.addingTimeInterval(-7 * 24 * 3600)
        let files = Array(jsonlFiles(under: root, modifiedAfter: cutoff).prefix(400))

        struct Accumulator {
            var title: String? = nil
            var project: String? = nil
            var tokens: Int = 0
            var events: Int = 0
            var latestAt: Date = .distantPast
            var sourceFile: String
        }

        var summaries: [String: Accumulator] = [:]

        for file in files {
            guard let text = readFullText(from: file, maxBytes: 32 * 1024 * 1024) else { continue }

            text.enumerateLines { line, _ in
                guard let object = parseJSON(line),
                      let sessionID = object["sessionId"] as? String else {
                    return
                }
                let type = object["type"] as? String
                let message = object["message"] as? [String: Any]

                // 标题：取该会话里第一条有效用户消息摘要
                if type == "user", let message, summaries[sessionID]?.title == nil,
                   let userText = claudeUserText(from: message) {
                    summaries[sessionID, default: Accumulator(sourceFile: file.lastPathComponent)].title = userText
                }

                // 项目名兜底标题（第一条用户消息不可用时使用）
                if summaries[sessionID]?.project == nil,
                   let cwd = object["cwd"] as? String, !cwd.isEmpty {
                    summaries[sessionID, default: Accumulator(sourceFile: file.lastPathComponent)].project =
                        URL(fileURLWithPath: cwd).lastPathComponent
                }

                // 精确 token：仅统计最近 7 天内的 assistant 消息 usage
                guard type == "assistant",
                      let message,
                      let usage = message["usage"] as? [String: Any],
                      let timestamp = parseDate(object["timestamp"] as? String),
                      timestamp >= cutoff else {
                    return
                }

                let input = int(usage["input_tokens"]) ?? 0
                let output = int(usage["output_tokens"]) ?? 0
                let cacheCreation = int(usage["cache_creation_input_tokens"]) ?? 0
                let cacheRead = int(usage["cache_read_input_tokens"]) ?? 0
                let total = input + output + cacheCreation + cacheRead
                guard total > 0 else { return }

                var acc = summaries[sessionID] ?? Accumulator(sourceFile: file.lastPathComponent)
                acc.tokens += total
                acc.events += 1
                acc.latestAt = max(acc.latestAt, timestamp)
                summaries[sessionID] = acc
            }
        }

        let conversations = summaries.compactMap { key, value -> TokenConversationUsage? in
            guard value.tokens > 0, value.latestAt > .distantPast else { return nil }
            let fallback = value.project ?? String(key.prefix(8))
            return TokenConversationUsage(
                id: key,
                title: value.title ?? fallback,
                tokens: value.tokens,
                events: value.events,
                latestAt: value.latestAt,
                sourceFile: value.sourceFile
            )
        }
        .sorted {
            if $0.tokens == $1.tokens { return $0.latestAt > $1.latestAt }
            return $0.tokens > $1.tokens
        }

        return (conversations, files.count, source)
    }

    private static func claudeUserText(from message: [String: Any]) -> String? {
        if let text = message["content"] as? String {
            return cleanClaudeTitle(text)
        }
        if let blocks = message["content"] as? [Any] {
            for block in blocks {
                guard let dict = block as? [String: Any],
                      (dict["type"] as? String) == "text",
                      let text = dict["text"] as? String else {
                    continue
                }
                if let cleaned = cleanClaudeTitle(text) {
                    return cleaned
                }
            }
        }
        return nil
    }

    private static func cleanClaudeTitle(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // 跳过命令包裹、系统提醒、中断标记等非真实用户输入
        if trimmed.hasPrefix("<") { return nil }
        if trimmed.hasPrefix("Caveat:") { return nil }
        if trimmed.hasPrefix("[Request interrupted") { return nil }
        if trimmed.hasPrefix("This session is being continued") { return nil }
        let firstLine = trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? trimmed
        let title = firstLine.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        if title.count > 42 {
            return String(title.prefix(42)) + "…"
        }
        return title
    }

    private static func codexWindow(
        from dictionary: [String: Any],
        label: String,
        event: CodexRateEvent,
        now: Date
    ) -> QuotaWindow? {
        guard let used = number(dictionary["used_percent"]),
              let minutes = int(dictionary["window_minutes"]),
              let resetSeconds = number(dictionary["resets_at"]) else {
            return nil
        }

        let resetAt = Date(timeIntervalSince1970: resetSeconds)
        let title = windowTitle(minutes: minutes)
        let timePercent = percentElapsed(windowMinutes: minutes, resetAt: resetAt, now: now)
        let expired = resetAt.timeIntervalSince(now) < -120
        let tokenSummary = event.tokenTotal.map {
            TokenSummary(total: Double($0), entries: 1)
        }
        return QuotaWindow(
            id: "codex-\(label)-\(minutes)",
            title: title,
            subtitle: label,
            usedPercent: min(100, max(0, used)),
            timePercent: timePercent,
            resetAt: resetAt,
            windowMinutes: minutes,
            latestAt: event.timestamp,
            official: true,
            basis: "Codex 本地 rate_limits",
            tokenSummary: tokenSummary,
            isExpired: expired
        )
    }

    private static func scanClaudeOfficial(now: Date) -> [ProviderSnapshot] {
        let source = "api.anthropic.com/api/oauth/usage"
        let accounts = ClaudeUsageClient.loadAll(now: now)
        guard !accounts.isEmpty else {
            return [
                ProviderSnapshot(
                    name: "Claude Code",
                    shortName: "Cl",
                    mode: "打开一个 Claude Code 会话后自动读取",
                    windows: [],
                    latestAt: nil,
                    source: source
                )
            ]
        }

        var primaryProviders: [ProviderSnapshot] = []
        var scopedProviders: [ProviderSnapshot] = []

        for account in accounts {
            let accountName = accounts.count > 1 ? "Claude Code \(account.ordinal)" : "Claude Code"
            let sourceWithAccount = accounts.count > 1 ? "\(source) · \(account.id)" : source

            switch account.result {
            case let .success(usage, live, subscription):
                var windows: [QuotaWindow] = []
                if let window = claudeWindow(
                    idPrefix: account.id, label: "短窗口", title: "5 小时窗口",
                    utilization: usage.fiveHourUsed, resetAt: usage.fiveHourReset,
                    windowMinutes: 300, now: now
                ) {
                    windows.append(window)
                }
                if let window = claudeWindow(
                    idPrefix: account.id, label: "长窗口", title: "7 天窗口",
                    utilization: usage.sevenDayUsed, resetAt: usage.sevenDayReset,
                    windowMinutes: 10_080, now: now
                ) {
                    windows.append(window)
                }

                let plan = subscription.map { "\($0) · 官方 usage" } ?? "官方 usage 接口"
                let accountSuffix = accounts.count > 1 ? " · 账号 \(account.ordinal)" : ""
                let mode = live ? "\(plan)\(accountSuffix)" : "\(plan)（缓存）\(accountSuffix)"
                primaryProviders.append(
                    ProviderSnapshot(
                        name: accountName,
                        shortName: accounts.count > 1 ? "Cl\(account.ordinal)" : "Cl",
                        mode: windows.isEmpty ? "官方 usage 接口暂无窗口数据" : mode,
                        windows: windows,
                        latestAt: usage.fetchedAt,
                        source: sourceWithAccount,
                        email: account.email
                    )
                )

                scopedProviders.append(contentsOf: usage.scopedLimits.map { limit in
                    let scopedName = accounts.count > 1 ? "Claude \(limit.displayName) \(account.ordinal)" : "Claude \(limit.displayName)"
                    let scopedShortName = scopedShortName(for: limit.displayName, ordinal: accounts.count > 1 ? account.ordinal : nil)
                    let window = claudeWindow(
                        idPrefix: "\(account.id)-\(limit.id)",
                        label: "模型钱包",
                        title: "\(limit.displayName) 周额度",
                        utilization: limit.usedPercent,
                        resetAt: limit.resetAt,
                        windowMinutes: 10_080,
                        now: now,
                        basis: "Claude 官方 usage limits"
                    )
                    return ProviderSnapshot(
                        name: scopedName,
                        shortName: scopedShortName,
                        mode: live ? "单独模型钱包\(accountSuffix)" : "单独模型钱包（缓存）\(accountSuffix)",
                        windows: window.map { [$0] } ?? [],
                        latestAt: usage.fetchedAt,
                        source: sourceWithAccount,
                        email: account.email
                    )
                })
            case let .failed(reason):
                primaryProviders.append(
                    ProviderSnapshot(
                        name: accountName,
                        shortName: accounts.count > 1 ? "Cl\(account.ordinal)" : "Cl",
                        mode: reason,
                        windows: [],
                        latestAt: nil,
                        source: sourceWithAccount,
                        email: account.email
                    )
                )
            case .noToken:
                primaryProviders.append(
                    ProviderSnapshot(
                        name: accountName,
                        shortName: accounts.count > 1 ? "Cl\(account.ordinal)" : "Cl",
                        mode: "打开一个 Claude Code 会话后自动读取",
                        windows: [],
                        latestAt: nil,
                        source: sourceWithAccount,
                        email: account.email
                    )
                )
            }
        }

        // 按账号交错输出（Code 1、Fable 1、Code 2、Fable 2……），
        // 让 status.json 和网页端的卡片顺序也严格按账号分组
        var ordered: [ProviderSnapshot] = []
        var pairedScopedIDs = Set<String>()
        for provider in primaryProviders {
            ordered.append(provider)
            let digits = provider.name.filter(\.isNumber)
            for scoped in scopedProviders where scoped.name.filter(\.isNumber) == digits && !pairedScopedIDs.contains(scoped.id) {
                ordered.append(scoped)
                pairedScopedIDs.insert(scoped.id)
            }
        }
        ordered += scopedProviders.filter { !pairedScopedIDs.contains($0.id) }
        return ordered
    }

    private static func claudeWindow(
        idPrefix: String,
        label: String,
        title: String,
        utilization: Double?,
        resetAt: Date?,
        windowMinutes: Int,
        now: Date,
        basis: String = "Claude 官方 usage 接口"
    ) -> QuotaWindow? {
        guard let utilization else { return nil }
        let timePercent = resetAt.map { percentElapsed(windowMinutes: windowMinutes, resetAt: $0, now: now) }
        let expired = resetAt.map { $0.timeIntervalSince(now) < -120 } ?? false
        return QuotaWindow(
            id: "claude-\(idPrefix)-\(label)-\(windowMinutes)",
            title: title,
            subtitle: label,
            usedPercent: min(100, max(0, utilization)),
            timePercent: timePercent,
            resetAt: resetAt,
            windowMinutes: windowMinutes,
            latestAt: now,
            official: true,
            basis: basis,
            tokenSummary: nil,
            isExpired: expired
        )
    }

    private static func scopedShortName(for displayName: String, ordinal: Int?) -> String {
        let base: String
        if displayName.localizedCaseInsensitiveContains("Fable") {
            base = "Fb"
        } else {
            let letters = displayName.filter { $0.isLetter }
            base = String(letters.prefix(2)).isEmpty ? "Sc" : String(letters.prefix(2))
        }
        if let ordinal {
            return "\(base)\(ordinal)"
        }
        return base
    }

    private static func codexSessionMetadata(file: URL) -> (sessionID: String?, cwd: String?, startedAt: Date?) {
        guard let text = readHeadText(from: file, maxBytes: 2 * 1024 * 1024) else {
            return (nil, nil, nil)
        }

        var result: (sessionID: String?, cwd: String?, startedAt: Date?) = (nil, nil, nil)
        text.enumerateLines { line, stop in
            guard let object = parseJSON(line),
                  let payload = object["payload"] as? [String: Any],
                  object["type"] as? String == "session_meta" || payload["type"] as? String == "session_meta" else {
                return
            }
            result.sessionID = (payload["session_id"] as? String) ?? (payload["id"] as? String)
            result.cwd = payload["cwd"] as? String
            result.startedAt = parseDate(payload["timestamp"] as? String)
            stop = true
        }
        return result
    }

    private static func sessionIDFromFilename(_ file: URL) -> String {
        let name = file.deletingPathExtension().lastPathComponent
        if let range = name.range(of: #"019[a-f0-9-]+"#, options: .regularExpression) {
            return String(name[range])
        }
        return name
    }

    private static func tokenConversationTitle(cwd: String?, startedAt: Date?, file: URL) -> String {
        let projectName: String
        if let cwd, !cwd.isEmpty {
            projectName = URL(fileURLWithPath: cwd).lastPathComponent
        } else {
            projectName = file.deletingPathExtension().lastPathComponent
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let timeText = startedAt.map { formatter.string(from: $0) } ?? "--:--"
        return "\(timeText) · \(projectName)"
    }

    private static func jsonlFiles(under root: URL, modifiedAfter cutoff: Date) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: []
        ) else {
            return []
        }

        var files: [(url: URL, modified: Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  modified >= cutoff else {
                continue
            }
            files.append((url, modified))
        }
        return files.sorted { $0.modified > $1.modified }.map(\.url)
    }

    private static func parseLines(
        in file: URL,
        matching needle: String,
        maxBytes: UInt64,
        handle: @escaping (String) -> Void
    ) {
        guard let text = readTailText(from: file, maxBytes: maxBytes) else { return }
        text.enumerateLines { line, _ in
            if line.contains(needle) {
                handle(line)
            }
        }
    }

    private static func readTailText(from file: URL, maxBytes: UInt64) -> String? {
        readTailData(from: file, maxBytes: maxBytes)
    }

    private static func readFullText(from file: URL, maxBytes: UInt64) -> String? {
        // 极大文件退回只读尾部，避免一次性载入过多内存
        readTailData(from: file, maxBytes: maxBytes)
    }

    private static func readTailData(from file: URL, maxBytes: UInt64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let truncated = size > maxBytes
        if truncated {
            try? handle.seek(toOffset: size - maxBytes)
        } else {
            try? handle.seek(toOffset: 0)
        }
        guard var data = try? handle.readToEnd(), !data.isEmpty else { return nil }
        // 截断点可能落在 UTF-8 多字节字符中间，整段解码会失败；
        // 丢掉第一个换行前的半截行，保证从完整行首开始
        if truncated, let newline = data.firstIndex(of: 0x0A) {
            data = data.subdata(in: data.index(after: newline)..<data.endIndex)
        }
        guard !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func readHeadText(from file: URL, maxBytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }

        let data = try? handle.read(upToCount: maxBytes)
        guard let data, !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func parseJSON(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: value) {
            return date
        }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: value)
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func percentElapsed(windowMinutes: Int, resetAt: Date, now: Date) -> Double {
        let duration = Double(windowMinutes) * 60
        let remaining = max(0, resetAt.timeIntervalSince(now))
        let elapsed = max(0, min(duration, duration - remaining))
        return elapsed / duration * 100
    }

    private static func windowTitle(minutes: Int) -> String {
        if minutes == 300 { return "5 小时窗口" }
        if minutes == 10_080 { return "7 天窗口" }
        if minutes % 1440 == 0 { return "\(minutes / 1440) 天窗口" }
        if minutes % 60 == 0 { return "\(minutes / 60) 小时窗口" }
        return "\(minutes) 分钟窗口"
    }

    private static func fixedWindow(now: Date, duration: TimeInterval) -> DateInterval {
        let startSeconds = floor(now.timeIntervalSince1970 / duration) * duration
        let start = Date(timeIntervalSince1970: startSeconds)
        return DateInterval(start: start, duration: duration)
    }

    private static func calendarWeekWindow(now: Date) -> DateInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        let start = calendar.date(from: components) ?? now.addingTimeInterval(-7 * 24 * 3600)
        return DateInterval(start: start, duration: 7 * 24 * 3600)
    }
}

private struct CodexRateEvent {
    let timestamp: Date
    let limitName: String?
    let primary: [String: Any]?
    let secondary: [String: Any]?
    let planType: String?
    let tokenTotal: Int?
}

// MARK: - Claude 官方 usage 接口

struct ClaudeUsageSnapshot {
    var fiveHourUsed: Double?
    var fiveHourReset: Date?
    var sevenDayUsed: Double?
    var sevenDayReset: Date?
    var scopedLimits: [ClaudeScopedLimit] = []
    var subscription: String?
    var fetchedAt: Date
}

struct ClaudeScopedLimit {
    let id: String
    let displayName: String
    let usedPercent: Double
    let resetAt: Date?
}

enum ClaudeUsageResult {
    /// live=true 表示刚从网络取得；live=false 表示用的是本地缓存快照。
    case success(ClaudeUsageSnapshot, live: Bool, subscription: String?)
    /// 找不到任何可用令牌，也没有缓存。
    case noToken
    /// 有令牌但请求失败，且无缓存兜底。
    case failed(String)
}

struct ClaudeAccountUsageResult {
    let id: String
    let ordinal: Int
    let result: ClaudeUsageResult
    var email: String? = nil
}

struct ClaudeTokenImportResult {
    let saved: Bool
    let id: String?
    let message: String
}

struct ClaudeAccountSummary: Identifiable {
    let id: String
    let subscription: String?
    let live: Bool
}

/// 从正在运行的 Claude Code 会话进程环境里取 OAuth 令牌，直接调用官方 usage 接口。
/// 令牌由桌面版 Claude 自动保持新鲜；本地只缓存最近一次结果做兜底，不做任何本地估算。
enum ClaudeUsageClient {
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let profileURL = URL(string: "https://api.anthropic.com/api/oauth/profile")!
    private static let betaHeader = "oauth-2025-04-20"
    private static let userAgent = "claude-code/2.1.197"

    private struct TokenAccount {
        let id: String
        let token: String
        let subscription: String?
        let live: Bool
    }

    static func importManualToken(_ rawToken: String) -> ClaudeTokenImportResult {
        var token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.lowercased().hasPrefix("bearer ") {
            token = String(token.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard token.count >= 40 else {
            return ClaudeTokenImportResult(saved: false, id: nil, message: "这个 token 看起来太短，未保存。")
        }
        guard token.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            return ClaudeTokenImportResult(saved: false, id: nil, message: "token 中不能包含空格或换行，未保存。")
        }
        guard let data = token.data(using: .utf8) else {
            return ClaudeTokenImportResult(saved: false, id: nil, message: "token 不是有效文本，未保存。")
        }

        ensureDirectory()
        let id = tokenID(token)
        let url = tokenCacheURL(id: id)
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return ClaudeTokenImportResult(saved: true, id: id, message: "已保存 Claude 账号 \(id)，正在刷新官方 usage。")
        } catch {
            return ClaudeTokenImportResult(saved: false, id: nil, message: "保存失败：\(error.localizedDescription)")
        }
    }

    static func loadAll(now: Date) -> [ClaudeAccountUsageResult] {
        let accounts = tokenAccounts()
        guard !accounts.isEmpty else {
            if let cached = cachedUsage(id: nil) {
                return [
                    ClaudeAccountUsageResult(
                        id: "cached",
                        ordinal: 1,
                        result: .success(cached, live: false, subscription: cached.subscription)
                    )
                ]
            }
            return []
        }

        return accounts.enumerated().map { index, account in
            ClaudeAccountUsageResult(
                id: account.id,
                ordinal: index + 1,
                result: load(account: account, now: now),
                email: accountEmail(id: account.id, token: account.token)
            )
        }
    }

    /// 账号邮箱：先读本地缓存，缺失时调官方 profile 接口取一次并落盘。
    static func accountEmail(id: String, token: String?) -> String? {
        let cacheURL = emailCacheURL(id: id)
        if let cached = try? String(contentsOf: cacheURL, encoding: .utf8) {
            let trimmed = cached.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        guard let token else { return nil }

        var request = URLRequest(url: profileURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let box = ResponseBox()
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            box.data = data
            box.status = (response as? HTTPURLResponse)?.statusCode ?? 0
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 10)

        guard box.status == 200,
              let data = box.data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = object["account"] as? [String: Any],
              let email = account["email"] as? String,
              !email.isEmpty else {
            return nil
        }

        ensureDirectory()
        try? email.data(using: .utf8)?.write(to: cacheURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
        return email
    }

    static func accountSummaries() -> [ClaudeAccountSummary] {
        tokenAccounts().map { account in
            ClaudeAccountSummary(
                id: account.id,
                subscription: account.subscription,
                live: account.live
            )
        }
    }

    private static func load(account: TokenAccount, now: Date) -> ClaudeUsageResult {
        let (data, status) = fetchUsage(token: account.token)
        if status != 401 && status != 403 {
            cacheToken(account.token, id: account.id)
        }
        if status == 200, let data, var snap = parse(data, now: now) {
            snap.subscription = account.subscription ?? snap.subscription ?? cachedUsage(id: account.id)?.subscription
            cacheUsage(snap, id: account.id)
            return .success(snap, live: true, subscription: snap.subscription)
        }

        // 请求失败：优先用缓存快照兜底，绝不本地估算。
        if let cached = cachedUsage(id: account.id) {
            return .success(cached, live: false, subscription: cached.subscription)
        }
        switch status {
        case 401, 403:
            return .failed("令牌已过期 · 打开 Claude Code 会话即可刷新")
        case 429:
            return .failed("usage 接口限流 · 稍后自动重试")
        case 0:
            return .failed("网络不可用 · 稍后自动重试")
        default:
            return .failed("usage 接口返回 \(status)")
        }
    }

    // MARK: 网络

    private static func fetchUsage(token: String) -> (Data?, Int) {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let box = ResponseBox()
        let semaphore = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            box.data = data
            box.status = (response as? HTTPURLResponse)?.statusCode ?? 0
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 10)
        return (box.data, box.status)
    }

    private final class ResponseBox: @unchecked Sendable {
        var data: Data?
        var status: Int = 0
    }

    private static func parse(_ data: Data, now: Date) -> ClaudeUsageSnapshot? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        var snapshot = ClaudeUsageSnapshot(fetchedAt: now)
        if let fiveHour = object["five_hour"] as? [String: Any] {
            snapshot.fiveHourUsed = double(fiveHour["utilization"])
            snapshot.fiveHourReset = parseISODate(fiveHour["resets_at"] as? String)
        }
        if let sevenDay = object["seven_day"] as? [String: Any] {
            snapshot.sevenDayUsed = double(sevenDay["utilization"])
            snapshot.sevenDayReset = parseISODate(sevenDay["resets_at"] as? String)
        }
        snapshot.scopedLimits = parseScopedLimits(object["limits"] as? [[String: Any]])
        // 至少要拿到一个窗口才算有效。
        if snapshot.fiveHourUsed == nil && snapshot.sevenDayUsed == nil && snapshot.scopedLimits.isEmpty {
            return nil
        }
        return snapshot
    }

    private static func parseScopedLimits(_ limits: [[String: Any]]?) -> [ClaudeScopedLimit] {
        guard let limits else { return [] }
        return limits.compactMap { limit in
            guard (limit["kind"] as? String) == "weekly_scoped",
                  let used = double(limit["percent"]),
                  let scope = limit["scope"] as? [String: Any],
                  let model = scope["model"] as? [String: Any],
                  let displayName = model["display_name"] as? String,
                  !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            return ClaudeScopedLimit(
                id: scopedLimitID(cleanName),
                displayName: cleanName,
                usedPercent: min(100, max(0, used)),
                resetAt: parseISODate(limit["resets_at"] as? String)
            )
        }
    }

    private static func scopedLimitID(_ name: String) -> String {
        let allowed = name.lowercased().map { char -> Character in
            if char.isLetter || char.isNumber { return char }
            return "-"
        }
        return String(allowed).split(separator: "-").joined(separator: "-")
    }

    // MARK: 令牌来源 —— 读运行中的 Claude Code 进程环境

    private static func tokenAccounts() -> [TokenAccount] {
        var accounts: [TokenAccount] = []
        var seenIDs = Set<String>()

        func append(token rawToken: String, subscription: String?, live: Bool) {
            let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { return }
            let id = tokenID(token)
            guard seenIDs.insert(id).inserted else { return }
            accounts.append(TokenAccount(id: id, token: token, subscription: subscription, live: live))
        }

        for env in liveEnvs() {
            if let token = env["CLAUDE_CODE_OAUTH_TOKEN"] {
                append(
                    token: token,
                    subscription: env["CLAUDE_CODE_SUBSCRIPTION_TYPE"].map(displaySubscription),
                    live: true
                )
            }
        }

        for account in cachedTokenAccounts() {
            append(token: account.token, subscription: account.subscription, live: false)
        }

        return accounts
    }

    /// 返回所有带 CLAUDE_CODE_OAUTH_TOKEN 的 claude 进程环境，并按令牌去重。
    private static func liveEnvs() -> [[String: String]] {
        var envs: [[String: String]] = []
        var seenIDs = Set<String>()
        for pid in claudePIDs() {
            if let env = readEnv(pid: pid),
               let token = env["CLAUDE_CODE_OAUTH_TOKEN"] {
                let id = tokenID(token)
                if seenIDs.insert(id).inserted {
                    envs.append(env)
                }
            }
        }
        return envs
    }

    private static func claudePIDs() -> [Int32] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        if sysctl(&mib, 4, nil, &size, nil, 0) != 0 { return [] }
        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        if sysctl(&mib, 4, &procs, &size, nil, 0) != 0 { return [] }
        let actual = size / MemoryLayout<kinfo_proc>.stride

        var pids: [Int32] = []
        for index in 0..<min(actual, procs.count) {
            var proc = procs[index]
            let comm = withUnsafeBytes(of: &proc.kp_proc.p_comm) { raw -> String in
                let base = raw.baseAddress!.assumingMemoryBound(to: CChar.self)
                return String(cString: base)
            }
            // 会话进程 comm 为 "claude"；其父 "disclaimer" 也继承同一环境。
            if comm == "claude" || comm == "disclaimer" {
                pids.append(proc.kp_proc.p_pid)
            }
        }
        return pids
    }

    /// 用 KERN_PROCARGS2 读取指定进程的环境变量（同用户进程无需特权）。
    private static func readEnv(pid: Int32) -> [String: String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        if sysctl(&mib, 3, nil, &size, nil, 0) != 0 || size == 0 { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        if sysctl(&mib, 3, &buffer, &size, nil, 0) != 0 { return nil }
        guard size > 4 else { return nil }

        // 布局：int32 argc; exec_path\0; padding\0…; argv[]\0; env[]\0…
        // 令牌等值不含 \0，按 \0 切段后取形如 KEY=VALUE 的段即可。
        var result: [String: String] = [:]
        var start = 4
        var i = 4
        while i < size {
            if buffer[i] == 0 {
                if i > start,
                   let segment = String(bytes: buffer[start..<i], encoding: .utf8),
                   let eq = segment.firstIndex(of: "="),
                   segment.startIndex != eq {
                    let key = String(segment[segment.startIndex..<eq])
                    // 只保留看起来像环境变量的键（全大写/下划线/数字）。
                    if key.allSatisfy({ $0.isUppercase || $0 == "_" || $0.isNumber }) {
                        result[key] = String(segment[segment.index(after: eq)...])
                    }
                }
                start = i + 1
            }
            i += 1
        }
        return result.isEmpty ? nil : result
    }

    // MARK: 本地缓存（仅缓存官方结果与令牌，做离线兜底，不做估算）

    private static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: QuotaConfig.expandedPath("~/Library/Application Support"))
        return base.appendingPathComponent("AIQuotaWatch", isDirectory: true)
    }

    private static var legacyUsageCacheURL: URL { cacheDirectory.appendingPathComponent("claude_usage.json") }
    private static var legacyTokenCacheURL: URL { cacheDirectory.appendingPathComponent("claude_token") }

    private static func usageCacheURL(id: String) -> URL {
        cacheDirectory.appendingPathComponent("claude_usage_\(id).json")
    }

    private static func tokenCacheURL(id: String) -> URL {
        cacheDirectory.appendingPathComponent("claude_token_\(id)")
    }

    private static func emailCacheURL(id: String) -> URL {
        cacheDirectory.appendingPathComponent("claude_email_\(id)")
    }

    private static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    private static func cacheUsage(_ snapshot: ClaudeUsageSnapshot, id: String) {
        ensureDirectory()
        var dict: [String: Any] = ["fetched_at": snapshot.fetchedAt.timeIntervalSince1970]
        if let value = snapshot.fiveHourUsed { dict["five_hour_used"] = value }
        if let value = snapshot.fiveHourReset { dict["five_hour_reset"] = value.timeIntervalSince1970 }
        if let value = snapshot.sevenDayUsed { dict["seven_day_used"] = value }
        if let value = snapshot.sevenDayReset { dict["seven_day_reset"] = value.timeIntervalSince1970 }
        if let value = snapshot.subscription { dict["subscription"] = value }
        if !snapshot.scopedLimits.isEmpty {
            dict["scoped_limits"] = snapshot.scopedLimits.map { limit in
                var item: [String: Any] = [
                    "id": limit.id,
                    "display_name": limit.displayName,
                    "used_percent": limit.usedPercent
                ]
                if let resetAt = limit.resetAt {
                    item["reset_at"] = resetAt.timeIntervalSince1970
                }
                return item
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        try? data.write(to: usageCacheURL(id: id), options: .atomic)
    }

    private static func cachedUsage(id: String?) -> ClaudeUsageSnapshot? {
        if let id {
            if let snapshot = readUsageCache(from: usageCacheURL(id: id)) {
                return snapshot
            }
            if cachedToken(at: legacyTokenCacheURL).map(tokenID) == id {
                return readUsageCache(from: legacyUsageCacheURL)
            }
            return nil
        }

        return readUsageCache(from: legacyUsageCacheURL)
    }

    private static func readUsageCache(from url: URL) -> ClaudeUsageSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fetched = dict["fetched_at"] as? Double else {
            return nil
        }
        var snapshot = ClaudeUsageSnapshot(fetchedAt: Date(timeIntervalSince1970: fetched))
        snapshot.fiveHourUsed = dict["five_hour_used"] as? Double
        if let reset = dict["five_hour_reset"] as? Double {
            snapshot.fiveHourReset = Date(timeIntervalSince1970: reset)
        }
        snapshot.sevenDayUsed = dict["seven_day_used"] as? Double
        if let reset = dict["seven_day_reset"] as? Double {
            snapshot.sevenDayReset = Date(timeIntervalSince1970: reset)
        }
        if let scoped = dict["scoped_limits"] as? [[String: Any]] {
            snapshot.scopedLimits = scoped.compactMap { item in
                guard let id = item["id"] as? String,
                      let displayName = item["display_name"] as? String,
                      let usedPercent = item["used_percent"] as? Double else {
                    return nil
                }
                let resetAt = (item["reset_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
                return ClaudeScopedLimit(
                    id: id,
                    displayName: displayName,
                    usedPercent: usedPercent,
                    resetAt: resetAt
                )
            }
        }
        snapshot.subscription = dict["subscription"] as? String
        if snapshot.fiveHourUsed == nil && snapshot.sevenDayUsed == nil && snapshot.scopedLimits.isEmpty { return nil }
        return snapshot
    }

    private static func cacheToken(_ token: String, id: String) {
        ensureDirectory()
        guard let data = token.data(using: .utf8) else { return }
        let url = tokenCacheURL(id: id)
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func cachedTokenAccounts() -> [TokenAccount] {
        var accounts: [TokenAccount] = []
        var seenIDs = Set<String>()

        func appendToken(_ token: String) {
            let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { return }
            let id = tokenID(token)
            guard seenIDs.insert(id).inserted else { return }
            accounts.append(TokenAccount(
                id: id,
                token: token,
                subscription: cachedUsage(id: id)?.subscription,
                live: false
            ))
        }

        if let token = cachedToken(at: legacyTokenCacheURL) {
            appendToken(token)
        }

        if let urls = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) {
            for url in urls where url.lastPathComponent.hasPrefix("claude_token_") {
                if let token = cachedToken(at: url) {
                    appendToken(token)
                }
            }
        }

        return accounts
    }

    private static func cachedToken(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            return nil
        }
        return token
    }

    private static func tokenID(_ token: String) -> String {
        let digest = SHA256.hash(data: Data(token.utf8))
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: 辅助

    private static func displaySubscription(_ raw: String) -> String {
        switch raw.lowercased() {
        case "max": return "Max"
        case "pro": return "Pro"
        case "team": return "Team"
        case "enterprise": return "Enterprise"
        case "free": return "Free"
        default: return raw.prefix(1).uppercased() + raw.dropFirst()
        }
    }

    private static func double(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    /// 解析形如 2026-07-02T06:10:00.012505+00:00 的时间戳（含微秒小数）。
    private static func parseISODate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        if let date = basic.date(from: value) { return date }
        // 小数秒位数超过毫秒时，剥离小数部分再解析。
        if let dot = value.firstIndex(of: ".") {
            let afterDot = value[value.index(after: dot)...]
            if let tzStart = afterDot.firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
                var trimmed = value
                trimmed.removeSubrange(dot..<tzStart)
                if let date = basic.date(from: trimmed) { return date }
            }
        }
        return nil
    }
}

enum Format {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--" }
        return "\(Int(max(0, min(100, value)).rounded()))%"
    }

    static func time(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    static func dateTime(_ date: Date?) -> String {
        guard let date else { return "--" }
        return dateTimeFormatter.string(from: date)
    }

    static func reset(_ date: Date?) -> String {
        guard let date else { return "无重置时间" }
        if date < Date() {
            return "已过 \(dateFormatter.string(from: date))"
        }
        return "重置 \(dateFormatter.string(from: date))"
    }

    static func countdown(to date: Date?, now: Date = Date()) -> String {
        guard let date else { return "无重置时间" }
        let delta = date.timeIntervalSince(now)
        if delta <= -120 {
            return "已重置 · 等官方更新"
        }
        if delta <= 0 {
            return "正在重置"
        }

        let totalSeconds = Int(ceil(delta))
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if days > 0 {
            return "剩 \(days)天\(hours)小时\(minutes)分"
        }
        if hours > 0 {
            return String(format: "剩 %d小时%02d分%02d秒", hours, minutes, seconds)
        }
        return String(format: "剩 %d分%02d秒", minutes, seconds)
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "--" }
        let delta = Date().timeIntervalSince(date)
        if delta < 60 { return "刚刚" }
        if delta < 3600 { return "\(Int(delta / 60)) 分钟前" }
        if delta < 86400 { return "\(Int(delta / 3600)) 小时前" }
        return "\(Int(delta / 86400)) 天前"
    }

    static func compact(_ value: Double) -> String {
        let absValue = abs(value)
        if absValue >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }
        if absValue >= 1_000 {
            return String(format: "%.0fK", value / 1_000)
        }
        return String(format: "%.0f", value)
    }

    static func tokenParts(_ event: TokenUsageEvent) -> String {
        var parts: [String] = []
        if let input = event.inputTokens { parts.append("入 \(compact(Double(input)))") }
        if let cached = event.cachedInputTokens, cached > 0 { parts.append("缓存 \(compact(Double(cached)))") }
        if let output = event.outputTokens { parts.append("出 \(compact(Double(output)))") }
        if let reasoning = event.reasoningTokens, reasoning > 0 { parts.append("思考 \(compact(Double(reasoning)))") }
        return parts.isEmpty ? event.sourceFile : parts.joined(separator: " · ")
    }
}
