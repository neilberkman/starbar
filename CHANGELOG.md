# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Real-time notifications for new issues and pull requests opened on your tracked repos, alongside the existing star events. A "Recent Activity" submenu shows the last 50 issues/PRs; clicking opens the issue/PR in the browser.
- Backfill on launch and on rescan: catches issues and PRs opened while StarBar was off. Per-repo cursor advances after each scan; first run defaults to a 7-day window.

### Changed

- GitHub token is now stored in the macOS Keychain instead of plaintext in `~/Library/Application Support/StarBar/config.json`. Existing installs auto-migrate on first launch and the token is scrubbed from the on-disk config.
- Webhooks now subscribe to `watch`, `issues`, and `pull_request` events. Existing single-event webhooks are auto-detected and re-registered with the full event set on next launch.
- Self-opened issues and pull requests are filtered out — notifications fire only for activity from other users.

## [0.3.0] - 2025-10-26

Initial public release.
