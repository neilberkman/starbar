# Webhook Testing Guide

## What Was Added

✅ **Webhook Signature Validation** - HMAC-SHA256 validation using CryptoKit
✅ **Webhook Secret Management** - Secrets stored in RepoState
✅ **Proper UserNotifications** - Switched from osascript to UserNotifications API

## Testing Status

### ✅ Signature Validation Logic - VERIFIED

Ran `test_webhook.swift` which confirmed:

- Valid signatures are accepted
- Invalid signatures are rejected
- Wrong secrets are rejected

### Manual Testing with Real Webhooks

The app needs to run as a proper macOS application (menu bar app) to test end-to-end. Here's how:

#### Option 1: Build and Run via Xcode (Recommended)

1. Open the project in Xcode:

   ```bash
   open Package.swift
   ```

2. Build and run the app (⌘R)

3. The app will:
   - Start cloudflared tunnel automatically
   - Log tunnel URL like: `Tunnel started: https://xxx.trycloudflare.com`
   - Create webhooks for your repos with generated secrets
   - Start webhook server on port 58472

4. Check the Xcode console for the tunnel URL

5. Send a test webhook:

   ```bash
   # Get a webhook secret from config
   SECRET=$(cat ~/Library/Application\ Support/starbar/config.json | jq -r '.state.repos | to_entries[0].value.webhook_secret')

   # Get tunnel URL from Xcode console logs, then:
   ./send_test_webhook.swift https://YOUR-TUNNEL-URL.trycloudflare.com "$SECRET"
   ```

#### Option 2: Test with Real GitHub Star

1. Run the app via Xcode
2. Star one of your repos
3. GitHub will send a real webhook
4. Check the console for signature validation logs:
   - `✓ Webhook signature validated for REPO_NAME`
   - Or `❌ Invalid webhook signature` if something's wrong

## Test Scripts Available

- `test_webhook.swift` - Unit test for signature validation (✅ passing)
- `send_test_webhook.swift` - Send a signed test webhook to your tunnel
- `test_webhook_server.swift` - Standalone webhook server for testing

## What's Been Committed

```
Add webhook signature validation and fix notifications

- Add HMAC-SHA256 signature validation for webhook security
- Store webhook secrets in RepoState for validation
- Switch from osascript to proper UserNotifications API
- Use webhook payload starredAt instead of API fetch
- Update .gitignore to exclude app bundles and test files
```

## Security Note

The test_api.swift file with an exposed token was deleted and .gitignore was updated.
**⚠️ REVOKE THE EXPOSED TOKEN**: https://github.com/settings/tokens
