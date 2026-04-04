import Foundation

enum ChildProfileStore {
    private static let cacheKey = "anky.child.profiles"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func load() -> [ChildProfile] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return [] }
        return (try? decoder.decode([ChildProfile].self, from: data)) ?? []
    }

    static func save(_ profiles: [ChildProfile]) {
        guard let data = try? encoder.encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    static func add(_ profile: ChildProfile) {
        var profiles = load().filter { $0.id != profile.id }
        profiles.append(profile)
        save(profiles)
    }

    static func remove(id: String) {
        let profiles = load().filter { $0.id != id }
        save(profiles)
    }
}
