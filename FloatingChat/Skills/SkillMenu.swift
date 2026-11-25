import Foundation

/// The menu that opens when the Draft starts with `/`: the skills matching what follows it.
struct SkillMenu: Equatable {
    enum State: Equatable {
        case loading
        case loaded([SkillInfo])
        case failed
    }

    private(set) var state: State
    private(set) var query: String
    private(set) var highlighted = 0

    init(state: State, query: String) {
        self.state = state
        self.query = query
    }

    /// What follows the `/` while the Draft is a single slash word, `nil` otherwise.
    static func query(in draft: String) -> String? {
        guard draft.hasPrefix("/"), !draft.contains(where: \.isWhitespace) else { return nil }
        return String(draft.dropFirst())
    }

    /// Name matches first, those starting with the query before the rest, then matches in
    /// the description only.
    var matches: [SkillInfo] {
        guard case .loaded(let skills) = state else { return [] }
        let sorted = skills.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return sorted }
        func rank(_ skill: SkillInfo) -> Int? {
            let names = [skill.name, skill.id]
            if names.contains(where: { $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil }) { return 0 }
            if names.contains(where: { $0.localizedStandardContains(needle) }) { return 1 }
            if skill.description?.localizedStandardContains(needle) == true { return 2 }
            return nil
        }
        return sorted.compactMap { skill in rank(skill).map { (skill, $0) } }
            .enumerated()
            .sorted { ($0.element.1, $0.offset) < ($1.element.1, $1.offset) }
            .map(\.element.0)
    }

    var highlightedSkill: SkillInfo? {
        let matches = matches
        return matches.indices.contains(highlighted) ? matches[highlighted] : nil
    }

    mutating func setQuery(_ query: String) {
        guard query != self.query else { return }
        self.query = query
        highlighted = 0
    }

    mutating func load(_ skills: [SkillInfo]) {
        state = .loaded(skills)
        highlighted = min(highlighted, max(matches.count - 1, 0))
    }

    mutating func fail() {
        if case .loaded = state { return }
        state = .failed
    }

    mutating func highlight(_ index: Int) {
        guard matches.indices.contains(index) else { return }
        highlighted = index
    }

    mutating func move(by offset: Int) {
        let count = matches.count
        guard count > 0 else { return }
        highlighted = min(max(highlighted + offset, 0), count - 1)
    }
}
