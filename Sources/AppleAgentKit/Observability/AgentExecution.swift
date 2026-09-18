//
//  AgentExecution.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

public enum AgentExecution {
    public static func run<Output: Sendable>(
        tracer: AgentTracer,
        name: String? = nil,
        metadata: [String: String] = [:],
        operation: @escaping @Sendable () async throws -> Output
    ) async throws -> Output {
        do {
            return try await operation()
        } catch {
            await tracer.record(
                error: error,
                name: name,
                metadata: metadata
            )

            throw error
        }
    }
}
