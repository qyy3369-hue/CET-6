using System.Text.Json;
using System.Text.Json.Serialization;
using System.IO;
using Goals.Windows.Models;

namespace Goals.Windows.Services;

public sealed class AppDataStore
{
    private readonly string _directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "GoalsStudyDesk");
    private readonly JsonSerializerOptions _options = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true,
        Converters = { new JsonStringEnumConverter() }
    };

    public string DataPath => Path.Combine(_directory, "study-data.json");

    public AppState Load()
    {
        try
        {
            if (File.Exists(DataPath))
            {
                var state = JsonSerializer.Deserialize<AppState>(File.ReadAllText(DataPath), _options);
                if (state is { Tracks.Count: > 0 }) return Repair(state);
            }
        }
        catch
        {
            BackupBrokenFile();
        }

        var fresh = DefaultDataFactory.Create();
        Save(fresh);
        return fresh;
    }

    public void Save(AppState state)
    {
        Directory.CreateDirectory(_directory);
        var temporary = DataPath + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(state, _options));
        File.Move(temporary, DataPath, true);
    }

    public void Reset()
    {
        if (File.Exists(DataPath))
            File.Delete(DataPath);
    }

    private static AppState Repair(AppState state)
    {
        if (state.Tracks.All(x => x.Id != state.CurrentTrackId))
            state.CurrentTrackId = state.Tracks[0].Id;
        foreach (var word in state.Words)
        {
            if (state.Progress.All(x => x.WordId != word.Id))
                state.Progress.Add(new FlashcardProgress { WordId = word.Id, DueAt = DateTime.Today });
        }
        return state;
    }

    private void BackupBrokenFile()
    {
        try
        {
            if (File.Exists(DataPath))
                File.Move(DataPath, DataPath + ".broken-" + DateTime.Now.ToString("yyyyMMddHHmmss"), true);
        }
        catch { }
    }
}
