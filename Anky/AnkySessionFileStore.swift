//
//  AnkySessionFileStore.swift
//  Anky
//

import CryptoKit
import Foundation

struct AnkyKeystrokeRecord: Equatable {
    let payload: String
    let timestamp: Date
}

struct AnkyStoredSessionArtifact: Equatable {
    let sessionString: String
    let sessionHash: String
    let fileURL: URL
}

struct AnkyRecoveredSessionArtifact: Equatable {
    let firstKeystrokeEpochMs: Int64
    let sessionString: String
    let text: String
    let keystrokes: [AnkyKeystrokeRecord]
    let fileURL: URL
}

enum AnkySessionFileStoreError: LocalizedError {
    case missingFirstKeystrokeTimestamp
    case invalidUTF8
    case existingFileHashMismatch(expected: String, actual: String)
    case verificationFailed(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .missingFirstKeystrokeTimestamp:
            return "The first keystroke timestamp was missing."
        case .invalidUTF8:
            return "The .anky file could not be decoded as UTF-8."
        case .existingFileHashMismatch(let expected, let actual):
            return "An existing .anky file hash mismatch was found. Expected \(expected), got \(actual)."
        case .verificationFailed(let expected, let actual):
            return "The written .anky file failed verification. Expected \(expected), got \(actual)."
        }
    }
}

enum AnkySessionFileStore {
    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    static func canonicalPayload(for character: Character) -> String {
        if character == " " {
            return "SPACE"
        }
        return String(character).precomposedStringWithCanonicalMapping
    }

    static func buildSessionString(
        keystrokes: [AnkyKeystrokeRecord],
        firstKeystrokeEpochMs: Int64?
    ) -> String? {
        guard !keystrokes.isEmpty, let firstKeystrokeEpochMs else { return nil }

        var lines: [String] = []
        lines.reserveCapacity(keystrokes.count)
        lines.append("\(firstKeystrokeEpochMs) \(normalizePayload(keystrokes[0].payload))")

        for index in 1..<keystrokes.count {
            let deltaMs = max(
                Int((keystrokes[index].timestamp.timeIntervalSince(keystrokes[index - 1].timestamp) * 1000).rounded()),
                0
            )
            lines.append("\(deltaMs) \(normalizePayload(keystrokes[index].payload))")
        }

        return lines.joined(separator: "\n")
    }

    static func persistSession(
        sessionString: String,
        firstKeystrokeEpochMs: Int64
    ) throws -> AnkyStoredSessionArtifact {
        let sessionData = Data(sessionString.utf8)
        let sessionHash = sha256Hex(of: sessionData)
        let fileURL = try canonicalFileURL(
            sessionHash: sessionHash,
            firstKeystrokeEpochMs: firstKeystrokeEpochMs
        )

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let verification = try verificationResult(for: fileURL)
            guard verification.expected == verification.actual else {
                throw AnkySessionFileStoreError.existingFileHashMismatch(
                    expected: verification.expected,
                    actual: verification.actual
                )
            }
            try ensureIncludedInBackup(fileURL)
            let writtenData = try Data(contentsOf: fileURL)
            guard let writtenString = String(data: writtenData, encoding: .utf8) else {
                throw AnkySessionFileStoreError.invalidUTF8
            }
            return AnkyStoredSessionArtifact(
                sessionString: writtenString,
                sessionHash: sessionHash,
                fileURL: fileURL
            )
        }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try sessionData.write(to: fileURL, options: [.atomic])
        try ensureIncludedInBackup(fileURL)

        let verification = try verificationResult(for: fileURL)
        guard verification.expected == verification.actual else {
            throw AnkySessionFileStoreError.verificationFailed(
                expected: verification.expected,
                actual: verification.actual
            )
        }

        let writtenData = try Data(contentsOf: fileURL)
        guard let writtenString = String(data: writtenData, encoding: .utf8) else {
            throw AnkySessionFileStoreError.invalidUTF8
        }

        return AnkyStoredSessionArtifact(
            sessionString: writtenString,
            sessionHash: sessionHash,
            fileURL: fileURL
        )
    }

    static func writePartialSession(
        sessionString: String,
        sessionId: String,
        firstKeystrokeEpochMs: Int64
    ) throws -> URL {
        let partialURL = try partialFileURL(
            sessionId: sessionId,
            firstKeystrokeEpochMs: firstKeystrokeEpochMs
        )
        try FileManager.default.createDirectory(
            at: partialURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(sessionString.utf8).write(to: partialURL, options: [.atomic])
        try ensureIncludedInBackup(partialURL)
        return partialURL
    }

    static func sealPartialSession(
        sessionString: String,
        sessionId: String,
        firstKeystrokeEpochMs: Int64
    ) throws -> AnkyStoredSessionArtifact {
        let sessionData = Data(sessionString.utf8)
        let sessionHash = sha256Hex(of: sessionData)
        let canonicalURL = try canonicalFileURL(
            sessionHash: sessionHash,
            firstKeystrokeEpochMs: firstKeystrokeEpochMs
        )
        let partialURL = try partialFileURL(
            sessionId: sessionId,
            firstKeystrokeEpochMs: firstKeystrokeEpochMs
        )

        if FileManager.default.fileExists(atPath: canonicalURL.path) {
            let verification = try verificationResult(for: canonicalURL)
            guard verification.expected == verification.actual else {
                throw AnkySessionFileStoreError.existingFileHashMismatch(
                    expected: verification.expected,
                    actual: verification.actual
                )
            }
            if FileManager.default.fileExists(atPath: partialURL.path) {
                try? FileManager.default.removeItem(at: partialURL)
            }
            try ensureIncludedInBackup(canonicalURL)
            let writtenData = try Data(contentsOf: canonicalURL)
            guard let writtenString = String(data: writtenData, encoding: .utf8) else {
                throw AnkySessionFileStoreError.invalidUTF8
            }
            return AnkyStoredSessionArtifact(
                sessionString: writtenString,
                sessionHash: sessionHash,
                fileURL: canonicalURL
            )
        }

        try FileManager.default.createDirectory(
            at: canonicalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if FileManager.default.fileExists(atPath: partialURL.path) {
            try sessionData.write(to: partialURL, options: [.atomic])
            try FileManager.default.moveItem(at: partialURL, to: canonicalURL)
        } else {
            try sessionData.write(to: canonicalURL, options: [.atomic])
        }

        try ensureIncludedInBackup(canonicalURL)

        let verification = try verificationResult(for: canonicalURL)
        guard verification.expected == verification.actual else {
            throw AnkySessionFileStoreError.verificationFailed(
                expected: verification.expected,
                actual: verification.actual
            )
        }

        let writtenData = try Data(contentsOf: canonicalURL)
        guard let writtenString = String(data: writtenData, encoding: .utf8) else {
            throw AnkySessionFileStoreError.invalidUTF8
        }

        return AnkyStoredSessionArtifact(
            sessionString: writtenString,
            sessionHash: sessionHash,
            fileURL: canonicalURL
        )
    }

    static func partialFileURL(
        sessionId: String,
        firstKeystrokeEpochMs: Int64
    ) throws -> URL {
        let baseDirectory = try sessionDirectory(firstKeystrokeEpochMs: firstKeystrokeEpochMs)
        return baseDirectory.appendingPathComponent("partial_\(sessionId).anky", isDirectory: false)
    }

    static func loadRecoveredSession(filePath: String) throws -> AnkyRecoveredSessionArtifact {
        let fileURL = URL(fileURLWithPath: filePath)
        let sessionData = try Data(contentsOf: fileURL)
        guard let sessionString = String(data: sessionData, encoding: .utf8) else {
            throw AnkySessionFileStoreError.invalidUTF8
        }

        let parsed = try parseSessionString(sessionString)
        return AnkyRecoveredSessionArtifact(
            firstKeystrokeEpochMs: parsed.firstKeystrokeEpochMs,
            sessionString: sessionString,
            text: plainText(from: parsed.keystrokes),
            keystrokes: parsed.keystrokes,
            fileURL: fileURL
        )
    }

    static func verify(filepath: String) -> Bool {
        guard let result = try? verificationResult(for: URL(fileURLWithPath: filepath)) else {
            return false
        }
        return result.expected == result.actual
    }

    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data)
            .compactMap { String(format: "%02x", $0) }
            .joined()
    }

    static func firstKeystrokeDate(from sessionString: String) -> Date? {
        guard let firstLine = sessionString.split(separator: "\n", omittingEmptySubsequences: false).first else {
            return nil
        }
        guard let separatorIndex = firstLine.firstIndex(of: " "),
              let epochMs = Int64(firstLine[..<separatorIndex]) else {
            return nil
        }
        return Date(timeIntervalSince1970: Double(epochMs) / 1000)
    }

    static func plainText(from keystrokes: [AnkyKeystrokeRecord]) -> String {
        keystrokes.reduce(into: "") { text, record in
            text.append(contentsOf: record.payload == "SPACE" ? " " : record.payload)
        }
    }

    static func recoverStoredSession(matching text: String, around date: Date) -> AnkyStoredSessionArtifact? {
        let fileManager = FileManager.default
        let normalizedText = text.precomposedStringWithCanonicalMapping
        let candidateDates = [-1, 0, 1].compactMap {
            utcCalendar.date(byAdding: .day, value: $0, to: date)
        }

        var visitedDirectories = Set<String>()
        var bestMatch: (artifact: AnkyStoredSessionArtifact, delta: TimeInterval)?

        for candidateDate in candidateDates {
            let candidateEpochMs = Int64(candidateDate.timeIntervalSince1970 * 1000)
            guard let directory = try? sessionDirectory(firstKeystrokeEpochMs: candidateEpochMs) else {
                continue
            }
            guard visitedDirectories.insert(directory.path).inserted else {
                continue
            }
            guard let fileURLs = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for fileURL in fileURLs
            where fileURL.pathExtension == "anky" && !fileURL.lastPathComponent.hasPrefix("partial_") {
                guard let recovered = try? loadRecoveredSession(filePath: fileURL.path) else {
                    continue
                }
                guard recovered.text.precomposedStringWithCanonicalMapping == normalizedText else {
                    continue
                }

                let firstKeystrokeDate = Date(
                    timeIntervalSince1970: Double(recovered.firstKeystrokeEpochMs) / 1000
                )
                let delta = abs(firstKeystrokeDate.timeIntervalSince(date))
                let artifact = AnkyStoredSessionArtifact(
                    sessionString: recovered.sessionString,
                    sessionHash: fileURL.deletingPathExtension().lastPathComponent,
                    fileURL: fileURL
                )

                if let bestMatch, bestMatch.delta <= delta {
                    continue
                }
                bestMatch = (artifact: artifact, delta: delta)
            }
        }

        return bestMatch?.artifact
    }

    private static func normalizePayload(_ payload: String) -> String {
        if payload == "SPACE" {
            return payload
        }
        return payload.precomposedStringWithCanonicalMapping
    }

    private static func canonicalFileURL(
        sessionHash: String,
        firstKeystrokeEpochMs: Int64
    ) throws -> URL {
        let baseDirectory = try sessionDirectory(firstKeystrokeEpochMs: firstKeystrokeEpochMs)
        return baseDirectory.appendingPathComponent("\(sessionHash).anky", isDirectory: false)
    }

    private static func sessionDirectory(firstKeystrokeEpochMs: Int64) throws -> URL {
        let date = Date(timeIntervalSince1970: Double(firstKeystrokeEpochMs) / 1000)
        let components = utcCalendar.dateComponents([.year, .month, .day], from: date)
        let year = String(format: "%04d", components.year ?? 0)
        let month = String(format: "%02d", components.month ?? 0)
        let day = String(format: "%02d", components.day ?? 0)

        return try storageRoot()
            .appendingPathComponent("ankys", isDirectory: true)
            .appendingPathComponent(year, isDirectory: true)
            .appendingPathComponent(month, isDirectory: true)
            .appendingPathComponent(day, isDirectory: true)
    }

    private static func storageRoot() throws -> URL {
        let containerIdentifier = "iCloud.\(Bundle.main.bundleIdentifier ?? "com.jpfraneto.Anky")"
        if let ubiquityContainer = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) {
            let documentsDirectory = ubiquityContainer.appendingPathComponent("Documents", isDirectory: true)
            try FileManager.default.createDirectory(
                at: documentsDirectory,
                withIntermediateDirectories: true
            )
            return documentsDirectory
        }

        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static func ensureIncludedInBackup(_ fileURL: URL) throws {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = false
        var mutableURL = fileURL
        try mutableURL.setResourceValues(resourceValues)

        let resolvedValues = try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        if resolvedValues.isExcludedFromBackup == true {
            var retryValues = URLResourceValues()
            retryValues.isExcludedFromBackup = false
            var retryURL = fileURL
            try retryURL.setResourceValues(retryValues)
        }
    }

    private static func verificationResult(for fileURL: URL) throws -> (expected: String, actual: String) {
        let expected = fileURL.deletingPathExtension().lastPathComponent
        let actual = sha256Hex(of: try Data(contentsOf: fileURL))
        return (expected, actual)
    }

    private static func parseSessionString(_ sessionString: String) throws -> (firstKeystrokeEpochMs: Int64, keystrokes: [AnkyKeystrokeRecord]) {
        let lines = sessionString.split(separator: "\n", omittingEmptySubsequences: false)
        guard let firstLine = lines.first,
              let firstSeparatorIndex = firstLine.firstIndex(of: " "),
              let firstEpochMs = Int64(firstLine[..<firstSeparatorIndex]) else {
            throw AnkySessionFileStoreError.missingFirstKeystrokeTimestamp
        }

        var currentEpochMs = firstEpochMs
        var keystrokes: [AnkyKeystrokeRecord] = []
        let firstPayload = normalizePayload(String(firstLine[firstLine.index(after: firstSeparatorIndex)...]))
        keystrokes.append(
            AnkyKeystrokeRecord(
                payload: firstPayload,
                timestamp: Date(timeIntervalSince1970: Double(firstEpochMs) / 1000)
            )
        )

        for line in lines.dropFirst() where !line.isEmpty {
            guard let separatorIndex = line.firstIndex(of: " "),
                  let deltaMs = Int64(line[..<separatorIndex]) else {
                continue
            }
            currentEpochMs += max(deltaMs, 0)
            let payload = normalizePayload(String(line[line.index(after: separatorIndex)...]))
            keystrokes.append(
                AnkyKeystrokeRecord(
                    payload: payload,
                    timestamp: Date(timeIntervalSince1970: Double(currentEpochMs) / 1000)
                )
            )
        }

        return (firstEpochMs, keystrokes)
    }
}
