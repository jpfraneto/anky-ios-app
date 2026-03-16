//
//  PromptLibrary.swift
//  Anky
//

import Foundation

enum PromptLibrary {
    private static let currentPromptKey = "anky.prompt.current"
    private static let promptIndexKey = "anky.prompt.index"

    private static let prompts = [
        "What are you avoiding feeling right now?",
        "Where does your body already know the truth?",
        "What have you been calling confusion that is actually fear?",
        "What keeps asking to be said in your life?",
        "What are you performing instead of admitting?",
        "What hurts more than you let yourself name?",
        "What part of you is tired of being managed?",
        "What would honesty cost you today?",
        "What are you pretending not to want?",
        "What sentence keeps trying to write itself through you?"
    ]

    static func currentPrompt() -> String {
        if let cached = UserDefaults.standard.string(forKey: currentPromptKey), !cached.isEmpty {
            return cached
        }

        let prompt = prompts.first ?? "What is here?"
        UserDefaults.standard.set(prompt, forKey: currentPromptKey)
        UserDefaults.standard.set(0, forKey: promptIndexKey)
        return prompt
    }

    @discardableResult
    static func advancePrompt(seed: String? = nil) -> String {
        let currentIndex = UserDefaults.standard.integer(forKey: promptIndexKey)
        let offset = max(1, seedOffset(seed))
        let nextIndex = (currentIndex + offset) % prompts.count
        let nextPrompt = prompts[nextIndex]

        UserDefaults.standard.set(nextPrompt, forKey: currentPromptKey)
        UserDefaults.standard.set(nextIndex, forKey: promptIndexKey)

        return nextPrompt
    }

    private static func seedOffset(_ seed: String?) -> Int {
        guard let seed, !seed.isEmpty else { return 1 }
        let scalarSum = seed.unicodeScalars.reduce(0) { partial, scalar in
            partial + Int(scalar.value)
        }
        return scalarSum % 3 + 1
    }
}
