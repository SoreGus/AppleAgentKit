//
//  DynamicProfile+AppleAgentKit.swift
//  AppleAgentKit
//
//  Created by Gustavo Soré on 18/09/26.
//

import FoundationModels

public extension LanguageModelSession.DynamicProfile {
    func traced(
        using tracer: AgentTracer,
        profileName: String? = nil
    ) -> some LanguageModelSession.DynamicProfile {
        self
            .onActivate {
                await tracer.record(
                    AgentTraceEvent(
                        kind: .profileChanged,
                        name: profileName,
                        metadata: ["state": "active"]
                    )
                )
            }
            .onDeactivate {
                await tracer.record(
                    AgentTraceEvent(
                        kind: .profileChanged,
                        name: profileName,
                        metadata: ["state": "inactive"]
                    )
                )
            }
            .onPrompt {
                await tracer.record(
                    AgentTraceEvent(
                        kind: .prompt,
                        name: profileName
                    )
                )
            }
            .onReasoning {
                await tracer.record(
                    AgentTraceEvent(
                        kind: .reasoning,
                        name: profileName
                    )
                )
            }
            .onToolCall { call in
                let configuration = await tracer.traceConfiguration()
                let arguments = configuration.captureToolArguments
                    ? call.arguments.jsonString
                    : nil

                await tracer.record(
                    AgentTraceEvent(
                        kind: .toolCall,
                        name: call.toolName,
                        message: arguments,
                        metadata: profileName.map { ["profile": $0] } ?? [:]
                    )
                )
            }
            .onToolOutput { call, output in
                let configuration = await tracer.traceConfiguration()
                let message = configuration.captureToolOutputs
                    ? output.traceText
                    : nil

                await tracer.record(
                    AgentTraceEvent(
                        kind: .toolOutput,
                        name: call.toolName,
                        message: message,
                        metadata: profileName.map { ["profile": $0] } ?? [:]
                    )
                )
            }
            .onResponse {
                await tracer.record(
                    AgentTraceEvent(
                        kind: .response,
                        name: profileName
                    )
                )
            }
    }

    func requiringApproval(
        using handler: any ApprovalHandler,
        when predicate: @escaping @Sendable (Transcript.ToolCall) -> Bool = { _ in true }
    ) -> some LanguageModelSession.DynamicProfile {
        onToolCall { call in
            guard predicate(call) else {
                return
            }

            guard await handler.requestApproval(for: call) else {
                throw ApprovalError.denied
            }
        }
    }
}

private extension Transcript.ToolOutput {
    var traceText: String {
        segments.compactMap { segment in
            switch segment {
            case .text(let text):
                text.content

            case .structure(let structure):
                structure.content.jsonString

            case .attachment:
                "[attachment]"

            @unknown default:
                nil
            }
        }
        .joined(separator: "\n")
    }
}
