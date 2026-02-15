import 'dart:convert';
import 'dart:io';

import 'package:read_pdf_text/read_pdf_text.dart';

/// Service for extracting text from PDF and text files, and chunking for RAG.
class PdfService {
  PdfService._();

  /// Extract text from a file at [filePath].
  ///
  /// Supports PDF (.pdf), plain text (.txt), and Markdown (.md) files.
  /// For PDFs, uses the read_pdf_text package.
  /// For text files, reads as UTF-8 with Latin-1 fallback.
  static Future<String> extractText(String filePath) async {
    final lowerPath = filePath.toLowerCase();

    if (lowerPath.endsWith('.pdf')) {
      // Extract text from PDF using read_pdf_text
      final pages = await ReadPdfText.getPDFtextPaginated(filePath);
      return pages.join('\n\n');
    }

    // Text / Markdown files: read as UTF-8, fall back to Latin-1
    final file = File(filePath);
    try {
      return await file.readAsString();
    } catch (_) {
      final bytes = await file.readAsBytes();
      return latin1.decode(bytes);
    }
  }

  /// Split [text] into overlapping chunks for embedding.
  ///
  /// Respects paragraph boundaries (\n\n), then sentence boundaries (. ),
  /// then hard-breaks at [maxChars]. Adjacent chunks overlap by [overlap]
  /// characters for context continuity.
  ///
  /// Copied from the proven algorithm in flutter/example/lib/main.dart.
  static List<String> chunkText(
    String text, {
    int maxChars = 500,
    int overlap = 50,
  }) {
    final chunks = <String>[];
    // Normalize whitespace
    text = text.replaceAll('\r\n', '\n').trim();
    if (text.isEmpty) return chunks;

    int start = 0;
    while (start < text.length) {
      int end = start + maxChars;
      if (end >= text.length) {
        final chunk = text.substring(start).trim();
        if (chunk.isNotEmpty) chunks.add(chunk);
        break;
      }
      // Try to break at paragraph boundary
      int breakPoint = text.lastIndexOf('\n\n', end);
      if (breakPoint <= start) {
        // Try sentence boundary
        breakPoint = text.lastIndexOf('. ', end);
        if (breakPoint > start) breakPoint += 2;
      }
      if (breakPoint <= start) {
        breakPoint = end;
      }
      final chunk = text.substring(start, breakPoint).trim();
      if (chunk.isNotEmpty) chunks.add(chunk);
      // Always advance forward -- overlap only if we advanced enough
      final nextStart = breakPoint - overlap;
      start = nextStart > start ? nextStart : breakPoint;
    }
    return chunks;
  }
}
