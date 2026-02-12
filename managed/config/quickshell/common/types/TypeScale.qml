import QtQml
import QtQuick
import ".."

QtObject {
    readonly property TextStyle bodyLarge: TextStyle { line: 24; size: 16; weight: Font.Normal }
    readonly property TextStyle bodyMedium: TextStyle { line: 20; size: 14; weight: Font.Normal }
    readonly property TextStyle bodySmall: TextStyle { line: 16; size: 12; weight: Font.Normal }

    readonly property TextStyle displayLarge: TextStyle { line: 64; size: 57; weight: Font.Normal }
    readonly property TextStyle displayMedium: TextStyle { line: 52; size: 45; weight: Font.Normal }
    readonly property TextStyle displaySmall: TextStyle { line: 44; size: 36; weight: Font.Normal }

    readonly property TextStyle headlineLarge: TextStyle { line: 40; size: 32; weight: Font.Normal }
    readonly property TextStyle headlineMedium: TextStyle { line: 36; size: 28; weight: Font.Normal }
    readonly property TextStyle headlineSmall: TextStyle { line: 32; size: 24; weight: Font.Normal }

    readonly property TextStyle labelLarge: TextStyle { line: 20; size: 14; weight: Font.Medium }
    readonly property TextStyle labelMedium: TextStyle { line: 16; size: 12; weight: Font.Medium }
    readonly property TextStyle labelSmall: TextStyle { line: 16; size: 11; weight: Font.Medium }

    readonly property TextStyle titleLarge: TextStyle { line: 28; size: 22; weight: Font.Normal }
    readonly property TextStyle titleMedium: TextStyle { line: 24; size: 16; weight: Font.Medium }
    readonly property TextStyle titleSmall: TextStyle { line: 20; size: 14; weight: Font.Medium }
}
