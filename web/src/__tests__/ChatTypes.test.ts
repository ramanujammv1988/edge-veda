import { ChatRole, SystemPromptPreset, getSystemPrompt } from '../ChatTypes';

describe('ChatTypes', () => {
  describe('ChatRole enum', () => {
    it('SYSTEM === "system"', () => {
      expect(ChatRole.SYSTEM).toBe('system');
    });

    it('USER === "user"', () => {
      expect(ChatRole.USER).toBe('user');
    });

    it('ASSISTANT === "assistant"', () => {
      expect(ChatRole.ASSISTANT).toBe('assistant');
    });

    it('has exactly 6 string values (including TOOL_CALL, TOOL_RESULT, SUMMARY)', () => {
      const values = Object.values(ChatRole).filter((v) => typeof v === 'string');
      expect(values).toHaveLength(6);
    });

    it('TOOL_CALL === "tool_call"', () => {
      expect(ChatRole.TOOL_CALL).toBe('tool_call');
    });

    it('TOOL_RESULT === "tool_result"', () => {
      expect(ChatRole.TOOL_RESULT).toBe('tool_result');
    });

    it('SUMMARY === "summary"', () => {
      expect(ChatRole.SUMMARY).toBe('summary');
    });
  });

  describe('SystemPromptPreset enum', () => {
    it('ASSISTANT preset exists', () => {
      expect(SystemPromptPreset.ASSISTANT).toBeDefined();
    });

    it('CODER preset exists', () => {
      expect(SystemPromptPreset.CODER).toBeDefined();
    });

    it('CONCISE preset exists', () => {
      expect(SystemPromptPreset.CONCISE).toBeDefined();
    });

    it('CREATIVE preset exists', () => {
      expect(SystemPromptPreset.CREATIVE).toBeDefined();
    });

    it('has exactly 4 string values', () => {
      const values = Object.values(SystemPromptPreset).filter(
        (v) => typeof v === 'string'
      );
      expect(values).toHaveLength(4);
    });
  });

  describe('getSystemPrompt', () => {
    it('returns non-empty string for ASSISTANT', () => {
      const prompt = getSystemPrompt(SystemPromptPreset.ASSISTANT);
      expect(typeof prompt).toBe('string');
      expect(prompt.trim()).not.toBe('');
    });

    it('returns text containing "programmer" for CODER', () => {
      const prompt = getSystemPrompt(SystemPromptPreset.CODER);
      expect(prompt.toLowerCase()).toMatch(/code|programmer/);
    });

    it('returns text containing "concise" or "brief" for CONCISE', () => {
      const prompt = getSystemPrompt(SystemPromptPreset.CONCISE);
      expect(prompt.toLowerCase()).toMatch(/concise|brief/);
    });

    it('returns text for CREATIVE', () => {
      const prompt = getSystemPrompt(SystemPromptPreset.CREATIVE);
      expect(typeof prompt).toBe('string');
      expect(prompt.trim()).not.toBe('');
    });

    it('all presets return distinct prompt texts', () => {
      const prompts = Object.values(SystemPromptPreset)
        .filter((v) => typeof v === 'string')
        .map((preset) => getSystemPrompt(preset as SystemPromptPreset));
      const unique = new Set(prompts);
      expect(unique.size).toBe(prompts.length);
    });

    it('ASSISTANT prompt mentions "assistant"', () => {
      const prompt = getSystemPrompt(SystemPromptPreset.ASSISTANT);
      expect(prompt.toLowerCase()).toContain('assistant');
    });
  });
});
