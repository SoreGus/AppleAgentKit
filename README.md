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

### Install a Core AI model from Hugging Face

AppleAgentKit can resolve and install a controlled catalog of Core AI artifacts
published on the Hugging Face Hub. Hugging Face is the artifact provider;
`CoreAILanguageModel` remains responsible for loading and running the model.

```swift
import AppleAgentKit
import CoreAILanguageModels

let provider = try HuggingFaceModelProvider(
    models: [
        HuggingFaceModel(
            id: "my-local-model",
            displayName: "My Local Model",
            repositoryID: "organization/core-ai-model",
            revision: "main"
        )
    ]
)

let installation = try await provider.install(
    "my-local-model"
) { progress in
    print(progress.fractionCompleted ?? 0)
}

let model = try await CoreAILanguageModel(
    resourcesAt: installation.localURL
)
let session = LanguageModelSession(model: model)
```

The provider resolves branch or tag names to an exact commit, downloads into a
staging location, validates the selected artifacts, and only then promotes the
installation to persistent Application Support storage. Call
`state(for:)`, `refreshedState(for:)`, `cancelInstallation(of:)`, or
`removeModel(identifiedBy:)` to manage its lifecycle. The refreshed state also
reports when the selected branch or tag resolves to a newer commit.

On iOS and macOS, downloads use a persistent background `URLSession` by default.
Its identifier is stable for the app and storage directory, and in-flight state
is restored by model ID after relaunch. Forward the system callback from the app
delegate so Foundation can finish reconnecting background events:

```swift
func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
) {
    _ = HuggingFaceModelProvider.handleEvents(
        forBackgroundURLSession: identifier,
        completionHandler: completionHandler
    )
}
```

After recreating the provider, call `install(_:)` for a restored model to await
any remaining transfers and run validation and atomic promotion. `state(for:)`
can be used first to restore the presentation without restarting the download.

Pass `backgroundDownloadConfiguration: nil` to retain foreground-only snapshot
downloads through `swift-huggingface`. A custom implementation of
`HuggingFaceModelDownloadTransport` can also be injected for testing or another
transfer backend.

The persistent transport intentionally downloads each resolved artifact through
the Hub `resolve` endpoint. This gives `URLSession` ownership of the HTTP transfer,
including LFS and server-side Xet redirects. The native Xet downloader used by
`swift-huggingface` remains available on the foreground path, but it cannot make
its own chunk transfers persistent merely by wrapping `install()` in an app
background task.

See `Examples/HuggingFaceLocalModel.swift` for metadata lookup, progress,
cancellation, loading, and removal.

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
