import EdgeVeda from './index';
import { ChatMessage, ChatRole, SystemPromptPreset, getSystemPrompt } from './ChatTypes';
import { ChatTemplate, formatMessages } from './ChatTemplate';

/**
 * Manages a multi-turn chat conversation with context tracking
 */
export class ChatSession {
  private edgeVeda: EdgeVeda;
  private messages: ChatMessage[] = [];
  private maxContextLength: number;
  private template: ChatTemplate;
  private systemPromptText: string | null;
  
  /**
   * Creates a new chat session
   */
  constructor(
    edgeVeda: EdgeVeda,
    options: {
      systemPrompt?: SystemPromptPreset;
      maxContextLength?: number;
      template?: ChatTemplate;
    } = {}
  ) {
    this.edgeVeda = edgeVeda;
    this.maxContextLength = options.maxContextLength ?? 2048;
    this.template = options.template ?? ChatTemplate.LLAMA3;
    
    // Add system prompt if provided
    this.systemPromptText = options.systemPrompt ? getSystemPrompt(options.systemPrompt) : null;
    if (this.systemPromptText) {
      this.messages.push({
        role: ChatRole.SYSTEM,
        content: this.systemPromptText,
        timestamp: new Date(),
      });
    }
  }
  
  /**
   * Sends a message and returns the complete response
   */
  async send(message: string, options?: any): Promise<string> {
    // Add user message
    this.messages.push({
      role: ChatRole.USER,
      content: message,
      timestamp: new Date(),
    });
    
    // Format the prompt
    const prompt = this.formatPrompt();
    
    // Generate response
    const response = await this.edgeVeda.generate({ prompt, ...options });
    
    // Add assistant response
    this.messages.push({
      role: ChatRole.ASSISTANT,
      content: response,
      timestamp: new Date(),
    });
    
    return response;
  }
  
  /**
   * Sends a message and streams the response token by token
   */
  async *sendStream(message: string, options?: any): AsyncGenerator<string, void, unknown> {
    // Add user message
    this.messages.push({
      role: ChatRole.USER,
      content: message,
      timestamp: new Date(),
    });
    
    // Format the prompt
    const prompt = this.formatPrompt();
    let fullResponse = '';
    
    // Stream tokens
    for await (const chunk of this.edgeVeda.generateStream({ prompt, ...options })) {
      fullResponse += chunk.token;
      yield chunk.token;
    }
    
    // Add complete assistant response
    this.messages.push({
      role: ChatRole.ASSISTANT,
      content: fullResponse,
      timestamp: new Date(),
    });
  }
  
  /**
   * Resets the conversation, keeping only the system prompt
   */
  async reset(): Promise<void> {
    const systemMsg = this.messages.find(m => m.role === ChatRole.SYSTEM);
    this.messages = systemMsg ? [systemMsg] : [];
    await this.edgeVeda.resetContext();
  }
  
  /**
   * Returns the number of conversation turns (user messages)
   */
  get turnCount(): number {
    return this.messages.filter(m => m.role === ChatRole.USER).length;
  }
  
  /**
   * Returns the estimated context usage as a percentage (0.0 to 1.0)
   */
  get contextUsage(): number {
    const totalTokens = this.estimateTokens();
    return totalTokens / this.maxContextLength;
  }
  
  /**
   * Returns all messages in the conversation
   */
  get allMessages(): ChatMessage[] {
    return [...this.messages];
  }
  
  /**
   * Returns the last N messages in the conversation
   */
  lastMessages(count: number): ChatMessage[] {
    const startIndex = Math.max(0, this.messages.length - count);
    return this.messages.slice(startIndex);
  }
  
  /**
   * Formats all messages into a prompt using the chat template
   */
  private formatPrompt(): string {
    return formatMessages(this.template, this.messages);
  }
  
  /**
   * Estimates the total token count for all messages
   * Uses a rough heuristic: ~4 characters per token
   */
  private estimateTokens(): number {
    const totalChars = this.messages.reduce((sum, msg) => sum + msg.content.length, 0);
    return Math.floor(totalChars / 4);
  }
}