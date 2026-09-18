//
//  DynamicProfile+Context.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

import FoundationModels

public extension LanguageModelSession.DynamicProfile {
    func agentContext(
        _ configuration: AgentContextConfiguration
    ) -> some LanguageModelSession.DynamicProfile {
        self
            .historyTransform { history in
                configuration.historyStrategy.transform(
                    history
                )
            }
            .maximumResponseTokens(
                configuration.maximumResponseTokens
            )
            .transcriptErrorHandlingPolicy(
                configuration.transcriptErrorHandling.foundationModelsValue
            )
    }
}

private extension AgentHistoryStrategy {
    func transform(
        _ history: [Transcript.Entry]
    ) -> [Transcript.Entry] {
        switch self {
        case .full:
            history

        case .droppingCompletedToolInteractions:
            history.droppingCompletedToolInteractions()

        case .rollingWindow(let maximumEntries):
            history.rollingWindow(
                maximumEntries: maximumEntries
            )

        case .automatic(let maximumEntries):
            history
                .droppingCompletedToolInteractions()
                .rollingWindow(
                    maximumEntries: maximumEntries
                )
        }
    }
}

private extension AgentTranscriptErrorHandling {
    var foundationModelsValue: TranscriptErrorHandlingPolicy {
        switch self {
        case .revertTranscript:
            .revertTranscript

        case .preserveTranscript:
            .preserveTranscript
        }
    }
}

private extension Array where Element == Transcript.Entry {
    func droppingCompletedToolInteractions() -> [Transcript.Entry] {
        guard let latestResponseIndex = lastIndex(where: { entry in
            if case .response = entry {
                return true
            }

            return false
        }) else {
            return self
        }

        return enumerated().compactMap { index, entry in
            guard index < latestResponseIndex else {
                return entry
            }

            switch entry {
            case .toolCalls, .toolOutput:
                return nil

            default:
                return entry
            }
        }
    }

    func rollingWindow(
        maximumEntries: Int
    ) -> [Transcript.Entry] {
        let limit = Swift.max(
            1,
            maximumEntries
        )

        guard count > limit else {
            return self
        }

        guard let latestPromptIndex = lastIndex(where: { entry in
            if case .prompt = entry {
                return true
            }

            return false
        }) else {
            return Array(
                suffix(limit)
            )
        }

        let currentTurn = Array(
            self[latestPromptIndex...]
        )

        guard currentTurn.count < limit else {
            return currentTurn
        }

        let previousEntryBudget = limit - currentTurn.count
        let previousHistory = self[..<latestPromptIndex]

        return Array(
            previousHistory.suffix(
                previousEntryBudget
            )
        ) + currentTurn
    }
}
