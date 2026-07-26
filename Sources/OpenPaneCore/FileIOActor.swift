import CryptoKit
import Darwin
import Foundation

public struct FileIOConfiguration: Sendable {
    public var editableByteLimit: UInt64
    public var boundedInspectionByteLimit: Int
    public var sampledFingerprintByteCount: Int
    public var recoveryDirectory: URL?

    public init(
        editableByteLimit: UInt64 = 20 * 1_024 * 1_024,
        boundedInspectionByteLimit: Int = 4 * 1_024 * 1_024,
        sampledFingerprintByteCount: Int = 64 * 1_024,
        recoveryDirectory: URL? = nil
    ) {
        self.editableByteLimit = editableByteLimit
        self.boundedInspectionByteLimit = max(1, boundedInspectionByteLimit)
        self.sampledFingerprintByteCount = max(1, sampledFingerprintByteCount)
        self.recoveryDirectory = recoveryDirectory
    }
}

public struct LoadedFile: Sendable {
    public let url: URL
    public let fileIdentity: FileIdentity
    /// Full bytes for normal files; a bounded prefix for large files.
    public let data: Data
    public let decodedText: DecodedText?
    public let classification: FileClassification
    public let fingerprint: FileFingerprint
    public let isBounded: Bool
    public let totalByteCount: UInt64

    public init(
        url: URL,
        fileIdentity: FileIdentity,
        data: Data,
        decodedText: DecodedText?,
        classification: FileClassification,
        fingerprint: FileFingerprint,
        isBounded: Bool,
        totalByteCount: UInt64
    ) {
        self.url = url
        self.fileIdentity = fileIdentity
        self.data = data
        self.decodedText = decodedText
        self.classification = classification
        self.fingerprint = fingerprint
        self.isBounded = isBounded
        self.totalByteCount = totalByteCount
    }
}

public struct SaveReceipt: Codable, Hashable, Sendable {
    public let url: URL
    public let fingerprint: FileFingerprint

    public init(url: URL, fingerprint: FileFingerprint) {
        self.url = url
        self.fingerprint = fingerprint
    }
}

public enum FileIOError: Error, Equatable, LocalizedError, Sendable {
    case notARegularFile(String)
    case unableToRead(String)
    case unableToWrite(String)
    case externalModification(expected: FileFingerprint, actual: FileFingerprint)
    case sourceMissing(String)
    case binaryOverwriteRefused(String)
    case destinationExists(String)

    public var errorDescription: String? {
        switch self {
        case let .notARegularFile(path):
            "“\(path)” is not a regular file."
        case let .unableToRead(message):
            "The file could not be read: \(message)"
        case let .unableToWrite(message):
            "The file could not be saved: \(message)"
        case .externalModification:
            "The file changed outside OpenPane after it was opened."
        case let .sourceMissing(path):
            "The original file no longer exists at “\(path)”."
        case let .binaryOverwriteRefused(path):
            "A text copy cannot replace the original binary file at “\(path)”."
        case let .destinationExists(path):
            "A file already exists at “\(path)”."
        }
    }
}

public actor FileIOActor {
    public let configuration: FileIOConfiguration
    private let classifier: FileClassifier
    private let fileManager: FileManager

    public init(
        configuration: FileIOConfiguration = .init(),
        fileManager: FileManager = .default
    ) {
        self.configuration = configuration
        self.fileManager = fileManager
        classifier = FileClassifier(
            configuration: .init(editableByteLimit: configuration.editableByteLimit)
        )
    }

    public func load(
        url: URL,
        declaredContentTypeIdentifier: String? = nil
    ) throws -> LoadedFile {
        let presentedURL = url.standardizedFileURL
        let targetURL = Self.editTarget(for: presentedURL)
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: targetURL.path)
        } catch {
            throw FileIOError.unableToRead(error.localizedDescription)
        }

        guard (attributes[.type] as? FileAttributeType) == .typeRegular else {
            throw FileIOError.notARegularFile(presentedURL.path)
        }

        let totalByteCount = Self.uint64Attribute(attributes[.size])
        let isBounded = totalByteCount > configuration.editableByteLimit
        let data: Data
        do {
            if isBounded {
                data = try Self.readPrefix(
                    of: targetURL,
                    byteCount: configuration.boundedInspectionByteLimit
                )
            } else {
                data = try Data(contentsOf: targetURL, options: .mappedIfSafe)
            }
        } catch {
            throw FileIOError.unableToRead(error.localizedDescription)
        }

        let fingerprint = try Self.makeFingerprint(
            url: targetURL,
            attributes: attributes,
            coverage: isBounded ? .sampled : .full,
            knownData: isBounded ? nil : data,
            sampleByteCount: configuration.sampledFingerprintByteCount
        )

        let typeIdentifier = declaredContentTypeIdentifier
            ?? (try? presentedURL.resourceValues(forKeys: [.contentTypeKey]))?
                .contentType?
                .identifier
        let classification = classifier.classify(
            data: data,
            filename: presentedURL.lastPathComponent,
            declaredContentTypeIdentifier: typeIdentifier,
            totalByteCount: totalByteCount
        )

        var decodedText: DecodedText?
        switch classification.kind {
        case .markdown, .text:
            decodedText = Self.decodePossiblyBounded(data, isBounded: isBounded)
        case .pdf, .systemPreview, .binary:
            decodedText = nil
        }

        if let value = decodedText {
            var metadata = value.metadata
            let permissions = Self.uint16Attribute(attributes[.posixPermissions])
            metadata.posixPermissions = permissions
            metadata.isExecutable = permissions.map { $0 & 0o111 != 0 } ?? false
            metadata.extendedAttributes = Self.extendedAttributes(of: targetURL)
            metadata.sourceFingerprint = fingerprint
            metadata.originalByteCount = totalByteCount
            decodedText = DecodedText(
                text: value.text,
                originalText: value.originalText,
                originalData: value.originalData,
                metadata: metadata
            )
        }

        return LoadedFile(
            url: presentedURL,
            fileIdentity: FileIdentity(url: presentedURL),
            data: data,
            decodedText: decodedText,
            classification: classification,
            fingerprint: fingerprint,
            isBounded: isBounded,
            totalByteCount: totalByteCount
        )
    }

    public func fingerprint(
        of url: URL,
        coverage: FingerprintCoverage = .full
    ) throws -> FileFingerprint {
        let targetURL = Self.editTarget(for: url.standardizedFileURL)
        guard fileManager.fileExists(atPath: targetURL.path) else {
            throw FileIOError.sourceMissing(url.path)
        }
        let attributes = try fileManager.attributesOfItem(atPath: targetURL.path)
        return try Self.makeFingerprint(
            url: targetURL,
            attributes: attributes,
            coverage: coverage,
            knownData: nil,
            sampleByteCount: configuration.sampledFingerprintByteCount
        )
    }

    public func save(
        text: String,
        decodedText: DecodedText,
        to url: URL,
        expectedFingerprint: FileFingerprint,
        overwriteExternalChanges: Bool = false
    ) throws -> SaveReceipt {
        let data = try TextCodec.encode(
            text,
            metadata: decodedText.metadata,
            originalText: decodedText.originalText,
            originalData: decodedText.originalData
        )
        return try save(
            data: data,
            to: url,
            expectedFingerprint: expectedFingerprint,
            metadata: decodedText.metadata,
            overwriteExternalChanges: overwriteExternalChanges
        )
    }

    public func save(
        data: Data,
        to url: URL,
        expectedFingerprint: FileFingerprint?,
        metadata: TextFileMetadata? = nil,
        overwriteExternalChanges: Bool = false
    ) throws -> SaveReceipt {
        let presentedURL = url.standardizedFileURL
        let targetURL = Self.editTarget(for: presentedURL)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var operationResult: Result<SaveReceipt, Error>?

        coordinator.coordinate(
            writingItemAt: targetURL,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedURL in
            operationResult = Result {
                let targetExists = self.fileManager.fileExists(atPath: coordinatedURL.path)
                if let expectedFingerprint {
                    guard targetExists else {
                        throw FileIOError.sourceMissing(presentedURL.path)
                    }
                    let attributes = try self.fileManager.attributesOfItem(
                        atPath: coordinatedURL.path
                    )
                    let actual = try Self.makeFingerprint(
                        url: coordinatedURL,
                        attributes: attributes,
                        coverage: expectedFingerprint.coverage,
                        knownData: nil,
                        sampleByteCount: self.configuration.sampledFingerprintByteCount
                    )
                    if actual != expectedFingerprint, !overwriteExternalChanges {
                        throw FileIOError.externalModification(
                            expected: expectedFingerprint,
                            actual: actual
                        )
                    }
                }

                try Self.atomicReplace(
                    data: data,
                    targetURL: coordinatedURL,
                    targetExists: targetExists,
                    metadata: metadata,
                    fileManager: self.fileManager
                )
                let attributes = try self.fileManager.attributesOfItem(
                    atPath: coordinatedURL.path
                )
                let fingerprint = try Self.makeFingerprint(
                    url: coordinatedURL,
                    attributes: attributes,
                    coverage: .full,
                    knownData: data,
                    sampleByteCount: self.configuration.sampledFingerprintByteCount
                )
                return SaveReceipt(url: presentedURL, fingerprint: fingerprint)
            }
        }

        if let coordinationError {
            throw FileIOError.unableToWrite(coordinationError.localizedDescription)
        }
        guard let operationResult else {
            throw FileIOError.unableToWrite("The coordinated save did not run.")
        }
        do {
            return try operationResult.get()
        } catch let error as FileIOError {
            throw error
        } catch {
            throw FileIOError.unableToWrite(error.localizedDescription)
        }
    }

    /// Writes a UTF-8 conversion as a new file. This is the only intended save
    /// path for raw binary inspection and it cannot target the original file.
    public func saveTextCopy(
        _ text: String,
        to destinationURL: URL,
        refusingOriginal originalURL: URL
    ) throws -> SaveReceipt {
        let destination = destinationURL.standardizedFileURL
        let original = originalURL.standardizedFileURL
        if Self.editTarget(for: destination) == Self.editTarget(for: original) {
            throw FileIOError.binaryOverwriteRefused(original.path)
        }
        if fileManager.fileExists(atPath: destination.path) {
            throw FileIOError.destinationExists(destination.path)
        }
        guard let data = text.data(using: .utf8) else {
            throw FileIOError.unableToWrite("The text copy could not be encoded as UTF-8.")
        }
        return try save(
            data: data,
            to: destination,
            expectedFingerprint: nil,
            metadata: TextFileMetadata(
                encoding: .utf8,
                lineEndings: TextCodec.lineEndingConvention(in: text),
                hasTrailingNewline: text.unicodeScalars.last.map {
                    $0.value == 0x0A || $0.value == 0x0D
                } ?? false,
                originalByteCount: UInt64(data.count)
            )
        )
    }

    /// Stores an editor recovery snapshot outside the source tree. The caller
    /// must explicitly remove it after a successful save or discard.
    public func writeRecoverySnapshot(
        sessionID: UUID,
        sourceURL: URL,
        text: String
    ) throws -> URL {
        let directory = try recoveryDirectory()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let snapshotURL = directory
            .appendingPathComponent(sessionID.uuidString)
            .appendingPathExtension("txt")
        let header = "// OpenPane recovery for \(sourceURL.path)\n"
        guard let data = (header + text).data(using: .utf8) else {
            throw FileIOError.unableToWrite("The recovery text could not be encoded.")
        }
        try data.write(to: snapshotURL, options: .atomic)
        return snapshotURL
    }

    public func removeRecoverySnapshot(sessionID: UUID) throws {
        let snapshotURL = try recoveryDirectory()
            .appendingPathComponent(sessionID.uuidString)
            .appendingPathExtension("txt")
        if fileManager.fileExists(atPath: snapshotURL.path) {
            try fileManager.removeItem(at: snapshotURL)
        }
    }

    private func recoveryDirectory() throws -> URL {
        if let configured = configuration.recoveryDirectory {
            return configured
        }
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base
            .appendingPathComponent("OpenPane", isDirectory: true)
            .appendingPathComponent("Recovery", isDirectory: true)
    }

    private static func editTarget(for url: URL) -> URL {
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        return values?.isSymbolicLink == true ? url.resolvingSymlinksInPath() : url
    }

    private static func decodePossiblyBounded(_ data: Data, isBounded: Bool) -> DecodedText? {
        if let decoded = TextCodec.decode(data) { return decoded }
        guard isBounded else { return nil }
        for count in 1...min(3, data.count) {
            if let decoded = TextCodec.decode(Data(data.dropLast(count))) {
                return decoded
            }
        }
        return nil
    }

    private static func readPrefix(of url: URL, byteCount: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: byteCount) ?? Data()
    }

    private static func atomicReplace(
        data: Data,
        targetURL: URL,
        targetExists: Bool,
        metadata: TextFileMetadata?,
        fileManager: FileManager
    ) throws {
        let directory = targetURL.deletingLastPathComponent()
        let temporaryURL = directory.appendingPathComponent(
            ".\(targetURL.lastPathComponent).openpane-\(UUID().uuidString).tmp"
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }

        try data.write(to: temporaryURL)
        let handle = try FileHandle(forWritingTo: temporaryURL)
        try handle.synchronize()
        try handle.close()

        if let permissions = metadata?.posixPermissions {
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: permissions)],
                ofItemAtPath: temporaryURL.path
            )
        }
        if let metadata {
            try applyExtendedAttributes(
                metadata.extendedAttributes,
                to: temporaryURL
            )
        }

        if targetExists {
            _ = try fileManager.replaceItemAt(
                targetURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: []
            )
        } else {
            try fileManager.moveItem(at: temporaryURL, to: targetURL)
        }
    }

    private static func makeFingerprint(
        url: URL,
        attributes: [FileAttributeKey: Any],
        coverage: FingerprintCoverage,
        knownData: Data?,
        sampleByteCount: Int
    ) throws -> FileFingerprint {
        let byteCount = uint64Attribute(attributes[.size])
        let modificationDate = (attributes[.modificationDate] as? Date) ?? .distantPast
        let systemNumber = optionalUInt64Attribute(attributes[.systemNumber])
        let fileNumber = optionalUInt64Attribute(attributes[.systemFileNumber])
        let digest: String

        if let knownData, coverage == .full {
            digest = SHA256.hash(data: knownData).hexString
        } else {
            digest = try hashFile(
                at: url,
                byteCount: byteCount,
                coverage: coverage,
                sampleByteCount: sampleByteCount
            )
        }

        return FileFingerprint(
            byteCount: byteCount,
            modificationTimeNanoseconds: modificationDate.nanosecondsSince1970,
            systemNumber: systemNumber,
            fileNumber: fileNumber,
            contentSHA256: digest,
            coverage: coverage
        )
    }

    private static func hashFile(
        at url: URL,
        byteCount: UInt64,
        coverage: FingerprintCoverage,
        sampleByteCount: Int
    ) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()

        if coverage == .sampled {
            let first = try handle.read(upToCount: sampleByteCount) ?? Data()
            hasher.update(data: first)
            if byteCount > UInt64(sampleByteCount) {
                let offset = byteCount > UInt64(sampleByteCount)
                    ? byteCount - UInt64(sampleByteCount)
                    : 0
                try handle.seek(toOffset: offset)
                let last = try handle.read(upToCount: sampleByteCount) ?? Data()
                hasher.update(data: last)
            }
            var count = byteCount.bigEndian
            withUnsafeBytes(of: &count) { hasher.update(bufferPointer: $0) }
        } else {
            while true {
                let chunk = try handle.read(upToCount: 1_024 * 1_024) ?? Data()
                guard !chunk.isEmpty else { break }
                hasher.update(data: chunk)
            }
        }
        return hasher.finalize().hexString
    }

    private static func extendedAttributes(of url: URL) -> [String: Data] {
        let path = url.path
        let length = path.withCString { listxattr($0, nil, 0, 0) }
        guard length > 0 else { return [:] }

        var names = [CChar](repeating: 0, count: length)
        let readLength = path.withCString {
            listxattr($0, &names, names.count, 0)
        }
        guard readLength > 0 else { return [:] }

        var result: [String: Data] = [:]
        var start = 0
        for index in 0..<readLength where names[index] == 0 {
            guard index > start else {
                start = index + 1
                continue
            }
            let name = names[start..<index].withUnsafeBufferPointer {
                String(cString: $0.baseAddress!)
            }
            start = index + 1

            let valueLength = path.withCString { pathPointer in
                name.withCString {
                    getxattr(pathPointer, $0, nil, 0, 0, 0)
                }
            }
            guard valueLength >= 0 else { continue }
            var value = Data(count: valueLength)
            let readValue = value.withUnsafeMutableBytes { buffer in
                path.withCString { pathPointer in
                    name.withCString {
                        getxattr(pathPointer, $0, buffer.baseAddress, buffer.count, 0, 0)
                    }
                }
            }
            if readValue >= 0 {
                result[name] = value
            }
        }
        return result
    }

    private static func applyExtendedAttributes(
        _ attributes: [String: Data],
        to url: URL
    ) throws {
        for (name, value) in attributes {
            let result = value.withUnsafeBytes { buffer in
                url.path.withCString { pathPointer in
                    name.withCString {
                        setxattr(
                            pathPointer,
                            $0,
                            buffer.baseAddress,
                            buffer.count,
                            0,
                            0
                        )
                    }
                }
            }
            guard result == 0 else {
                throw POSIXError(
                    POSIXErrorCode(rawValue: errno) ?? .EIO
                )
            }
        }
    }

    private static func uint64Attribute(_ value: Any?) -> UInt64 {
        optionalUInt64Attribute(value) ?? 0
    }

    private static func optionalUInt64Attribute(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber { return number.uint64Value }
        if let value = value as? UInt64 { return value }
        if let value = value as? Int, value >= 0 { return UInt64(value) }
        return nil
    }

    private static func uint16Attribute(_ value: Any?) -> UInt16? {
        optionalUInt64Attribute(value).map { UInt16(truncatingIfNeeded: $0) }
    }
}

private extension Date {
    var nanosecondsSince1970: Int64 {
        let value = timeIntervalSince1970 * 1_000_000_000
        guard value.isFinite else { return 0 }
        if value >= Double(Int64.max) { return Int64.max }
        if value <= Double(Int64.min) { return Int64.min }
        return Int64(value.rounded())
    }
}

private extension Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
