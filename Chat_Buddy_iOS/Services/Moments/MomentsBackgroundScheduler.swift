import BackgroundTasks
import Foundation

// MARK: - Background Task Identifiers
// These MUST be registered in Info.plist under "Permitted background task scheduler identifiers"

enum BGTaskIdentifier {
    static let momentsRefresh = "com.chatbuddy.moments.refresh"
    static let storyEvents    = "com.chatbuddy.moments.storyevents"
}

// MARK: - Background Task Scheduler

/// Registers and schedules iOS `BGTask` jobs for Moments AI content generation.
/// Call `MomentsBackgroundScheduler.register()` once at app launch (before the first scene connects).
enum MomentsBackgroundScheduler {

    // MARK: - Registration (call once at app launch)

    static func register(
        momentsStore: MomentsStore,
        apiConfigStore: APIConfigStore
    ) {
        // 1. Periodic AI post generation (appRefreshTask — fires every ~30 min when system allows)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BGTaskIdentifier.momentsRefresh,
            using: nil
        ) { task in
            guard let appRefreshTask = task as? BGAppRefreshTask else { return }
            handleMomentsRefresh(task: appRefreshTask,
                                 momentsStore: momentsStore,
                                 apiConfigStore: apiConfigStore)
        }

        // 2. Story Events (birthdays / holidays) — runs once per day as a processing task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BGTaskIdentifier.storyEvents,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            handleStoryEvents(task: processingTask,
                              momentsStore: momentsStore,
                              apiConfigStore: apiConfigStore)
        }
    }

    // MARK: - Schedule (call when app enters background)

    static func scheduleMomentsRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: BGTaskIdentifier.momentsRefresh)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60) // 30 minutes
        try? BGTaskScheduler.shared.submit(request)
    }

    static func scheduleStoryEvents() {
        let request = BGProcessingTaskRequest(identifier: BGTaskIdentifier.storyEvents)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60) // 1 hour
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }

    static func scheduleAll() {
        scheduleMomentsRefresh()
        scheduleStoryEvents()
    }

    // MARK: - Handlers

    private static func handleMomentsRefresh(
        task: BGAppRefreshTask,
        momentsStore: MomentsStore,
        apiConfigStore: APIConfigStore
    ) {
        // Re-schedule immediately so the next refresh is queued
        scheduleMomentsRefresh()

        let bgTask = Task {
            do {
                try await periodicMomentsPost(
                    momentsStore: momentsStore,
                    apiConfigStore: apiConfigStore
                )
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            bgTask.cancel()
        }
    }

    private static func handleStoryEvents(
        task: BGProcessingTask,
        momentsStore: MomentsStore,
        apiConfigStore: APIConfigStore
    ) {
        scheduleStoryEvents()

        let bgTask = Task {
            do {
                try await checkAndPostStoryEvents(
                    momentsStore: momentsStore,
                    apiConfigStore: apiConfigStore
                )
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            bgTask.cancel()
        }
    }

    // MARK: - AI Generation Logic (mirrors MomentsOrchestrator but cancellation-safe)

    private static func periodicMomentsPost(
        momentsStore: MomentsStore,
        apiConfigStore: APIConfigStore
    ) async throws {
        let config = apiConfigStore.activeConfig
        guard config.isValid else { return }

        let now = Date().timeIntervalSince1970
        let companions = PersonaStore.socialCompanions.shuffled()

        for persona in companions {
            try Task.checkCancellation()
            let lastPost = await MainActor.run { momentsStore.lastAIPostTime[persona.id] ?? 0 }
            let cooldown = Double.random(in: 1800...7200)
            guard now - lastPost > cooldown else { continue }

            let prompt = MomentsService.generatePostPrompt(
                persona: persona,
                timeContext: MomentsService.timeContext(),
                location: MomentsService.randomLocation(for: persona.id)
            )
            let messages = [ChatMessage(role: .user, content: prompt)]
            if let text = try? await callAI(messages: messages, config: config), !text.isEmpty {
                await MainActor.run {
                    momentsStore.createPost(
                        content: text,
                        imageData: [],
                        location: MomentsService.randomLocation(for: persona.id),
                        authorId: persona.id
                    )
                    momentsStore.recordAIPost(personaId: persona.id)
                }
            }
            break  // one post per BGTask invocation
        }
    }

    private static func checkAndPostStoryEvents(
        momentsStore: MomentsStore,
        apiConfigStore: APIConfigStore
    ) async throws {
        let config = apiConfigStore.activeConfig
        guard config.isValid else { return }

        let todayStr = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date())).prefix(10).description
        guard await MainActor.run(body: { momentsStore.lastStoryEventDate != todayStr }) else { return }

        let events = MomentsService.todayEvents()
        try Task.checkCancellation()

        for personaId in events.birthdays {
            guard let persona = PersonaStore.persona(byId: personaId) else { continue }
            let prompt = MomentsService.generateBirthdayPrompt(persona: persona)
            if let text = try? await callAI(messages: [ChatMessage(role: .user, content: prompt)], config: config), !text.isEmpty {
                await MainActor.run {
                    momentsStore.createPost(content: text, imageData: [], location: nil, authorId: personaId)
                    momentsStore.recordAIPost(personaId: personaId)
                }
            }
        }

        if let holiday = events.holiday, let persona = PersonaStore.socialCompanions.randomElement() {
            let prompt = MomentsService.generateHolidayPrompt(persona: persona, holidayName: holiday.nameEn)
            if let text = try? await callAI(messages: [ChatMessage(role: .user, content: prompt)], config: config), !text.isEmpty {
                await MainActor.run {
                    momentsStore.createPost(content: text, imageData: [], location: nil, authorId: persona.id)
                    momentsStore.recordAIPost(personaId: persona.id)
                }
            }
        }

        await MainActor.run { momentsStore.recordStoryEvent(date: todayStr) }
    }

    private static func callAI(messages: [ChatMessage], config: APIConfig) async throws -> String? {
        let response = try await AIClient.shared.sendChatCompletion(messages: messages, config: config)
        return response.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
