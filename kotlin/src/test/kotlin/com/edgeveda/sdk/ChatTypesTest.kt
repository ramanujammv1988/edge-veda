package com.edgeveda.sdk

import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for ChatMessage, ChatRole, and SystemPromptPreset.
 */
class ChatTypesTest {

    // ── ChatMessage ────────────────────────────────────────────────────────────

    @Test
    fun `ChatMessage stores role and content correctly`() {
        val msg = ChatMessage(ChatRole.USER, "Hello world")
        assertEquals(ChatRole.USER, msg.role)
        assertEquals("Hello world", msg.content)
    }

    @Test
    fun `ChatMessage timestamp defaults to current time`() {
        val before = System.currentTimeMillis()
        val msg = ChatMessage(ChatRole.ASSISTANT, "Hi")
        val after = System.currentTimeMillis()
        assertTrue(msg.timestamp.time in before..after)
    }

    @Test
    fun `ChatMessage data class equality holds for same values`() {
        val t = java.util.Date(1_000_000L)
        val a = ChatMessage(ChatRole.USER, "test", t)
        val b = ChatMessage(ChatRole.USER, "test", t)
        assertEquals(a, b)
    }

    @Test
    fun `ChatMessage data class inequality on different roles`() {
        val t = java.util.Date(1_000_000L)
        val a = ChatMessage(ChatRole.USER, "test", t)
        val b = ChatMessage(ChatRole.ASSISTANT, "test", t)
        assertNotEquals(a, b)
    }

    @Test
    fun `ChatMessage data class inequality on different content`() {
        val t = java.util.Date(1_000_000L)
        val a = ChatMessage(ChatRole.USER, "hello", t)
        val b = ChatMessage(ChatRole.USER, "world", t)
        assertNotEquals(a, b)
    }

    @Test
    fun `ChatMessage copy produces independent instance`() {
        val original = ChatMessage(ChatRole.USER, "original")
        val copy = original.copy(content = "copy")
        assertEquals("original", original.content)
        assertEquals("copy", copy.content)
        assertEquals(original.role, copy.role)
    }

    @Test
    fun `ChatMessage accepts empty content`() {
        val msg = ChatMessage(ChatRole.SYSTEM, "")
        assertEquals("", msg.content)
    }

    // ── ChatRole ───────────────────────────────────────────────────────────────

    @Test
    fun `ChatRole has exactly 3 values`() {
        assertEquals(3, ChatRole.entries.size)
    }

    @Test
    fun `ChatRole entries contain SYSTEM USER and ASSISTANT`() {
        val names = ChatRole.entries.map { it.name }.toSet()
        assertEquals(setOf("SYSTEM", "USER", "ASSISTANT"), names)
    }

    @Test
    fun `ChatRole SYSTEM value is lowercase system`() {
        assertEquals("system", ChatRole.SYSTEM.value)
    }

    @Test
    fun `ChatRole USER value is lowercase user`() {
        assertEquals("user", ChatRole.USER.value)
    }

    @Test
    fun `ChatRole ASSISTANT value is lowercase assistant`() {
        assertEquals("assistant", ChatRole.ASSISTANT.value)
    }

    @Test
    fun `ChatRole value returns lowercase of name`() {
        for (role in ChatRole.entries) {
            assertEquals(role.name.lowercase(), role.value)
        }
    }

    // ── SystemPromptPreset ────────────────────────────────────────────────────

    @Test
    fun `SystemPromptPreset Assistant text is non-empty`() {
        assertTrue(SystemPromptPreset.Assistant.text.isNotEmpty())
    }

    @Test
    fun `SystemPromptPreset Coder text is non-empty`() {
        assertTrue(SystemPromptPreset.Coder.text.isNotEmpty())
    }

    @Test
    fun `SystemPromptPreset Concise text is non-empty`() {
        assertTrue(SystemPromptPreset.Concise.text.isNotEmpty())
    }

    @Test
    fun `SystemPromptPreset Creative text is non-empty`() {
        assertTrue(SystemPromptPreset.Creative.text.isNotEmpty())
    }

    @Test
    fun `SystemPromptPreset Custom returns provided prompt as text`() {
        val custom = SystemPromptPreset.Custom("You are a pirate.")
        assertEquals("You are a pirate.", custom.text)
    }

    @Test
    fun `SystemPromptPreset Custom with empty string returns empty text`() {
        val custom = SystemPromptPreset.Custom("")
        assertEquals("", custom.text)
    }

    @Test
    fun `SystemPromptPreset Custom data class equality`() {
        val a = SystemPromptPreset.Custom("same")
        val b = SystemPromptPreset.Custom("same")
        assertEquals(a, b)
    }

    @Test
    fun `SystemPromptPreset Custom data class inequality on different prompts`() {
        val a = SystemPromptPreset.Custom("a")
        val b = SystemPromptPreset.Custom("b")
        assertNotEquals(a, b)
    }

    @Test
    fun `all preset texts are distinct`() {
        val texts = listOf(
            SystemPromptPreset.Assistant.text,
            SystemPromptPreset.Coder.text,
            SystemPromptPreset.Concise.text,
            SystemPromptPreset.Creative.text,
        )
        assertEquals("All preset texts should be distinct", texts.size, texts.toSet().size)
    }
}
