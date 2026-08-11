using Velopack;

namespace Goals.Windows;

public static class Program
{
    [STAThread]
    public static void Main()
    {
        // Must be the first application call so install/update hooks can exit quickly.
        VelopackApp.Build().Run();

        var app = new App();
        app.InitializeComponent();
        app.Run();
    }
}
