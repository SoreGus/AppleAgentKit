//
//  HuggingFaceModelProvider.swift
//  AppleAgentKit
//

import Foundation
import HuggingFace

public actor HuggingFaceModelProvider {
  public typealias ProgressHandler =
    @MainActor @Sendable (
      LocalModelDownloadProgress
    ) -> Void

  public nonisolated let models: [HuggingFaceModel]
  public nonisolated let storageDirectory: URL

  private let modelsByID: [String: HuggingFaceModel]
  private let client: HubClient
  private var installationTasks: [String: Task<LocalModelInstallation, any Error>] = [:]
  private var progressByModelID: [String: LocalModelDownloadProgress] = [:]

  public init(
    models: [HuggingFaceModel],
    storageDirectory: URL = HuggingFaceModelProvider.defaultStorageDirectory,
    client: HubClient = HubClient()
  ) throws {
    var modelsByID: [String: HuggingFaceModel] = [:]

    for model in models {
      guard modelsByID.updateValue(model, forKey: model.id) == nil else {
        throw LocalModelError.duplicateModelID(model.id)
      }

      guard Repo.ID(rawValue: model.repositoryID) != nil else {
        throw LocalModelError.invalidRepositoryID(model.repositoryID)
      }
    }

    self.models = models
    self.modelsByID = modelsByID
    self.storageDirectory = storageDirectory
    self.client = client
  }

  public nonisolated static var defaultStorageDirectory: URL {
    let applicationSupport =
      FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first ?? FileManager.default.temporaryDirectory

    return
      applicationSupport
      .appending(path: "AppleAgentKit", directoryHint: .isDirectory)
      .appending(path: "Models", directoryHint: .isDirectory)
      .appending(path: "HuggingFace", directoryHint: .isDirectory)
  }

  public func model(
    identifiedBy id: String
  ) throws -> HuggingFaceModel {
    guard let model = modelsByID[id] else {
      throw LocalModelError.unknownModel(id)
    }

    return model
  }

  public func information(
    for id: String
  ) async throws -> LocalModelInformation {
    let model = try model(identifiedBy: id)
    return try await Self.fetchInformation(
      for: model,
      client: client
    )
  }

  public func state(
    for id: String
  ) throws -> LocalModelInstallationState {
    let model = try model(identifiedBy: id)

    if let progress = progressByModelID[id] {
      return .downloading(progress)
    }

    do {
      guard let installation = try localInstallation(for: model) else {
        return .notInstalled
      }

      return .installed(installation)
    } catch {
      return .invalid(error.localizedDescription)
    }
  }

  public func installedModel(
    identifiedBy id: String
  ) throws -> LocalModelInstallation? {
    let model = try model(identifiedBy: id)
    return try localInstallation(for: model)
  }

  public func refreshedState(
    for id: String
  ) async throws -> LocalModelInstallationState {
    let localState = try state(for: id)

    guard case .installed(let installation) = localState else {
      return localState
    }

    let information = try await information(for: id)

    guard information.resolvedRevision != installation.resolvedRevision else {
      return localState
    }

    return .updateAvailable(
      installed: installation,
      availableRevision: information.resolvedRevision
    )
  }

  public func install(
    _ id: String,
    progressHandler: ProgressHandler? = nil
  ) async throws -> LocalModelInstallation {
    let model = try model(identifiedBy: id)

    guard installationTasks[id] == nil else {
      throw LocalModelError.installationInProgress(id)
    }

    let existingInstallation: LocalModelInstallation?

    do {
      existingInstallation = try localInstallation(for: model)
    } catch LocalModelError.invalidInstallation {
      existingInstallation = nil
    }

    if let existingInstallation,
      model.revision == existingInstallation.resolvedRevision
    {
      return existingInstallation
    }

    let initialProgress = LocalModelDownloadProgress(
      phase: .preparing,
      totalBytes: model.expectedDownloadSize
    )
    progressByModelID[id] = initialProgress

    if let progressHandler {
      await progressHandler(initialProgress)
    }

    let task = Task { [client, storageDirectory] in
      try await Self.performInstallation(
        of: model,
        existingInstallation: existingInstallation,
        client: client,
        storageDirectory: storageDirectory,
        progressHandler: progressHandler,
        stateHandler: { progress in
          await self.recordProgress(
            progress,
            for: id
          )
        }
      )
    }

    installationTasks[id] = task

    do {
      let installation = try await withTaskCancellationHandler {
        try await task.value
      } onCancel: {
        task.cancel()
      }

      installationTasks[id] = nil
      progressByModelID[id] = nil
      return installation
    } catch {
      installationTasks[id] = nil
      progressByModelID[id] = nil

      if error is CancellationError {
        throw LocalModelError.installationCancelled(id)
      }

      throw error
    }
  }

  public func cancelInstallation(
    of id: String
  ) throws {
    _ = try model(identifiedBy: id)
    installationTasks[id]?.cancel()
  }

  public func removeModel(
    identifiedBy id: String
  ) async throws {
    let model = try model(identifiedBy: id)

    if let task = installationTasks[id] {
      task.cancel()
      _ = try? await task.value
      installationTasks[id] = nil
      progressByModelID[id] = nil
    }

    let directory = modelDirectory(for: model)

    guard FileManager.default.fileExists(atPath: directory.path) else {
      return
    }

    do {
      try FileManager.default.removeItem(at: directory)
    } catch {
      throw LocalModelError.fileSystemFailure(
        error.localizedDescription
      )
    }
  }
}

extension HuggingFaceModelProvider {
  fileprivate static let manifestFilename = ".appleagentkit-installation.json"

  fileprivate func recordProgress(
    _ progress: LocalModelDownloadProgress,
    for id: String
  ) {
    guard installationTasks[id] != nil else {
      return
    }

    progressByModelID[id] = progress
  }

  fileprivate func localInstallation(
    for model: HuggingFaceModel
  ) throws -> LocalModelInstallation? {
    let modelDirectory = modelDirectory(for: model)

    guard
      FileManager.default.fileExists(
        atPath: modelDirectory.path
      )
    else {
      return nil
    }

    let manifestURL = modelDirectory.appending(
      path: Self.manifestFilename,
      directoryHint: .notDirectory
    )

    guard FileManager.default.fileExists(atPath: manifestURL.path) else {
      throw LocalModelError.invalidInstallation(
        "The installation manifest is missing for model '\(model.id)'."
      )
    }

    let manifest: HuggingFaceInstallationManifest

    do {
      let data = try Data(contentsOf: manifestURL)
      manifest = try JSONDecoder().decode(
        HuggingFaceInstallationManifest.self,
        from: data
      )
    } catch {
      throw LocalModelError.invalidInstallation(
        "The installation manifest for model '\(model.id)' could not be decoded."
      )
    }

    guard manifest.schemaVersion == HuggingFaceInstallationManifest.currentSchemaVersion,
      manifest.modelID == model.id,
      manifest.repositoryID == model.repositoryID,
      Self.isCommitHash(manifest.resolvedRevision)
    else {
      throw LocalModelError.invalidInstallation(
        "The installation manifest does not match model '\(model.id)'."
      )
    }

    let revisionDirectory = modelDirectory.appending(
      path: manifest.resolvedRevision,
      directoryHint: .isDirectory
    )

    try Self.validateInstalledFiles(
      manifest.files,
      in: revisionDirectory,
      modelID: model.id
    )

    return LocalModelInstallation(
      modelID: manifest.modelID,
      repositoryID: manifest.repositoryID,
      requestedRevision: manifest.requestedRevision,
      resolvedRevision: manifest.resolvedRevision,
      localURL: revisionDirectory,
      installedAt: manifest.installedAt,
      files: manifest.files
    )
  }

  fileprivate func modelDirectory(
    for model: HuggingFaceModel
  ) -> URL {
    storageDirectory.appending(
      path: Self.fileSystemIdentifier(for: model.id),
      directoryHint: .isDirectory
    )
  }

  fileprivate static func fetchInformation(
    for model: HuggingFaceModel,
    client: HubClient
  ) async throws -> LocalModelInformation {
    guard let repositoryID = Repo.ID(rawValue: model.repositoryID) else {
      throw LocalModelError.invalidRepositoryID(model.repositoryID)
    }

    let remoteModel: Model

    do {
      remoteModel = try await client.getModel(
        repositoryID,
        revision: model.revision,
        full: true,
        filesMetadata: true
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      if Task.isCancelled {
        throw CancellationError()
      }

      throw LocalModelError.providerFailure(
        error.localizedDescription
      )
    }

    guard let resolvedRevision = remoteModel.sha,
      isCommitHash(resolvedRevision)
    else {
      throw LocalModelError.unavailableRevision(
        repositoryID: model.repositoryID,
        revision: model.revision
      )
    }

    let files = (remoteModel.siblings ?? [])
      .filter { sibling in
        model.matchingFiles.isEmpty
          || model.matchingFiles.contains { pattern in
            GlobMatcher.matches(
              sibling.relativeFilename,
              pattern: pattern
            )
          }
      }
      .map {
        LocalModelFileInformation(
          path: $0.relativeFilename,
          size: $0.size.map(Int64.init)
        )
      }
      .sorted { $0.path < $1.path }

    guard !files.isEmpty else {
      throw LocalModelError.noMatchingFiles(model.id)
    }

    guard files.allSatisfy({ isSafeRelativePath($0.path) }) else {
      throw LocalModelError.providerFailure(
        "Hugging Face returned an unsafe artifact path."
      )
    }

    let knownSize: Int64? =
      if files.allSatisfy({ $0.size != nil }) {
        files.reduce(into: Int64(0)) {
          $0 += $1.size ?? 0
        }
      } else {
        model.expectedDownloadSize
      }

    let access: LocalModelInformation.Access =
      switch remoteModel.gated {
      case .auto:
        .gatedAutomatic
      case .manual:
        .gatedManual
      case .notGated, nil:
        .publicAccess
      }

    return LocalModelInformation(
      modelID: model.id,
      repositoryID: model.repositoryID,
      requestedRevision: model.revision,
      resolvedRevision: resolvedRevision,
      lastModified: remoteModel.lastModified,
      access: access,
      files: files,
      downloadSize: knownSize
    )
  }

  fileprivate static func performInstallation(
    of model: HuggingFaceModel,
    existingInstallation: LocalModelInstallation?,
    client: HubClient,
    storageDirectory: URL,
    progressHandler: ProgressHandler?,
    stateHandler:
      @escaping @Sendable (
        LocalModelDownloadProgress
      ) async -> Void
  ) async throws -> LocalModelInstallation {
    try Task.checkCancellation()

    let information = try await fetchInformation(
      for: model,
      client: client
    )

    if let existingInstallation,
      existingInstallation.resolvedRevision == information.resolvedRevision
    {
      return existingInstallation
    }

    let preparing = LocalModelDownloadProgress(
      phase: .preparing,
      totalBytes: information.downloadSize
    )
    await stateHandler(preparing)

    if let progressHandler {
      await progressHandler(preparing)
    }

    let fileManager = FileManager.default

    do {
      try fileManager.createDirectory(
        at: storageDirectory,
        withIntermediateDirectories: true
      )
    } catch {
      throw LocalModelError.fileSystemFailure(
        error.localizedDescription
      )
    }

    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    var persistentStorageDirectory = storageDirectory
    try? persistentStorageDirectory.setResourceValues(resourceValues)

    try verifyAvailableStorage(
      for: information.downloadSize,
      at: storageDirectory
    )

    let stagingRoot =
      storageDirectory
      .appending(path: ".staging", directoryHint: .isDirectory)
    let stagingDirectory = stagingRoot.appending(
      path: UUID().uuidString,
      directoryHint: .isDirectory
    )

    do {
      try fileManager.createDirectory(
        at: stagingRoot,
        withIntermediateDirectories: true
      )
    } catch {
      throw LocalModelError.fileSystemFailure(
        error.localizedDescription
      )
    }

    defer {
      try? fileManager.removeItem(at: stagingDirectory)
    }

    guard let repositoryID = Repo.ID(rawValue: model.repositoryID) else {
      throw LocalModelError.invalidRepositoryID(model.repositoryID)
    }

    let downloadedDirectory: URL

    do {
      downloadedDirectory = try await client.downloadSnapshot(
        of: repositoryID,
        to: stagingDirectory,
        revision: information.resolvedRevision,
        matching: model.matchingFiles,
        progressHandler: { progress in
          let total =
            progress.totalUnitCount > 0
            ? progress.totalUnitCount
            : nil
          let update = LocalModelDownloadProgress(
            phase: .downloading,
            receivedBytes: progress.completedUnitCount,
            totalBytes: total
          )

          Task {
            await stateHandler(update)
          }

          progressHandler?(update)
        }
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      if Task.isCancelled {
        throw CancellationError()
      }

      throw LocalModelError.providerFailure(
        error.localizedDescription
      )
    }

    try Task.checkCancellation()

    let installing = LocalModelDownloadProgress(
      phase: .installing,
      receivedBytes: information.downloadSize ?? 0,
      totalBytes: information.downloadSize
    )
    await stateHandler(installing)

    if let progressHandler {
      await progressHandler(installing)
    }

    let installedAt = Date()
    let files = information.files.map(\.path)
    try validateInstalledFiles(
      files,
      in: downloadedDirectory,
      modelID: model.id
    )

    let manifest = HuggingFaceInstallationManifest(
      modelID: model.id,
      repositoryID: model.repositoryID,
      requestedRevision: model.revision,
      resolvedRevision: information.resolvedRevision,
      installedAt: installedAt,
      files: files
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    let manifestData: Data

    do {
      manifestData = try encoder.encode(manifest)
      try manifestData.write(
        to: downloadedDirectory.appending(
          path: manifestFilename,
          directoryHint: .notDirectory
        ),
        options: .atomic
      )
    } catch {
      throw LocalModelError.fileSystemFailure(
        error.localizedDescription
      )
    }

    let modelDirectory = storageDirectory.appending(
      path: fileSystemIdentifier(for: model.id),
      directoryHint: .isDirectory
    )
    let finalDirectory = modelDirectory.appending(
      path: information.resolvedRevision,
      directoryHint: .isDirectory
    )

    do {
      try fileManager.createDirectory(
        at: modelDirectory,
        withIntermediateDirectories: true
      )

      if fileManager.fileExists(atPath: finalDirectory.path) {
        try fileManager.removeItem(at: finalDirectory)
      }

      try fileManager.moveItem(
        at: downloadedDirectory,
        to: finalDirectory
      )

      try manifestData.write(
        to: modelDirectory.appending(
          path: manifestFilename,
          directoryHint: .notDirectory
        ),
        options: .atomic
      )
    } catch {
      throw LocalModelError.fileSystemFailure(
        error.localizedDescription
      )
    }

    return LocalModelInstallation(
      modelID: model.id,
      repositoryID: model.repositoryID,
      requestedRevision: model.revision,
      resolvedRevision: information.resolvedRevision,
      localURL: finalDirectory,
      installedAt: installedAt,
      files: files
    )
  }

  fileprivate static func verifyAvailableStorage(
    for downloadSize: Int64?,
    at directory: URL
  ) throws {
    guard let downloadSize,
      downloadSize > 0
    else {
      return
    }

    let required: Int64
    let doubled = downloadSize.multipliedReportingOverflow(by: 2)
    required = doubled.overflow ? Int64.max : doubled.partialValue

    guard
      let values = try? directory.resourceValues(
        forKeys: [.volumeAvailableCapacityForImportantUsageKey]
      ),
      let available = values.volumeAvailableCapacityForImportantUsage,
      available < required
    else {
      return
    }

    throw LocalModelError.insufficientStorage(
      required: required,
      available: available
    )
  }

  fileprivate static func validateInstalledFiles(
    _ files: [String],
    in directory: URL,
    modelID: String
  ) throws {
    guard !files.isEmpty else {
      throw LocalModelError.invalidInstallation(
        "No artifacts were recorded for model '\(modelID)'."
      )
    }

    for file in files {
      guard isSafeRelativePath(file),
        FileManager.default.fileExists(
          atPath: directory.appending(path: file).path
        )
      else {
        throw LocalModelError.invalidInstallation(
          "Required artifact '\(file)' is missing for model '\(modelID)'."
        )
      }
    }
  }

  fileprivate static func isSafeRelativePath(
    _ path: String
  ) -> Bool {
    guard !path.isEmpty,
      !path.hasPrefix("/"),
      !path.contains("\\"),
      !path.contains("\0")
    else {
      return false
    }

    return path.split(
      separator: "/",
      omittingEmptySubsequences: false
    ).allSatisfy {
      !$0.isEmpty && $0 != "." && $0 != ".."
    }
  }

  fileprivate static func isCommitHash(
    _ value: String
  ) -> Bool {
    value.count == 40 && value.allSatisfy(\.isHexDigit)
  }

  fileprivate static func fileSystemIdentifier(
    for value: String
  ) -> String {
    value.utf8.map {
      String(format: "%02x", $0)
    }.joined()
  }
}

private enum GlobMatcher {
  static func matches(
    _ value: String,
    pattern: String
  ) -> Bool {
    let value = Array(value)
    let pattern = Array(pattern)
    var row = Array(repeating: false, count: pattern.count + 1)
    row[0] = true

    for patternIndex in pattern.indices where pattern[patternIndex] == "*" {
      guard row[patternIndex] else {
        break
      }
      row[patternIndex + 1] = true
    }

    for character in value {
      var next = Array(repeating: false, count: pattern.count + 1)

      for patternIndex in pattern.indices {
        switch pattern[patternIndex] {
        case "*":
          next[patternIndex + 1] =
            next[patternIndex]
            || row[patternIndex + 1]
        case "?":
          next[patternIndex + 1] = row[patternIndex]
        default:
          next[patternIndex + 1] =
            row[patternIndex]
            && pattern[patternIndex] == character
        }
      }

      row = next
    }

    return row[pattern.count]
  }
}
