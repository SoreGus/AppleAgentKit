# AppleAgentKit

A thin Swift package for composing agentic experiences on Apple platforms using the shipping `FoundationModels` APIs.

AppleAgentKit does **not** replace Foundation Models. It adds small reusable abstractions for:

- agent/profile composition;
- native, local and remote model selection;
- remote provider infrastructure;
- OpenAI as a `LanguageModel` provider;
- approval handlers;
- observability and trace persistence.

The package intentionally uses Apple types directly for sessions, tools, guided generation, transcripts, multimodal input and dynamic profiles.

## Requirements

- Swift 6.2
- Xcode 27
- iOS / iPadOS 27+
- macOS 27+

## Add the package

Open `Package.swift` directly in Xcode, or add the package to an application project as a local Swift package.

## Native model

```swift
import AppleAgentKit

let model = SystemLanguageModel.default
let session = LanguageModelSession(model: model)

let response = try await session.respond(
    to: "Explain Swift actors."
)

print(response.content)
```

## Local Core AI model

Core AI is provided by Apple's `coreai-models` package and can be passed directly to `LanguageModelSession`.

```swift
import AppleAgentKit
import CoreAILanguageModels

let model = try await CoreAILanguageModel(
    resourcesAt: modelURL
)

let session = LanguageModelSession(model: model)
```

No AppleAgentKit wrapper is required.

## OpenAI model

```swift
import AppleAgentKit

let model = OpenAILanguageModel(
    modelID: "gpt-5.6",
    apiKey: apiKey
)

let session = LanguageModelSession(model: model)

let response = try await session.respond(
    to: "Explain dependency injection in Swift."
)

print(response.content)
```

For production apps, do not embed long-lived provider secrets in the application bundle. Inject a secure `RemoteHTTPClient` or authentication mechanism appropriate to your architecture.

## Guided response

```swift
@Generable
struct Summary {
    let title: String
    let topics: [String]
}

let response = try await session.respond(
    to: "Summarize Swift concurrency.",
    generating: Summary.self
)

let summary = response.content
```

## Tool

```swift
@Generable
struct SearchArguments {
    @Guide(description: "Search query.")
    let query: String
}

struct SearchTool: Tool {
    let name = "search"
    let description = "Searches the local knowledge store."

    func call(
        arguments: SearchArguments
    ) async throws -> String {
        "Result for: \(arguments.query)"
    }
}
```

## Multimodal prompt

```swift
let response = try await session.respond {
    "Analyze this image."
    Attachment(image)
}
```

## Dynamic profiles

Use `LanguageModelSession.DynamicProfile` directly for phases, model routing and tool composition. AppleAgentKit deliberately does not create a parallel agent loop.

See `Examples/DynamicAgent.swift`.

## Observability

```swift
let memory = MemoryTraceSink()
let file = JSONLTraceSink(fileURL: traceURL)

let tracer = AgentTracer(
    sinks: [
        memory,
        file
    ]
)

await tracer.record(
    AgentTraceEvent(
        kind: .toolCall,
        name: "search"
    )
)
```

Lifecycle hooks from `DynamicProfile` should feed the tracer so tools remain focused on their application responsibility.

## Testing strategy

The first version intentionally contains no tests or test targets. Package-owned infrastructure is protocol-based and dependency-injected where useful so tests can be added later without redesigning the package.

## Architecture

See `Documentation/Architecture.md`.
