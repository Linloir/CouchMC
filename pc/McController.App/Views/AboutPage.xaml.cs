using System.Reflection;
using Microsoft.UI.Xaml.Controls;
using McController.App.Util;

namespace McController.App.Views;

public sealed partial class AboutPage : Page
{
    public AboutPage()
    {
        InitializeComponent();
        ApplyTranslations();
        VersionValue.Text = ResolveVersionString();
    }

    private void ApplyTranslations()
    {
        HeaderTitle.Text     = L.Get("about.title", HeaderTitle.Text);
        HeaderSubtitle.Text  = L.Get("about.subtitle", HeaderSubtitle.Text);
        AppName.Text         = L.Get("about.app.header", AppName.Text);
        AppTagline.Text      = L.Get("about.app.tagline", AppTagline.Text);
        VersionCard.Header   = L.Get("about.version.header", VersionCard.Header?.ToString() ?? "");
        AuthorCard.Header    = L.Get("about.author.header", AuthorCard.Header?.ToString() ?? "");
        AuthorValue.Text     = L.Get("about.author.value", AuthorValue.Text);
        LoveCard.Header      = L.Get("about.love.header", LoveCard.Header?.ToString() ?? "");
        LoveBody.Text        = L.Get("about.love.body", LoveBody.Text);
    }

    /// <summary>
    /// Read the assembly's informational / file version. Falls back to
    /// "dev" if neither is set (running fresh out of git without tags).
    /// </summary>
    private static string ResolveVersionString()
    {
        var asm = typeof(AboutPage).Assembly;
        var info = asm.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;
        if (!string.IsNullOrWhiteSpace(info))
        {
            // Strip the "+<git-sha>" suffix MSBuild appends when source-link is on.
            var plus = info.IndexOf('+');
            return plus >= 0 ? info[..plus] : info;
        }
        return asm.GetName().Version?.ToString(3) ?? "dev";
    }
}
