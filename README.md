# hair_flutter

Hairstyle and beauty try-on app built with Flutter.

## AI text generation

The prompt optimizer uses an OpenAI-compatible chat completions API. Configure it
with compile-time values instead of committing keys:

```sh
flutter run \
  --dart-define=AI_TEXT_API_KEY=your_api_key \
  --dart-define=AI_TEXT_BASE_URL=https://api.gptsapi.net/v1 \
  --dart-define=AI_TEXT_MODEL=gpt-4o-mini
```

If `AI_TEXT_API_KEY` is not provided, the app uses a local fallback prompt so the
flow remains testable.

Do not put production API keys into a GitHub Pages build. Static web builds
expose `dart-define` values to the browser; use a backend proxy for public web
deployments that need real text generation.

## AI image generation

Image generation uses Ark Seedream through a compile-time API key. The app has
defaults for the Ark endpoint and Seedream model, so local/mobile builds usually
only need the key:

```sh
flutter run \
  --dart-define=SEEDREAM_API_KEY=your_seedream_key
```

Optional overrides:

```sh
flutter run \
  --dart-define=SEEDREAM_API_KEY=your_seedream_key \
  --dart-define=SEEDREAM_BASE_URL=https://ark.cn-beijing.volces.com/api/v3/images/generations \
  --dart-define=SEEDREAM_MODEL=doubao-seedream-4-0-250828
```

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
