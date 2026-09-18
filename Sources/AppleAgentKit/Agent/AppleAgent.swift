//
//  AppleAgent.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

import FoundationModels

public protocol AppleAgent: Sendable {
    associatedtype Profile: LanguageModelSession.DynamicProfile

    var profile: Profile { get }
}

public extension AppleAgent {
    func makeSession() -> LanguageModelSession {
        LanguageModelSession(profile: profile)
    }
}
