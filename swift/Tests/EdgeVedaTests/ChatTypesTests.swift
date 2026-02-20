import XCTest
@testable import EdgeVeda

@available(iOS 15.0, macOS 12.0, *)
final class ChatTypesTests: XCTestCase {

    // MARK: - SystemPromptPreset

    func testAssistantPresetTextIsNonEmpty() {
        XCTAssertFalse(SystemPromptPreset.assistant.text.isEmpty)
    }

    func testCoderPresetTextMentionsProgrammerOrCode() {
        let text = SystemPromptPreset.coder.text.lowercased()
        XCTAssertTrue(text.contains("programmer") || text.contains("code"))
    }

    func testConcisePresetTextMentionsConciseOrBrief() {
        let text = SystemPromptPreset.concise.text.lowercased()
        XCTAssertTrue(text.contains("concise") || text.contains("brief"))
    }

    func testCreativePresetTextMentionsCreativeOrImagination() {
        let text = SystemPromptPreset.creative.text.lowercased()
        XCTAssertTrue(text.contains("creative") || text.contains("imagination"))
    }

    func testCustomPresetReturnsProvidedText() {
        let preset = SystemPromptPreset.custom("Be terse.")
        XCTAssertEqual(preset.text, "Be terse.")
    }

    func testCustomPresetEmptyStringIsValid() {
        let preset = SystemPromptPreset.custom("")
        XCTAssertEqual(preset.text, "")
    }

    func testNamedPresetsProduceDifferentText() {
        let texts = [
            SystemPromptPreset.assistant.text,
            SystemPromptPreset.coder.text,
            SystemPromptPreset.concise.text,
            SystemPromptPreset.creative.text
        ]
        let unique = Set(texts)
        XCTAssertEqual(unique.count, 4, "All 4 named presets should have distinct text")
    }

    // MARK: - ChatRole

    func testChatRoleHasThreeCases() {
        XCTAssertEqual(ChatRole.allCases.count, 3)
    }

    func testChatRoleSystemRawValue() {
        XCTAssertEqual(ChatRole.system.rawValue, "system")
    }

    func testChatRoleUserRawValue() {
        XCTAssertEqual(ChatRole.user.rawValue, "user")
    }

    func testChatRoleAssistantRawValue() {
        XCTAssertEqual(ChatRole.assistant.rawValue, "assistant")
    }

    // MARK: - ChatMessage

    func testChatMessageStoresRole() {
        let msg = ChatMessage(role: .user, content: "Hello")
        XCTAssertEqual(msg.role, .user)
    }

    func testChatMessageStoresContent() {
        let msg = ChatMessage(role: .assistant, content: "Hi there!")
        XCTAssertEqual(msg.content, "Hi there!")
    }

    func testChatMessageTimestampIsApproximatelyNow() {
        let before = Date()
        let msg = ChatMessage(role: .user, content: "test")
        let after = Date()
        XCTAssertGreaterThanOrEqual(msg.timestamp, before)
        XCTAssertLessThanOrEqual(msg.timestamp, after)
    }

    func testChatMessagesWithSameContentButDifferentRolesAreDistinct() {
        let userMsg = ChatMessage(role: .user, content: "Hello")
        let assistantMsg = ChatMessage(role: .assistant, content: "Hello")
        XCTAssertNotEqual(userMsg.role, assistantMsg.role)
    }

    func testChatMessageIsSendable() {
        // Compile-time verification: ChatMessage conforms to Sendable
        let _: any Sendable = ChatMessage(role: .user, content: "test")
    }
}
