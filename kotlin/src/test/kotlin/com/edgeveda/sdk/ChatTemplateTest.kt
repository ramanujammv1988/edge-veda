package com.edgeveda.sdk

import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for ChatTemplate — verifies all 6 chat format implementations:
 * LLAMA3, CHATML, MISTRAL, GENERIC, QWEN3, GEMMA3.
 *
 * Mirrors the Flutter gold standard's ChatTemplate format tests.
 * All tests are pure (no I/O, no coroutines, no mocks).
 */
class ChatTemplateTest {

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun user(text: String) = ChatMessage(ChatRole.USER, text)
    private fun system(text: String) = ChatMessage(ChatRole.SYSTEM, text)
    private fun assistant(text: String) = ChatMessage(ChatRole.ASSISTANT, text)

    // ── LLAMA3 ────────────────────────────────────────────────────────────────

    @Test
    fun `LLAMA3 output starts with begin_of_text token`() {
        val result = ChatTemplate.LLAMA3.format(listOf(user("Hello")))
        assertTrue("Must start with BOS token", result.startsWith("<|begin_of_text|>"))
    }

    @Test
    fun `LLAMA3 wraps user message with header tokens`() {
        val result = ChatTemplate.LLAMA3.format(listOf(user("Hello")))
        assertTrue(result.contains("<|start_header_id|>user<|end_header_id|>"))
        assertTrue(result.contains("Hello"))
    }

    @Test
    fun `LLAMA3 wraps system message with header tokens`() {
        val result = ChatTemplate.LLAMA3.format(listOf(system("Be helpful"), user("Hi")))
        assertTrue(result.contains("<|start_header_id|>system<|end_header_id|>"))
        assertTrue(result.contains("Be helpful"))
    }

    @Test
    fun `LLAMA3 includes eot_id token after each message`() {
        val result = ChatTemplate.LLAMA3.format(listOf(user("Hello")))
        assertTrue(result.contains("<|eot_id|>"))
    }

    @Test
    fun `LLAMA3 ends with assistant header to prompt continuation`() {
        val result = ChatTemplate.LLAMA3.format(listOf(user("Hello")))
        assertTrue(result.endsWith("<|start_header_id|>assistant<|end_header_id|>\n\n"))
    }

    @Test
    fun `LLAMA3 multi-turn conversation contains all messages`() {
        val messages = listOf(
            system("You are helpful"),
            user("What is 2+2?"),
            assistant("4"),
            user("Thanks")
        )
        val result = ChatTemplate.LLAMA3.format(messages)
        assertTrue(result.contains("You are helpful"))
        assertTrue(result.contains("What is 2+2?"))
        assertTrue(result.contains("4"))
        assertTrue(result.contains("Thanks"))
    }

    @Test
    fun `LLAMA3 uses role value in lowercase`() {
        val result = ChatTemplate.LLAMA3.format(listOf(user("Hi")))
        assertFalse("Should not have uppercase USER", result.contains("<|start_header_id|>USER<|end_header_id|>"))
        assertTrue(result.contains("<|start_header_id|>user<|end_header_id|>"))
    }

    // ── CHATML ────────────────────────────────────────────────────────────────

    @Test
    fun `CHATML wraps user message with im_start and im_end`() {
        val result = ChatTemplate.CHATML.format(listOf(user("Hello")))
        assertTrue(result.contains("<|im_start|>user"))
        assertTrue(result.contains("<|im_end|>"))
        assertTrue(result.contains("Hello"))
    }

    @Test
    fun `CHATML wraps system message with im_start and im_end`() {
        val result = ChatTemplate.CHATML.format(listOf(system("Be concise"), user("Hi")))
        assertTrue(result.contains("<|im_start|>system"))
        assertTrue(result.contains("Be concise"))
    }

    @Test
    fun `CHATML wraps assistant message with im_start and im_end`() {
        val result = ChatTemplate.CHATML.format(listOf(user("Hi"), assistant("Hello!")))
        assertTrue(result.contains("<|im_start|>assistant"))
        assertTrue(result.contains("Hello!"))
    }

    @Test
    fun `CHATML ends with assistant im_start to prompt continuation`() {
        val result = ChatTemplate.CHATML.format(listOf(user("Hello")))
        assertTrue("Must end with assistant prompt", result.endsWith("<|im_start|>assistant\n"))
    }

    @Test
    fun `CHATML multi-turn conversation preserves message order`() {
        val messages = listOf(
            system("System prompt"),
            user("First user message"),
            assistant("First response"),
            user("Second user message")
        )
        val result = ChatTemplate.CHATML.format(messages)
        val systemIndex = result.indexOf("System prompt")
        val firstUserIndex = result.indexOf("First user message")
        val assistantIndex = result.indexOf("First response")
        val secondUserIndex = result.indexOf("Second user message")
        assertTrue(systemIndex < firstUserIndex)
        assertTrue(firstUserIndex < assistantIndex)
        assertTrue(assistantIndex < secondUserIndex)
    }

    // ── MISTRAL ───────────────────────────────────────────────────────────────

    @Test
    fun `MISTRAL wraps user message with INST markers`() {
        val result = ChatTemplate.MISTRAL.format(listOf(user("Hello")))
        assertTrue(result.contains("[INST]"))
        assertTrue(result.contains("[/INST]"))
        assertTrue(result.contains("Hello"))
    }

    @Test
    fun `MISTRAL embeds system in first user message via SYS markers`() {
        val messages = listOf(system("Be helpful"), user("Hello"))
        val result = ChatTemplate.MISTRAL.format(messages)
        assertTrue(result.contains("<<SYS>>"))
        assertTrue(result.contains("<</SYS>>"))
        assertTrue(result.contains("Be helpful"))
    }

    @Test
    fun `MISTRAL system content appears before first user content`() {
        val messages = listOf(system("System"), user("User"))
        val result = ChatTemplate.MISTRAL.format(messages)
        val sysIndex = result.indexOf("System")
        val userIndex = result.indexOf("User")
        assertTrue(sysIndex < userIndex)
    }

    @Test
    fun `MISTRAL does not produce standalone system header`() {
        val messages = listOf(system("Instructions"), user("Hello"))
        val result = ChatTemplate.MISTRAL.format(messages)
        assertFalse(result.contains("[INST] Instructions [/INST]"))
    }

    @Test
    fun `MISTRAL assistant message ends with closing s tag`() {
        val messages = listOf(user("Hi"), assistant("Hello!"))
        val result = ChatTemplate.MISTRAL.format(messages)
        assertTrue(result.contains("Hello!</s>"))
    }

    // ── GENERIC ───────────────────────────────────────────────────────────────

    @Test
    fun `GENERIC uses hash System marker`() {
        val result = ChatTemplate.GENERIC.format(listOf(system("Rules"), user("Hi")))
        assertTrue(result.contains("### System:\nRules"))
    }

    @Test
    fun `GENERIC uses hash User marker`() {
        val result = ChatTemplate.GENERIC.format(listOf(user("Hello")))
        assertTrue(result.contains("### User:\nHello"))
    }

    @Test
    fun `GENERIC ends with assistant marker to prompt continuation`() {
        val result = ChatTemplate.GENERIC.format(listOf(user("Hello")))
        assertTrue(result.endsWith("### Assistant:\n"))
    }

    @Test
    fun `GENERIC includes assistant content when provided`() {
        val messages = listOf(user("Hi"), assistant("Hey there"))
        val result = ChatTemplate.GENERIC.format(messages)
        assertTrue(result.contains("### Assistant:\nHey there"))
    }

    @Test
    fun `GENERIC multi-turn keeps all messages in order`() {
        val messages = listOf(
            system("Be concise"),
            user("Q1"),
            assistant("A1"),
            user("Q2")
        )
        val result = ChatTemplate.GENERIC.format(messages)
        val sysIdx = result.indexOf("### System:")
        val q1Idx = result.indexOf("Q1")
        val a1Idx = result.indexOf("A1")
        val q2Idx = result.indexOf("Q2")
        assertTrue(sysIdx < q1Idx)
        assertTrue(q1Idx < a1Idx)
        assertTrue(a1Idx < q2Idx)
    }

    // ── QWEN3 ─────────────────────────────────────────────────────────────────

    @Test
    fun `QWEN3 uses im_start and im_end tokens like CHATML`() {
        val result = ChatTemplate.QWEN3.format(listOf(user("Hello")))
        assertTrue(result.contains("<|im_start|>"))
        assertTrue(result.contains("<|im_end|>"))
    }

    @Test
    fun `QWEN3 uses lowercase role names`() {
        val messages = listOf(system("System"), user("User"), assistant("Assistant"))
        val result = ChatTemplate.QWEN3.format(messages)
        assertTrue(result.contains("<|im_start|>system"))
        assertTrue(result.contains("<|im_start|>user"))
        assertTrue(result.contains("<|im_start|>assistant"))
        assertFalse(result.contains("<|im_start|>SYSTEM"))
        assertFalse(result.contains("<|im_start|>USER"))
    }

    @Test
    fun `QWEN3 ends with assistant im_start to prompt continuation`() {
        val result = ChatTemplate.QWEN3.format(listOf(user("Hello")))
        assertTrue(result.endsWith("<|im_start|>assistant\n"))
    }

    @Test
    fun `QWEN3 contains message content`() {
        val result = ChatTemplate.QWEN3.format(listOf(user("test content")))
        assertTrue(result.contains("test content"))
    }

    // ── GEMMA3 ────────────────────────────────────────────────────────────────

    @Test
    fun `GEMMA3 uses start_of_turn user token`() {
        val result = ChatTemplate.GEMMA3.format(listOf(user("Hello")))
        assertTrue(result.contains("<start_of_turn>user"))
    }

    @Test
    fun `GEMMA3 uses start_of_turn model token for assistant`() {
        val messages = listOf(user("Hi"), assistant("Hello!"))
        val result = ChatTemplate.GEMMA3.format(messages)
        assertTrue(result.contains("<start_of_turn>model"))
        assertTrue(result.contains("Hello!"))
    }

    @Test
    fun `GEMMA3 does not use system role token`() {
        val messages = listOf(system("Be brief"), user("Hi"))
        val result = ChatTemplate.GEMMA3.format(messages)
        assertFalse("GEMMA3 must not have system turn token",
            result.contains("<start_of_turn>system"))
    }

    @Test
    fun `GEMMA3 merges system message content into first user turn`() {
        val messages = listOf(system("Be brief"), user("Hello"))
        val result = ChatTemplate.GEMMA3.format(messages)
        assertTrue("System content must appear in result", result.contains("Be brief"))
        // System and user content appear in the same user turn block
        val userTurnStart = result.indexOf("<start_of_turn>user")
        val sysMsgStart = result.indexOf("Be brief")
        val userMsgStart = result.indexOf("Hello")
        assertTrue(userTurnStart < sysMsgStart)
        assertTrue(sysMsgStart < userMsgStart)
    }

    @Test
    fun `GEMMA3 without system prompt produces single user turn`() {
        val result = ChatTemplate.GEMMA3.format(listOf(user("Just a question")))
        assertEquals(1, result.split("<start_of_turn>user").size - 1)
    }

    @Test
    fun `GEMMA3 ends with model turn to prompt continuation`() {
        val result = ChatTemplate.GEMMA3.format(listOf(user("Hello")))
        assertTrue(result.endsWith("<start_of_turn>model\n"))
    }

    @Test
    fun `GEMMA3 includes end_of_turn token after each completed turn`() {
        val messages = listOf(user("Hi"), assistant("Hello"))
        val result = ChatTemplate.GEMMA3.format(messages)
        assertTrue(result.contains("<end_of_turn>"))
    }

    // ── Edge cases (all templates) ─────────────────────────────────────────────

    @Test
    fun `all templates produce non-empty output for a user message`() {
        val messages = listOf(user("Hello"))
        ChatTemplate.entries.forEach { template ->
            val result = template.format(messages)
            assertTrue("${template.name} produced empty output", result.isNotEmpty())
        }
    }

    @Test
    fun `all templates include user message content`() {
        val content = "unique-test-content-12345"
        val messages = listOf(user(content))
        ChatTemplate.entries.forEach { template ->
            val result = template.format(messages)
            assertTrue("${template.name} does not contain user content",
                result.contains(content))
        }
    }

    @Test
    fun `ChatTemplate has exactly 6 variants`() =
        assertEquals(6, ChatTemplate.entries.size)
}
