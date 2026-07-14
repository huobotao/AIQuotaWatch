import Foundation

enum StatusPayloadBuilder {
    static func payload(from snapshot: DashboardSnapshot, now: Date = Date()) -> [String: Any] {
        let normalClaude = snapshot.claudes.filter { !$0.isFableWallet }
        let fable = snapshot.claudes.filter { $0.isFableWallet }
        let claudeRemaining = normalClaude
            .map { $0.tightestRemainingText }
            .minByPercent() ?? "--"
        let fableRemaining = fable
            .map { $0.tightestRemainingText }
            .minByPercent() ?? "--"

        return [
            "schemaVersion": 2,
            "generatedBy": "Codex (GPT-5) for Richard",
            "menuTitle": snapshot.compactMenuTitle,
            "summary": snapshot.statusMenuSummary,
            "scannedAt": Int(snapshot.scannedAt.timeIntervalSince1970),
            "scannedAtISO": iso(snapshot.scannedAt),
            "codexRemaining": snapshot.codex.tightestRemainingText,
            "claudeRemaining": claudeRemaining,
            "fableRemaining": fableRemaining,
            "web": [
                "title": "AI 额度观察",
                "api": "/api/status",
                "refreshSeconds": 10
            ],
            "providers": snapshot.providers.map { providerPayload($0, now: now) },
            "tokenReport": tokenReportPayload(snapshot.tokenReport)
        ]
    }

    private static func providerPayload(_ provider: ProviderSnapshot, now: Date) -> [String: Any] {
        [
            "id": provider.id,
            "name": provider.name,
            "shortName": provider.shortName,
            "remaining": provider.tightestRemainingText,
            "mode": provider.mode,
            "source": provider.source,
            "email": provider.email ?? NSNull(),
            "latestAt": optionalISO(provider.latestAt),
            "latestAtEpoch": optionalEpoch(provider.latestAt),
            "windows": provider.windows.map { windowPayload($0, now: now) }
        ]
    }

    private static func windowPayload(_ window: QuotaWindow, now: Date) -> [String: Any] {
        var payload: [String: Any] = [
            "id": window.id,
            "title": window.title,
            "subtitle": window.subtitle,
            "usedPercent": optionalNumber(window.activeUsedPercent(at: now)),
            "remainingPercent": optionalNumber(window.remainingPercent(at: now)),
            "timePercent": optionalNumber(window.timePercent(at: now)),
            "resetAt": optionalISO(window.resetAt),
            "resetAtEpoch": optionalEpoch(window.resetAt),
            "resetText": Format.reset(window.resetAt),
            "countdown": Format.countdown(to: window.resetAt, now: now),
            "windowMinutes": window.windowMinutes,
            "latestAt": optionalISO(window.latestAt),
            "latestAtEpoch": optionalEpoch(window.latestAt),
            "official": window.official,
            "basis": window.basis,
            "isExpired": window.isExpired(at: now),
            "pace": window.pace(at: now).text
        ]

        if let tokenSummary = window.tokenSummary {
            payload["tokenSummary"] = [
                "total": tokenSummary.total,
                "entries": tokenSummary.entries
            ]
        } else {
            payload["tokenSummary"] = NSNull()
        }

        return payload
    }

    private static func tokenReportPayload(_ report: TokenUsageReport) -> [String: Any] {
        let events = report.codexEvents.suffix(120)
        let conversations = report.codexConversations
            .sorted { $0.tokens > $1.tokens }
            .prefix(30)
        let claudeConversations = report.claudeConversations.prefix(30)

        return [
            "source": report.source,
            "scannedFiles": report.scannedFiles,
            "totalTokens": report.totalTokens,
            "peakEvent": report.peakEvent.map(tokenEventPayload) ?? NSNull(),
            "latestEvent": report.latestEvent.map(tokenEventPayload) ?? NSNull(),
            "events": events.map(tokenEventPayload),
            "conversations": conversations.map(conversationPayload),
            "claudeSource": report.claudeSource,
            "claudeScannedFiles": report.claudeScannedFiles,
            "claudeTotalTokens": report.claudeTotalTokens,
            "claudeConversations": claudeConversations.map(conversationPayload)
        ]
    }

    private static func conversationPayload(_ conversation: TokenConversationUsage) -> [String: Any] {
        [
            "id": conversation.id,
            "title": conversation.title,
            "tokens": conversation.tokens,
            "events": conversation.events,
            "latestAt": iso(conversation.latestAt),
            "latestAtEpoch": Int(conversation.latestAt.timeIntervalSince1970),
            "sourceFile": conversation.sourceFile
        ]
    }

    private static func tokenEventPayload(_ event: TokenUsageEvent) -> [String: Any] {
        [
            "id": event.id,
            "timestamp": iso(event.timestamp),
            "timestampEpoch": Int(event.timestamp.timeIntervalSince1970),
            "sessionID": event.sessionID,
            "conversationTitle": event.conversationTitle,
            "tokens": event.tokens,
            "inputTokens": event.inputTokens ?? NSNull(),
            "cachedInputTokens": event.cachedInputTokens ?? NSNull(),
            "outputTokens": event.outputTokens ?? NSNull(),
            "reasoningTokens": event.reasoningTokens ?? NSNull(),
            "cumulativeTokens": event.cumulativeTokens ?? NSNull(),
            "sourceFile": event.sourceFile
        ]
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func optionalISO(_ date: Date?) -> Any {
        date.map(iso) ?? NSNull()
    }

    private static func optionalEpoch(_ date: Date?) -> Any {
        date.map { Int($0.timeIntervalSince1970) } ?? NSNull()
    }

    private static func optionalNumber(_ value: Double?) -> Any {
        guard let value, value.isFinite else { return NSNull() }
        return value
    }
}
