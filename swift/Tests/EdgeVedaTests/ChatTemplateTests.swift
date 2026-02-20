import XCTest
@testable import EdgeVeda

@available(iOS 15.0, macOS 12.0, *)
final class ChatTemplateTests: XCTestCase {

    // MARK: - Helper

    private func msg(_ role: ChatRole, _ content: String) -> ChatMessage {
        ChatMessage(role: role, content: content)
    }

    // MARK: - Llama3 format

    func testLlama3ContainsUserHeaderMarker() {
        let result = ChatTemplate.llama3.format(messages: [msg(.user, "Hi")])
        XCTAssertTrue(result.contains("<|start_header_id|>user<|end_header_id|>"))
    }

    func testLlama3ContainsSystemHeaderMarker() {
        let result = ChatTemplate.llama3.format(messages: [msg(.system, "Be helpful"), msg(.user, "Hi")])
        XCTAssertTrue(result.contains("<|start_header_id|>system<|end_header_id|>"))
    }

    func testLlama3EndsWithAssistantHeader() {
        let result = ChatTemplate.llama3.format(messages: [msg(.user, "Hi")])
        XCTAssertTrue(result.hasSuffix("<|start_header_id|>assistant<|end_header_id|>\n\n"))
    }

    func testLlama3ContainsEotIdMarker() {
        let result = ChatTemplate.llama3.format(messages: [msg(.user, "Hi")])
        XCTAssertTrue(result.contains("<|eot_id|>"))
    }

    func testLlama3ContainsUserContent() {
        let result = ChatTemplate.llama3.format(messages: [msg(.user, "Hello world")])
        XCTAssertTrue(result.contains("Hello world"))
    }

    func testLlama3EmptyMessagesProducesAssistantPrompt() {
        let result = ChatTemplate.llama3.format(messages: [])
        XCTAssertTrue(result.contains("<|start_header_id|>assistant<|end_header_id|>"))
    }

    func testLlama3MultiTurnOrderIsPreserved() {
        let messages = [
            msg(.user, "First question"),
            msg(.assistant, "First answer"),
            msg(.user, "Second question")
        ]
        let result = ChatTemplate.llama3.format(messages: messages)
        let firstUserRange = result.range(of: "First question")
        let firstAnswerRange = result.range(of: "First answer")
        let secondUserRange = result.range(of: "Second question")
        XCTAssertNotNil(firstUserRange)
        XCTAssertNotNil(firstAnswerRange)
        XCTAssertNotNil(secondUserRange)
        XCTAssertLessThan(firstUserRange!.lowerBound, firstAnswerRange!.lowerBound)
        XCTAssertLessThan(firstAnswerRange!.lowerBound, secondUserRange!.lowerBound)
    }

    // MARK: - ChatML format

    func testChatMLContainsImStartUser() {
        let result = ChatTemplate.chatml.format(messages: [msg(.user, "Hi")])
        XCTAssertTrue(result.contains("<|im_start|>user"))
    }

    func testChatMLContainsImEnd() {
        let result = ChatTemplate.chatml.format(messages: [msg(.user, "Hi")])
        XCTAssertTrue(result.contains("<|im_end|>"))
    }

    func testChatMLSystemMessageContainsSystemBlock() {
        let result = ChatTemplate.chatml.format(messages: [msg(.system, "System prompt")])
        XCTAssertTrue(result.contains("<|im_start|>system"))
    }

    func testChatMLNoSystemInputProducesNoSystemBlock() {
        let result = ChatTemplate.chatml.format(messages: [msg(.user, "Hi")])
        XCTAssertFalse(result.contains("<|im_start|>system"))
    }

    func testChatMLEndsWithImStartAssistant() {
        let result = ChatTemplate.chatml.format(messages: [msg(.user, "Hi")])
        XCTAssertTrue(result.hasSuffix("<|im_start|>assistant\n"))
    }

    // MARK: - Mistral format

    func testMistralContainsINSTOpenMarker() {
        let result = ChatTemplate.mistral.format(messages: [msg(.user, "Hi")])
        XCTAssertTrue(result.contains("[INST]"))
    }

    func testMistralContainsINSTCloseMarker() {
        let result = ChatTemplate.mistral.format(messages: [msg(.user, "Hi")])
        XCTAssertTrue(result.contains("[/INST]"))
    }

    func testMistralSystemIsPrependedInsideINSTBlock() {
        let messages = [msg(.system, "Be concise"), msg(.user, "Hi")]
        let result = ChatTemplate.mistral.format(messages: messages)
        // System content should appear inside [INST] using <<SYS>> markers
        XCTAssertTrue(result.contains("<<SYS>>"))
        XCTAssertTrue(result.contains("Be concise"))
        // There should be no standalone system block outside of [INST]
        let instRange = result.range(of: "[INST]")
        let sysRange = result.range(of: "Be concise")
        XCTAssertNotNil(instRange)
        XCTAssertNotNil(sysRange)
        XCTAssertGreaterThan(sysRange!.lowerBound, instRange!.lowerBound)
    }

    func testMistralStartsWithBOSToken() {
        let result = ChatTemplate.mistral.format(messages: [msg(.user, "Hi")])
        XCTAssertTrue(result.hasPrefix("<s>"))
    }

    // MARK: - Generic format

    func testGenericContainsUserMarker() {
        let result = ChatTemplate.generic.format(messages: [msg(.user, "Hi")])
        XCTAssertTrue(result.contains("### User:"))
    }

    func testGenericContainsAssistantMarker() {
        let result = ChatTemplate.generic.format(messages: [msg(.user, "Hi")])
        XCTAssertTrue(result.contains("### Assistant:"))
    }

    func testGenericSystemMessageContainsSystemMarker() {
        let result = ChatTemplate.generic.format(messages: [msg(.system, "Sys"), msg(.user, "Hi")])
        XCTAssertTrue(result.contains("### System:"))
    }

    func testGenericEndsWithAssistantMarker() {
        let result = ChatTemplate.generic.format(messages: [msg(.user, "Hi")])
        XCTAssertTrue(result.hasSuffix("### Assistant:\n"))
    }

    // MARK: - Qwen3 format

    func testQwen3ContainsImStartUser() {
        let result = ChatTemplate.qwen3.format(messages: [msg(.user, "Hi")])
        XCTAssertTrue(result.contains("<|im_start|>user"))
    }

    func testQwen3ContainsImEnd() {
        let result = ChatTemplate.qwen3.format(messages: [msg(.user, "Hi")])
        XCTAssertTrue(result.contains("<|im_end|>"))
    }

    func testQwen3EndsWithImStartAssistant() {
        let result = ChatTemplate.qwen3.format(messages: [msg(.user, "Hi")])
        XCTAssertTrue(result.hasSuffix("<|im_start|>assistant\n"))
    }

    // MARK: - Gemma3 format

    func testGemma3ContainsStartOfTurnUser() {
        let result = ChatTemplate.gemma3.format(messages: [msg(.user, "Hi")])
        XCTAssertTrue(result.contains("<start_of_turn>user"))
    }

    func testGemma3ContainsStartOfTurnModel() {
        let result = ChatTemplate.gemma3.format(messages: [msg(.user, "Hi")])
        XCTAssertTrue(result.contains("<start_of_turn>model"))
    }

    func testGemma3DoesNotContainStartOfTurnAssistant() {
        let result = ChatTemplate.gemma3.format(messages: [msg(.user, "Hi")])
        XCTAssertFalse(result.contains("<start_of_turn>assistant"))
    }

    func testGemma3MergesSystemIntoFirstUserTurn() {
        let messages = [msg(.system, "Be brief"), msg(.user, "Hi")]
        let result = ChatTemplate.gemma3.format(messages: messages)
        XCTAssertTrue(result.contains("Be brief"), "System content should appear in output")
        XCTAssertFalse(result.contains("<start_of_turn>system"), "Gemma3 has no system turn")
    }

    func testGemma3SystemContentAppearsBeforeUserContent() {
        let messages = [msg(.system, "SYS_CONTENT"), msg(.user, "USER_CONTENT")]
        let result = ChatTemplate.gemma3.format(messages: messages)
        let sysRange = result.range(of: "SYS_CONTENT")
        let userRange = result.range(of: "USER_CONTENT")
        XCTAssertNotNil(sysRange)
        XCTAssertNotNil(userRange)
        XCTAssertLessThan(sysRange!.lowerBound, userRange!.lowerBound)
    }

    func testGemma3EndsWithStartOfTurnModel() {
        let result = ChatTemplate.gemma3.format(messages: [msg(.user, "Hi")])
        XCTAssertTrue(result.hasSuffix("<start_of_turn>model\n"))
    }

    // MARK: - Cross-format

    func testAllFormatsProduceNonEmptyOutputForSingleUserMessage() {
        let messages = [msg(.user, "Hello")]
        let templates: [(ChatTemplate, String)] = [
            (.llama3, "llama3"),
            (.chatml, "chatml"),
            (.mistral, "mistral"),
            (.generic, "generic"),
            (.qwen3, "qwen3"),
            (.gemma3, "gemma3")
        ]
        for (template, name) in templates {
            let result = template.format(messages: messages)
            XCTAssertFalse(result.isEmpty, "\(name) produced empty output")
        }
    }

    func testDifferentFormatsProduceDifferentOutput() {
        let messages = [msg(.user, "Hello")]
        let llama3 = ChatTemplate.llama3.format(messages: messages)
        let chatml = ChatTemplate.chatml.format(messages: messages)
        let mistral = ChatTemplate.mistral.format(messages: messages)
        let generic = ChatTemplate.generic.format(messages: messages)
        let outputs = Set([llama3, chatml, mistral, generic])
        XCTAssertEqual(outputs.count, 4, "Different templates should produce different output")
    }
}
