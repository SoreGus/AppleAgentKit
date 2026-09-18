import AppleAgentKit
import Observation

@Observable
final class ExampleOrchestrator {
    enum Phase {
        case discovery
        case execution
    }

    var phase: Phase = .discovery

    let discoveryModel: any LanguageModel
    let executionModel: any LanguageModel

    init(
        discoveryModel: any LanguageModel,
        executionModel: any LanguageModel
    ) {
        self.discoveryModel = discoveryModel
        self.executionModel = executionModel
    }
}

@Generable
struct BeginExecutionArguments {
    @Guide(description: "Why discovery is complete.")
    let reason: String
}

struct BeginExecutionTool: Tool {
    let orchestrator: ExampleOrchestrator

    let name = "begin_execution"
    let description = "Moves the agent from discovery to execution."

    func call(
        arguments: BeginExecutionArguments
    ) async throws -> String {
        orchestrator.phase = .execution
        return "Execution started: \(arguments.reason)"
    }
}

struct ExampleSearchTool: Tool {
    @Generable
    struct Arguments {
        let query: String
    }

    let name = "search"
    let description = "Searches for information."

    func call(
        arguments: Arguments
    ) async throws -> String {
        "Search result for \(arguments.query)"
    }
}

struct ExampleExecuteTool: Tool {
    @Generable
    struct Arguments {
        let instruction: String
    }

    let name = "execute"
    let description = "Executes an approved operation."

    func call(
        arguments: Arguments
    ) async throws -> String {
        "Executed: \(arguments.instruction)"
    }
}

struct ExampleDynamicProfile: LanguageModelSession.DynamicProfile {
    let orchestrator: ExampleOrchestrator

    var body: some DynamicProfile {
        switch orchestrator.phase {
        case .discovery:
            Profile {
                Instructions {
                    "Discover the information required before executing."
                }

                ExampleSearchTool()
                BeginExecutionTool(
                    orchestrator: orchestrator
                )
            }
            .model(orchestrator.discoveryModel)
            .toolCallingMode(.allowed)

        case .execution:
            Profile {
                Instructions {
                    "Execute using the validated discovery context."
                }

                ExampleExecuteTool()
            }
            .model(orchestrator.executionModel)
            .toolCallingMode(.allowed)
        }
    }
}
