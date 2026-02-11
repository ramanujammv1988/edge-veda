/**
 * Represents a message in a chat conversation
 */
export interface ChatMessage {
  /** The role of the message sender */
  role: ChatRole;
  
  /** The content of the message */
  content: string;
  
  /** When the message was created */
  timestamp: Date;
}

/**
 * The role of a message in a chat conversation
 */
export enum ChatRole {
  /** System messages set the behavior and context */
  SYSTEM = 'system',
  
  /** User messages contain user input */
  USER = 'user',
  
  /** Assistant messages contain AI responses */
  ASSISTANT = 'assistant',
}

/**
 * Pre-configured system prompts for different use cases
 */
export enum SystemPromptPreset {
  /** General helpful AI assistant */
  ASSISTANT = 'assistant',
  
  /** Expert programmer assistant */
  CODER = 'coder',
  
  /** Brief, to-the-point assistant */
  CONCISE = 'concise',
  
  /** Creative and expressive assistant */
  CREATIVE = 'creative',
}

/**
 * Gets the text for a system prompt preset
 */
export function getSystemPrompt(preset: SystemPromptPreset): string {
  switch (preset) {
    case SystemPromptPreset.ASSISTANT:
      return 'You are a helpful AI assistant.';
    case SystemPromptPreset.CODER:
      return 'You are an expert programmer. Provide clear, concise code examples.';
    case SystemPromptPreset.CONCISE:
      return 'You are a concise assistant. Keep responses brief and to the point.';
    case SystemPromptPreset.CREATIVE:
      return 'You are a creative AI with vivid imagination. Be expressive and original.';
  }
}