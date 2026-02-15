import 'package:sqflite/sqflite.dart';

import '../models/journal_entry.dart';

/// SQLite persistence for journal entries.
class JournalDb {
  Database? _db;

  /// Lazy database initialization.
  Future<Database> _getDb() async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      '$dbPath/voice_journal.db',
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE entries(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at TEXT NOT NULL,
            transcript TEXT NOT NULL,
            summary TEXT,
            tags TEXT,
            duration_seconds INTEGER
          )
        ''');
      },
    );
    return _db!;
  }

  /// Insert a new entry and return its auto-generated ID.
  Future<int> insertEntry(JournalEntry entry) async {
    final db = await _getDb();
    return db.insert('entries', entry.toMap());
  }

  /// Get all entries, newest first.
  Future<List<JournalEntry>> getAllEntries() async {
    final db = await _getDb();
    final rows = await db.query(
      'entries',
      orderBy: 'created_at DESC',
    );
    return rows.map((r) => JournalEntry.fromMap(r)).toList();
  }

  /// Get a single entry by ID.
  Future<JournalEntry?> getEntry(int id) async {
    final db = await _getDb();
    final rows = await db.query(
      'entries',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return JournalEntry.fromMap(rows.first);
  }

  /// Update an existing entry (summary, tags, etc.).
  Future<void> updateEntry(JournalEntry entry) async {
    if (entry.id == null) return;
    final db = await _getDb();
    await db.update(
      'entries',
      entry.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  /// Delete an entry by ID.
  Future<void> deleteEntry(int id) async {
    final db = await _getDb();
    await db.delete(
      'entries',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
