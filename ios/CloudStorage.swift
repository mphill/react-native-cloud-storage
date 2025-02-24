import Foundation

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
