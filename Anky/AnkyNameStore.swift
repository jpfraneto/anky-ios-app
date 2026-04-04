//
//  AnkyNameStore.swift
//  Anky
//
//  Stores the name Anky has given the user, derived from their first reflection.
//  The name evolves as the user writes more — extracted from anky responses.
//

import Foundation

enum AnkyNameStore {
    private static let nameKey = "anky.given_name"

    /// The name Anky has given this user.
    static var name: String? {
        UserDefaults.standard.string(forKey: nameKey)
    }

    /// Store a new anky-given name.
    static func setName(_ name: String) {
        UserDefaults.standard.set(name, forKey: nameKey)
    }

    /// Attempt to extract a name from an anky reflection response.
    /// Looks for patterns like "dear X," or "X, you..." or addresses the user directly.
    static func extractNameIfPresent(from reflection: String) -> String? {
        let lower = reflection.lowercased()

        // Pattern: "dear X," at the start
        if lower.hasPrefix("dear ") {
            let rest = reflection.dropFirst(5)
            if let commaIndex = rest.firstIndex(of: ",") {
                let candidate = String(rest[rest.startIndex..<commaIndex]).trimmingCharacters(in: .whitespaces)
                if isValidName(candidate) {
                    return candidate
                }
            }
        }

        // Pattern: first word followed by comma at sentence start
        let lines = reflection.components(separatedBy: "\n").filter { !$0.isEmpty }
        if let first = lines.first {
            let words = first.components(separatedBy: " ")
            if let firstWord = words.first, firstWord.hasSuffix(",") {
                let candidate = String(firstWord.dropLast()).trimmingCharacters(in: .whitespaces)
                if isValidName(candidate) {
                    return candidate.lowercased()
                }
            }
        }

        return nil
    }

    /// Update the stored name from a reflection, if a name can be extracted.
    static func updateFromReflection(_ reflection: String) {
        if let extracted = extractNameIfPresent(from: reflection) {
            setName(extracted)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: nameKey)
    }

    private static func isValidName(_ candidate: String) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.count >= 2, trimmed.count <= 30 else { return false }
        // Must be a single word (no spaces) and mostly letters
        guard !trimmed.contains(" ") else { return false }
        let letterCount = trimmed.filter { $0.isLetter }.count
        return letterCount >= trimmed.count / 2
    }
}
