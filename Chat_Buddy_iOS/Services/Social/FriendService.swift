import Foundation

struct FriendGroup: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var nameZh: String
    var colorHex: String
    var icon: String

    init(id: String = UUID().uuidString, name: String, nameZh: String, colorHex: String, icon: String) {
        self.id = id
        self.name = name
        self.nameZh = nameZh
        self.colorHex = colorHex
        self.icon = icon
    }
}

struct FriendMeta: Codable {
    var starred: Bool
    var groupId: String?
    var remark: String?

    static let `default` = FriendMeta(starred: false, groupId: nil, remark: nil)
}

@Observable final class FriendService {
    private static let groupsKey = "friends.groups"
    private static let metaKey = "friends.meta"

    private(set) var groups: [FriendGroup] = []
    private(set) var meta: [String: FriendMeta] = [:]

    init() {
        reloadFromStorage()
    }

    func reloadFromStorage() {
        groups = StorageService.shared.get(Self.groupsKey, default: Self.defaultGroups)
        if groups.isEmpty { groups = Self.defaultGroups }
        meta = StorageService.shared.get(Self.metaKey, default: [:])
    }

    func friendMeta(for personaId: String) -> FriendMeta {
        meta[personaId] ?? .default
    }

    func toggleStar(for personaId: String) {
        var item = meta[personaId] ?? .default
        item.starred.toggle()
        meta[personaId] = item
        saveMeta()
    }

    func updateRemark(for personaId: String, remark: String?) {
        var item = meta[personaId] ?? .default
        item.remark = remark?.trimmingCharacters(in: .whitespacesAndNewlines)
        meta[personaId] = item
        saveMeta()
    }

    func assignGroup(_ groupId: String?, for personaId: String) {
        var item = meta[personaId] ?? .default
        item.groupId = groupId
        meta[personaId] = item
        saveMeta()
    }

    func addGroup(name: String, nameZh: String, colorHex: String, icon: String) {
        let group = FriendGroup(name: name, nameZh: nameZh, colorHex: colorHex, icon: icon)
        groups.append(group)
        saveGroups()
    }

    func updateGroup(_ group: FriendGroup) {
        guard let idx = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[idx] = group
        saveGroups()
    }

    func deleteGroup(id: String) {
        groups.removeAll { $0.id == id }
        for key in meta.keys {
            if meta[key]?.groupId == id {
                meta[key]?.groupId = nil
            }
        }
        saveGroups()
        saveMeta()
    }

    private func saveGroups() {
        StorageService.shared.set(Self.groupsKey, value: groups)
    }

    private func saveMeta() {
        StorageService.shared.set(Self.metaKey, value: meta)
    }

    private static let defaultGroups: [FriendGroup] = [
        FriendGroup(id: "friends-group-close", name: "Close", nameZh: "亲密", colorHex: "#FF6B9D", icon: "❤️"),
        FriendGroup(id: "friends-group-anime", name: "Anime", nameZh: "二次元", colorHex: "#8B5CF6", icon: "✨"),
        FriendGroup(id: "friends-group-work", name: "Work", nameZh: "工作", colorHex: "#3B82F6", icon: "💼"),
    ]
}
