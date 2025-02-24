import CloudKit
import Foundation

// Type aliases for React Native promise blocks
typealias RCTPromiseResolveBlock = (Any?) -> Void
typealias RCTPromiseRejectBlock = (String?, String?, Error?) -> Void

// Error handling
enum CloudStorageError: Error {
  case fileAlreadyExists(path: String)
  case fileNotFound(path: String)
  case unknown(message: String = "An unknown error occurred")

  var code: String {
    switch self {
    case .fileAlreadyExists: return "FILE_EXISTS"
    case .fileNotFound: return "FILE_NOT_FOUND"
    case .unknown: return "UNKNOWN_ERROR"
    }
  }

  var localizedDescription: String {
    switch self {
    case .fileAlreadyExists(let path): return "File already exists at path: \(path)"
    case .fileNotFound(let path): return "File not found at path: \(path)"
    case .unknown(let message): return message
    }
  }
}

// Directory scope enum
enum DirectoryScope: String {
  case appData = "APP_DATA"
  case documents = "DOCUMENTS"
  case cache = "CACHE"
}

// Utility function to handle promises
func withPromise<T>(
  resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock,
  block: () throws -> T
) {
  do {
    let result = try block()
    resolve(result)
  } catch let error as CloudStorageError {
    reject(error.code, error.localizedDescription, error)
  } catch {
    let unknownError = CloudStorageError.unknown(message: error.localizedDescription)
    reject(unknownError.code, unknownError.localizedDescription, error)
  }
}

// CloudKit utilities
class CloudKitUtils {
  static func getFileURL(path: String, scope: String) throws -> URL {
    guard let directoryScope = DirectoryScope(rawValue: scope) else {
      throw CloudStorageError.unknown(message: "Invalid scope: \(scope)")
    }

    let baseURL: URL
    switch directoryScope {
    case .appData:
      baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first!
    case .documents:
      baseURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    case .cache:
      baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    }

    return baseURL.appendingPathComponent(path)
  }

  static func isCloudKitAvailable() -> Bool {
    return FileManager.default.ubiquityIdentityToken != nil
  }

  static func downloadFile(fileUrl: URL) throws -> String {
    try FileManager.default.startDownloadingUbiquitousItem(at: fileUrl)
    return try FileUtils.readFile(fileUrl: fileUrl)
  }
}

// File utilities
class FileUtils {
  static func checkFileExists(fileUrl: URL) throws -> Bool {
    return FileManager.default.fileExists(atPath: fileUrl.path)
  }

  static func readFile(fileUrl: URL) throws -> String {
    guard FileManager.default.fileExists(atPath: fileUrl.path) else {
      throw CloudStorageError.fileNotFound(path: fileUrl.path)
    }
    return try String(contentsOf: fileUrl, encoding: .utf8)
  }

  static func writeFile(fileUrl: URL, content: String) throws -> String {
    // Create parent directories if needed
    try createDirectory(directoryUrl: fileUrl.deletingLastPathComponent())
    try content.write(to: fileUrl, atomically: true, encoding: .utf8)
    return content
  }

  static func createDirectory(directoryUrl: URL) throws -> Bool {
    try FileManager.default.createDirectory(at: directoryUrl, withIntermediateDirectories: true)
    return true
  }

  static func deleteFileOrDirectory(fileUrl: URL) throws -> Bool {
    if FileManager.default.fileExists(atPath: fileUrl.path) {
      try FileManager.default.removeItem(at: fileUrl)
    }
    return true
  }

  static func listFiles(directoryUrl: URL) throws -> [[String: Any]] {
    let contents = try FileManager.default.contentsOfDirectory(
      at: directoryUrl, includingPropertiesForKeys: nil)
    return try contents.map { url in
      try statFile(fileUrl: url).toDictionary()
    }
  }

  static func statFile(fileUrl: URL) throws -> FileStats {
    let attributes = try FileManager.default.attributesOfItem(atPath: fileUrl.path)
    return FileStats(
      name: fileUrl.lastPathComponent,
      path: fileUrl.path,
      size: attributes[.size] as? Int64 ?? 0,
      type: attributes[.type] as? String ?? "",
      modificationDate: attributes[.modificationDate] as? Date ?? Date()
    )
  }
}

// File stats structure
struct FileStats {
  let name: String
  let path: String
  let size: Int64
  let type: String
  let modificationDate: Date

  func toDictionary() -> [String: Any] {
    return [
      "name": name,
      "path": path,
      "size": size,
      "type": type,
      "modificationDate": Int64(modificationDate.timeIntervalSince1970 * 1000),
    ]
  }
}

// Helper function for getCloudUrl
func getCloudUrl(path: String, scope: DirectoryScope) throws -> URL {
  return try CloudKitUtils.getFileURL(path: path, scope: scope.rawValue)
}

@objc(CloudStorage)
class CloudStorage: NSObject {
  @objc(fileExists:withScope:withResolver:withRejecter:)
  func fileExists(
    path: String, scope: String, resolve: @escaping RCTPromiseResolveBlock,
    reject: @escaping RCTPromiseRejectBlock
  ) {
    withPromise(resolve: resolve, reject: reject) {
      let fileUrl = try CloudKitUtils.getFileURL(path: path, scope: scope)
      return try FileUtils.checkFileExists(fileUrl: fileUrl)
    }
  }

  @objc(appendToFile:withData:withScope:withResolver:withRejecter:)
  func appendToFile(
    path: String, data: String, scope: String, resolve: @escaping RCTPromiseResolveBlock,
    reject: @escaping RCTPromiseRejectBlock
  ) {
    withPromise(resolve: resolve, reject: reject) {
      let fileUrl = try CloudKitUtils.getFileURL(path: path, scope: scope)

      var existingData = ""
      if try FileUtils.checkFileExists(fileUrl: fileUrl) {
        existingData = try FileUtils.readFile(fileUrl: fileUrl)
      }

      let newData = existingData + data
      return try FileUtils.writeFile(fileUrl: fileUrl, content: newData)
    }
  }

  @objc(createFile:withData:withScope:withOverwrite:withResolver:withRejecter:)
  func createFile(
    path: String, data: String, scope: String, overwrite: Bool,
    resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock
  ) {
    withPromise(resolve: resolve, reject: reject) {
      let fileUrl = try CloudKitUtils.getFileURL(path: path, scope: scope)

      if try (FileUtils.checkFileExists(fileUrl: fileUrl) && !overwrite) {
        throw CloudStorageError.fileAlreadyExists(path: path)
      }

      return try FileUtils.writeFile(fileUrl: fileUrl, content: data)
    }
  }

  @objc(createDirectory:withScope:withResolver:withRejecter:)
  func createDirectory(
    path: String, scope: String, resolve: @escaping RCTPromiseResolveBlock,
    reject: @escaping RCTPromiseRejectBlock
  ) {
    withPromise(resolve: resolve, reject: reject) {
      let fileUrl = try CloudKitUtils.getFileURL(path: path, scope: scope)
      return try FileUtils.createDirectory(directoryUrl: fileUrl)
    }
  }

  @objc(listFiles:withScope:withResolver:withRejecter:)
  func listFiles(
    path: String, scope: String, resolve: @escaping RCTPromiseResolveBlock,
    reject: @escaping RCTPromiseRejectBlock
  ) {
    withPromise(resolve: resolve, reject: reject) {
      let fileUrl = try CloudKitUtils.getFileURL(path: path, scope: scope)
      return try FileUtils.listFiles(directoryUrl: fileUrl)
    }
  }

  @objc(readFile:withScope:withResolver:withRejecter:)
  func readFile(
    path: String, scope: String, resolve: @escaping RCTPromiseResolveBlock,
    reject: @escaping RCTPromiseRejectBlock
  ) {
    withPromise(resolve: resolve, reject: reject) {
      let fileUrl = try CloudKitUtils.getFileURL(path: path, scope: scope)
      return try FileUtils.readFile(fileUrl: fileUrl)
    }
  }

  @objc(downloadFile:withScope:withResolver:withRejecter:)
  func downloadFile(
    path: String, scope: String, resolve: @escaping RCTPromiseResolveBlock,
    reject: @escaping RCTPromiseRejectBlock
  ) {
    withPromise(resolve: resolve, reject: reject) {
      let fileUrl = try CloudKitUtils.getFileURL(path: path, scope: scope)
      return try CloudKitUtils.downloadFile(fileUrl: fileUrl)
    }
  }

  @objc(deleteFile:withScope:withResolver:withRejecter:)
  func deleteFile(
    path: String, scope: String, resolve: @escaping RCTPromiseResolveBlock,
    reject: @escaping RCTPromiseRejectBlock
  ) {
    withPromise(resolve: resolve, reject: reject) {
      let fileUrl = try CloudKitUtils.getFileURL(path: path, scope: scope)
      return try FileUtils.deleteFileOrDirectory(fileUrl: fileUrl)
    }
  }

  @objc(deleteDirectory:withRecursive:withScope:withResolver:withRejecter:)
  func deleteDirectory(
    path: String, recursive _: Bool, scope: String, resolve: @escaping RCTPromiseResolveBlock,
    reject: @escaping RCTPromiseRejectBlock
  ) {
    withPromise(resolve: resolve, reject: reject) {
      let fileUrl = try CloudKitUtils.getFileURL(path: path, scope: scope)
      return try FileUtils.deleteFileOrDirectory(fileUrl: fileUrl)
    }
  }

  @objc(statFile:withScope:withResolver:withRejecter:)
  func statFile(
    path: String, scope: String, resolve: @escaping RCTPromiseResolveBlock,
    reject: @escaping RCTPromiseRejectBlock
  ) {
    withPromise(resolve: resolve, reject: reject) {
      let fileUrl = try CloudKitUtils.getFileURL(path: path, scope: scope)
      return try FileUtils.statFile(fileUrl: fileUrl).toDictionary()
    }
  }

  @objc(isCloudAvailable:withRejecter:)
  func isCloudAvailable(
    resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock
  ) {
    withPromise(resolve: resolve, reject: reject) {
      CloudKitUtils.isCloudKitAvailable()
    }
  }

  @objc(createBinaryFile:sourcePath:scope:resolver:rejecter:)
  func createBinaryFile(
    _ remotePath: String,
    sourcePath: String,
    scope: String,
    resolve: @escaping RCTPromiseResolveBlock,
    reject: @escaping RCTPromiseRejectBlock
  ) {
    do {
      let directoryScope = try DirectoryScope(rawValue: scope) ?? .appData
      let remoteUrl = try getCloudUrl(path: remotePath, scope: directoryScope)
      let sourceUrl = URL(fileURLWithPath: sourcePath)

      // Create parent directories if needed
      if let parentUrl = remoteUrl.deletingLastPathComponent() as URL? {
        try FileUtils.createDirectory(directoryUrl: parentUrl)
      }

      // Copy file to iCloud
      try FileManager.default.copyItem(at: sourceUrl, to: remoteUrl)
      resolve(nil)
    } catch let error as CloudStorageError {
      reject(error.code, error.localizedDescription, error)
    } catch {
      reject(CloudStorageError.unknown().code, error.localizedDescription, error)
    }
  }

  @objc(downloadBinaryFile:localDestinationPath:scope:resolver:rejecter:)
  func downloadBinaryFile(
    _ remotePath: String,
    localDestinationPath: String,
    scope: String,
    resolve: @escaping RCTPromiseResolveBlock,
    reject: @escaping RCTPromiseRejectBlock
  ) {
    do {
      let directoryScope = try DirectoryScope(rawValue: scope) ?? .appData
      let remoteUrl = try getCloudUrl(path: remotePath, scope: directoryScope)
      let destinationUrl = URL(fileURLWithPath: localDestinationPath)

      // Create parent directories if needed
      if let parentUrl = destinationUrl.deletingLastPathComponent() as URL? {
        try FileUtils.createDirectory(directoryUrl: parentUrl)
      }

      // Copy file from iCloud
      try FileManager.default.copyItem(at: remoteUrl, to: destinationUrl)
      resolve(nil)
    } catch let error as CloudStorageError {
      reject(error.code, error.localizedDescription, error)
    } catch {
      reject(CloudStorageError.unknown().code, error.localizedDescription, error)
    }
  }
}
