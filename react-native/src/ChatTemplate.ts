import { ChatMessage, ChatRole } from './ChatTypes';

/**
 * Chat template formats for different model families
 */
export enum ChatTemplate {
  /** Llama 3 chat format */
  LLAMA3 = 'llama3',

  /** ChatML format (used by OpenAI, GPT-4, etc.) */
  CHATML = 'chatml',

  /** Mistral/Mixtral chat format */
  MISTRAL = 'mistral',

  /** Generic markdown-style format (### System: / ### User: / ### Assistant:) */
  GENERIC = 'generic',

  /** Qwen3 format — ChatML base with tool-call support */
  QWEN3 = 'qwen3',

  /** Gemma3 format — <start_of_turn> / <end_of_turn> with "model" role */
  GEMMA3 = 'gemma3',
}

/**
 * Formats messages according to a chat template
 */
export function formatMessages(template: ChatTemplate, messages: ChatMessage[]): string {
  switch (template) {
    case ChatTemplate.LLAMA3:
      return formatLlama3(messages);
    case ChatTemplate.CHATML:
      return formatChatML(messages);
    case ChatTemplate.MISTRAL:
      return formatMistral(messages);
    case ChatTemplate.GENERIC:
      return formatGeneric(messages);
    case ChatTemplate.QWEN3:
      return formatQwen3(messages);
    case ChatTemplate.GEMMA3:
      return formatGemma3(messages);
  }
}

function formatLlama3(messages: ChatMessage[]): string {
  let prompt = '<|begin_of_text|>';

  for (const message of messages) {
    prompt += `<|start_header_id|>${message.role}<|end_header_id|>\n\n`;
    prompt += `${message.content}<|eot_id|>`;
  }

  // Add assistant prompt to continue generation
  prompt += '<|start_header_id|>assistant<|end_header_id|>\n\n';

  return prompt;
}

function formatChatML(messages: ChatMessage[]): string {
  let prompt = '';

  for (const message of messages) {
    prompt += `<|im_start|>${message.role}\n`;
    prompt += `${message.content}<|im_end|>\n`;
  }

  // Add assistant prompt to continue generation
  prompt += '<|im_start|>assistant\n';

  return prompt;
}

function formatMistral(messages: ChatMessage[]): string {
  let prompt = '<s>';
  let pendingSystem: string | undefined;

  for (const message of messages) {
    switch (message.role) {
      case ChatRole.SYSTEM:
        pendingSystem = message.content;
        break;
      case ChatRole.USER:
        prompt += '[INST]';
        if (pendingSystem !== undefined) {
          prompt += ` <<SYS>>\n${pendingSystem}\n<</SYS>>\n\n`;
          pendingSystem = undefined;
        } else {
          prompt += ' ';
        }
        prompt += `${message.content} [/INST]`;
        break;
      case ChatRole.ASSISTANT:
        prompt += ` ${message.content}</s>`;
        break;
      case ChatRole.TOOL_RESULT:
        prompt += `[INST] Tool result: ${message.content} [/INST]`;
        break;
      case ChatRole.SUMMARY:
        // Inject summary as the next system block
        pendingSystem = `[Context Summary] ${message.content}`;
        break;
      // TOOL_CALL is already part of the assistant output — skip to avoid duplication
    }
  }

  return prompt;
}

function formatGeneric(messages: ChatMessage[]): string {
  let prompt = '';

  for (const message of messages) {
    switch (message.role) {
      case ChatRole.SYSTEM:
        prompt += `### System:\n${message.content}\n\n`;
        break;
      case ChatRole.USER:
        prompt += `### User:\n${message.content}\n`;
        break;
      case ChatRole.ASSISTANT:
        prompt += `### Assistant:\n${message.content}\n`;
        break;
      case ChatRole.TOOL_CALL:
        prompt += `### Tool Call:\n${message.content}\n`;
        break;
      case ChatRole.TOOL_RESULT:
        prompt += `### Tool Result:\n${message.content}\n`;
        break;
      case ChatRole.SUMMARY:
        prompt += `### Context Summary:\n${message.content}\n\n`;
        break;
    }
  }

  prompt += '### Assistant:\n';
  return prompt;
}

function formatQwen3(messages: ChatMessage[]): string {
  let prompt = '';

  for (const message of messages) {
    switch (message.role) {
      case ChatRole.SYSTEM:
        prompt += `<|im_start|>system\n${message.content}<|im_end|>\n`;
        break;
      case ChatRole.USER:
        prompt += `<|im_start|>user\n${message.content}<|im_end|>\n`;
        break;
      case ChatRole.ASSISTANT:
        prompt += `<|im_start|>assistant\n${message.content}<|im_end|>\n`;
        break;
      case ChatRole.TOOL_CALL:
        // Hermes-style: tool call is part of the assistant turn
        prompt += `<|im_start|>assistant\n${message.content}<|im_end|>\n`;
        break;
      case ChatRole.TOOL_RESULT:
        // Hermes-style: tool results use the "tool" role
        prompt += `<|im_start|>tool\n${message.content}<|im_end|>\n`;
        break;
      case ChatRole.SUMMARY:
        prompt += `<|im_start|>system\n[Context Summary] ${message.content}<|im_end|>\n`;
        break;
    }
  }

  // Prime assistant turn for generation
  prompt += '<|im_start|>assistant\n';
  return prompt;
}

function formatGemma3(messages: ChatMessage[]): string {
  let prompt = '';

  for (const message of messages) {
    switch (message.role) {
      case ChatRole.SYSTEM:
        // Gemma3 has no dedicated system turn — prepend to first user turn
        prompt += `<start_of_turn>user\n${message.content}<end_of_turn>\n`;
        break;
      case ChatRole.USER:
        prompt += `<start_of_turn>user\n${message.content}<end_of_turn>\n`;
        break;
      case ChatRole.ASSISTANT:
        // Gemma3 uses "model" as the assistant role name
        prompt += `<start_of_turn>model\n${message.content}<end_of_turn>\n`;
        break;
      case ChatRole.TOOL_CALL:
        prompt += `<start_of_turn>model\n${message.content}<end_of_turn>\n`;
        break;
      case ChatRole.TOOL_RESULT:
        prompt += `<start_of_turn>tool\n${message.content}<end_of_turn>\n`;
        break;
      case ChatRole.SUMMARY:
        prompt += `<start_of_turn>user\n[Context Summary] ${message.content}<end_of_turn>\n`;
        break;
    }
  }

  // Prime model turn for generation
  prompt += '<start_of_turn>model\n';
  return prompt;
}
