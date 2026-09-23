# AppleAgentKit

## Architecture and Implementation Guide

**Target:** iOS 27 / iPadOS 27 / macOS 27  
**Language:** Swift  
**Foundation:** Apple `FoundationModels` + Core AI  
**Goal:** provide a thin, native composition layer over Apple’s current AI stack without duplicating functionality already provided by Apple.

---

## 1. Vision

`AppleAgentKit` is **not** a replacement for `FoundationModels`, a second agent runtime, or a custom tool-calling framework.

Its role is to make Apple’s agentic APIs easier to compose, configure, observe, reuse, and test across applications.

The package should use Apple types directly whenever possible:

- `LanguageModel`
- `LanguageModelExecutor`
- `LanguageModelSession`
- `LanguageModelSession.DynamicProfile`
- `Profile`
- `DynamicInstructions`
- `Tool`
- `@Generable`
- `@Guide`
- `Transcript`
- `GenerationOptions`
- `ContextOptions`
- `Attachment`
- `ImageReference`
- session properties and lifecycle hooks

Primary rule:

> **If Foundation Models already solves it, AppleAgentKit must compose it rather than recreate it.**

---

## 2. Architecture

```text
┌──────────────────────────────────────────────┐
│                AppleAgentKit                 │
│                                              │
│ Agent composition                            │
│ Profile composition                          │
│ Model selection                              │
│ Approval / permission rules                  │
│ Reusable skills                              │
│ Observability and tracing                    │
│ Trace persistence                            │
│ Remote-provider infrastructure               │
│ Small convenience APIs                       │
└──────────────────────┬───────────────────────┘
                       │
┌──────────────────────▼───────────────────────┐
│              FoundationModels                │
│                                              │
│ LanguageModelSession                         │
│ DynamicProfile / Profile                     │
│ DynamicInstructions                          │
│ Tool                                         │
│ @Generable / @Guide                          │
│ Transcript                                   │
│ GenerationOptions / ContextOptions           │
│ Attachments / ImageReference                 │
│ Tool calling and guided generation           │
│ Session state and lifecycle                  │
└──────────────────────┬───────────────────────┘
                       │
┌──────────────────────▼───────────────────────┐
│                  Models                      │
│                                              │
│ LanguageModel                                │
│ LanguageModelExecutor                        │
│                                              │
│ SystemLanguageModel      Native              │
│ CoreAILanguageModel      Local               │
│ Custom LanguageModel     Remote              │
└──────────────────────────────────────────────┘
```

AppleAgentKit should not introduce parallel equivalents of Apple concepts unless a real limitation appears.

Avoid public replacements for:

```text
AgentMessage
AgentToolCall
AgentRequest
AgentResponse
AgentTranscript
ToolSchema
GenerationSchema
```

when Apple’s native types already satisfy the requirement.

---

## 3. Engineering Principles

### 3.1 No tests in the first implementation

Do **not** add unit tests, integration tests, test targets, mocks, fixtures, or test-only utilities in the initial implementation.

The architecture must nevertheless be prepared for testing from the beginning.

### 3.2 Protocol-oriented where it adds real value

Use protocols in points that benefit from substitution, isolation, or dependency injection.

Good candidates include:

- remote transport;
- HTTP client;
- authentication;
- trace sinks;
- approval handlers;
- persistent storage;
- host-provided services.

Do not create protocols merely to wrap Apple protocols that already exist.

For example, do **not** invent:

```text
AppleAgentLanguageModelProtocol
AppleAgentToolProtocol
AppleAgentSessionProtocol
```

when `LanguageModel`, `Tool`, and `LanguageModelSession` already provide the required abstraction.

### 3.3 Testability

Even without tests initially:

- inject dependencies;
- avoid global mutable state;
- avoid hidden singletons;
- keep provider-specific code isolated;
- prefer value types and immutable state;
- prefer `Sendable`;
- use `async/await`;
- use actors for shared mutable concurrent state;
- keep filesystem/network dependencies replaceable;
- expose dependencies through initializers where practical.

Consumers of AppleAgentKit should also be able to substitute:

- transports;
- authentication;
- trace sinks;
- approval handlers;
- remote models;
- other package-owned dependencies.

### 3.4 Native-first

Prefer native Foundation Models APIs over custom abstractions.

AppleAgentKit should make the Apple APIs easier to compose, not hide them.

---

## 4. Model Layer

### 4.1 Common abstraction

All models should enter through Apple’s `LanguageModel` abstraction.

Conceptually:

```swift
public protocol LanguageModel: Sendable {
    associatedtype Executor: LanguageModelExecutor

    var capabilities: LanguageModelCapabilities { get }
    var executorConfiguration: Executor.Configuration { get }
}
```

A `LanguageModel` declares:

1. the model capabilities;
2. the configuration required to create its executor.

The paired `LanguageModelExecutor` performs inference or remote API work.

Conceptually:

```swift
public protocol LanguageModelExecutor: Sendable {
    associatedtype Configuration: Hashable & Sendable
    associatedtype Model: LanguageModel

    init(configuration: Configuration) throws

    func prewarm(
        model: Model,
        transcript: Transcript
    )

    func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: Model,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws
}
```

---

## 5. Native Model

Use Apple’s model directly:

```swift
let model = SystemLanguageModel()
```

AppleAgentKit should not wrap `SystemLanguageModel` unless a wrapper provides a concrete package-level benefit.

---

## 6. Local Model

Local LLMs should use Core AI through `CoreAILanguageModel`:

```swift
let model = try await CoreAILanguageModel(
    resourcesAt: modelURL
)
```

AppleAgentKit should not recreate:

- tokenization;
- KV-cache handling;
- model loading;
- guided decoding;
- tool-call parsing;
- chunk loading;
- inference scheduling;

when Core AI / Foundation Models already provide those responsibilities.

### 6.1 Local artifact providers

A local artifact provider acquires and manages model resources. It is not a
`LanguageModel` or a `LanguageModelExecutor`; inference remains the responsibility
of Core AI.

```text
Local/
├── LocalModel.swift
├── LocalModelInstallation.swift
├── LocalModelInstallationState.swift
├── LocalModelDownloadProgress.swift
├── LocalModelError.swift
└── Providers/
    └── HuggingFace/
        ├── HuggingFaceBackgroundDownloadTransport.swift
        ├── HuggingFaceModel.swift
        ├── HuggingFaceModelProvider.swift
        └── Internal/
            └── HuggingFaceInstallationManifest.swift
```

`HuggingFaceModelProvider` accepts a controlled list of compatible models. Each
entry carries a stable package-level identifier, a Hub repository ID, an optional
revision, artifact filters, expected size, and runtime compatibility.

The installation flow is:

```text
known model
    → resolve repository revision to an exact commit
    → inspect matching artifacts and logical size
    → persist transfer metadata by model ID
    → download each artifact to staging with a background URLSession
    → validate required artifacts
    → write the installation manifest
    → promote to persistent storage
    → pass the installed URL to CoreAILanguageModel
```

Installations live under Application Support by default and are separated by
model and commit. The Hugging Face SDK cache remains independently owned and is
not deleted when AppleAgentKit removes an installation.

The provider is an actor so installation tasks and progress state are safe to
access concurrently. On supported Apple platforms, a stable background session
continues HTTP transfers while the app is suspended or terminated by the system.
The app forwards Foundation's background-session lifecycle callback, while the
provider reconstructs active tasks and progress from disk when it is recreated.
Cancellation removes both the system tasks and resumable staging state.

The persistent path uses the Hub's resolved HTTP artifact URLs. This covers
classic Git LFS and Xet-backed repositories without depending on the process-bound
Xet chunk downloader. The `swift-huggingface` snapshot/Xet implementation remains
the foreground fallback. Network behavior remains injectable through
`HuggingFaceModelDownloadTransport`, and callers can opt out by passing a `nil`
background configuration.

---

## 7. Remote Models

Remote models should conform to Apple’s `LanguageModel` and use a provider-specific `LanguageModelExecutor`.

AppleAgentKit should add a reusable remote infrastructure layer without turning it into a generic mega-runtime.

Recommended structure:

```text
Remote/
├── RemoteLanguageModel.swift
├── RemoteTransport.swift
├── RemoteHTTPClient.swift
├── RemoteAuthentication.swift
├── RemoteStreamDecoder.swift
├── RemoteError.swift
└── Providers/
    └── OpenAI/
        ├── OpenAILanguageModel.swift
        ├── OpenAILanguageModelExecutor.swift
        └── Internal/
            ├── OpenAIRequest.swift
            ├── OpenAIResponse.swift
            └── OpenAIStreamEvent.swift
```

### 7.1 RemoteLanguageModel

Keep `RemoteLanguageModel` intentionally thin.

```swift
public protocol RemoteLanguageModel: LanguageModel {
    var transport: any RemoteTransport { get }
    var baseURL: URL { get }
    var modelID: String { get }
}
```

It identifies common remote-model concepts without imposing provider-specific request semantics.

### 7.2 RemoteTransport

```swift
public protocol RemoteTransport: Sendable {
    func data(
        for request: URLRequest
    ) async throws -> (Data, URLResponse)

    func bytes(
        for request: URLRequest
    ) async throws -> (URLSession.AsyncBytes, URLResponse)
}
```

A default implementation can use `URLSession`.

```swift
public struct URLSessionRemoteTransport: RemoteTransport {
    public let session: URLSession

    public init(
        session: URLSession = .shared
    ) {
        self.session = session
    }

    public func data(
        for request: URLRequest
    ) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }

    public func bytes(
        for request: URLRequest
    ) async throws -> (URLSession.AsyncBytes, URLResponse) {
        try await session.bytes(for: request)
    }
}
```

### 7.3 Authentication

```swift
public protocol RemoteAuthentication: Sendable {
    func apply(
        to request: inout URLRequest
    ) throws
}
```

Example:

```swift
public struct BearerTokenAuthentication: RemoteAuthentication {
    public let token: String

    public init(token: String) {
        self.token = token
    }

    public func apply(
        to request: inout URLRequest
    ) throws {
        request.setValue(
            "Bearer \(token)",
            forHTTPHeaderField: "Authorization"
        )
    }
}
```

### 7.4 RemoteHTTPClient

```swift
public protocol RemoteHTTPClient: Sendable {
    func send(
        _ request: URLRequest
    ) async throws -> Data

    func stream(
        _ request: URLRequest
    ) async throws -> URLSession.AsyncBytes
}
```

Its implementation may compose:

- `RemoteTransport`;
- authentication;
- response validation;
- common headers;
- timeout behavior;
- retry policy if later required.

Provider-specific request/response translation must remain outside this shared layer.

---

## 8. OpenAILanguageModel

`OpenAILanguageModel` should be the first concrete remote provider.

```swift
public struct OpenAILanguageModel: RemoteLanguageModel {
    public typealias Executor = OpenAILanguageModelExecutor

    public let transport: any RemoteTransport
    public let baseURL: URL
    public let modelID: String
    public let apiKey: String

    public init(
        modelID: String,
        apiKey: String,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        transport: any RemoteTransport = URLSessionRemoteTransport()
    ) {
        self.modelID = modelID
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.transport = transport
    }

    public var capabilities: LanguageModelCapabilities {
        .init(capabilities: [
            .toolCalling,
            .guidedGeneration,
            .reasoning
        ])
    }

    public var executorConfiguration: Executor.Configuration {
        .init(
            modelID: modelID,
            apiKey: apiKey,
            baseURL: baseURL,
            transport: transport
        )
    }
}
```

The exact capabilities must reflect the selected remote model rather than being blindly hard-coded for every OpenAI model.

### 8.1 OpenAILanguageModelExecutor

```swift
public struct OpenAILanguageModelExecutor: LanguageModelExecutor {
    public typealias Model = OpenAILanguageModel

    public struct Configuration: Sendable {
        public let modelID: String
        public let apiKey: String
        public let baseURL: URL
        public let transport: any RemoteTransport
    }

    private let configuration: Configuration

    public init(
        configuration: Configuration
    ) throws {
        self.configuration = configuration
    }

    public func prewarm(
        model: Model,
        transcript: Transcript
    ) {
        // Optional remote preparation.
    }

    public func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: Model,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        // 1. Translate Foundation Models request.
        // 2. Build OpenAI request.
        // 3. Execute through injected remote transport/client.
        // 4. Decode OpenAI stream events.
        // 5. Translate events into Foundation Models generation events.
        // 6. Stream them through the supplied channel.
    }
}
```

Provider-specific DTOs should be internal/private.

Examples:

```text
OpenAIRequest
OpenAIResponse
OpenAIStreamEvent
OpenAIToolDefinition
OpenAIReasoningConfiguration
```

They must not leak into the AppleAgentKit public API.

---

## 9. Session Layer

`LanguageModelSession` is the central Foundation Models runtime.

It coordinates:

- prompts;
- responses;
- reasoning;
- tools;
- tool outputs;
- transcript;
- guided generation;
- streaming;
- attachments;
- model configuration.

Simple response:

```swift
let session = LanguageModelSession(model: model)

let response = try await session.respond(
    to: "Explain Swift actors."
)

let text = response.content
```

Structured response:

```swift
@Generable
struct Answer {
    let summary: String
    let topics: [String]
}

let response = try await session.respond(
    to: "Explain Swift actors.",
    generating: Answer.self
)

let answer: Answer = response.content
```

AppleAgentKit should preserve these native response paths instead of introducing a universal `AgentResponse`.

---

## 10. Tools and Guided Generation

Use Foundation Models `Tool` directly.

### 10.1 Guided arguments

```swift
@Generable
struct SearchArguments {
    @Guide(description: "Search query.")
    let query: String

    @Guide(description: "Maximum number of results.")
    let limit: Int
}
```

### 10.2 Tool

```swift
struct SearchTool: Tool {
    let name = "search"
    let description = "Searches the knowledge store."

    func call(
        arguments: SearchArguments
    ) async throws -> String {
        print("Searching:", arguments.query)
        return "Example result"
    }
}
```

Do not add a second:

- JSON schema layer;
- tool registry;
- generic argument decoder;
- manual tool-call parser;

unless Foundation Models proves insufficient.

---

## 11. Guided Responses

The final session response may be simple text or a typed guided model.

```swift
@Generable
struct Result {
    let title: String
    let summary: String
}

let response = try await session.respond(
    to: "Create a concise result.",
    generating: Result.self
)

let result: Result = response.content
```

Prefer `@Generable` for stable typed contracts.

Use dynamic `GenerationSchema` only when the schema itself is genuinely dynamic.

---

## 12. Multimodal Input

Use native Foundation Models attachments.

```swift
let response = try await session.respond {
    "Analyze this image."
    Attachment(image)
}
```

Structured multimodal response:

```swift
@Generable
struct ImageAnalysis {
    let summary: String
    let detectedObjects: [String]
}
```

```swift
let response = try await session.respond(
    generating: ImageAnalysis.self
) {
    "Analyze this image."
    Attachment(image)
}
```

Use `ImageReference` when a tool must refer back to an image already present in the transcript.

Do not introduce a custom image-message abstraction.

---

## 13. Dynamic Profiles

`LanguageModelSession.DynamicProfile` is the primary agentic orchestration primitive.

A profile can define:

- instructions;
- tools;
- model;
- temperature;
- sampling;
- reasoning level;
- tool-calling mode;
- lifecycle behavior.

Example:

```swift
@Observable
final class AgentOrchestrator {
    enum Phase {
        case discovery
        case execution
    }

    var phase: Phase = .discovery

    let fastModel: any LanguageModel
    let strongModel: any LanguageModel
}
```

```swift
struct AgentProfile: LanguageModelSession.DynamicProfile {
    let orchestrator: AgentOrchestrator

    var body: some DynamicProfile {
        switch orchestrator.phase {
        case .discovery:
            Profile {
                Instructions {
                    "Inspect available information before acting."
                }

                SearchTool()
                BeginExecutionTool(
                    orchestrator: orchestrator
                )
            }
            .model(orchestrator.fastModel)
            .toolCallingMode(.allowed)

        case .execution:
            Profile {
                Instructions {
                    "Execute using validated context."
                }

                ExecuteTool()
            }
            .model(orchestrator.strongModel)
            .toolCallingMode(.allowed)
        }
    }
}
```

This is the preferred replacement for a custom agent loop.

---

## 14. Multi-model Composition

Model selection should be explicit and profile-driven.

Recommended pattern:

```text
Discovery
  SystemLanguageModel
  lightweight tools
       │
       ▼
Validation
  SystemLanguageModel or CoreAILanguageModel
  validation tools
       │
       ▼
Execution
  OpenAILanguageModel
  execution tools
```

Prefer:

```text
Profile A -> Model X + Tools A/B
Profile B -> Model Y + Tools C/D
```

rather than inventing a separate routing table unless a future use case truly requires it.

---

## 15. Tool Calling Modes

Use `GenerationOptions.ToolCallingMode` directly:

- `.allowed`
- `.required`
- `.disallowed`

A required-tool state must have a clear exit condition.

---

## 16. Agent Guardrails and Approval

Differentiate:

1. model/content safety;
2. agent/action safety.

AppleAgentKit should focus on action safety such as:

- user approval before mutations;
- denied operations;
- phase-specific tool access;
- permission checks;
- validation before destructive actions;
- resource or iteration constraints.

Use Dynamic Profile hooks before inventing a custom policy engine.

```swift
public protocol ApprovalHandler: Sendable {
    func requestApproval(
        for call: Transcript.ToolCall
    ) async -> Bool
}
```

---

## 17. Lifecycle Hooks

Use Foundation Models lifecycle hooks for:

- approvals;
- tracing;
- metrics;
- progress;
- state transitions;
- debugging.

Relevant hooks include:

- `onPrompt`
- `onReasoning`
- `onResponse`
- `onToolCall`
- `onToolOutput`

Avoid requiring every tool to manually emit duplicate lifecycle events.

---

## 18. Observability

Observability is a primary AppleAgentKit responsibility.

### 18.1 Event model

```swift
public enum AgentTraceEvent: Sendable {
    case prompt(AgentPromptTrace)
    case reasoning(AgentReasoningTrace)
    case toolCall(AgentToolCallTrace)
    case toolOutput(AgentToolOutputTrace)
    case response(AgentResponseTrace)
    case profileChanged(AgentProfileTrace)
    case error(AgentErrorTrace)
}
```

### 18.2 Sink

```swift
public protocol AgentTraceSink: Sendable {
    func record(
        _ event: AgentTraceEvent
    ) async
}
```

Initial implementations:

```text
MemoryTraceSink
JSONLTraceSink
CompositeTraceSink
```

### 18.3 Trace privacy

Tracing must be configurable because prompts, reasoning, tool arguments, outputs, and attachments may contain sensitive information.

```swift
public struct AgentTraceConfiguration: Sendable {
    public var capturePrompts: Bool
    public var captureResponses: Bool
    public var captureReasoning: Bool
    public var captureToolArguments: Bool
    public var captureToolOutputs: Bool
}
```

Prefer metadata over raw content by default.

---

## 19. Reusable Skills

Use `DynamicInstructions` as the primary reusable skill primitive.

```swift
struct ResearchSkill: DynamicInstructions {
    var body: some DynamicInstructions {
        Instructions {
            "Verify uncertain facts using the available tools."
        }

        SearchTool()
        ReadDocumentTool()
    }
}
```

Compose skills inside profiles rather than creating a parallel skill runtime.

---

## 20. State

Prefer native state mechanisms:

- `Transcript`;
- `SessionProperty`;
- observable orchestration state.

Do not recreate a generic `AgentState` unless a concrete missing requirement appears.

---

## 21. Errors

Preserve Foundation Models errors directly.

AppleAgentKit should define errors only for package-owned concerns.

```swift
public enum AppleAgentKitError: Error {
    case approvalDenied
    case invalidAgentConfiguration
    case tracePersistenceFailed
    case remoteTransportFailed
}
```

Do not collapse every underlying failure into a generic package error.

---

## 22. Proposed Package Structure

```text
AppleAgentKit/
├── Package.swift
├── Sources/
│   └── AppleAgentKit/
│       ├── Agent/
│       │   ├── AppleAgent.swift
│       │   └── AgentConfiguration.swift
│       │
│       ├── Approval/
│       │   ├── ApprovalHandler.swift
│       │   └── ApprovalError.swift
│       │
│       ├── Remote/
│       │   ├── RemoteLanguageModel.swift
│       │   ├── RemoteTransport.swift
│       │   ├── RemoteHTTPClient.swift
│       │   ├── RemoteAuthentication.swift
│       │   ├── RemoteStreamDecoder.swift
│       │   ├── RemoteError.swift
│       │   └── Providers/
│       │       └── OpenAI/
│       │           ├── OpenAILanguageModel.swift
│       │           ├── OpenAILanguageModelExecutor.swift
│       │           └── Internal/
│       │               ├── OpenAIRequest.swift
│       │               ├── OpenAIResponse.swift
│       │               └── OpenAIStreamEvent.swift
│       │
│       ├── Observability/
│       │   ├── AgentTraceEvent.swift
│       │   ├── AgentTraceSink.swift
│       │   ├── MemoryTraceSink.swift
│       │   ├── JSONLTraceSink.swift
│       │   └── CompositeTraceSink.swift
│       │
│       └── Support/
│           └── ...
│
└── README.md
```

Do not create folders just to wrap Foundation Models concepts unless real package-owned behavior appears.

---

## 23. Minimal AppleAgent Abstraction

A thin semantic abstraction is acceptable if it does not hide Foundation Models.

```swift
public protocol AppleAgent {
    associatedtype Profile: LanguageModelSession.DynamicProfile

    var profile: Profile { get }
}
```

Optional convenience:

```swift
extension AppleAgent {
    func makeSession() -> LanguageModelSession {
        LanguageModelSession(
            profile: profile
        )
    }
}
```

The public API should be finalized only after building a small working prototype against the shipping SDK.

---

## 24. What AppleAgentKit Must Not Reimplement

Avoid custom equivalents of:

```text
LanguageModel
LanguageModelExecutor
LanguageModelSession
Transcript
Tool
ToolCall
tool schemas
guided generation
Generable
Guide
GenerationOptions
ContextOptions
tool-calling loop
attachments
ImageReference
DynamicProfile
DynamicInstructions
session properties
model capabilities
```

Reimplementation is justified only after proving a concrete limitation in the native API.

---

## 25. First Implementation Milestone

### Required

1. Swift Package for iOS/iPadOS 27 and macOS 27.
2. Minimal `AppleAgent` abstraction.
3. Native `SystemLanguageModel` example.
4. Local `CoreAILanguageModel` example.
5. Reusable remote infrastructure.
6. `RemoteLanguageModel`.
7. `OpenAILanguageModel`.
8. `OpenAILanguageModelExecutor`.
9. One `@Generable` response.
10. One `Tool` with `@Generable` arguments.
11. One multimodal prompt.
12. One `DynamicProfile` with two phases and different models/tools.
13. Tool approval through lifecycle hooks.
14. `MemoryTraceSink`.
15. `JSONLTraceSink`.

### Explicitly out of scope initially

- tests;
- test targets;
- mocks;
- custom agent loop;
- custom tool registry;
- custom message hierarchy;
- custom JSON schema system;
- legacy OS support;
- pre-iOS/macOS 27 compatibility;
- Python interoperability.

---

## 26. Implementation Principle

A successful AppleAgentKit should feel like:

```swift
let agent = MyAgent(...)
let session = agent.makeSession()

let response = try await session.respond(
    generating: Result.self
) {
    "Perform the task."
    Attachment(image)
}
```

while advanced users can still access Foundation Models APIs directly.

AppleAgentKit adds value through:

- composition;
- model routing;
- reusable profiles;
- approvals;
- observability;
- remote-provider infrastructure;
- testable dependency boundaries.

It should not become a parallel AI framework.

---

## 27. Apple References

- Foundation Models updates  
  https://developer.apple.com/documentation/updates/foundationmodels

- Bring an LLM provider to the Foundation Models framework — WWDC26  
  https://developer.apple.com/videos/play/wwdc2026/339/

- Build agentic app experiences with the Foundation Models framework — WWDC26  
  https://developer.apple.com/videos/play/wwdc2026/242/

- What’s new in the Foundation Models framework — WWDC26  
  https://developer.apple.com/videos/play/wwdc2026/241/

- `LanguageModelExecutor`  
  https://developer.apple.com/documentation/foundationmodels/languagemodelexecutor

- `LanguageModelSession.DynamicProfile`  
  https://developer.apple.com/documentation/foundationmodels/languagemodelsession/dynamicprofile

- Tool calling  
  https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling
