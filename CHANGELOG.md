# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed

- GitHub token is now stored in the macOS Keychain instead of plaintext in `~/Library/Application Support/StarBar/config.json`. Existing installs auto-migrate on first launch and the token is scrubbed from the on-disk config.

## [0.3.0] - 2025-10-26

Initial public release.
