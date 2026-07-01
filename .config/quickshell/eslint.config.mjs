import sonarjs from "eslint-plugin-sonarjs";
import qmlJs from "eslint-plugin-qml-js";

export default [
  {
    ignores: [
      "**/.cache/**",
      "**/build/**",
      "**/build-clang-tidy/**",
      "**/target/**",
      "outlook/**"
    ]
  },
  {
    files: ["**/*.js"],
    processor: qmlJs.processors[".js"],
    plugins: {
      "qml-js": qmlJs,
      sonarjs
    },
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "script",
      globals: {
        console: "readonly",
        Qt: "readonly",
        Quickshell: "readonly"
      }
    },
    rules: {
      complexity: ["error", { max: 20 }],
      "max-depth": ["error", 4],
      "max-lines-per-function": ["error", { max: 90, skipBlankLines: true, skipComments: true }],
      "max-params": ["error", 5],
      "sonarjs/cognitive-complexity": ["error", 25]
    }
  }
];
