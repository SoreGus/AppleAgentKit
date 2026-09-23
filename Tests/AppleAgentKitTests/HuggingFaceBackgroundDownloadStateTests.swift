import Foundation
import Testing

@testable import AppleAgentKit

@Suite("Hugging Face background download state")
struct HuggingFaceBackgroundDownloadStateTests {
  @Test("persists progress independently for each model")
  func persistsProgressByModelID() throws {
    let storageDirectory = FileManager.default.temporaryDirectory.appending(
      path: UUID().uuidString,
      directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: storageDirectory) }

    let request = HuggingFaceModelDownloadRequest(
      modelID: "model-a",
      repositoryID: "owner/repository",
      resolvedRevision: String(repeating: "a", count: 40),
      files: [
        LocalModelFileInformation(path: "model.bin", size: 100),
        LocalModelFileInformation(path: "config.json", size: 20),
      ],
      host: URL(string: "https://huggingface.co")!
    )
    var state = HuggingFaceBackgroundDownloadState(request: request)
    state.completedPaths.insert("config.json")
    state.receivedBytesByPath["model.bin"] = 35

    try HuggingFaceBackgroundDownloadStateStore.save(
      state,
      storageDirectory: storageDirectory
    )

    let restored = try #require(
      HuggingFaceBackgroundDownloadStateStore.load(
        modelID: "model-a",
        storageDirectory: storageDirectory
      )
    )
    #expect(restored.repositoryID == "owner/repository")
    #expect(restored.progress.phase == .downloading)
    #expect(restored.progress.receivedBytes == 55)
    #expect(restored.progress.totalBytes == 120)
    #expect(
      HuggingFaceBackgroundDownloadStateStore.load(
        modelID: "model-b",
        storageDirectory: storageDirectory
      ) == nil
    )
  }

  @Test("ignores corrupt persisted state")
  func ignoresCorruptState() throws {
    let storageDirectory = FileManager.default.temporaryDirectory.appending(
      path: UUID().uuidString,
      directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: storageDirectory) }

    let url = HuggingFaceBackgroundDownloadStateStore.stateURL(
      modelID: "model-a",
      storageDirectory: storageDirectory
    )
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("not-json".utf8).write(to: url)

    #expect(
      HuggingFaceBackgroundDownloadStateStore.load(
        modelID: "model-a",
        storageDirectory: storageDirectory
      ) == nil
    )
  }
}
