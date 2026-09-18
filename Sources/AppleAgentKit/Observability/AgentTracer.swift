//
//  AgentTracer.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

import Foundation

public actor AgentTracer {
    public let configuration: AgentTraceConfiguration

    private let sinks: [any AgentTraceSink]

    public init(
        configuration: AgentTraceConfiguration = .init(),
        sinks: [any AgentTraceSink]
    ) {
        self.configuration = configuration
        self.sinks = sinks
    }

    public static func console(
        configuration: AgentTraceConfiguration = .verbose,
        label: String = "AppleAgentKit"
    ) -> AgentTracer {
        AgentTracer(
            configuration: configuration,
            sinks: [
                ConsoleTraceSink(
                    label: label
                )
            ]
        )
    }

    public func traceConfiguration() -> AgentTraceConfiguration {
        configuration
    }

    public func record(
        _ event: AgentTraceEvent
    ) async {
        for sink in sinks {
            await sink.record(event)
        }
    }

    public func record(
        error: any Error,
        name: String? = nil,
        metadata: [String: String] = [:]
    ) async {
        var metadata = metadata
        metadata["errorType"] = String(
            reflecting: type(of: error)
        )

        await record(
            AgentTraceEvent(
                kind: .error,
                name: name,
                message: Self.errorMessage(error),
                metadata: metadata
            )
        )
    }
}

private extension AgentTracer {
    static func errorMessage(
        _ error: any Error
    ) -> String {
        if let localizedError = error as? any LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        let description = String(
            describing: error
        )

        if !description.isEmpty {
            return description
        }

        return error.localizedDescription
    }
}
