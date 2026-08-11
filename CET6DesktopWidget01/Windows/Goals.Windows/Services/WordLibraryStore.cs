using System.Collections.ObjectModel;
using System.Globalization;
using System.IO;
using System.Text.Json;
using Goals.Windows.Models;
using Microsoft.Data.Sqlite;

namespace Goals.Windows.Services;

public sealed record WordLibraryPage(IReadOnlyList<VocabularyWord> Words, int Total, int FavoriteCount);
public sealed record WordReviewSummary(int Due, int Started, int Mastered);
public sealed record WordbookInfo(
    string Id,
    string Name,
    int WordCount,
    int ActiveCount,
    long Processed,
    int Total,
    string Status,
    DateTime UpdatedAt)
{
    public string StatusLabel => Status switch
    {
        "complete" => "已完成",
        "paused" => "已暂停",
        _ => "导入中"
    };
}
public sealed record WordbookEntry(VocabularyWord Word, bool IsActive)
{
    public string StarText => IsActive ? "★" : "☆";
    public string StarHint => IsActive ? "已在单词本，点击移除" : "加入单词本";
}
public sealed record WordbookEntryPage(IReadOnlyList<WordbookEntry> Entries, int Total);
public sealed record DailyWordFillResult(int Goal, int AssignedToday, int AddedNow);
public sealed record WordImportSession(
    string Id,
    long Processed,
    int Added,
    int Skipped,
    int Total,
    string SourceName,
    bool IsComplete);
public sealed record WordImportWriteResult(int Added, int Duplicates);

/// <summary>
/// Stores imported dictionaries outside study-data.json. Queries are paged so a
/// dictionary with hundreds of thousands of entries never has to be loaded at startup.
/// </summary>
public sealed class WordLibraryStore : IDisposable
{
    public const int PageSize = 80;
    public const int ReviewBatchSize = 200;

    private readonly string _connectionString;
    private readonly object _schemaLock = new();
    private bool _schemaReady;

    public WordLibraryStore(string? directory = null)
    {
        directory ??= Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "GoalsStudyDesk");
        Directory.CreateDirectory(directory);
        DataPath = Path.Combine(directory, "word-library.db");
        _connectionString = new SqliteConnectionStringBuilder
        {
            DataSource = DataPath,
            Mode = SqliteOpenMode.ReadWriteCreate,
            Cache = SqliteCacheMode.Shared,
            Pooling = true
        }.ToString();
        EnsureSchema();
    }

    public string DataPath { get; }
    public static bool IsLibraryWord(VocabularyWord word) => word.Id.StartsWith("lib-", StringComparison.Ordinal);

    public void Dispose() => SqliteConnection.ClearAllPools();

    public WordLibraryPage QueryWords(string trackId, string query, int offset, int limit)
    {
        query = query.Trim();
        offset = Math.Max(0, offset);
        limit = Math.Clamp(limit, 1, 500);
        using var connection = Open();

        var where = "w.track_id = $track";
        if (!string.IsNullOrWhiteSpace(query))
            where += " AND (w.headword LIKE $query ESCAPE '\\' OR w.reading LIKE $query ESCAPE '\\' OR w.romanization LIKE $query ESCAPE '\\' OR w.meaning LIKE $query ESCAPE '\\' OR w.tag LIKE $query ESCAPE '\\')";

        using var count = connection.CreateCommand();
        count.CommandText = $"SELECT COUNT(*), COUNT(f.word_id) FROM words w JOIN active_words a ON a.word_id = w.id LEFT JOIN favorites f ON f.word_id = w.id WHERE {where};";
        AddSearchParameters(count, trackId, query);
        using var countReader = count.ExecuteReader();
        countReader.Read();
        var total = countReader.GetInt32(0);
        var favorites = countReader.GetInt32(1);

        using var command = connection.CreateCommand();
        command.CommandText = $"""
            SELECT w.id, w.track_id, w.headword, w.reading, w.romanization, w.phonetic,
                   w.part_of_speech, w.meaning, w.example, w.example_translation,
                   w.phrases_json, w.mnemonic, w.tag, w.difficulty
            FROM words w
            JOIN active_words a ON a.word_id = w.id
            WHERE {where}
            ORDER BY w.headword COLLATE NOCASE, w.id
            LIMIT $limit OFFSET $offset;
            """;
        AddSearchParameters(command, trackId, query);
        command.Parameters.AddWithValue("$limit", limit);
        command.Parameters.AddWithValue("$offset", offset);
        return new WordLibraryPage(ReadWords(command), total, favorites);
    }

    public IReadOnlyList<VocabularyWord> QueryReviewWords(string trackId, string filter, DateTime now, int limit = ReviewBatchSize)
    {
        using var connection = Open();
        var condition = filter switch
        {
            "favorite" => "f.word_id IS NOT NULL",
            "hard" => "(w.difficulty >= 4 OR (COALESCE(p.level, 0) = 0 AND COALESCE(p.review_count, 0) > 0))",
            "all" => "1 = 1",
            _ => "COALESCE(p.due_ticks, 0) <= $now"
        };
        using var command = connection.CreateCommand();
        command.CommandText = $"""
            SELECT w.id, w.track_id, w.headword, w.reading, w.romanization, w.phonetic,
                   w.part_of_speech, w.meaning, w.example, w.example_translation,
                   w.phrases_json, w.mnemonic, w.tag, w.difficulty
            FROM words w
            JOIN active_words a ON a.word_id = w.id
            LEFT JOIN progress p ON p.word_id = w.id
            LEFT JOIN favorites f ON f.word_id = w.id
            WHERE w.track_id = $track
              AND COALESCE(p.is_banished, 0) = 0
              AND {condition}
            ORDER BY COALESCE(p.due_ticks, 0), w.rowid
            LIMIT $limit;
            """;
        command.Parameters.AddWithValue("$track", trackId);
        command.Parameters.AddWithValue("$now", now.Ticks);
        command.Parameters.AddWithValue("$limit", Math.Clamp(limit, 1, 1000));
        return ReadWords(command);
    }

    public IReadOnlyList<VocabularyWord> QuerySpecialWords(string trackId, bool banished, string query, int limit = 500)
    {
        query = query.Trim();
        using var connection = Open();
        var membership = banished ? "COALESCE(p.is_banished, 0) = 1" : "f.word_id IS NOT NULL";
        var search = string.IsNullOrWhiteSpace(query)
            ? ""
            : " AND (w.headword LIKE $query ESCAPE '\\' OR w.reading LIKE $query ESCAPE '\\' OR w.meaning LIKE $query ESCAPE '\\')";
        using var command = connection.CreateCommand();
        command.CommandText = $"""
            SELECT w.id, w.track_id, w.headword, w.reading, w.romanization, w.phonetic,
                   w.part_of_speech, w.meaning, w.example, w.example_translation,
                   w.phrases_json, w.mnemonic, w.tag, w.difficulty
            FROM words w
            JOIN active_words a ON a.word_id = w.id
            LEFT JOIN progress p ON p.word_id = w.id
            LEFT JOIN favorites f ON f.word_id = w.id
            WHERE w.track_id = $track AND {membership}{search}
            ORDER BY w.headword COLLATE NOCASE
            LIMIT $limit;
            """;
        AddSearchParameters(command, trackId, query);
        command.Parameters.AddWithValue("$limit", Math.Clamp(limit, 1, 2000));
        return ReadWords(command);
    }

    public WordReviewSummary GetReviewSummary(string trackId, DateTime now)
    {
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT
              COALESCE(SUM(CASE WHEN COALESCE(p.is_banished, 0) = 0 AND COALESCE(p.due_ticks, 0) <= $now THEN 1 ELSE 0 END), 0),
              COALESCE(SUM(CASE WHEN COALESCE(p.review_count, 0) > 0 THEN 1 ELSE 0 END), 0),
              COALESCE(SUM(CASE WHEN COALESCE(p.level, 0) >= 5 THEN 1 ELSE 0 END), 0)
            FROM words w JOIN active_words a ON a.word_id = w.id LEFT JOIN progress p ON p.word_id = w.id
            WHERE w.track_id = $track;
            """;
        command.Parameters.AddWithValue("$track", trackId);
        command.Parameters.AddWithValue("$now", now.Ticks);
        using var reader = command.ExecuteReader();
        reader.Read();
        return new WordReviewSummary(reader.GetInt32(0), reader.GetInt32(1), reader.GetInt32(2));
    }

    public FlashcardProgress GetProgress(VocabularyWord word)
    {
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT level, due_ticks, review_count, is_banished, last_reviewed_ticks FROM progress WHERE word_id = $id;";
        command.Parameters.AddWithValue("$id", word.Id);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) return new FlashcardProgress { WordId = word.Id, DueAt = DateTime.Today };
        return new FlashcardProgress
        {
            WordId = word.Id,
            Level = reader.GetInt32(0),
            DueAt = new DateTime(reader.GetInt64(1), DateTimeKind.Local),
            ReviewCount = reader.GetInt32(2),
            IsBanished = reader.GetInt32(3) != 0,
            LastReviewedAt = reader.IsDBNull(4) ? null : new DateTime(reader.GetInt64(4), DateTimeKind.Local)
        };
    }

    public void SaveProgress(FlashcardProgress progress)
    {
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = """
            INSERT INTO progress(word_id, level, due_ticks, review_count, is_banished, last_reviewed_ticks)
            VALUES($id, $level, $due, $reviews, $banished, $last)
            ON CONFLICT(word_id) DO UPDATE SET
              level = excluded.level,
              due_ticks = excluded.due_ticks,
              review_count = excluded.review_count,
              is_banished = excluded.is_banished,
              last_reviewed_ticks = excluded.last_reviewed_ticks;
            """;
        command.Parameters.AddWithValue("$id", progress.WordId);
        command.Parameters.AddWithValue("$level", progress.Level);
        command.Parameters.AddWithValue("$due", progress.DueAt.Ticks);
        command.Parameters.AddWithValue("$reviews", progress.ReviewCount);
        command.Parameters.AddWithValue("$banished", progress.IsBanished ? 1 : 0);
        command.Parameters.AddWithValue("$last", progress.LastReviewedAt?.Ticks is { } ticks ? ticks : DBNull.Value);
        command.ExecuteNonQuery();
    }

    public bool IsFavorite(string wordId)
    {
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT EXISTS(SELECT 1 FROM favorites WHERE word_id = $id);";
        command.Parameters.AddWithValue("$id", wordId);
        return Convert.ToInt32(command.ExecuteScalar(), CultureInfo.InvariantCulture) != 0;
    }

    public void SetFavorite(string wordId, bool value)
    {
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = value
            ? "INSERT OR IGNORE INTO favorites(word_id) VALUES($id);"
            : "DELETE FROM favorites WHERE word_id = $id;";
        command.Parameters.AddWithValue("$id", wordId);
        command.ExecuteNonQuery();
    }

    public IReadOnlyList<WordbookInfo> QueryWordbooks(string trackId)
    {
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT i.id, i.source_name, COUNT(w.id), COUNT(a.word_id),
                   i.processed_count, i.total_count, i.status, i.updated_ticks
            FROM imports i
            LEFT JOIN words w ON w.source_id = i.id
            LEFT JOIN active_words a ON a.word_id = w.id
            WHERE i.track_id = $track
            GROUP BY i.id, i.source_name, i.processed_count, i.total_count, i.status, i.updated_ticks
            ORDER BY i.updated_ticks DESC;
            """;
        command.Parameters.AddWithValue("$track", trackId);
        var result = new List<WordbookInfo>();
        using var reader = command.ExecuteReader();
        while (reader.Read())
        {
            result.Add(new WordbookInfo(
                reader.GetString(0), reader.GetString(1), reader.GetInt32(2), reader.GetInt32(3),
                reader.GetInt64(4), reader.GetInt32(5), reader.GetString(6),
                new DateTime(reader.GetInt64(7), DateTimeKind.Local)));
        }
        return result;
    }

    public WordbookEntryPage QueryWordbookEntries(string trackId, string? sourceId, string query, int offset, int limit, bool preferNonLatin = false)
    {
        query = query.Trim();
        offset = Math.Max(0, offset);
        limit = Math.Clamp(limit, 1, 500);
        var where = "w.track_id = $track";
        if (!string.IsNullOrWhiteSpace(sourceId)) where += " AND w.source_id = $source";
        if (!string.IsNullOrWhiteSpace(query))
            where += " AND (w.headword LIKE $query ESCAPE '\\' OR w.reading LIKE $query ESCAPE '\\' OR w.romanization LIKE $query ESCAPE '\\' OR w.meaning LIKE $query ESCAPE '\\')";
        using var connection = Open();
        using var count = connection.CreateCommand();
        count.CommandText = $"SELECT COUNT(*) FROM words w WHERE {where};";
        AddWordbookParameters(count, trackId, sourceId, query);
        var total = Convert.ToInt32(count.ExecuteScalar(), CultureInfo.InvariantCulture);

        using var command = connection.CreateCommand();
        command.CommandText = $"""
            SELECT w.id, w.track_id, w.headword, w.reading, w.romanization, w.phonetic,
                   w.part_of_speech, w.meaning, w.example, w.example_translation,
                   w.phrases_json, w.mnemonic, w.tag, w.difficulty,
                   CASE WHEN a.word_id IS NULL THEN 0 ELSE 1 END
            FROM words w
            LEFT JOIN active_words a ON a.word_id = w.id
            WHERE {where}
            ORDER BY CASE
                       WHEN $hasExactQuery = 1 AND w.headword = $exactQuery THEN 0
                       ELSE 1
                     END,
                     CASE
                       WHEN $preferNonLatin = 1 AND length(CAST(substr(w.headword, 1, 1) AS BLOB)) = 1 THEN 1
                       ELSE 0
                     END,
                     w.rowid
            LIMIT $limit OFFSET $offset;
            """;
        AddWordbookParameters(command, trackId, sourceId, query);
        command.Parameters.AddWithValue("$limit", limit);
        command.Parameters.AddWithValue("$offset", offset);
        command.Parameters.AddWithValue("$preferNonLatin", preferNonLatin ? 1 : 0);
        command.Parameters.AddWithValue("$hasExactQuery", string.IsNullOrWhiteSpace(query) ? 0 : 1);
        command.Parameters.AddWithValue("$exactQuery", query);
        var entries = new List<WordbookEntry>();
        using var reader = command.ExecuteReader();
        while (reader.Read()) entries.Add(new WordbookEntry(ReadWord(reader), reader.GetInt32(14) != 0));
        return new WordbookEntryPage(entries, total);
    }

    public bool IsActiveWord(string wordId)
    {
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT EXISTS(SELECT 1 FROM active_words WHERE word_id = $id);";
        command.Parameters.AddWithValue("$id", wordId);
        return Convert.ToInt32(command.ExecuteScalar(), CultureInfo.InvariantCulture) != 0;
    }

    public void SetActiveWord(string wordId, bool active)
    {
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = active
            ? "INSERT OR IGNORE INTO active_words(word_id, added_date, reason) VALUES($id, $date, 'manual');"
            : "DELETE FROM active_words WHERE word_id = $id;";
        command.Parameters.AddWithValue("$id", wordId);
        command.Parameters.AddWithValue("$date", DateTime.Today.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture));
        command.ExecuteNonQuery();
    }

    public int GetDailyNewWordCount(string trackId)
    {
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT daily_new_count FROM track_settings WHERE track_id = $track;";
        command.Parameters.AddWithValue("$track", trackId);
        return command.ExecuteScalar() is { } value ? Convert.ToInt32(value, CultureInfo.InvariantCulture) : 20;
    }

    public void SetDailyNewWordCount(string trackId, int count)
    {
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = """
            INSERT INTO track_settings(track_id, daily_new_count) VALUES($track, $count)
            ON CONFLICT(track_id) DO UPDATE SET daily_new_count = excluded.daily_new_count;
            """;
        command.Parameters.AddWithValue("$track", trackId);
        command.Parameters.AddWithValue("$count", Math.Clamp(count, 0, 200));
        command.ExecuteNonQuery();
    }

    public DailyWordFillResult EnsureDailyWords(string trackId, DateTime date)
    {
        var goal = GetDailyNewWordCount(trackId);
        var dateKey = date.Date.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        using var connection = Open();
        using var transaction = connection.BeginTransaction();
        var assigned = 0;
        using (var read = connection.CreateCommand())
        {
            read.Transaction = transaction;
            read.CommandText = "SELECT assigned_count FROM daily_assignments WHERE track_id = $track AND date_key = $date;";
            read.Parameters.AddWithValue("$track", trackId);
            read.Parameters.AddWithValue("$date", dateKey);
            if (read.ExecuteScalar() is { } value) assigned = Convert.ToInt32(value, CultureInfo.InvariantCulture);
        }

        var requested = Math.Max(0, goal - assigned);
        var added = 0;
        if (requested > 0)
        {
            using var select = connection.CreateCommand();
            select.Transaction = transaction;
            select.CommandText = """
                SELECT w.id FROM words w
                LEFT JOIN active_words a ON a.word_id = w.id
                WHERE w.track_id = $track AND a.word_id IS NULL
                ORDER BY w.rowid
                LIMIT $limit;
                """;
            select.Parameters.AddWithValue("$track", trackId);
            select.Parameters.AddWithValue("$limit", requested);
            var ids = new List<string>();
            using (var reader = select.ExecuteReader()) while (reader.Read()) ids.Add(reader.GetString(0));
            foreach (var id in ids)
            {
                using var insert = connection.CreateCommand();
                insert.Transaction = transaction;
                insert.CommandText = "INSERT OR IGNORE INTO active_words(word_id, added_date, reason) VALUES($id, $date, 'daily');";
                insert.Parameters.AddWithValue("$id", id);
                insert.Parameters.AddWithValue("$date", dateKey);
                added += insert.ExecuteNonQuery();
            }
            assigned += added;
        }

        using (var save = connection.CreateCommand())
        {
            save.Transaction = transaction;
            save.CommandText = """
                INSERT INTO daily_assignments(track_id, date_key, assigned_count) VALUES($track, $date, $count)
                ON CONFLICT(track_id, date_key) DO UPDATE SET assigned_count = excluded.assigned_count;
                """;
            save.Parameters.AddWithValue("$track", trackId);
            save.Parameters.AddWithValue("$date", dateKey);
            save.Parameters.AddWithValue("$count", assigned);
            save.ExecuteNonQuery();
        }
        transaction.Commit();
        return new DailyWordFillResult(goal, assigned, added);
    }

    public void DeleteWordbook(string sourceId)
    {
        using var connection = Open();
        using var transaction = connection.BeginTransaction();
        foreach (var sql in new[]
                 {
                     "DELETE FROM favorites WHERE word_id IN (SELECT id FROM words WHERE source_id = $source);",
                     "DELETE FROM progress WHERE word_id IN (SELECT id FROM words WHERE source_id = $source);",
                     "DELETE FROM active_words WHERE word_id IN (SELECT id FROM words WHERE source_id = $source);",
                     "DELETE FROM words WHERE source_id = $source;",
                     "DELETE FROM imports WHERE id = $source;"
                 })
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText = sql;
            command.Parameters.AddWithValue("$source", sourceId);
            command.ExecuteNonQuery();
        }
        transaction.Commit();
    }

    public void DeleteWord(string wordId)
    {
        using var connection = Open();
        using var transaction = connection.BeginTransaction();
        foreach (var sql in new[]
                 {
                     "DELETE FROM favorites WHERE word_id = $id;",
                     "DELETE FROM progress WHERE word_id = $id;",
                     "DELETE FROM active_words WHERE word_id = $id;",
                     "DELETE FROM words WHERE id = $id;"
                 })
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText = sql;
            command.Parameters.AddWithValue("$id", wordId);
            command.ExecuteNonQuery();
        }
        transaction.Commit();
    }

    public void DeleteTrack(string trackId)
    {
        using var connection = Open();
        using var transaction = connection.BeginTransaction();
        foreach (var sql in new[]
                 {
                     "DELETE FROM favorites WHERE word_id IN (SELECT id FROM words WHERE track_id = $track);",
                     "DELETE FROM progress WHERE word_id IN (SELECT id FROM words WHERE track_id = $track);",
                     "DELETE FROM active_words WHERE word_id IN (SELECT id FROM words WHERE track_id = $track);",
                     "DELETE FROM words WHERE track_id = $track;",
                     "DELETE FROM imports WHERE track_id = $track;",
                     "DELETE FROM track_settings WHERE track_id = $track;",
                     "DELETE FROM daily_assignments WHERE track_id = $track;"
                 })
        {
            using var command = connection.CreateCommand();
            command.Transaction = transaction;
            command.CommandText = sql;
            command.Parameters.AddWithValue("$track", trackId);
            command.ExecuteNonQuery();
        }
        transaction.Commit();
    }

    public WordImportSession BeginImport(string id, string trackId, string filePath, string sourceName, int total)
    {
        using var connection = Open();
        using (var insert = connection.CreateCommand())
        {
            insert.CommandText = """
                INSERT OR IGNORE INTO imports(
                  id, track_id, file_path, source_name, total_count, processed_count,
                  added_count, skipped_count, status, updated_ticks)
                VALUES($id, $track, $path, $name, $total, 0, 0, 0, 'running', $updated);
                """;
            insert.Parameters.AddWithValue("$id", id);
            insert.Parameters.AddWithValue("$track", trackId);
            insert.Parameters.AddWithValue("$path", filePath);
            insert.Parameters.AddWithValue("$name", sourceName);
            insert.Parameters.AddWithValue("$total", total);
            insert.Parameters.AddWithValue("$updated", DateTime.Now.Ticks);
            insert.ExecuteNonQuery();
        }
        using (var update = connection.CreateCommand())
        {
            update.CommandText = "UPDATE imports SET total_count = $total, status = CASE WHEN status = 'complete' THEN status ELSE 'running' END, updated_ticks = $updated WHERE id = $id;";
            update.Parameters.AddWithValue("$id", id);
            update.Parameters.AddWithValue("$total", total);
            update.Parameters.AddWithValue("$updated", DateTime.Now.Ticks);
            update.ExecuteNonQuery();
        }
        return ReadImport(connection, id);
    }

    public WordImportWriteResult WriteImportBatch(
        WordImportSession session,
        StudyTrack track,
        IReadOnlyList<VocabularyWord> words,
        long processed,
        int skipped)
    {
        using var connection = Open();
        using var transaction = connection.BeginTransaction();
        var added = 0;
        var duplicates = 0;
        foreach (var word in words)
        {
            word.TrackId = track.Id;
            word.Id = "lib-" + Guid.NewGuid().ToString("N");
            using var insert = connection.CreateCommand();
            insert.Transaction = transaction;
            insert.CommandText = """
                INSERT OR IGNORE INTO words(
                  id, track_id, source_id, source_name, headword, word_key, reading,
                  romanization, phonetic, part_of_speech, meaning, example,
                  example_translation, phrases_json, mnemonic, tag, difficulty)
                VALUES($id, $track, $source, $sourceName, $word, $key, $reading,
                  $romanization, $phonetic, $pos, $meaning, $example,
                  $translation, $phrases, $mnemonic, $tag, $difficulty);
                """;
            insert.Parameters.AddWithValue("$id", word.Id);
            insert.Parameters.AddWithValue("$track", track.Id);
            insert.Parameters.AddWithValue("$source", session.Id);
            insert.Parameters.AddWithValue("$sourceName", session.SourceName);
            insert.Parameters.AddWithValue("$word", word.Word.Trim());
            insert.Parameters.AddWithValue("$key", Normalize(word.Word));
            insert.Parameters.AddWithValue("$reading", word.Reading ?? "");
            insert.Parameters.AddWithValue("$romanization", word.Romanization ?? "");
            insert.Parameters.AddWithValue("$phonetic", word.Phonetic ?? "");
            insert.Parameters.AddWithValue("$pos", word.PartOfSpeech ?? "");
            insert.Parameters.AddWithValue("$meaning", word.Meaning.Trim());
            insert.Parameters.AddWithValue("$example", word.Example ?? "");
            insert.Parameters.AddWithValue("$translation", word.ExampleTranslation ?? "");
            insert.Parameters.AddWithValue("$phrases", JsonSerializer.Serialize(word.Phrases));
            insert.Parameters.AddWithValue("$mnemonic", word.Mnemonic ?? "");
            insert.Parameters.AddWithValue("$tag", word.Tag ?? "");
            insert.Parameters.AddWithValue("$difficulty", Math.Clamp(word.Difficulty, 1, 5));
            if (insert.ExecuteNonQuery() == 1) added++;
            else duplicates++;
        }

        using var update = connection.CreateCommand();
        update.Transaction = transaction;
        update.CommandText = """
            UPDATE imports
            SET processed_count = $processed,
                added_count = added_count + $added,
                skipped_count = $skipped,
                status = 'running',
                updated_ticks = $updated
            WHERE id = $id;
            """;
        update.Parameters.AddWithValue("$processed", processed);
        update.Parameters.AddWithValue("$added", added);
        update.Parameters.AddWithValue("$skipped", skipped);
        update.Parameters.AddWithValue("$updated", DateTime.Now.Ticks);
        update.Parameters.AddWithValue("$id", session.Id);
        update.ExecuteNonQuery();
        transaction.Commit();
        return new WordImportWriteResult(added, duplicates);
    }

    public WordImportSession FinishImport(string id, long processed, int skipped, bool complete, string? error = null)
    {
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = """
            UPDATE imports
            SET processed_count = $processed, skipped_count = $skipped,
                status = $status, error = $error, updated_ticks = $updated
            WHERE id = $id;
            """;
        command.Parameters.AddWithValue("$processed", processed);
        command.Parameters.AddWithValue("$skipped", skipped);
        command.Parameters.AddWithValue("$status", complete ? "complete" : "paused");
        command.Parameters.AddWithValue("$error", error ?? "");
        command.Parameters.AddWithValue("$updated", DateTime.Now.Ticks);
        command.Parameters.AddWithValue("$id", id);
        command.ExecuteNonQuery();
        return ReadImport(connection, id);
    }

    private WordImportSession ReadImport(SqliteConnection connection, string id)
    {
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT id, processed_count, added_count, skipped_count, total_count, status, source_name FROM imports WHERE id = $id;";
        command.Parameters.AddWithValue("$id", id);
        using var reader = command.ExecuteReader();
        if (!reader.Read()) throw new InvalidOperationException("导入任务不存在。");
        return new WordImportSession(
            reader.GetString(0), reader.GetInt64(1), reader.GetInt32(2), reader.GetInt32(3),
            reader.GetInt32(4), reader.GetString(6), reader.GetString(5) == "complete");
    }

    private SqliteConnection Open()
    {
        EnsureSchema();
        var connection = new SqliteConnection(_connectionString);
        connection.Open();
        using var pragma = connection.CreateCommand();
        pragma.CommandText = "PRAGMA busy_timeout=5000; PRAGMA foreign_keys=OFF;";
        pragma.ExecuteNonQuery();
        return connection;
    }

    private void EnsureSchema()
    {
        if (_schemaReady) return;
        lock (_schemaLock)
        {
            if (_schemaReady) return;
            using var connection = new SqliteConnection(_connectionString);
            connection.Open();
            using var command = connection.CreateCommand();
            command.CommandText = """
                PRAGMA journal_mode=WAL;
                PRAGMA synchronous=NORMAL;
                CREATE TABLE IF NOT EXISTS words(
                  id TEXT PRIMARY KEY,
                  track_id TEXT NOT NULL,
                  source_id TEXT NOT NULL,
                  source_name TEXT NOT NULL,
                  headword TEXT NOT NULL,
                  word_key TEXT NOT NULL,
                  reading TEXT NOT NULL DEFAULT '',
                  romanization TEXT NOT NULL DEFAULT '',
                  phonetic TEXT NOT NULL DEFAULT '',
                  part_of_speech TEXT NOT NULL DEFAULT '',
                  meaning TEXT NOT NULL,
                  example TEXT NOT NULL DEFAULT '',
                  example_translation TEXT NOT NULL DEFAULT '',
                  phrases_json TEXT NOT NULL DEFAULT '[]',
                  mnemonic TEXT NOT NULL DEFAULT '',
                  tag TEXT NOT NULL DEFAULT '',
                  difficulty INTEGER NOT NULL DEFAULT 3,
                  UNIQUE(track_id, word_key)
                );
                CREATE INDEX IF NOT EXISTS idx_words_track_headword ON words(track_id, headword COLLATE NOCASE);
                CREATE INDEX IF NOT EXISTS idx_words_source ON words(source_id);
                CREATE TABLE IF NOT EXISTS progress(
                  word_id TEXT PRIMARY KEY,
                  level INTEGER NOT NULL DEFAULT 0,
                  due_ticks INTEGER NOT NULL DEFAULT 0,
                  review_count INTEGER NOT NULL DEFAULT 0,
                  is_banished INTEGER NOT NULL DEFAULT 0,
                  last_reviewed_ticks INTEGER NULL
                );
                CREATE TABLE IF NOT EXISTS favorites(word_id TEXT PRIMARY KEY);
                CREATE TABLE IF NOT EXISTS active_words(
                  word_id TEXT PRIMARY KEY,
                  added_date TEXT NOT NULL,
                  reason TEXT NOT NULL DEFAULT 'manual'
                );
                CREATE INDEX IF NOT EXISTS idx_active_words_date ON active_words(added_date);
                CREATE TABLE IF NOT EXISTS track_settings(
                  track_id TEXT PRIMARY KEY,
                  daily_new_count INTEGER NOT NULL DEFAULT 20
                );
                CREATE TABLE IF NOT EXISTS daily_assignments(
                  track_id TEXT NOT NULL,
                  date_key TEXT NOT NULL,
                  assigned_count INTEGER NOT NULL DEFAULT 0,
                  PRIMARY KEY(track_id, date_key)
                );
                CREATE TABLE IF NOT EXISTS imports(
                  id TEXT PRIMARY KEY,
                  track_id TEXT NOT NULL,
                  file_path TEXT NOT NULL,
                  source_name TEXT NOT NULL,
                  total_count INTEGER NOT NULL DEFAULT 0,
                  processed_count INTEGER NOT NULL DEFAULT 0,
                  added_count INTEGER NOT NULL DEFAULT 0,
                  skipped_count INTEGER NOT NULL DEFAULT 0,
                  status TEXT NOT NULL DEFAULT 'running',
                  error TEXT NOT NULL DEFAULT '',
                  updated_ticks INTEGER NOT NULL DEFAULT 0
                );
                """;
            command.ExecuteNonQuery();
            _schemaReady = true;
        }
    }

    private static List<VocabularyWord> ReadWords(SqliteCommand command)
    {
        var result = new List<VocabularyWord>();
        using var reader = command.ExecuteReader();
        while (reader.Read())
        {
            result.Add(ReadWord(reader));
        }
        return result;
    }

    private static void AddSearchParameters(SqliteCommand command, string trackId, string query)
    {
        command.Parameters.AddWithValue("$track", trackId);
        if (!string.IsNullOrWhiteSpace(query)) command.Parameters.AddWithValue("$query", $"%{EscapeLike(query)}%");
    }

    private static void AddWordbookParameters(SqliteCommand command, string trackId, string? sourceId, string query)
    {
        AddSearchParameters(command, trackId, query);
        if (!string.IsNullOrWhiteSpace(sourceId)) command.Parameters.AddWithValue("$source", sourceId);
    }

    private static VocabularyWord ReadWord(SqliteDataReader reader)
    {
        ObservableCollection<string> phrases;
        try { phrases = JsonSerializer.Deserialize<ObservableCollection<string>>(reader.GetString(10)) ?? []; }
        catch { phrases = []; }
        return new VocabularyWord
        {
            Id = reader.GetString(0),
            TrackId = reader.GetString(1),
            Word = reader.GetString(2),
            Reading = reader.GetString(3),
            Romanization = reader.GetString(4),
            Phonetic = reader.GetString(5),
            PartOfSpeech = reader.GetString(6),
            Meaning = reader.GetString(7),
            Example = reader.GetString(8),
            ExampleTranslation = reader.GetString(9),
            Phrases = phrases,
            Mnemonic = reader.GetString(11),
            Tag = reader.GetString(12),
            Difficulty = reader.GetInt32(13)
        };
    }

    private static string EscapeLike(string value) => value.Replace("\\", "\\\\").Replace("%", "\\%").Replace("_", "\\_");
    public static string Normalize(string value) => value.Trim().ToUpperInvariant();
}
