# StarBar Design Document

**Date:** 2025-10-26
**Project:** StarBar - Real-time GitHub star notifications in your Mac menu bar

## Overview

StarBar is a native macOS menu bar application that provides real-time notifications when repositories receive new stars. It combines GitHub webhooks for instant notifications with polling for catching up on missed events.

## Goals

- **Real-time notifications** when any of your repos gets starred
- **Zero configuration** beyond GitHub token
- **Reliable** even when laptop sleeps/moves between networks
- **Good citizen** - clean up webhooks, respect rate limits
- **Native macOS** experience - small binary, fast, native notifications

## Architecture

### Tech Stack

- **Language:** Swift (native macOS)
- **UI:** NSStatusBar for menu bar, AppKit for windows
- **Tunnel:** Cloudflare Tunnel (cloudflared) for webhook endpoint
- **HTTP Server:** URLSession/Network framework for local webhook receiver

### Components

```
StarBar.app
├── AppDelegate.swift           - App lifecycle, setup/teardown
├── TunnelManager.swift          - cloudflared process management
├── WebhookServer.swift          - Local HTTP server on :3000
├── GitHubAPI.swift              - API client (webhooks, repos, stargazers)
├── NotificationManager.swift    - macOS notifications + badge
├── NetworkMonitor.swift         - Detect network changes
├── Config.swift                 - Configuration management
└── Models/
    ├── Repository.swift
    └── StarEvent.swift
```

## User Experience

### First Run

1. App launches, detects no config
2. Shows setup window: "Welcome to StarBar"
3. User pastes GitHub token (with link to create one)
4. App validates token, saves config
5. Runs initial repo scan
6. Shows success message, hides to menu bar

### Normal Operation

**Menu bar shows:**

- Star icon with badge count (unread stars)
- Click reveals menu:
  ```
  StarBar
  ├── Total Stars: 142
  ├── Recent Stars ▸
  │   ├── ⭐ user/repo1 from @alice (2m ago)
  │   ├── ⭐ user/repo2 from @bob (1h ago)
  │   └── ⭐ user/repo3 from @charlie (3h ago)
  ├── ───────────
  ├── Rescan Repos Now
  ├── Clear Badge
  ├── Preferences
  └── Quit
  ```

**Notifications:**

- Native macOS notification banner
- "⭐ New star on user/repo-name from @username"
- Click opens repo in browser

### Network Changes

When moving between networks (cafe to home):

1. App detects network change
2. Automatically restarts tunnel
3. Updates webhook with new URL
4. User sees no interruption

## Data Flow

### Startup Sequence

```
1. Load config from ~/Library/Application Support/StarBar/config.json
2. Validate GitHub token
3. Start cloudflared subprocess
4. Parse tunnel URL from stdout (10s timeout)
5. Start local HTTP server on :3000
6. Clean up old webhooks (delete *.trycloudflare.com)
7. Create new user-level webhook with current tunnel URL
8. Check if weekly scan needed (last_full_scan + 7 days)
9. If scan needed OR first run:
   - Fetch all repos (paginate through /user/repos)
   - Filter: stargazers_count > 0
   - Update tracked_repos list
10. Poll stargazers for all tracked repos
11. Compare against last_star_at → notify for new stars
12. Start network change monitoring
13. Start health check timer (60s interval)
```

### Real-time Webhook Flow

```
GitHub → Cloudflare Tunnel → localhost:3000/webhook

POST /webhook receives:
{
  "action": "created",
  "starred_at": "2025-10-26T15:30:00Z",
  "repository": {
    "full_name": "user/repo",
    "stargazers_count": 26
  },
  "sender": {
    "login": "username"
  }
}

Handler:
1. Verify X-Hub-Signature-256 header
2. Add repo to tracked_repos if not present
3. Update repos[repo].last_star_at
4. Update repos[repo].star_count
5. Show notification: "⭐ user/repo from @username"
6. Increment badge count
7. Save state to disk
```

### Polling Algorithm

For each tracked repo:

```
GET /repos/:owner/:repo/stargazers
  ?per_page=100
  Accept: application/vnd.github.v3.star+json

Response: [
  {
    "starred_at": "2025-10-26T15:30:00Z",
    "user": {"login": "username"}
  }
]

Filter: starred_at > last_star_at
For each new star:
  - Show notification
  - Increment badge count
Update last_star_at to most recent
Save state
```

### Shutdown Sequence

```
1. Delete user webhook (using stored webhook_id)
2. Kill cloudflared subprocess
3. Save final state to disk
4. Quit
```

## Configuration

### File Location

`~/Library/Application Support/StarBar/config.json`

### Structure

```json
{
  "github_token": "ghp_xxxxxxxxxxxx",
  "state": {
    "last_full_scan": "2025-10-26T15:00:00Z",
    "scan_interval_days": 7,
    "user_webhook_id": 789012,
    "tracked_repos": ["user/repo1", "user/repo2"],
    "repos": {
      "user/repo1": {
        "last_star_at": "2025-10-26T15:00:00Z",
        "star_count": 25
      },
      "user/repo2": {
        "last_star_at": "2025-10-26T14:00:00Z",
        "star_count": 17
      }
    }
  }
}
```

### GitHub Token Permissions

Required scopes:

- `repo` - Read repository data and stargazers
- `admin:repo_hook` - Create and delete webhooks

## Webhook Management

### User-level Webhook

**Why user-level?**

- One webhook catches stars on ALL repos
- Simpler than N per-repo webhooks
- No webhook limit concerns (20 user-level vs 25 per repo)

**Endpoint:** `POST https://api.github.com/users/:username/hooks`

**Payload:**

```json
{
  "name": "web",
  "active": true,
  "events": ["watch"],
  "config": {
    "url": "https://random-url.trycloudflare.com/webhook",
    "content_type": "json",
    "secret": "generated-secret"
  }
}
```

**Note:** GitHub's "watch" event fires for both watching AND starring (legacy naming)

### Webhook Cleanup

**At startup:**

1. `GET /users/:username/hooks` - list all webhooks
2. Filter for `*.trycloudflare.com` URLs
3. Delete each: `DELETE /users/:username/hooks/:id`
4. Create new webhook with current tunnel URL

**On shutdown:**

1. Delete webhook using stored `user_webhook_id`

This ensures we don't accumulate dead webhooks over time.

## Resilience

### Network Change Handling

**Dual approach:**

1. **Network Reachability Monitoring**
   - Use `SCNetworkReachability` callbacks
   - Detect network changes immediately
   - Trigger tunnel restart + webhook update

2. **Health Check Polling**
   - Every 60 seconds: `GET http://localhost:3000/health`
   - If fails → tunnel is dead → restart flow
   - Catches tunnel crashes, not just network changes

**Restart flow:**

```
1. Kill old cloudflared process
2. Start new cloudflared → parse new URL
3. Delete old webhook (using stored webhook_id)
4. Create new webhook with new URL
5. Update state with new webhook_id
```

### Cloudflare Tunnel Failures

**Detection:**

- Parse cloudflared stdout for URL (regex: `https://.*\.trycloudflare\.com`)
- Timeout after 10 seconds if URL not found
- Monitor process exit codes

**Recovery:**

- If cloudflared exits unexpectedly → auto-restart
- Show user notification if restart fails 3 times
- Log stderr to `~/Library/Logs/StarBar/tunnel.log`

### GitHub API Rate Limits

**Limits:**

- Authenticated: 5,000 requests/hour
- Tracked via `X-RateLimit-Remaining` header

**Mitigation:**

- Track remaining quota
- If < 100 remaining → pause polling, show warning
- Webhook events don't count against limit
- Startup polling: ~1 request per tracked repo (typically < 50)

**Rate limit recovery:**

- Wait for `X-RateLimit-Reset` timestamp
- Resume operations after reset

### Webhook Delivery Failures

**GitHub behavior:**

- Retries failed webhooks for 1 hour
- Exponential backoff
- After repeated failures → webhook disabled → email sent

**Our handling:**

- If offline/sleeping, GitHub gives up eventually
- Startup polling catches ALL missed stars
- User never sees gap in notifications

### Error Handling

**Invalid/missing token:**

- Detect on startup (401 response)
- Show setup window again
- Don't start tunnel until valid token

**Webhook registration failures:**

- 422 (validation) → show error with response details
- 403 (permissions) → prompt to regenerate token with correct scopes
- Network error → retry 3 times with exponential backoff
- After 3 failures → show error dialog

**State corruption:**

- If config.json malformed → backup to `.backup`
- Create fresh config
- Prompt for token again

## Repository Discovery

### Initial Scan

Triggered on:

- First run
- Manual "Rescan Repos Now"
- Automatic weekly scan (configurable interval)

**Algorithm:**

```
1. GET /user/repos?per_page=100&page=1
2. Continue pagination until all repos fetched
3. Filter: stargazers_count > 0
4. Store in tracked_repos list
5. For each tracked repo:
   - Record current star_count
   - Record last_star_at (most recent stargazer)
6. Save state
```

**Optimization:**

- New repos (first seen) → don't notify for existing stars
- Only notify for stars received AFTER app started tracking

### Weekly Auto-scan

**Purpose:** Discover new repos that got stars

**Frequency:** Every 7 days (configurable)

**Behavior:**

- Silent background operation
- Updates tracked_repos list
- Doesn't spam notifications for existing stars on newly discovered repos

### Webhook-driven Discovery

**Bonus:** If untracked repo gets star:

- Webhook delivers event
- App adds repo to tracked_repos
- No need to wait for weekly scan

## Testing Strategy

### Local Development

**Fast iteration:**

- Use ngrok instead of cloudflared during dev
- Mock GitHub API responses
- Test webhook with `curl` requests

**Test cases:**

- First run setup flow
- Tunnel startup/restart
- Network change simulation
- Webhook CRUD operations
- Rate limit handling
- Invalid token handling
- Malformed webhook payloads
- Concurrent star events

### Manual Testing

**Checklist:**

- [ ] First run: token input, initial scan
- [ ] Real-time: star a repo, verify notification
- [ ] Startup polling: miss stars while offline, verify catch-up
- [ ] Network change: switch WiFi, verify reconnection
- [ ] Weekly scan: verify auto-scan triggers
- [ ] Manual rescan: click menu item, verify scan
- [ ] Badge count: verify increments, clear works
- [ ] Preferences: change settings, verify persistence
- [ ] Quit: verify webhook cleanup

## Distribution

### Build & Packaging

**Requirements:**

- Xcode 15+
- macOS 13+ (target)
- Swift 5.9+

**Build:**

```bash
xcodebuild -project StarBar.xcodeproj \
  -scheme StarBar \
  -configuration Release \
  -archivePath StarBar.xcarchive \
  archive

xcodebuild -exportArchive \
  -archiveFolder StarBar.xcarchive \
  -exportPath dist \
  -exportOptionsPlist ExportOptions.plist
```

**Output:** `dist/StarBar.app`

### Distribution Channels

**1. GitHub Releases**

- Upload .zip of StarBar.app
- Include cloudflared install instructions
- Unsigned app - document first launch steps

**2. Homebrew Cask**

```ruby
cask "starbar" do
  version "1.0.0"
  sha256 "..."

  url "https://github.com/user/starbar/releases/download/v#{version}/StarBar.zip"
  name "StarBar"
  desc "GitHub star notifications in your menu bar"
  homepage "https://github.com/user/starbar"

  app "StarBar.app"

  postflight do
    system "brew", "install", "cloudflare/cloudflare/cloudflared"
  end
end
```

**3. Direct Download**

- Host on GitHub Pages
- Simple landing page with download link

### First Launch Instructions

**README includes:**

```
## Installation

1. Download StarBar.app from Releases
2. Move to /Applications
3. Right-click > Open (first time only, to bypass Gatekeeper)
4. Install cloudflared: `brew install cloudflare/cloudflare/cloudflared`
5. Create GitHub token: https://github.com/settings/tokens/new?scopes=repo,admin:repo_hook
6. Launch StarBar, paste token
```

### Auto-updates (Optional)

**Sparkle Framework:**

- Add to Xcode project
- Check GitHub Releases for new versions
- Show in-app update notification
- Works without code signing

**Or:** Manual updates via Homebrew

## Future Enhancements

**Nice to have (not MVP):**

- Filter repos by organization
- Custom notification sounds
- Star analytics/trends
- Export star data to CSV
- Dark mode icon variants
- Keyboard shortcuts
- Multiple GitHub accounts

## Open Questions

None - design is complete and validated.

## References

- [GitHub Webhooks API](https://docs.github.com/en/webhooks)
- [GitHub Activity API](https://docs.github.com/en/rest/activity)
- [Cloudflare Tunnel Docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [NSStatusBar Documentation](https://developer.apple.com/documentation/appkit/nsstatusbar)
