import 'dart:convert';
import 'dart:io';

import 'package:read_pdf_text/read_pdf_text.dart';

/// Extracts and chunks text from PDF, TXT, and MD files.
class PdfService {
  PdfService._();

  /// Extract text from a file path.
  ///
  /// Supports .pdf (via read_pdf_text), .txt, and .md (via UTF-8 with
  /// Latin-1 fallback).
  static Future<String> extractText(String filePath) async {
    final lower = filePath.toLowerCase();

    if (lower.endsWith('.pdf')) {
      // PDF extraction via native PDFKit (iOS) / PDFBox (Android)
      final pages = await ReadPdfText.getPDFtextPaginated(filePath);
      return pages.join('\n\n');
    }

    // Plain text / markdown: try UTF-8, fall back to Latin-1
    try {
      return await File(filePath).readAsString();
    } catch (_) {
      final bytes = await File(filePath).readAsBytes();
      return latin1.decode(bytes);
    }
  }

  /// Split text into overlapping chunks at paragraph/sentence boundaries.
  ///
  /// Uses 500-char chunks with 50-char overlap -- proven in the SDK example
  /// app for RAG indexing with all-MiniLM-L6-v2 embeddings.
  static List<String> chunkText(
    String text, {
    int maxChars = 500,
    int overlap = 50,
  }) {
    final chunks = <String>[];
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

      // Try paragraph boundary first
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

      // Advance with overlap
      final nextStart = breakPoint - overlap;
      start = nextStart > start ? nextStart : breakPoint;
    }
    return chunks;
  }
}
