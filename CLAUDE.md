# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ClaudeBar is a macOS menu bar application that monitors AI coding assistant usage quotas (Claude, Codex, Gemini). It probes CLI tools to fetch quota information and displays it in a menu bar interface with system notifications for status changes.

## Build & Test Commands

```bash
# Build the project
swift build

# Run all tests
swift test

# Run a specific test file
swift test --filter DomainTests

# Run a specific test
swift test --filter "QuotaMonitorTests/monitor fetches usage from a single provider"

# Run the app (requires macOS 15+)
swift run ClaudeBar
```

## Architecture

The project follows a clean architecture with hexagonal/ports-and-adapters patterns:

### Layers

- **Domain** (`Sources/Domain/`): Pure business logic with no external dependencies
  - Models: `AIProvider`, `UsageQuota`, `UsageSnapshot`, `QuotaStatus`, `QuotaType`
  - Services: `QuotaMonitor` - the aggregate root actor that coordinates monitoring
  - Ports: `UsageProbePort` (for fetching quotas), `QuotaObserverPort` (for notifications)

- **Infrastructure** (`Sources/Infrastructure/`): Technical implementations
  - CLI probes: `ClaudeUsageProbe`, `CodexUsageProbe`, `GeminiUsageProbe` - parse CLI output
  - `PTYCommandRunner` - runs CLI commands with PTY for interactive prompts
  - `NotificationQuotaObserver` - macOS notification center integration

- **App** (`Sources/App/`): SwiftUI menu bar application
  - Views directly consume domain models (no ViewModel layer)
  - `AppState` is an `@Observable` class shared across views

### Key Patterns

- **Ports and Adapters**: Domain defines ports (`UsageProbePort`, `QuotaObserverPort`), infrastructure provides adapters
- **Actor-based concurrency**: `QuotaMonitor` is an actor for thread-safe state management
- **Mockable protocol mocks**: Uses `@Mockable` macro from Mockable package for test doubles
- **Swift Testing framework**: Tests use `@Test` and `@Suite` attributes, not XCTest

### Adding a New AI Provider

1. Add case to `AIProvider` enum in `Sources/Domain/Models/AIProvider.swift`
2. Create probe in `Sources/Infrastructure/CLI/` implementing `UsageProbePort`
3. Register probe in `ClaudeBarApp.init()`
4. Add parsing tests in `Tests/InfrastructureTests/CLI/`

## Dependencies

- **Sparkle**: Auto-update framework for macOS
- **Mockable**: Protocol mocking for tests via Swift macros
