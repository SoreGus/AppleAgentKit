//
//  HuggingFaceBackgroundDownloadTransport.swift
//  AppleAgentKit
//

import Foundation

/// Configuration for persistent Hugging Face downloads.
public struct HuggingFaceBackgroundDownloadConfiguration: Hashable, Sendable {
  /// A configuration that derives a stable session identifier from the app and storage directory.
  public static let automatic = Self()

  /// The identifier passed to `URLSessionConfiguration.background(withIdentifier:)`.
  ///
  /// Leave this value `nil` to let AppleAgentKit derive a stable identifier. Apps that use more
  /// than one provider should either use distinct storage directories or distinct identifiers.
  public let sessionIdentifier: String?
  public let isDiscretionary: Bool
  public let allowsCellularAccess: Bool

  public init(
    sessionIdentifier: String? = nil,
    isDiscretionary: Bool = false,
    allowsCellularAccess: Bool = true
  ) {
    self.sessionIdentifier = sessionIdentifier
    self.isDiscretionary = isDiscretionary
    self.allowsCellularAccess = allowsCellularAccess
  }
}

/// A resolved snapshot request supplied to an injected model download transport.
public struct HuggingFaceModelDownloadRequest: Hashable, Sendable {
  public let modelID: String
  public let repositoryID: String
  public let resolvedRevision: String
  public let files: [LocalModelFileInformation]
  public let host: URL
  public let bearerToken: String?
  public let userAgent: String?

  public init(
    modelID: String,
    repositoryID: String,
    resolvedRevision: String,
    files: [LocalModelFileInformation],
    host: URL,
    bearerToken: String? = nil,
    userAgent: String? = nil
  ) {
    self.modelID = modelID
    self.repositoryID = repositoryID
    self.resolvedRevision = resolvedRevision
    self.files = files
    self.host = host
    self.bearerToken = bearerToken
    self.userAgent = userAgent
  }
}

/// An injectable transport used by `HuggingFaceModelProvider` to download a resolved snapshot.
public protocol HuggingFaceModelDownloadTransport: Sendable {
  /// The background session identifier, or `nil` for a foreground-only transport.
  var backgroundSessionIdentifier: String? { get }

  /// Downloads all requested files into a directory that the provider can validate and promote.
  func download(
    _ request: HuggingFaceModelDownloadRequest,
    progressHandler: @escaping @Sendable (LocalModelDownloadProgress) async -> Void
  ) async throws -> URL

  /// Cancels all transfer work associated with a model.
  func cancel(modelID: String) async
}

/// Connects app lifecycle callbacks to AppleAgentKit's persistent URL sessions.
///
/// Forward `application(_:handleEventsForBackgroundURLSession:completionHandler:)` here. The
/// callback may arrive before the provider is recreated; it is retained until that provider
/// reconnects to the session and Foundation finishes delivering its events.
public enum HuggingFaceBackgroundDownloadEvents {
  @discardableResult
  public static func handleEvents(
    forBackgroundURLSession identifier: String,
    completionHandler: @escaping @Sendable () -> Void
  ) -> Bool {
    BackgroundSessionEventRegistry.shared.register(
      identifier: identifier,
      completionHandler: completionHandler
    )
  }
}

internal struct HuggingFaceBackgroundDownloadState: Codable, Sendable {
  static let currentSchemaVersion = 1

  let schemaVersion: Int
  let modelID: String
  let repositoryID: String
  let resolvedRevision: String
  let files: [PersistedFile]
  var completedPaths: Set<String>
  var receivedBytesByPath: [String: Int64]

  struct PersistedFile: Codable, Hashable, Sendable {
    let path: String
    let size: Int64?
  }

  init(request: HuggingFaceModelDownloadRequest) {
    schemaVersion = Self.currentSchemaVersion
    modelID = request.modelID
    repositoryID = request.repositoryID
    resolvedRevision = request.resolvedRevision
    files = request.files.map { PersistedFile(path: $0.path, size: $0.size) }
    completedPaths = []
    receivedBytesByPath = [:]
  }

  var progress: LocalModelDownloadProgress {
    let received = files.reduce(into: Int64(0)) { result, file in
      if completedPaths.contains(file.path), let size = file.size {
        result += size
      } else {
        result += receivedBytesByPath[file.path] ?? 0
      }
    }
    let total: Int64? = files.allSatisfy { $0.size != nil }
      ? files.reduce(into: Int64(0)) { $0 += $1.size ?? 0 }
      : nil
    return LocalModelDownloadProgress(
      phase: completedPaths.count == files.count ? .installing : .downloading,
      receivedBytes: received,
      totalBytes: total
    )
  }
}

internal enum HuggingFaceBackgroundDownloadStateStore {
  static let directoryName = ".background-downloads"

  static func stateURL(modelID: String, storageDirectory: URL) -> URL {
    storageDirectory
      .appending(path: directoryName, directoryHint: .isDirectory)
      .appending(
        path: HuggingFaceModelProvider.fileSystemIdentifier(for: modelID) + ".json",
        directoryHint: .notDirectory
      )
  }

  static func load(modelID: String, storageDirectory: URL) -> HuggingFaceBackgroundDownloadState? {
    let url = stateURL(modelID: modelID, storageDirectory: storageDirectory)
    guard let data = try? Data(contentsOf: url),
      let state = try? JSONDecoder().decode(HuggingFaceBackgroundDownloadState.self, from: data),
      state.schemaVersion == HuggingFaceBackgroundDownloadState.currentSchemaVersion,
      state.modelID == modelID
    else {
      return nil
    }
    return state
  }

  static func save(_ state: HuggingFaceBackgroundDownloadState, storageDirectory: URL) throws {
    let url = stateURL(modelID: state.modelID, storageDirectory: storageDirectory)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(state).write(to: url, options: .atomic)
  }

  static func remove(modelID: String, storageDirectory: URL) {
    try? FileManager.default.removeItem(
      at: stateURL(modelID: modelID, storageDirectory: storageDirectory)
    )
  }
}

private final class BackgroundSessionEventRegistry: @unchecked Sendable {
  static let shared = BackgroundSessionEventRegistry()

  private let lock = NSLock()
  private var handlers: [String: @Sendable () -> Void] = [:]

  private var knownIdentifiers: Set<String> = []

  @discardableResult
  func register(
    identifier: String,
    completionHandler: @escaping @Sendable () -> Void
  ) -> Bool {
    lock.withLock {
      guard knownIdentifiers.contains(identifier)
        || identifier.contains(".AppleAgentKit.HuggingFace.")
      else { return false }
      handlers[identifier] = completionHandler
      return true
    }
  }

  func recognize(identifier: String) {
    _ = lock.withLock {
      knownIdentifiers.insert(identifier)
    }
  }

  func complete(identifier: String) {
    let handler = lock.withLock { handlers.removeValue(forKey: identifier) }
    handler?()
  }
}

#if canImport(Darwin)
internal actor URLSessionHuggingFaceBackgroundTransport: HuggingFaceModelDownloadTransport {
  nonisolated let backgroundSessionIdentifier: String?

  private let storageDirectory: URL
  private let delegate: Delegate
  private let session: URLSession
  private var didRestoreTasks = false
  private var tasksByModelID: [String: [String: URLSessionDownloadTask]] = [:]
  private var stateByModelID: [String: HuggingFaceBackgroundDownloadState] = [:]
  private var lastStatePersistenceByModelID: [String: Date] = [:]
  private var waiters: [String: CheckedContinuation<URL, any Error>] = [:]
  private var progressHandlers:
    [String: @Sendable (LocalModelDownloadProgress) async -> Void] = [:]

  init(
    storageDirectory: URL,
    configuration: HuggingFaceBackgroundDownloadConfiguration
  ) {
    let identifier = configuration.sessionIdentifier
      ?? Self.defaultIdentifier(storageDirectory: storageDirectory)
    let delegate = Delegate(storageDirectory: storageDirectory, sessionIdentifier: identifier)
    let sessionConfiguration = URLSessionConfiguration.background(withIdentifier: identifier)
    sessionConfiguration.isDiscretionary = configuration.isDiscretionary
    sessionConfiguration.allowsCellularAccess = configuration.allowsCellularAccess
    sessionConfiguration.sessionSendsLaunchEvents = true

    self.backgroundSessionIdentifier = identifier
    self.storageDirectory = storageDirectory
    self.delegate = delegate
    self.session = URLSession(
      configuration: sessionConfiguration,
      delegate: delegate,
      delegateQueue: delegate.queue
    )
    delegate.owner = self
    BackgroundSessionEventRegistry.shared.recognize(identifier: identifier)
  }

  func download(
    _ request: HuggingFaceModelDownloadRequest,
    progressHandler: @escaping @Sendable (LocalModelDownloadProgress) async -> Void
  ) async throws -> URL {
    try Task.checkCancellation()
    try await restoreTasksIfNeeded()

    var state = HuggingFaceBackgroundDownloadStateStore.load(
      modelID: request.modelID,
      storageDirectory: storageDirectory
    )

    if let existingState = state,
      existingState.repositoryID != request.repositoryID
        || existingState.resolvedRevision != request.resolvedRevision
        || existingState.files != request.files.map({ .init(path: $0.path, size: $0.size) })
    {
      await cancel(modelID: request.modelID)
      self.removeStagingDirectory(for: existingState)
      HuggingFaceBackgroundDownloadStateStore.remove(
        modelID: request.modelID,
        storageDirectory: storageDirectory
      )
      self.tasksByModelID[request.modelID] = nil
      state = nil
    }

    var activeState = state ?? HuggingFaceBackgroundDownloadState(request: request)
    try reconcileCompletedFiles(in: &activeState)
    try HuggingFaceBackgroundDownloadStateStore.save(
      activeState,
      storageDirectory: storageDirectory
    )
    stateByModelID[request.modelID] = activeState
    lastStatePersistenceByModelID[request.modelID] = Date()
    progressHandlers[request.modelID] = progressHandler
    await progressHandler(activeState.progress)

    if activeState.completedPaths.count == activeState.files.count {
      progressHandlers[request.modelID] = nil
      return stagingDirectory(for: activeState)
    }

    var modelTasks = tasksByModelID[request.modelID] ?? [:]
    for file in request.files where !activeState.completedPaths.contains(file.path) {
      guard modelTasks[file.path] == nil else { continue }
      let task = session.downloadTask(with: try makeURLRequest(for: file.path, request: request))
      task.taskDescription = TaskDescription(modelID: request.modelID, path: file.path).encoded
      modelTasks[file.path] = task
      task.resume()
    }
    tasksByModelID[request.modelID] = modelTasks

    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        waiters[request.modelID] = continuation
      }
    } onCancel: {
      Task { await self.cancel(modelID: request.modelID) }
    }
  }

  func cancel(modelID: String) async {
    try? await restoreTasksIfNeeded()
    for task in tasksByModelID[modelID]?.values ?? [:].values {
      task.cancel()
    }
    tasksByModelID[modelID] = nil
    stateByModelID[modelID] = nil
    lastStatePersistenceByModelID[modelID] = nil
    progressHandlers[modelID] = nil
    if let state = HuggingFaceBackgroundDownloadStateStore.load(
      modelID: modelID,
      storageDirectory: storageDirectory
    ) {
      removeStagingDirectory(for: state)
    }
    HuggingFaceBackgroundDownloadStateStore.remove(
      modelID: modelID,
      storageDirectory: storageDirectory
    )
    waiters.removeValue(forKey: modelID)?.resume(throwing: CancellationError())
  }

  fileprivate func didWriteData(
    modelID: String,
    path: String,
    receivedBytes: Int64
  ) async {
    guard var state = stateByModelID[modelID]
      ?? HuggingFaceBackgroundDownloadStateStore.load(
        modelID: modelID,
        storageDirectory: storageDirectory
      )
    else { return }

    state.receivedBytesByPath[path] = receivedBytes
    stateByModelID[modelID] = state
    let now = Date()
    if now.timeIntervalSince(lastStatePersistenceByModelID[modelID] ?? .distantPast) >= 1 {
      try? HuggingFaceBackgroundDownloadStateStore.save(
        state,
        storageDirectory: storageDirectory
      )
      lastStatePersistenceByModelID[modelID] = now
    }
    if let handler = progressHandlers[modelID] {
      await handler(state.progress)
    }
  }

  fileprivate func didFinishDownload(modelID: String, path: String) async {
    guard var state = stateByModelID[modelID]
      ?? HuggingFaceBackgroundDownloadStateStore.load(
        modelID: modelID,
        storageDirectory: storageDirectory
      )
    else { return }

    state.completedPaths.insert(path)
    state.receivedBytesByPath[path] = nil
    stateByModelID[modelID] = state
    do {
      try HuggingFaceBackgroundDownloadStateStore.save(state, storageDirectory: storageDirectory)
      tasksByModelID[modelID]?[path] = nil
      if let handler = progressHandlers[modelID] {
        await handler(state.progress)
      }
      if state.completedPaths.count == state.files.count {
        tasksByModelID[modelID] = nil
        stateByModelID[modelID] = nil
        lastStatePersistenceByModelID[modelID] = nil
        progressHandlers[modelID] = nil
        waiters.removeValue(forKey: modelID)?.resume(returning: stagingDirectory(for: state))
      }
    } catch {
      didFail(modelID: modelID, error: error)
    }
  }

  fileprivate func didFail(modelID: String, error: any Error) {
    if let state = stateByModelID[modelID] {
      try? HuggingFaceBackgroundDownloadStateStore.save(
        state,
        storageDirectory: storageDirectory
      )
    }
    for task in tasksByModelID[modelID]?.values ?? [:].values {
      task.cancel()
    }
    tasksByModelID[modelID] = nil
    stateByModelID[modelID] = nil
    lastStatePersistenceByModelID[modelID] = nil
    progressHandlers[modelID] = nil
    waiters.removeValue(forKey: modelID)?.resume(throwing: error)
  }

  private func restoreTasksIfNeeded() async throws {
    guard !didRestoreTasks else { return }
    didRestoreTasks = true
    let tasks = await session.allTasks
    for case let task as URLSessionDownloadTask in tasks {
      guard let description = TaskDescription(task.taskDescription) else {
        task.cancel()
        continue
      }
      tasksByModelID[description.modelID, default: [:]][description.path] = task
      if task.state == .suspended {
        task.resume()
      }
    }
  }

  private func reconcileCompletedFiles(in state: inout HuggingFaceBackgroundDownloadState) throws {
    let directory = stagingDirectory(for: state)
    for file in state.files {
      let url = directory.appending(path: file.path, directoryHint: .notDirectory)
      guard FileManager.default.fileExists(atPath: url.path) else {
        state.completedPaths.remove(file.path)
        continue
      }
      if let size = file.size {
        let actual = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init)
        guard actual == size else {
          try? FileManager.default.removeItem(at: url)
          state.completedPaths.remove(file.path)
          continue
        }
      }
      state.completedPaths.insert(file.path)
    }
  }

  private func makeURLRequest(
    for path: String,
    request: HuggingFaceModelDownloadRequest
  ) throws -> URLRequest {
    let components = request.repositoryID.split(separator: "/", maxSplits: 1).map(String.init)
    guard components.count == 2 else {
      throw LocalModelError.invalidRepositoryID(request.repositoryID)
    }
    let url = request.host
      .appending(path: components[0])
      .appending(path: components[1])
      .appending(path: "resolve")
      .appending(path: request.resolvedRevision)
      .appending(path: path)
    var urlRequest = URLRequest(url: url)
    if let bearerToken = request.bearerToken {
      urlRequest.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
    }
    if let userAgent = request.userAgent {
      urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    }
    return urlRequest
  }

  private func stagingDirectory(for state: HuggingFaceBackgroundDownloadState) -> URL {
    storageDirectory
      .appending(path: ".staging", directoryHint: .isDirectory)
      .appending(path: "background", directoryHint: .isDirectory)
      .appending(
        path: HuggingFaceModelProvider.fileSystemIdentifier(for: state.modelID),
        directoryHint: .isDirectory
      )
      .appending(path: state.resolvedRevision, directoryHint: .isDirectory)
  }

  private func removeStagingDirectory(for state: HuggingFaceBackgroundDownloadState) {
    try? FileManager.default.removeItem(at: stagingDirectory(for: state))
  }

  private nonisolated static func defaultIdentifier(storageDirectory: URL) -> String {
    let bundle = Bundle.main.bundleIdentifier ?? "org.openai.AppleAgentKit.host"
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in storageDirectory.standardizedFileURL.path.utf8 {
      hash ^= UInt64(byte)
      hash &*= 1_099_511_628_211
    }
    return "\(bundle).AppleAgentKit.HuggingFace.\(String(hash, radix: 16))"
  }

  private struct TaskDescription: Codable {
    let modelID: String
    let path: String

    init(modelID: String, path: String) {
      self.modelID = modelID
      self.path = path
    }

    init?(_ encoded: String?) {
      guard let encoded,
        let data = encoded.data(using: .utf8),
        let value = try? JSONDecoder().decode(Self.self, from: data)
      else { return nil }
      self = value
    }

    var encoded: String? {
      guard let data = try? JSONEncoder().encode(self) else { return nil }
      return String(data: data, encoding: .utf8)
    }
  }

  fileprivate final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    weak var owner: URLSessionHuggingFaceBackgroundTransport?
    let queue: OperationQueue
    private let storageDirectory: URL
    private let sessionIdentifier: String

    init(storageDirectory: URL, sessionIdentifier: String) {
      self.storageDirectory = storageDirectory
      self.sessionIdentifier = sessionIdentifier
      queue = OperationQueue()
      queue.maxConcurrentOperationCount = 1
      super.init()
    }

    func urlSession(
      _ session: URLSession,
      downloadTask: URLSessionDownloadTask,
      didWriteData bytesWritten: Int64,
      totalBytesWritten: Int64,
      totalBytesExpectedToWrite: Int64
    ) {
      guard let description = TaskDescription(downloadTask.taskDescription) else { return }
      Task {
        await owner?.didWriteData(
          modelID: description.modelID,
          path: description.path,
          receivedBytes: totalBytesWritten
        )
      }
    }

    func urlSession(
      _ session: URLSession,
      downloadTask: URLSessionDownloadTask,
      didFinishDownloadingTo location: URL
    ) {
      guard let description = TaskDescription(downloadTask.taskDescription) else { return }
      do {
        guard let response = downloadTask.response as? HTTPURLResponse,
          (200..<300).contains(response.statusCode)
        else {
          throw LocalModelError.providerFailure(
            "The background download returned an invalid HTTP response."
          )
        }
        let state = HuggingFaceBackgroundDownloadStateStore.load(
          modelID: description.modelID,
          storageDirectory: storageDirectory
        )
        guard let state else { return }
        let destination = storageDirectory
          .appending(path: ".staging", directoryHint: .isDirectory)
          .appending(path: "background", directoryHint: .isDirectory)
          .appending(
            path: HuggingFaceModelProvider.fileSystemIdentifier(for: state.modelID),
            directoryHint: .isDirectory
          )
          .appending(path: state.resolvedRevision, directoryHint: .isDirectory)
          .appending(path: description.path, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
          at: destination.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: location, to: destination)
        Task {
          await owner?.didFinishDownload(
            modelID: description.modelID,
            path: description.path
          )
        }
      } catch {
        Task { await owner?.didFail(modelID: description.modelID, error: error) }
      }
    }

    func urlSession(
      _ session: URLSession,
      task: URLSessionTask,
      didCompleteWithError error: (any Error)?
    ) {
      guard let error,
        let description = TaskDescription(task.taskDescription)
      else { return }
      Task { await owner?.didFail(modelID: description.modelID, error: error) }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
      BackgroundSessionEventRegistry.shared.complete(identifier: sessionIdentifier)
    }
  }
}
#endif
