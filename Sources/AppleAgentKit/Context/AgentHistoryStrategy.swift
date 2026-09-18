//
//  AgentHistoryStrategy.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

public enum AgentHistoryStrategy: Sendable, Equatable {
    case full
    case droppingCompletedToolInteractions
    case rollingWindow(maximumEntries: Int)
    case automatic(maximumEntries: Int)
}
