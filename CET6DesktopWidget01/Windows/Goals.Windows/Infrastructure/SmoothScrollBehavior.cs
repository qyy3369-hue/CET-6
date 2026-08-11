using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Media3D;

namespace Goals.Windows.Infrastructure;

public static class SmoothScrollBehavior
{
    // Applied at the main window, so every page shares one predictable scroll feel.
    private const double WheelDistanceFactor = 0.86;
    private const double MinimumWheelDistance = 68;
    private const double MaximumWheelDistance = 126;
    private const int ScrollAnimationMilliseconds = 130;

    private static readonly DependencyProperty AnimatedOffsetProperty = DependencyProperty.RegisterAttached(
        "AnimatedOffset",
        typeof(double),
        typeof(SmoothScrollBehavior),
        new PropertyMetadata(0d, OnAnimatedOffsetChanged));

    public static void Enable(UIElement root) =>
        root.AddHandler(UIElement.PreviewMouseWheelEvent, new MouseWheelEventHandler(OnPreviewMouseWheel), true);

    private static void OnPreviewMouseWheel(object sender, MouseWheelEventArgs e)
    {
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Shift)) return;
        var viewer = FindScrollableViewer(e.OriginalSource as DependencyObject, sender as DependencyObject);
        if (viewer is null) return;

        var start = viewer.VerticalOffset;
        var distance = Math.Clamp(Math.Abs(e.Delta) * WheelDistanceFactor, MinimumWheelDistance, MaximumWheelDistance);
        var target = Math.Clamp(start - Math.Sign(e.Delta) * distance, 0, viewer.ScrollableHeight);
        if (Math.Abs(target - start) < 0.5) return;

        viewer.BeginAnimation(AnimatedOffsetProperty, null);
        viewer.SetValue(AnimatedOffsetProperty, start);
        var animation = new DoubleAnimation(start, target, TimeSpan.FromMilliseconds(ScrollAnimationMilliseconds))
        {
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut },
            FillBehavior = FillBehavior.HoldEnd
        };
        viewer.BeginAnimation(AnimatedOffsetProperty, animation, HandoffBehavior.SnapshotAndReplace);
        e.Handled = true;
    }

    private static ScrollViewer? FindScrollableViewer(DependencyObject? current, DependencyObject? root)
    {
        ScrollViewer? fallback = null;
        while (current is not null)
        {
            if (current is ScrollViewer viewer)
            {
                fallback ??= viewer;
                if (viewer.ScrollableHeight > 0) return viewer;
            }
            if (ReferenceEquals(current, root)) break;
            current = GetInteractionParent(current);
        }
        return fallback is { ScrollableHeight: > 0 } ? fallback : null;
    }

    private static DependencyObject? GetInteractionParent(DependencyObject element)
    {
        if (element is ContentElement content)
            return ContentOperations.GetParent(content) ?? (content as FrameworkContentElement)?.Parent;
        if (element is Visual or Visual3D)
            return VisualTreeHelper.GetParent(element);
        return LogicalTreeHelper.GetParent(element);
    }

    private static void OnAnimatedOffsetChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is ScrollViewer viewer && e.NewValue is double offset)
            viewer.ScrollToVerticalOffset(offset);
    }
}
