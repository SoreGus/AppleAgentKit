//
//  AgentContextConfiguration.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

public enum AgentTranscriptErrorHandling: Sendable, Equatable {
    case revertTranscript
    case preserveTranscript
}

public struct AgentContextConfiguration: Sendable, Equatable {
    public var historyStrategy: AgentHistoryStrategy
    public var maximumResponseTokens: Int?
    public var transcriptErrorHandling: AgentTranscriptErrorHandling

    public init(
        historyStrategy: AgentHistoryStrategy = .automatic(
            maximumEntries: 12
        ),
        maximumResponseTokens: Int? = nil,
        transcriptErrorHandling: AgentTranscriptErrorHandling = .revertTranscript
    ) {
        self.historyStrategy = historyStrategy
        self.maximumResponseTokens = maximumResponseTokens
        self.transcriptErrorHandling = transcriptErrorHandling
    }

    public static let full = AgentContextConfiguration(
        historyStrategy: .full
    )

    public static let compact = AgentContextConfiguration(
        historyStrategy: .automatic(
            maximumEntries: 8
        ),
        maximumResponseTokens: 512
    )
}
