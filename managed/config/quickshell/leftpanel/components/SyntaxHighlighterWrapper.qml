import QtQuick
import org.kde.syntaxhighlighting

SyntaxHighlighter {
    id: root
    property var targetTextEdit: null
    property string lang: "None"

    textEdit: targetTextEdit

    // Prefer Catppuccin Mocha to match the panel palette, fallback to default dark.
    readonly property var catppuccinTheme: Repository.theme("Catppuccin Mocha")
    theme: catppuccinTheme && catppuccinTheme.name ? catppuccinTheme : Repository.defaultTheme(Repository.DarkTheme)

    definition: {
        // Map common language names to KSyntaxHighlighting definitions
        const langMap = {
            "js": "JavaScript",
            "javascript": "JavaScript",
            "ts": "TypeScript",
            "typescript": "TypeScript",
            "py": "Python",
            "python": "Python",
            "rb": "Ruby",
            "ruby": "Ruby",
            "rs": "Rust",
            "rust": "Rust",
            "go": "Go",
            "golang": "Go",
            "c": "C",
            "cpp": "C++",
            "c++": "C++",
            "h": "C",
            "hpp": "C++",
            "java": "Java",
            "kt": "Kotlin",
            "kotlin": "Kotlin",
            "swift": "Swift",
            "sh": "Bash",
            "bash": "Bash",
            "zsh": "Zsh",
            "fish": "Fish",
            "ps1": "PowerShell",
            "powershell": "PowerShell",
            "html": "HTML",
            "htm": "HTML",
            "css": "CSS",
            "scss": "SCSS",
            "sass": "SCSS",
            "less": "LESS",
            "json": "JSON",
            "yaml": "YAML",
            "yml": "YAML",
            "toml": "TOML",
            "xml": "XML",
            "sql": "SQL",
            "md": "Markdown",
            "markdown": "Markdown",
            "qml": "QML",
            "lua": "Lua",
            "vim": "vim",
            "dockerfile": "Dockerfile",
            "docker": "Dockerfile",
            "makefile": "Makefile",
            "make": "Makefile",
            "cmake": "CMake",
            "nix": "Nix",
            "zig": "Zig",
            "php": "PHP",
            "perl": "Perl",
            "r": "R",
            "scala": "Scala",
            "clojure": "Clojure",
            "clj": "Clojure",
            "elixir": "Elixir",
            "ex": "Elixir",
            "erl": "Erlang",
            "erlang": "Erlang",
            "hs": "Haskell",
            "haskell": "Haskell",
            "ocaml": "OCaml",
            "ml": "OCaml",
            "f#": "FSharp",
            "fsharp": "FSharp",
            "diff": "Diff",
            "patch": "Diff",
            "ini": "INI Files",
            "conf": "INI Files",
            "txt": "None",
            "text": "None",
            "plain": "None"
        };
        return langMap[root.lang.toLowerCase()] || root.lang || "None";
    }
}
