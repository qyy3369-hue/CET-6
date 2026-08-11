using Goals.Windows.Models;

namespace Goals.Windows.Services;

public static class FlashcardScheduler
{
    private static readonly TimeSpan[] Intervals =
    [
        TimeSpan.FromMinutes(30),
        TimeSpan.FromHours(12),
        TimeSpan.FromDays(3),
        TimeSpan.FromDays(7),
        TimeSpan.FromDays(15)
    ];

    public static void MarkCorrect(FlashcardProgress progress)
    {
        progress.Level = Math.Min(5, progress.Level + 1);
        progress.ReviewCount++;
        var now = DateTime.Now;
        progress.LastReviewedAt = now;
        progress.DueAt = now.Add(Intervals[progress.Level - 1]);
        progress.IsBanished = false;
    }

    public static void MarkIncorrect(FlashcardProgress progress)
    {
        progress.Level = 0;
        progress.ReviewCount++;
        var now = DateTime.Now;
        progress.LastReviewedAt = now;
        progress.DueAt = now;
    }
}
