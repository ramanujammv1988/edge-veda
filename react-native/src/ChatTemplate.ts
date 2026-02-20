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
  }
}

function formatLlama3(messages: ChatMessage[]): string {
  let prompt = '';
  
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
  let prompt = '';
  
  for (const message of messages) {
    switch (message.role) {
      case ChatRole.SYSTEM:
        // Mistral typically includes system messages at the start
        prompt += `${message.content}\n\n`;
        break;
      case ChatRole.USER:
        prompt += `[INST] ${message.content} [/INST]`;
        break;
      case ChatRole.ASSISTANT:
        prompt += ` ${message.content}</s>`;
        break;
    }
  }
  
  return prompt;
}