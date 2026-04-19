# LlamaiOS

LlamaiOS is a native iOS 17+ SwiftUI app for private, fully local GGUF chat using llama.cpp. It is designed as a serious foundation for on-device language-model inference: SwiftData persistence, model import and selection, streaming generation, prompt assembly, generation controls, and a narrow Objective-C++ bridge around llama.cpp.

## Architecture

- `LlamaiOS/App`: app entry point, SwiftData container, and root navigation.
- `LlamaiOS/Features/Chat`: conversation list, chat view, message composer, system prompt editor, streaming flow.
- `LlamaiOS/Features/Models`: GGUF import, registry, metadata display, active model selection, safe deletion.
- `LlamaiOS/Features/Settings`: default prompts, generation defaults, performance options, privacy, and backend info.
- `LlamaiOS/Core/Engine`: `LlamaEngine` async Swift API plus `LlamaCppBridge.mm` Objective-C++ llama.cpp integration.
- `LlamaiOS/Core/Persistence`: SwiftData records and generation settings.
- `LlamaiOS/Core/Prompting`: chat template/fallback prompt builder with context protection.
- `LlamaiOS/Core/Markdown`: native Markdown rendering and fenced code blocks with copy buttons.

No runtime network inference or external AI API is included.

## llama.cpp Setup

The Xcode project expects the official llama.cpp XCFramework here:

```text
Vendor/llama.xcframework
```

If the framework is missing, the app target intentionally fails with a clear setup error.

One practical way to produce the framework is to build llama.cpp for iOS with Metal enabled, then copy the resulting XCFramework into `Vendor/llama.xcframework`. The bridge accepts either of these header layouts:

```objc
#import <llama/llama.h>
#import <llama.h>
```

The linked framework must expose the llama.cpp C API used by `LlamaCppBridge.mm`, including model loading, metadata reads, tokenization, sampler chains, and decode.

## Running

1. Open `LlamaiOS.xcodeproj` in Xcode 16 or newer.
2. Add `Vendor/llama.xcframework`.
3. Select a real iPhone or iOS device destination. Large GGUF models are not practical in the simulator.
4. Set your development team in Signing & Capabilities.
5. Build and run.
6. Open Models, import a `.gguf` file from Files, select it, then start chatting.

## Model Import

Imported models are copied into the app's Application Support `Models` directory. The registry stores display name, original file name, local path, file size, import date, last used date, selection state, and llama.cpp metadata when available.

Validation checks:

- `.gguf` extension
- readable file
- non-empty file size
- copy success into app storage
- best-effort llama.cpp metadata read

## Features

- Multiple local conversations persisted with SwiftData.
- Per-conversation system prompt and generation settings snapshot.
- Token-by-token streaming through `AsyncThrowingStream`.
- Stop, regenerate, edit/resend last user message, and clear conversation.
- Native Markdown rendering for assistant messages.
- Fenced code block rendering with copy button.
- Settings for temperature, top-p, top-k, repeat penalty, max new tokens, context length, seed, threads, and GPU layers.
- Compact performance strip with tokens/sec and elapsed time.
- Local-only privacy page.

## Tests

The test target covers prompt formatting, context truncation, generation setting clamping, GGUF import validation, SwiftData persistence, and engine single-flight behavior with a test-only fake bridge.

Run from Xcode after adding `Vendor/llama.xcframework`.

## Known Limitations

- The project cannot be fully compiled until a compatible `Vendor/llama.xcframework` is present.
- Built-in chat template support is best-effort. If metadata exposes `tokenizer.chat_template`, the prompt layer uses it in a simple replacement path; otherwise it falls back to ChatML-style formatting.
- Token counting uses a conservative heuristic before inference. Exact token counts depend on the loaded model tokenizer.
- GPU acceleration depends entirely on how the llama.cpp XCFramework was built.
- App icons are placeholder asset catalog entries and should be replaced before App Store submission.

## Future Improvements

- Richer Jinja-compatible llama.cpp chat template rendering.
- Background model download/import workflows for user-supplied files.
- Conversation export/import.
- More detailed memory pressure handling and model compatibility diagnostics.
- Optional per-model presets and automatic recommended settings.
