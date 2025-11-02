# StarBar

Real-time GitHub star notifications in your Mac menu bar.

## Features

- Real-time notifications when your repos get starred
- Automatic catch-up on missed stars when offline
- Native macOS menu bar app
- Zero configuration (just paste GitHub token)
- Weekly auto-scan for new repos

## Installation

### via Homebrew (recommended)

```bash
brew install neilberkman/starbar/starbar
```

This automatically installs ngrok as a dependency. After installation:

1. Configure ngrok:

   ```bash
   ngrok config add-authtoken YOUR_AUTHTOKEN
   ```

   Get your authtoken at: https://dashboard.ngrok.com/get-started/your-authtoken

2. Launch StarBar from Applications

3. Create GitHub token:
   - Visit: https://github.com/settings/tokens/new?scopes=repo,admin:repo_hook
   - Generate token
   - Paste in StarBar setup window

### Manual Installation

**Requirements:**

- macOS 13.0+
- ngrok account (free tier works)

**Steps:**

1. Install and configure ngrok:

   ```bash
   brew install ngrok
   ngrok config add-authtoken YOUR_AUTHTOKEN
   ```

   Get your authtoken at: https://dashboard.ngrok.com/get-started/your-authtoken

2. Download StarBar.app from [Releases](https://github.com/neilberkman/starbar/releases)

3. Move to Applications:

   ```bash
   mv StarBar.app /Applications/
   ```

4. First launch (bypass Gatekeeper):
   - Right-click StarBar.app
   - Click "Open"
   - Click "Open" in the dialog

5. Create GitHub token:
   - Visit: https://github.com/settings/tokens/new?scopes=repo,admin:repo_hook
   - Generate token
   - Paste in StarBar setup window

## Usage

- Click menu bar icon to see recent stars
- "Rescan Repos Now" to manually check for new repos
- "Clear Badge" to reset notification count

## Building from Source

```bash
git clone https://github.com/neilberkman/starbar
cd starbar
swift build -c release
```

## License

MIT
