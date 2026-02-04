# User Behaviors Catalog

All observable user-facing behaviors in ClaudeBar, organized by feature area.
This catalog serves as the foundation for BDD-style acceptance criteria and test coverage mapping.

## Menu Bar

| # | Behavior |
|---|----------|
| 1 | User clicks menu bar icon → sees popup with provider pills, quota cards, action bar |
| 2 | Menu bar icon reflects the selected provider's worst quota status (healthy/warning/critical/depleted) |
| 3 | Menu bar icon appearance changes with selected theme |

## Provider Selection

| # | Behavior |
|---|----------|
| 4 | User clicks a provider pill → switches view and triggers refresh |
| 5 | Only enabled providers appear as pills |
| 6 | Disabling the currently selected provider → auto-switches to first enabled provider |
| 7 | Provider selection persists across app restarts |

## Quota Display

| # | Behavior |
|---|----------|
| 8 | User sees account info card (email, tier badge, "Updated 2m ago") |
| 9 | User sees quota cards with percentage, progress bar, reset time |
| 10 | User toggles "Remaining" vs "Used" display mode in settings |
| 11 | Stale data (>5 min) shows warning indicator |
| 12 | Loading state shows spinner with "Fetching usage data..." |
| 13 | Unavailable provider shows error message with guidance |
| 14 | Over-quota displays negative percentages (e.g., -98%) |

## Refresh

| # | Behavior |
|---|----------|
| 15 | User clicks Refresh → fetches latest quota for current provider |
| 16 | Button shows "Syncing..." spinner while in progress |
| 17 | Duplicate refresh clicks are ignored while syncing |
| 18 | Background sync auto-refreshes at configured interval |

## Notifications

| # | Behavior |
|---|----------|
| 19 | Quota drops to Warning (≤50%) → system notification |
| 20 | Quota drops to Critical (<20%) → system notification |
| 21 | Quota hits Depleted (0%) → system notification |
| 22 | Quota improves → no notification (only degrades trigger alerts) |
| 23 | App requests notification permission on first launch |

## Action Bar

| # | Behavior |
|---|----------|
| 24 | User clicks Dashboard → opens provider's web dashboard in browser |
| 25 | User clicks Share (Claude only) → shows referral link overlay with pass count |
| 26 | Settings button shows red badge when app update available |
| 27 | User clicks Quit → app terminates |

## Claude Configuration

| # | Behavior |
|---|----------|
| 28 | User switches Claude to API mode → uses OAuth HTTP API instead of CLI |
| 29 | API mode shows credential status (found / not found) |
| 30 | Expired session shows "Run `claude` in terminal to log in again" |
| 31 | User sets monthly budget → sees cost-based usage card |
| 32 | Auto-trusts probe directory when CLI shows trust dialog |

## Codex Configuration

| # | Behavior |
|---|----------|
| 33 | User switches Codex to API mode → uses ChatGPT backend API instead of RPC |
| 34 | API mode shows credential status (found / not found) |

## Copilot Configuration

| # | Behavior |
|---|----------|
| 35 | User enters GitHub PAT + username → Copilot quota fetched via API |
| 36 | User sets plan tier (Free/Pro/Business/Enterprise/Pro+) → adjusts monthly limit |
| 37 | User enables manual override → enters usage count or percentage |
| 38 | API returns empty → warning banner suggests manual entry |
| 39 | "Save & Test Connection" validates token |
| 40 | Manual usage auto-clears when billing period changes |

## Z.ai Configuration

| # | Behavior |
|---|----------|
| 41 | User sets custom config path → probe reads from that file |
| 42 | User sets env var fallback → probe uses env var if config file has no token |

## Bedrock Configuration

| # | Behavior |
|---|----------|
| 43 | User sets AWS profile → probe authenticates with that SSO profile |
| 44 | User sets regions → probe queries CloudWatch across those regions |
| 45 | User sets daily budget → shows budget progress bar |

## Provider Enable/Disable

| # | Behavior |
|---|----------|
| 46 | User toggles provider off → removed from pills, excluded from monitoring |
| 47 | User toggles provider on → appears in pills, included in monitoring |
| 48 | Enabled state persists across restarts |

## Themes

| # | Behavior |
|---|----------|
| 49 | User selects Dark/Light/CLI/Christmas theme → UI updates immediately |
| 50 | System theme follows macOS light/dark mode |
| 51 | Christmas theme auto-enables Dec 24–26, reverts after |

## Updates

| # | Behavior |
|---|----------|
| 52 | App checks for updates when menu opens |
| 53 | User toggles beta channel → receives pre-release updates |
| 54 | User clicks manual check → shows available version or "up to date" |
