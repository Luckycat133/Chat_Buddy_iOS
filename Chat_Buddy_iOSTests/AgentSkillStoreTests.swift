import XCTest
@testable import Chat_Buddy_iOS

final class AgentSkillStoreTests: XCTestCase {

    // MARK: - Data Integrity

    func testAllSkillsCount() {
        XCTAssertEqual(AgentSkillStore.allSkills.count, 20)
    }

    func testUniqueSkillIds() {
        let ids = AgentSkillStore.allSkills.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Duplicate skill IDs found")
    }

    func testAllSkillsHaveNames() {
        for skill in AgentSkillStore.allSkills {
            XCTAssertFalse(skill.name.isEmpty, "Skill \(skill.id) has empty name")
            XCTAssertFalse(skill.nameZh.isEmpty, "Skill \(skill.id) has empty nameZh")
        }
    }

    func testAllSkillsHaveCategory() {
        for skill in AgentSkillStore.allSkills {
            XCTAssertTrue(AgentSkillStore.categories.contains(skill.category),
                         "Skill \(skill.id) has unknown category: \(skill.category)")
        }
    }

    // MARK: - Categories

    func testCategoriesCount() {
        XCTAssertEqual(AgentSkillStore.categories.count, 6)
    }

    func testGetSkillsByCategory() {
        let programmingSkills = AgentSkillStore.getSkillsByCategory("programming")
        XCTAssertGreaterThan(programmingSkills.count, 0)
        for skill in programmingSkills {
            XCTAssertEqual(skill.category, "programming")
        }
    }

    func testGetSkillsByCategoryEmpty() {
        let skills = AgentSkillStore.getSkillsByCategory("nonexistent")
        XCTAssertTrue(skills.isEmpty)
    }

    func testCategoryLabel() {
        XCTAssertEqual(AgentSkillStore.categoryLabel("programming", isZh: false), "Programming")
        XCTAssertEqual(AgentSkillStore.categoryLabel("programming", isZh: true), "编程")
    }

    // MARK: - Skill Lookup

    func testGetSkillById() {
        let skill = AgentSkillStore.getSkillById("code-generation")
        XCTAssertNotNil(skill)
        XCTAssertEqual(skill?.name, "Code Generation")
    }

    func testGetSkillByIdNotFound() {
        let skill = AgentSkillStore.getSkillById("nonexistent-skill")
        XCTAssertNil(skill)
    }

    // MARK: - Combine Prompts

    func testCombineSkillPrompts() {
        let combined = AgentSkillStore.combineSkillPrompts(["code-generation", "code-review"])
        XCTAssertFalse(combined.isEmpty)
        XCTAssertTrue(combined.contains("\n\n")) // Two skills joined
    }

    func testCombineSkillPromptsEmpty() {
        let combined = AgentSkillStore.combineSkillPrompts([])
        XCTAssertTrue(combined.isEmpty)
    }

    func testCombineSkillPromptsInvalidIds() {
        let combined = AgentSkillStore.combineSkillPrompts(["fake1", "fake2"])
        XCTAssertTrue(combined.isEmpty)
    }

    // MARK: - Required Tools

    func testGetRequiredTools() {
        let tools = AgentSkillStore.getRequiredTools(["code-generation", "debugging"])
        // code-generation and debugging both have tools
        XCTAssertFalse(tools.isEmpty)
    }

    func testGetRequiredToolsNoDuplicates() {
        let tools = AgentSkillStore.getRequiredTools(["code-generation", "debugging"])
        XCTAssertEqual(tools.count, Set(tools).count)
    }

    func testGetRequiredToolsNoToolsSkill() {
        // creative-writing has no tools
        let tools = AgentSkillStore.getRequiredTools(["creative-writing"])
        XCTAssertTrue(tools.isEmpty)
    }

    // MARK: - Agent Skill Mapping

    func testGetSkillsForCodeAgent() {
        let skills = AgentSkillStore.getSkillsForAgent(agentId: "code-developer")
        XCTAssertFalse(skills.isEmpty)
        XCTAssertTrue(skills.contains { $0.id == "code-generation" })
    }

    func testGetSkillsForUnknownAgent() {
        let skills = AgentSkillStore.getSkillsForAgent(agentId: "random-agent-no-keywords")
        XCTAssertTrue(skills.isEmpty)
    }
}
