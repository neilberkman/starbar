# StarBar

Real-time GitHub star notifications in your Mac menu bar.

## Features

- Real-time notifications when your repos get starred
- Automatic catch-up on missed stars when offline
- Native macOS menu bar app
- Zero configuration (just paste GitHub token)
- Weekly auto-scan for new repos

## Installation

### Requirements

- macOS 13.0+
- ngrok account (free tier works)

### Steps

1. Install ngrok:

   ```bash
   brew install ngrok
   ```

2. Configure ngrok with your authtoken:

   ```bash
   ngrok config add-authtoken YOUR_AUTHTOKEN
   ```

   Get your authtoken at: https://dashboard.ngrok.com/get-started/your-authtoken

3. Download StarBar.app from [Releases](https://github.com/yourusername/starbar/releases)

4. Move to Applications:

   ```bash
   mv StarBar.app /Applications/
   ```

5. First launch (bypass Gatekeeper):
   - Right-click StarBar.app
   - Click "Open"
   - Click "Open" in the dialog

6. Create GitHub token:
   - Visit: https://github.com/settings/tokens/new?scopes=repo,admin:repo_hook
   - Generate token
   - Paste in StarBar setup window

## Usage

- Click menu bar icon to see recent stars
- "Rescan Repos Now" to manually check for new repos
- "Clear Badge" to reset notification count

## Building from Source

```bash
git clone https://github.com/yourusername/starbar
cd starbar
open StarBar.xcodeproj
# Build in Xcode
```

## License

MIT
