using System.Windows;
using System.Threading;
using Goals.Windows.Services;
using Goals.Windows.ViewModels;
using Goals.Windows.Views;

namespace Goals.Windows;

public partial class App : Application
{
    private Mutex? _singleInstanceMutex;
    private readonly HashSet<string> _shownUnhandledErrors = new(StringComparer.Ordinal);
    public MainViewModel ViewModel { get; private set; } = null!;

    protected override void OnStartup(StartupEventArgs e)
    {
        _singleInstanceMutex = new Mutex(true, @"Local\GoalsStudyDesk.SingleInstance", out var isFirstInstance);
        if (!isFirstInstance)
        {
            MessageBox.Show("Goals 已经在运行，请切换到已打开的窗口。", "Goals", MessageBoxButton.OK, MessageBoxImage.Information);
            _singleInstanceMutex.Dispose();
            _singleInstanceMutex = null;
            Shutdown();
            return;
        }
        base.OnStartup(e);
        DispatcherUnhandledException += (_, args) =>
        {
            var signature = $"{args.Exception.GetType().FullName}\n{args.Exception.Message}";
            if (_shownUnhandledErrors.Add(signature))
                MessageBox.Show(args.Exception.Message, "Goals 遇到问题", MessageBoxButton.OK, MessageBoxImage.Error);
            args.Handled = true;
        };

        var store = new AppDataStore();
        var state = store.Load();
        ViewModel = new MainViewModel(state, store, new DeepSeekService(new WindowsCredentialStore()), new WordLibraryStore());

        var main = new MainWindow(ViewModel);
        MainWindow = main;
        main.Show();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        if (_singleInstanceMutex is not null)
        {
            _singleInstanceMutex.ReleaseMutex();
            _singleInstanceMutex.Dispose();
        }
        base.OnExit(e);
    }

    public void OpenMainWindow()
    {
        MainWindow?.Show();
        if (MainWindow?.WindowState == WindowState.Minimized)
            MainWindow.WindowState = WindowState.Normal;
        MainWindow?.Activate();
    }
}
