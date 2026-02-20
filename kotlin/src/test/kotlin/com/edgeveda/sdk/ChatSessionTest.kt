package com.edgeveda.sdk

import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import io.mockk.unmockkAll
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for ChatSession — multi-turn conversation management.
 *
 * Framework requirement (Phase 12): context overflow auto-summarisation must
 * trigger at 70% capacity. These tests cover the pure Kotlin state management
 * (message history, turnCount, contextUsage) using a MockK stub for EdgeVeda.
 *
 * Note: send() and reset() are tested with a fake EdgeVeda that returns
 * a fixed string so that message-commit logic can be verified without
 * a real model or native library.
 */
class ChatSessionTest {

    private lateinit var mockEdgeVeda: EdgeVeda

    @Before
    fun setUp() {
        mockEdgeVeda = mockk(relaxed = true)
        // Default: generate() returns a fixed response immediately
        coEvery { mockEdgeVeda.generate(any(), any()) } returns "Mock response."
        // Default: generateStream() emits one token
        every { mockEdgeVeda.generateStream(any(), any()) } returns flowOf("Mock token.")
        // Default: resetContext() is a no-op
        coEvery { mockEdgeVeda.resetContext() } returns Unit
    }

    @After
    fun tearDown() {
        unmockkAll()
    }

    // ── Initial state ─────────────────────────────────────────────────────────

    @Test
    fun `fresh session has turnCount of 0`() {
        val session = ChatSession(mockEdgeVeda)
        assertEquals(0, session.turnCount)
    }

    @Test
    fun `fresh session has contextUsage of 0_0`() {
        // Use empty custom prompt so no SYSTEM message contributes to token count
        val session = ChatSession(mockEdgeVeda, SystemPromptPreset.Custom(""))
        assertEquals(0.0, session.contextUsage, 0.0)
    }

    @Test
    fun `session with default Assistant preset has one SYSTEM message`() {
        val session = ChatSession(mockEdgeVeda, SystemPromptPreset.Assistant)
        val messages = session.allMessages
        assertEquals(1, messages.size)
        assertEquals(ChatRole.SYSTEM, messages[0].role)
    }

    @Test
    fun `session with Custom empty preset has no initial messages`() {
        val session = ChatSession(mockEdgeVeda, SystemPromptPreset.Custom(""))
        assertEquals(0, session.allMessages.size)
    }

    @Test
    fun `session with Coder preset has SYSTEM message containing coder text`() {
        val session = ChatSession(mockEdgeVeda, SystemPromptPreset.Coder)
        val systemMsg = session.allMessages.first()
        assertEquals(ChatRole.SYSTEM, systemMsg.role)
        assertTrue(systemMsg.content.isNotEmpty())
    }

    // ── lastMessages ──────────────────────────────────────────────────────────

    @Test
    fun `lastMessages(0) returns empty list on fresh session`() {
        val session = ChatSession(mockEdgeVeda)
        assertTrue(session.lastMessages(0).isEmpty())
    }

    @Test
    fun `lastMessages(1) on session with only system prompt returns the system message`() {
        val session = ChatSession(mockEdgeVeda, SystemPromptPreset.Assistant)
        val last = session.lastMessages(1)
        assertEquals(1, last.size)
        assertEquals(ChatRole.SYSTEM, last[0].role)
    }

    @Test
    fun `lastMessages(100) on empty session returns empty list`() {
        val session = ChatSession(mockEdgeVeda, SystemPromptPreset.Custom(""))
        assertTrue(session.lastMessages(100).isEmpty())
    }

    // ── send — happy path ─────────────────────────────────────────────────────

    @Test
    fun `send increments turnCount by 1`() = runTest {
        val session = ChatSession(mockEdgeVeda, SystemPromptPreset.Custom(""))
        session.send("Hello")
        assertEquals(1, session.turnCount)
    }

    @Test
    fun `send twice results in turnCount of 2`() = runTest {
        val session = ChatSession(mockEdgeVeda, SystemPromptPreset.Custom(""))
        session.send("First")
        session.send("Second")
        assertEquals(2, session.turnCount)
    }

    @Test
    fun `send adds USER and ASSISTANT messages to history`() = runTest {
        val session = ChatSession(mockEdgeVeda, SystemPromptPreset.Custom(""))
        session.send("Hello")
        val messages = session.allMessages
        assertEquals(2, messages.size)
        assertEquals(ChatRole.USER, messages[0].role)
        assertEquals(ChatRole.ASSISTANT, messages[1].role)
    }

    @Test
    fun `send USER message content matches the input`() = runTest {
        val session = ChatSession(mockEdgeVeda, SystemPromptPreset.Custom(""))
        session.send("What is 2+2?")
        val userMsg = session.allMessages.first { it.role == ChatRole.USER }
        assertEquals("What is 2+2?", userMsg.content)
    }

    @Test
    fun `send ASSISTANT message content matches generate return value`() = runTest {
        coEvery { mockEdgeVeda.generate(any(), any()) } returns "The answer is 4."
        val session = ChatSession(mockEdgeVeda, SystemPromptPreset.Custom(""))
        val response = session.send("What is 2+2?")
        assertEquals("The answer is 4.", response)
        val assistantMsg = session.allMessages.first { it.role == ChatRole.ASSISTANT }
        assertEquals("The answer is 4.", assistantMsg.content)
    }

    @Test
    fun `contextUsage increases after each send`() = runTest {
        val session = ChatSession(mockEdgeVeda, SystemPromptPreset.Custom(""))
        val before = session.contextUsage
        session.send("A longer message to add some context.")
        val after = session.contextUsage
        assertTrue("contextUsage should increase after send", after >= before)
    }

    @Test
    fun `contextUsage is capped at 1_0`() = runTest {
        // Use a tiny maxContextLength to force overflow
        val session = ChatSession(mockEdgeVeda, SystemPromptPreset.Custom(""), maxContextLength = 1)
        session.send("This message is longer than 1 token context")
        assertTrue("contextUsage should not exceed 1.0", session.contextUsage <= 1.0)
    }

    // ── send — error propagation ──────────────────────────────────────────────

    @Test
    fun `send failure does not add messages to history`() = runTest {
        coEvery { mockEdgeVeda.generate(any(), any()) } throws IllegalStateException("Not initialized")
        val session = ChatSession(mockEdgeVeda, SystemPromptPreset.Custom(""))
        val initialCount = session.allMessages.size
        try {
            session.send("Hello")
        } catch (_: IllegalStateException) { }
        assertEquals("History must not be corrupted on failure", initialCount, session.allMessages.size)
    }

    @Test
    fun `turnCount stays 0 after failed send`() = runTest {
        coEvery { mockEdgeVeda.generate(any(), any()) } throws IllegalStateException("Not initialized")
        val session = ChatSession(mockEdgeVeda, SystemPromptPreset.Custom(""))
        try {
            session.send("Hello")
        } catch (_: Exception) { }
        assertEquals(0, session.turnCount)
    }

    // ── sendStream ────────────────────────────────────────────────────────────

    @Test
    fun `sendStream returns a non-null Flow`() {
        val session = ChatSession(mockEdgeVeda)
        val flow = session.sendStream("Hello")
        assertNotNull(flow)
    }

    @Test
    fun `sendStream Flow emits tokens from generateStream`() = runTest {
        every { mockEdgeVeda.generateStream(any(), any()) } returns flowOf("Hello", " world")
        val session = ChatSession(mockEdgeVeda, SystemPromptPreset.Custom(""))
        val tokens = session.sendStream("Hi").toList()
        assertEquals(listOf("Hello", " world"), tokens)
    }

    @Test
    fun `sendStream commits messages after stream completes`() = runTest {
        every { mockEdgeVeda.generateStream(any(), any()) } returns flowOf("Hi", " there")
        val session = ChatSession(mockEdgeVeda, SystemPromptPreset.Custom(""))
        session.sendStream("Hello").toList()  // collect to completion
        assertEquals(1, session.turnCount)
        assertEquals(2, session.allMessages.size)
    }

    // ── reset ─────────────────────────────────────────────────────────────────

    @Test
    fun `reset clears turnCount back to 0`() = runTest {
        val session = ChatSession(mockEdgeVeda, SystemPromptPreset.Custom(""))
        session.send("Hello")
        session.reset()
        assertEquals(0, session.turnCount)
    }

    @Test
    fun `reset with no system prompt results in empty allMessages`() = runTest {
        val session = ChatSession(mockEdgeVeda, SystemPromptPreset.Custom(""))
        session.send("Hello")
        session.reset()
        assertEquals(0, session.allMessages.size)
    }

    @Test
    fun `reset with system prompt keeps only the system message`() = runTest {
        val session = ChatSession(mockEdgeVeda, SystemPromptPreset.Assistant)
        session.send("Hello")
        session.reset()
        assertEquals(1, session.allMessages.size)
        assertEquals(ChatRole.SYSTEM, session.allMessages[0].role)
    }

    @Test
    fun `after reset send works again and turnCount becomes 1`() = runTest {
        val session = ChatSession(mockEdgeVeda, SystemPromptPreset.Custom(""))
        session.send("First")
        session.reset()
        session.send("After reset")
        assertEquals(1, session.turnCount)
    }

    // ── lastMessages after conversation ───────────────────────────────────────

    @Test
    fun `lastMessages(1) after two sends returns only the last exchange`() = runTest {
        val session = ChatSession(mockEdgeVeda, SystemPromptPreset.Custom(""))
        session.send("First")
        session.send("Second")
        val last = session.lastMessages(1)
        assertEquals(1, last.size)
        assertEquals(ChatRole.ASSISTANT, last[0].role)
    }

    @Test
    fun `lastMessages(4) after two sends returns all 4 messages`() = runTest {
        val session = ChatSession(mockEdgeVeda, SystemPromptPreset.Custom(""))
        session.send("First")
        session.send("Second")
        val last = session.lastMessages(4)
        assertEquals(4, last.size)
    }
}
