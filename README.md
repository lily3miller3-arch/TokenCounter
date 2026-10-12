# TokenCounter

A lightweight macOS utility that counts OpenAI (`cl100k_base`) tokens directly from your clipboard.

## Features

- **Instant & Minimal**: A small floating pad. Just press `⌘V` to paste text and see the exact token count instantly.
- **Privacy First & 100% Offline**: Counting happens entirely on device using a local BPE implementation. No text is ever uploaded or sent over the network.
- **Fast**: High-performance local tokenizer implementation in pure Swift with zero external dependencies.
- **Native**: Built cleanly for macOS with native AppKit/Cocoa.

## Requirements

- macOS 14.0 or later
- Xcode 15.0 or later (to build from source)

## Getting Started

1. Clone the repository:
   ```bash
   git clone https://github.com/lily3miller3-arch/TokenCounter.git
   ```
2. Open `TokenCounter.xcodeproj` in Xcode.
3. Build and run (`⌘R`).
4. Copy any text, bring the floating pad to focus, and hit `⌘V`.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
