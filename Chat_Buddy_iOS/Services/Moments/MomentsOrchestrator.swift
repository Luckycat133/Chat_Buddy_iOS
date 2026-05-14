import Foundation

// MARK: - MomentsOrchestrating Protocol

protocol MomentsOrchestrating: Sendable {
    func run(store: MomentsStore, configStore: APIConfigStore) async
    func reactToUserPost(postId: String, store: MomentsStore, configStore: APIConfigStore) async
}

// MARK: - Default Implementation

final class MomentsOrchestrator: MomentsOrchestrating {
    private let aiClient: AIClientProtocol
    private let seedCount            = 4
    private let periodicInterval: UInt64 = 300_000_000_000
    private let reactionDelayMin     = 15.0
    private let reactionDelayMax     = 40.0
    private let commentDelayMin      = 30.0
    private let commentDelayMax      = 90.0
    private let minPostCooldown      = 1_800.0
    private let maxPostCooldown      = 7_200.0

    init(aiClient: AIClientProtocol = AIClient.shared) {
        self.aiClient = aiClient
    }

    func run(store: MomentsStore, configStore: APIConfigStore) async {
        let config = configStore.activeConfig

        if store.posts.isEmpty {
            await seedInitialPosts(store: store, config: config)
        }

        await checkStoryEvents(store: store, config: config)

        await runPeriodicLoop(store: store, config: config)
    }

    func reactToUserPost(postId: String, store: MomentsStore, configStore: APIConfigStore) async {
        let config = configStore.activeConfig

        let firstDelay = Double.random(in: reactionDelayMin...reactionDelayMax)
        try? await Task.sleep(nanoseconds: UInt64(firstDelay * 1_000_000_000))

        guard !Task.isCancelled else { return }

        let companions = PersonaStore.socialCompanions.shuffled()
        let reactorCount = Int.random(in: 2...min(4, companions.count))
        for persona in companions.prefix(reactorCount) {
            let useReaction = Bool.random()
            if useReaction {
                let emoji = MomentsService.reactionEmojis.randomElement() ?? "👍"
                await MainActor.run { store.addReaction(postId: postId, emoji: emoji, userId: persona.id) }
            } else {
                await MainActor.run { _ = store.toggleLike(postId: postId, userId: persona.id) }
            }
            try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.5...2.0) * 1_000_000_000))
        }

        guard !Task.isCancelled else { return }

        let commentDelay = Double.random(in: commentDelayMin...commentDelayMax)
        try? await Task.sleep(nanoseconds: UInt64(commentDelay * 1_000_000_000))

        guard !Task.isCancelled else { return }

        let commenters = companions.dropFirst(reactorCount).shuffled()
        let commenterCount = Int.random(in: 1...min(2, commenters.count))
        guard let post = await MainActor.run(body: { store.posts.first { $0.id == postId } }) else { return }

        for persona in commenters.prefix(commenterCount) {
            let existing = post.comments.prefix(3).map { c in
                let aName = c.authorId == "user-me" ? "User" : (PersonaStore.persona(byId: c.authorId)?.name ?? c.authorId)
                return "\(aName): \(c.content)"
            }.joined(separator: "\n")

            let prompt = MomentsService.generateCommentPrompt(
                persona: persona,
                postAuthorName: "you (the user)",
                postContent: post.content,
                existingComments: existing,
                replyTo: nil
            )
            let messages = [ChatMessage(role: .user, content: prompt)]
            if let text = await callAI(messages: messages, config: config), !text.isEmpty {
                await MainActor.run {
                    _ = store.addComment(postId: postId, content: text, authorId: persona.id)
                }
            }
            try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 1.0...3.0) * 1_000_000_000))
        }
    }

    private func seedInitialPosts(store: MomentsStore, config: APIConfig) async {
        let companions = PersonaStore.socialCompanions.shuffled().prefix(seedCount)
        for persona in companions {
            guard !Task.isCancelled else { return }
            let time = MomentsService.timeContext()
            let loc  = MomentsService.randomLocation(for: persona.id)
            let prompt = MomentsService.generatePostPrompt(persona: persona, timeContext: time, location: loc)
            let messages = [ChatMessage(role: .user, content: prompt)]
            if let text = await callAI(messages: messages, config: config), !text.isEmpty {
                await MainActor.run {
                    var post = MomentPost(authorId: persona.id, content: text, location: loc)
                    let offset = Double.random(in: 3600...86400)
                    post.createdAt = Date().addingTimeInterval(-offset)
                    store.addHistoricalPost(post)
                    store.recordAIPost(personaId: persona.id)
                }
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    private func checkStoryEvents(store: MomentsStore, config: APIConfig) async {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let todayStr = ISO8601DateFormatter().string(from: today).prefix(10).description

        guard store.lastStoryEventDate != todayStr else { return }

        let events = MomentsService.todayEvents()

        for personaId in events.birthdays {
            guard !Task.isCancelled,
                  let persona = PersonaStore.persona(byId: personaId) else { continue }
            let prompt = MomentsService.generateBirthdayPrompt(persona: persona)
            let messages = [ChatMessage(role: .user, content: prompt)]
            if let text = await callAI(messages: messages, config: config), !text.isEmpty {
                await MainActor.run {
                    store.createPost(content: text, imageData: [], location: nil, authorId: personaId)
                    store.recordAIPost(personaId: personaId)
                }
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        if let holiday = events.holiday,
           let persona = PersonaStore.socialCompanions.randomElement() {
            guard !Task.isCancelled else { return }
            let prompt = MomentsService.generateHolidayPrompt(persona: persona, holidayName: holiday.nameEn)
            let messages = [ChatMessage(role: .user, content: prompt)]
            if let text = await callAI(messages: messages, config: config), !text.isEmpty {
                await MainActor.run {
                    store.createPost(content: text, imageData: [], location: nil, authorId: persona.id)
                    store.recordAIPost(personaId: persona.id)
                }
            }
        }

        await MainActor.run { store.recordStoryEvent(date: todayStr) }
    }

    private func runPeriodicLoop(store: MomentsStore, config: APIConfig) async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: periodicInterval)
            guard !Task.isCancelled else { return }

            let now = Date().timeIntervalSince1970
            let companions = PersonaStore.socialCompanions.shuffled()

            for persona in companions {
                guard !Task.isCancelled else { return }
                let lastPost = await MainActor.run { store.lastAIPostTime[persona.id] ?? 0 }
                let cooldown = Double.random(in: minPostCooldown...maxPostCooldown)
                guard now - lastPost > cooldown else { continue }

                let time = MomentsService.timeContext()
                let loc  = MomentsService.randomLocation(for: persona.id)
                let prompt = MomentsService.generatePostPrompt(persona: persona, timeContext: time, location: loc)
                let messages = [ChatMessage(role: .user, content: prompt)]

                if let text = await callAI(messages: messages, config: config), !text.isEmpty {
                    await MainActor.run {
                        store.createPost(content: text, imageData: [], location: loc, authorId: persona.id)
                        store.recordAIPost(personaId: persona.id)
                    }
                }
                break
            }
        }
    }

    private func callAI(messages: [ChatMessage], config: APIConfig) async -> String? {
        do {
            let response = try await aiClient.sendChatCompletion(messages: messages, config: config)
            return response.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("[MomentsOrchestrator] AI call failed: \(error)")
            return nil
        }
    }
}

// MARK: - Legacy Static API (Backward Compatibility)

extension MomentsOrchestrator {
    static func run(store: MomentsStore, configStore: APIConfigStore) async {
        let instance = MomentsOrchestrator()
        await instance.run(store: store, configStore: configStore)
    }

    static func reactToUserPost(postId: String, store: MomentsStore, configStore: APIConfigStore) async {
        let instance = MomentsOrchestrator()
        await instance.reactToUserPost(postId: postId, store: store, configStore: configStore)
    }
}
