import AppleAgentKit
import CoreAILanguageModels

// Replace this entry with a repository containing artifacts already prepared
// for Core AI by AppleAgentKitPython. Pin a validated commit when reproducibility
// is required.
let supportedLocalModels = [
  HuggingFaceModel(
    id: "example-core-ai-model",
    displayName: "Example Core AI Model",
    repositoryID: "your-organization/your-core-ai-model",
    revision: "main",
    expectedDownloadSize: 935 * 1_024 * 1_024
  )
]

func makeLocalSession() async throws -> LanguageModelSession {
  let provider = try HuggingFaceModelProvider(
    models: supportedLocalModels
  )

  let localState = try await provider.state(
    for: "example-core-ai-model"
  )
  print("Local state:", String(describing: localState))

  let information = try await provider.information(
    for: "example-core-ai-model"
  )
  print(
    "Resolved revision:",
    information.resolvedRevision
  )

  let installation = try await provider.install(
    "example-core-ai-model"
  ) { progress in
    if let fraction = progress.fractionCompleted {
      print("Download:", fraction.formatted(.percent))
    } else {
      print("Phase:", progress.phase.rawValue)
    }
  }

  let model = try await CoreAILanguageModel(
    resourcesAt: installation.localURL
  )

  return LanguageModelSession(model: model)
}

func cancelLocalModelDownload(
  using provider: HuggingFaceModelProvider
) async throws {
  try await provider.cancelInstallation(
    of: "example-core-ai-model"
  )
}

func removeLocalModel(
  using provider: HuggingFaceModelProvider
) async throws {
  try await provider.removeModel(
    identifiedBy: "example-core-ai-model"
  )
}
