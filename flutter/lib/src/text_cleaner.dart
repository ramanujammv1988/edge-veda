/// Pure-Dart text cleaning utilities for LLM response post-processing.
///
/// Strips special tokens and template artifacts from model output before
/// display or TTS. No native dependencies -- safe for unit testing.
library;

/// Utility class for cleaning LLM response text.
///
/// Removes special tokens (Llama 3, ChatML, Gemma) that may leak into
/// generated text as literal strings. These tokens are meaningful to
/// llama.cpp's tokenizer but should never appear in user-facing text.
class TextCleaner {
  // Prevent instantiation -- all methods are static.
  TextCleaner._();

  /// Pattern matching Llama 3, ChatML, and Gemma special tokens that
  /// may leak into generated text.
  static final specialTokenPattern = RegExp(
    // Match full Llama 3 header blocks: <|start_header_id|>role<|end_header_id|>
    // This catches leaked next-turn headers like "assistant", "user", "system"
    // that would otherwise be left as orphaned text after stripping tags.
    r'<\|start_header_id\|>[^<]*<\|end_header_id\|>'
    // ChatML role headers: <|im_start|>role\n -- must come BEFORE the
    // individual token list so that the longer match (including role name
    // and trailing newline) wins over the bare <|im_start|> token.
    // Only consumes trailing word+newline (not bare word without newline).
    r'|<\|im_start\|>(?:\w+\n|\n)'
    // Individual special tokens (Llama 3, ChatML, Gemma)
    r'|<\|(?:begin_of_text|end_of_text|start_header_id|end_header_id|eot_id|'
    r'im_start|im_end|finetune_right_pad|reserved_special_token_\d+)\|>'
    // Gemma turn markers
    r'|<(?:start_of_turn|end_of_turn)>\s*\w*\n?',
    caseSensitive: false,
  );

  /// Strip special tokens and template artifacts from LLM response text.
  ///
  /// Llama 3.x, ChatML, and Gemma models may emit special tokens as
  /// literal text (e.g., `<|eot_id|>`, `<|im_end|>`). These must be
  /// removed before displaying or speaking the response. Also strips
  /// complete header blocks like `<|start_header_id|>assistant<|end_header_id|>`
  /// that would otherwise leave the role name ("assistant") as orphaned text.
  static String cleanResponseText(String text) {
    return text
        .replaceAll(specialTokenPattern, '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n') // Collapse excessive newlines
        .trim();
  }
}
