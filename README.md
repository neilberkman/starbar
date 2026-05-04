# StarBar

Is your repo getting a little attention? Stop refreshing GitHub.

StarBar gives you real-time menu bar notifications for stars, new issues, and new pull requests on your repos. Webhooks deliver events straight to your Mac — no polling, no delays.

## How it works

1. Creates webhooks (subscribed to `watch`, `issues`, and `pull_request`) on your active repos — repos with >10 stars, recent activity, or created in the last 3 months
2. Runs a local webhook server with ngrok tunnel to receive GitHub events
3. Validates webhook signatures and shows native notifications
4. Automatically handles network changes and tunnel restarts
5. Syncs new repos, missed stars, and missed issues/PRs when you manually trigger a rescan or relaunch the app

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

**Menu bar icon shows:**

- Total star count across all repos
- Tunnel status (active/offline)
- Number of tracked repos
- Recent Stars submenu with last 50 stars (unread marked with bullet)
- Recent Activity submenu with last 50 issues/PRs (unread marked with bullet)

**Actions:**

- Click "Rescan Repos Now" to sync new repos and catch up on missed stars and issues/PRs
- Click "Launch at Startup" to toggle launch behavior
- Click any star in Recent Stars to open that repo's stargazers page
- Click any issue or PR in Recent Activity to open it on GitHub

Notifications only fire for activity from other users — issues and PRs you open yourself are ignored.

**Which repos get webhooks:**

StarBar only creates webhooks on "active" repos to stay within GitHub's webhook limits:

- Repos with more than 10 stars
- Repos starred in the last 6 months
- Repos created in the last 3 months

Inactive repos are still tracked but won't send real-time notifications until they become active again.

## Storage

- **GitHub token**: macOS Keychain (service `com.xuku.starbar`, account `github_token`)
- **Repo state and per-repo webhook secrets**: `~/Library/Application Support/StarBar/config.json`

Upgrading from an earlier version that kept the token in `config.json`? Just relaunch — StarBar moves the token to the Keychain on next launch and removes it from the JSON file.

## Troubleshooting

**Tunnel shows offline:**

- Verify ngrok is configured: `ngrok config check`
- Check ngrok is in PATH: `which ngrok`
- Restart StarBar to reconnect

**No notifications:**

- Check macOS notification settings for StarBar
- Verify webhook was created: check repo Settings > Webhooks on GitHub
- Only "active" repos get webhooks (see criteria above)

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
