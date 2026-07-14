import Foundation
import SwiftUI

struct ContentView: View {
    @StateObject private var model = QuotaPhoneModel()
    @AppStorage("macBaseURL") private var macBaseURL = "http://192.168.0.251:17676"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    summaryStrip

                    ForEach(model.status?.providers ?? []) { provider in
                        ProviderCard(provider: provider)
                    }

                    TokenSection(report: model.status?.tokenReport)

                    Text("由 Codex（GPT-5）为 Richard 制作")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 10)
                }
                .padding(14)
            }
            .background(AppColors.background)
            .navigationTitle("AI 额度观察")
            .toolbar {
                Button {
                    Task { await model.refresh(baseURL: macBaseURL) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(model.isLoading)
            }
            .task {
                await model.refresh(baseURL: macBaseURL)
            }
            .refreshable {
                await model.refresh(baseURL: macBaseURL)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mac 实时快照")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(model.status?.summary ?? "正在连接 Mac")
                        .font(.title2.weight(.semibold))
                }
                Spacer()
                if model.isLoading {
                    ProgressView()
                }
            }

            HStack(spacing: 8) {
                TextField("Mac 地址", text: $macBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)

                Button("连接") {
                    Task { await model.refresh(baseURL: macBaseURL) }
                }
                .buttonStyle(.borderedProminent)
            }

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(AppColors.warning)
            }
        }
        .padding(14)
        .background(AppColors.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }

    private var summaryStrip: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            MetricTile(title: "Codex", value: model.status?.codexRemaining ?? "--")
            MetricTile(title: "Claude", value: model.status?.claudeRemaining ?? "--")
            if let fable = model.status?.fableRemaining, fable != "--" {
                MetricTile(title: "Fable", value: fable)
            }
            MetricTile(title: "扫描", value: model.status.map { Formatters.time(epoch: $0.scannedAt) } ?? "--")
        }
    }
}

struct MetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.monospacedDigit().weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColors.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }
}

struct ProviderCard: View {
    let provider: ProviderStatus

    var tint: Color {
        provider.name.localizedCaseInsensitiveContains("Claude") ? AppColors.claude : AppColors.codex
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(tint)
                    .frame(width: 10, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.name)
                        .font(.title3.weight(.semibold))
                    Text(provider.mode)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(provider.remaining)
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            if provider.windows.isEmpty {
                Text("等待官方额度窗口")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(provider.windows) { window in
                    WindowCard(window: window, tint: tint)
                }
            }

            HStack {
                Text(provider.source)
                    .lineLimit(1)
                Spacer()
                Text(provider.latestAtEpoch.map(Formatters.relative(epoch:)) ?? "--")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
        .padding(14)
        .background(AppColors.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }
}

struct WindowCard: View {
    let window: QuotaWindowStatus
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(window.title)
                        .font(.headline)
                    Text(window.subtitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(window.countdown)
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .multilineTextAlignment(.trailing)
            }

            Text(window.pace)
                .font(.caption.weight(.bold))
                .foregroundStyle(paceColor)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(paceColor.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            ProgressLine(
                title: "额度",
                valueText: "\(Formatters.percent(window.usedPercent)) · 剩 \(Formatters.percent(window.remainingPercent))",
                value: window.usedPercent,
                marker: window.timePercent,
                tint: tint
            )

            ProgressLine(
                title: "时间",
                valueText: Formatters.percent(window.timePercent),
                value: window.timePercent,
                marker: nil,
                tint: AppColors.time
            )

            HStack {
                Text(window.basis)
                    .lineLimit(1)
                Spacer()
                Text(window.resetText)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(AppColors.panelAlt)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.border.opacity(0.75), lineWidth: 1)
        )
    }

    private var paceColor: Color {
        if window.pace.contains("额度") { return AppColors.warning }
        if window.pace.contains("时间") { return AppColors.good }
        return AppColors.time
    }
}

struct ProgressLine: View {
    let title: String
    let valueText: String
    let value: Double?
    let marker: Double?
    let tint: Color

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(valueText)
                    .font(.caption.monospacedDigit().weight(.bold))
            }
            .font(.caption.weight(.bold))

            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(tint)
                        .frame(width: width * normalized(value))
                    if let marker {
                        Capsule()
                            .fill(AppColors.time)
                            .frame(width: 4, height: 24)
                            .offset(x: width * normalized(marker) - 2)
                    }
                }
            }
            .frame(height: 12)
        }
    }

    private func normalized(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0 }
        return max(0, min(1, value / 100))
    }
}

struct TokenSection: View {
    let report: TokenReport?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Token 消耗")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text("随时间变化")
                        .font(.headline)
                }
                Spacer()
                Text(report.map { Formatters.compact($0.totalTokens) + " tokens" } ?? "--")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(AppColors.time.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            TokenChart(events: Array(report?.events.suffix(36) ?? []))

            ForEach(Array((report?.conversations ?? []).prefix(6))) { conversation in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(conversation.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        Text(Formatters.relative(epoch: conversation.latestAtEpoch))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Formatters.compact(Double(conversation.tokens)))
                        .font(.subheadline.monospacedDigit().weight(.bold))
                }
                .padding(.top, 8)
            }
        }
        .padding(14)
        .background(AppColors.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.border, lineWidth: 1)
        )
    }
}

struct TokenChart: View {
    let events: [TokenEvent]

    var body: some View {
        GeometryReader { proxy in
            let maxTokens = max(events.map(\.tokens).max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(events) { event in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(
                            colors: [AppColors.time.opacity(0.9), AppColors.codex],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .frame(height: max(4, proxy.size.height * CGFloat(event.tokens) / CGFloat(maxTokens)))
                }
            }
        }
        .frame(height: 130)
        .padding(10)
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.border.opacity(0.7), lineWidth: 1)
        )
    }
}

@MainActor
final class QuotaPhoneModel: ObservableObject {
    @Published var status: StatusResponse?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func refresh(baseURL: String) async {
        let normalized = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: normalized + "/api/status") else {
            errorMessage = "Mac 地址不正确"
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            status = try JSONDecoder().decode(StatusResponse.self, from: data)
        } catch {
            errorMessage = "连接失败：\(error.localizedDescription)"
        }
    }
}

struct StatusResponse: Decodable {
    let summary: String
    let scannedAt: Int
    let codexRemaining: String
    let claudeRemaining: String
    let fableRemaining: String?
    let providers: [ProviderStatus]
    let tokenReport: TokenReport?
}

struct ProviderStatus: Decodable, Identifiable {
    let id: String
    let name: String
    let shortName: String
    let remaining: String
    let mode: String
    let source: String
    let latestAtEpoch: Int?
    let windows: [QuotaWindowStatus]
}

struct QuotaWindowStatus: Decodable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let usedPercent: Double?
    let remainingPercent: Double?
    let timePercent: Double?
    let resetText: String
    let countdown: String
    let basis: String
    let pace: String
}

struct TokenReport: Decodable {
    let totalTokens: Double
    let events: [TokenEvent]
    let conversations: [TokenConversation]
}

struct TokenEvent: Decodable, Identifiable {
    let id: String
    let timestampEpoch: Int
    let tokens: Int
}

struct TokenConversation: Decodable, Identifiable {
    let id: String
    let title: String
    let tokens: Int
    let latestAtEpoch: Int
}

enum AppColors {
    static let background = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let panel = Color(red: 0.105, green: 0.118, blue: 0.14)
    static let panelAlt = Color(red: 0.13, green: 0.145, blue: 0.17)
    static let border = Color.white.opacity(0.12)
    static let codex = Color(red: 0.18, green: 0.50, blue: 0.91)
    static let claude = Color(red: 0.78, green: 0.38, blue: 0.19)
    static let time = Color(red: 0.31, green: 0.58, blue: 0.78)
    static let good = Color(red: 0.22, green: 0.65, blue: 0.40)
    static let warning = Color(red: 0.90, green: 0.64, blue: 0.23)
}

enum Formatters {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--" }
        return "\(Int(max(0, min(100, value)).rounded()))%"
    }

    static func time(epoch: Int) -> String {
        timeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(epoch)))
    }

    static func relative(epoch: Int) -> String {
        let delta = max(0, Date().timeIntervalSince1970 - TimeInterval(epoch))
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
            return String(format: "%.1fK", value / 1_000)
        }
        return "\(Int(value.rounded()))"
    }
}
