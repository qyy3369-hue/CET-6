using System.Collections.ObjectModel;
using System.Text.Json.Serialization;

namespace Goals.Windows.Models;

public enum LearningMode
{
    English,
    Japanese,
    Other
}

public sealed class AppState
{
    public int SchemaVersion { get; set; } = 1;
    public string CurrentTrackId { get; set; } = "cet6";
    public ObservableCollection<StudyTrack> Tracks { get; set; } = [];
    public ObservableCollection<StudyTask> Tasks { get; set; } = [];
    public ObservableCollection<VocabularyWord> Words { get; set; } = [];
    public ObservableCollection<FlashcardProgress> Progress { get; set; } = [];
    public ObservableCollection<string> FavoriteWordIds { get; set; } = [];
}

public sealed class StudyTrack
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string Title { get; set; } = "新目标";
    [JsonConverter(typeof(JsonStringEnumConverter))]
    public LearningMode Mode { get; set; }
    public string Category { get; set; } = "考试冲刺";
    public string Focus { get; set; } = "把目标拆成每天可执行、可勾选、可复盘的任务。";
    public ObservableCollection<PlanSheet> Plans { get; set; } = [];

    [JsonIgnore]
    public string ModeLabel => Mode switch
    {
        LearningMode.Japanese => "日语 · JLPT N4",
        LearningMode.English => "英语 · CET-6",
        _ => "其他 · 自定义"
    };

    public override string ToString() => Title;
}

public sealed class PlanSheet
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string Title { get; set; } = "计划表 01";
    public string Content { get; set; } = "";
    public DateTime UpdatedAt { get; set; } = DateTime.Now;

    public override string ToString() => Title;
}

public sealed class StudyTask
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string TrackId { get; set; } = "";
    public string PlanId { get; set; } = "";
    public DateTime Date { get; set; } = DateTime.Today;
    public string Time { get; set; } = "19:30";
    public string Title { get; set; } = "";
    public bool IsDone { get; set; }
    public string Source { get; set; } = "manual";
}

public sealed class VocabularyWord
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string TrackId { get; set; } = "";
    public string Word { get; set; } = "";
    public string Reading { get; set; } = "";
    public string Romanization { get; set; } = "";
    public string Phonetic { get; set; } = "";
    public string PartOfSpeech { get; set; } = "";
    public string Meaning { get; set; } = "";
    public string Example { get; set; } = "";
    public string ExampleTranslation { get; set; } = "";
    public ObservableCollection<string> Phrases { get; set; } = [];
    public string Mnemonic { get; set; } = "";
    public string Tag { get; set; } = "";
    public int Difficulty { get; set; } = 3;

    [JsonIgnore]
    public string Pronunciation => !string.IsNullOrWhiteSpace(Reading) ? Reading : Phonetic;
}

public sealed class FlashcardProgress
{
    public string WordId { get; set; } = "";
    public int Level { get; set; }
    public DateTime DueAt { get; set; } = DateTime.Today;
    public int ReviewCount { get; set; }
    public bool IsBanished { get; set; }
    public DateTime? LastReviewedAt { get; set; }
}

public sealed class AiPlanResult
{
    public string Summary { get; set; } = "";
    public List<AiPlanTask> Tasks { get; set; } = [];
}

public sealed class AiPlanTask
{
    public int DayOffset { get; set; }
    public string Time { get; set; } = "19:30";
    public string Title { get; set; } = "";
}
