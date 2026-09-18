//
//  OpenAILanguageModel.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

import Foundation
import FoundationModels

public struct OpenAILanguageModel: RemoteLanguageModel {
    public typealias Executor = OpenAILanguageModelExecutor

    public let baseURL: URL
    public let modelID: String
    public let client: RemoteHTTPClientHandle
    public let declaredCapabilities: LanguageModelCapabilities

    public init(
        modelID: String,
        apiKey: String,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        capabilities: LanguageModelCapabilities = .init([
            .toolCalling,
            .guidedGeneration,
            .reasoning,
            .vision
        ]),
        transport: any RemoteTransport = URLSessionRemoteTransport()
    ) {
        let authentication = BearerTokenAuthentication(token: apiKey)
        let httpClient = DefaultRemoteHTTPClient(
            transport: transport,
            authentication: authentication
        )

        self.init(
            modelID: modelID,
            baseURL: baseURL,
            capabilities: capabilities,
            client: httpClient
        )
    }

    public init(
        modelID: String,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        capabilities: LanguageModelCapabilities = .init([
            .toolCalling,
            .guidedGeneration,
            .reasoning,
            .vision
        ]),
        client: any RemoteHTTPClient
    ) {
        self.baseURL = baseURL
        self.modelID = modelID
        self.declaredCapabilities = capabilities
        self.client = RemoteHTTPClientHandle(client: client)
    }

    public var capabilities: LanguageModelCapabilities {
        declaredCapabilities
    }

    public var executorConfiguration: Executor.Configuration {
        Executor.Configuration(
            modelID: modelID,
            baseURL: baseURL,
            client: client
        )
    }
}
