using System;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Data;

namespace McController.App.Util;

/// <summary>
/// bool → <see cref="Visibility"/>. WinUI 3 dropped the built-in WPF
/// BooleanToVisibilityConverter; this is the equivalent.
/// </summary>
public sealed class BoolToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
        => value is bool b && b ? Visibility.Visible : Visibility.Collapsed;

    public object ConvertBack(object value, Type targetType, object parameter, string language)
        => value is Visibility v && v == Visibility.Visible;
}
