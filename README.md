# StarBar

Real-time menu bar notifications for activity on the public repos you own — stars, new issues, and new pull requests, delivered to your Mac within seconds.

GitHub email digests and the web inbox both work, but neither tells you in real time when a stranger files a bug or opens a PR on one of your projects. StarBar does, by listening for repo webhooks directly.

> The name comes from the original scope (just stars). It grew to cover issues and PRs; the name stuck.

## What you'll see

- **⭐ Stars** — someone stars your repo (with star count and user)
- **📩 New issues** — someone opens or reopens an issue
- **🔃 New pull requests** — someone opens or reopens a PR

Activity you trigger yourself is filtered out. Clicking a menu entry opens it on GitHub.

## How it works

1. Enumerates the public repos you own
2. Creates a webhook on each "active" repo (subscribed to `watch`, `issues`, `pull_request`)
3. Runs a local webhook server with an ngrok tunnel so GitHub can reach it
4. Validates HMAC signatures, then fires a native notification
5. On launch and on rescan, backfills anything missed while offline via the GitHub API

Network changes and tunnel restarts are handled automatically. Webhooks whose subscribed events drift out of sync are detected and re-registered.

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

**Menu bar shows:**

- Total star count across all tracked repos
- Tunnel status (active/offline) and number of tracked repos
- **Recent Stars** — last 50 star events (unread marked with •)
- **Recent Activity** — last 50 issues + PRs (unread marked with •)

**Actions:**

- "Rescan Repos Now" — sync new repos and backfill anything missed while StarBar was off
- "Launch at Startup" — toggle launch behavior
- Click a star in Recent Stars → opens the repo's stargazers page
- Click an issue or PR in Recent Activity → opens it on GitHub

**Which repos get realtime updates:**

To stay under GitHub's per-account webhook limit, StarBar only registers webhooks on "active" repos:

- Repos with more than 10 stars
- Repos starred in the last 6 months
- Repos created in the last 3 months

Inactive repos are still tracked. They won't deliver realtime notifications, but their stars and activity are picked up by backfill on each rescan.

## Storage

- **GitHub token**: macOS Keychain (service `com.xuku.starbar`, account `github_token`)
- **Repo state, per-repo webhook secrets, and activity cursors**: `~/Library/Application Support/StarBar/config.json`

Upgrading from an earlier version that kept the token in `config.json`? Just relaunch — StarBar moves the token to the Keychain on next launch and removes it from the JSON file.

## Troubleshooting

**Tunnel shows offline:**

- Verify ngrok is configured: `ngrok config check`
- Check ngrok is in PATH: `which ngrok`
- Restart StarBar to reconnect

**No notifications:**

- Check macOS notification settings for StarBar
- Verify the webhook was created: check repo Settings → Webhooks on GitHub
- Only "active" repos get webhooks (see criteria above) — other repos arrive via backfill on rescan, not realtime

**View logs:**

```bash
# Show last hour of activity
log show --predicate 'subsystem == "com.xuku.starbar"' --info --last 1h

# Stream live events
log stream --predicate 'subsystem == "com.xuku.starbar"' --level info
```

## Building from Source

```bash
git clone https://github.com/neilberkman/starbar
cd starbar
./scripts/build-app.sh
```

This builds `dist/StarBar.app`, which you can move into `/Applications`.

If you launch the raw binary in `.build/.../StarBar` directly, macOS treats it like a command-line executable and may open a Terminal window for it. Use the `.app` bundle instead.

You'll still need to configure ngrok separately.

## License

MIT
