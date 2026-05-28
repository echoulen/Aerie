# Aerie — Design Doc

> macOS dashboard for overseeing many git repos at once — local git state, PRs, quick actions.

**Project**: Aerie
**Date**: 2026-05-28
**Author**: carlos
**Status**: draft

> **Design status**: Claude Design has produced every UI surface this
> spec calls for — two top-level views (PRs, Repos), Settings (Accounts,
> Repositories, MCP, Advanced, About), Add-repo sheet, four confirmation
> dialogs (reset, merge, sign-out, remove), first-run gh setup (both
> sub-states), MCP consent dialog, and the MCP activity toast. See
> [§9 UI Handoff Notes](#9-ui-handoff-notes) for the visual + behavioral
> contract derived from the design.

## Goal

A macOS-only desktop app that gives the user a single dashboard for managing
~50 git repos at once — surfacing local git state and open PRs (with the
state of each PR's local branch, if any), plus three targeted actions
(hard reset to `origin/main`, merge PR, open in browser).

Replaces the current workflow of jumping between `gh pr list` runs, terminals
in each repo directory, and the GitHub web UI.

Aerie also exposes its cache and write actions over **MCP** (see §10), so
parallel Claude Code sessions can share Aerie's polling + auth instead of
each agent maintaining its own.

## Non-goals

- Cross-platform (Linux / Windows). macOS only.
- Background notifications, menu bar mode, system-wide hotkeys. App only does
  work while open in the foreground.
- Auto-discovery of repos. User adds them manually.
- General-purpose git client. Only one git action: `hard reset to origin/main`.
- General-purpose PR management. Only one GitHub action: `merge PR` (assumes
  mergeable). No commenting, approving, requesting changes, etc.
- Opening editor / terminal from the dashboard. The only "jump" is to the
  browser.
- Cross-repo search. Filtering. Sorting controls. (Kept simple by request; can
  be revisited later.)
- Webhooks / push notifications.
- Mobile / web access.
- GitHub Issues — no listing, no tracking. Browser is the way to view issues.
- Commit history view — no per-repo "recent N commits" panel. `gh` / `git log`
  cover that need; Aerie's value is at the repo-summary grain.

## Stack

| Layer | Choice | Notes |
|---|---|---|
| App shell | macOS native (SwiftUI) | "Best GUI experience" requirement |
| Local git | `SwiftGitX` (modern Swift wrapper over libgit2) | Read state + run hard reset. Picked over `SwiftGit2` because SwiftGitX is actively maintained (latest 0.4.0, 2025-12), Swift 6 ready (zero data-race errors), and exposes an async/await + throwing API. |
| GitHub API | `URLSession` + `Codable` | GraphQL primary, REST for `merge` |
| Persistence | `GRDB` (SQLite) | Repo config + response cache |
| Auth source | `gh` CLI (`gh auth status`) | Multi-account, tokens held in-memory |
| Concurrency | Swift `async/await` + actors | No callback-based code |
| MCP server | `Hummingbird` (Swift HTTP server) | Localhost-bound MCP HTTP streamable transport (see §10) |

## Features

### F1. Repo management

- User manually adds repos by selecting a local folder containing a `.git/`.
- App reads `origin` URL to infer `owner/repo` for GitHub identification.
- User can rename display name, set sort order, hide (not delete) a repo.
- Repo list persists across launches.

### F2. Local git status

For each repo, show:

- Current branch name.
- Dirty / clean flag (staged + unstaged + untracked combined).
- Commits ahead of the **default branch** (`origin/<defaultBranch>`).
- Commits behind the default branch.
- Unpushed commits on current branch (vs its tracked upstream, if any).

**Default branch detection**: read `refs/remotes/origin/HEAD` (set by
`git clone` / `git remote set-head`). If unset, fall back to checking
existence of `origin/main`, then `origin/master`, in that order. The
chosen name is stored on the Repository row (`defaultBranch`) and can
be edited in Settings.

### F3. GitHub Pull Requests

- For each configured repo, list **all** open PRs (not filtered to the user).
- Per PR: number, title, author login, CI status, review status, labels.
- Per PR, also resolve the **local checkout state** of the PR's source
  branch (see below) — this lets the UI surface a single combined PR row
  with both GitHub and local status.
- Clicking a PR opens its GitHub HTML URL in the default browser.
- The UI typically aggregates these per-repo lists into one flat view.

**PR local checkout state**: for each open PR, check whether its source
branch (`head.ref`) exists as a local branch in the matching repo. If so,
report whether that local branch is the currently checked-out branch,
plus (when checked out) dirty / ahead / behind / unpushed counts using
the same logic as F2.

### F4. Actions

| Action | Target | Implementation |
|---|---|---|
| **Hard reset to default branch** | one repo | Sequence: `git fetch origin` → `git checkout <defaultBranch>` → `git reset --hard origin/<defaultBranch>`. If working tree is dirty, the confirmation dialog explicitly warns "this will discard N uncommitted changes". Aborts (does not partially apply) on any error. Implemented via SwiftGitX (`repository.fetch(remote:)` → `repository.switch(to:)` → `repository.reset(to: commit, mode: .hard)`). |
| **Merge PR** | one PR | GitHub REST `PUT /repos/{owner}/{repo}/pulls/{number}/merge` using the repo's primary account token. Assumes PR is mergeable; surfaces GitHub's error if not. Merge method: `squash` (matches the user's standard workflow). Confirmation dialog required. |

| **Open in browser** | repo / PR | `NSWorkspace.shared.open(url)` to the entity's GitHub HTML URL. Repo-level shortcuts: open the repo page, the Pull Requests tab, the Code tab. (The Issues tab is also a valid jump target even though Aerie itself does not list issues.) |

**Confirmation note**: the confirmation dialog applies only to the **GUI**
path. The MCP path (§10) invokes the same underlying service without a
dialog, by design — agents are expected to execute autonomously and
each MCP write surfaces a GUI toast for audit instead.

### F5. Polling

- App fetches all data on launch.
- Two-tier cadence (matches the Settings → Advanced design):
  - **Active repo** → refresh every **30 s** (range: 10 s — 5 min).
  - **Background repos** → refresh every **5 min** (range: 1 min — 30 min).
- Default values keep 50 repos within the 5000/hr per-token quota with
  headroom for multi-account fallback (50 × 12/hr = 600/hr at the
  background cadence; the active repo adds at most one row at 120/hr).
- **Active-repo definition**: the repo the user is currently paying
  attention to. Without a dedicated detail view, attention is captured
  from these signals (in priority order):
  1. The repo of the PR card whose action menu is open / merge is being
     considered.
  2. The repo card most recently hovered or selected (within a sliding
     30 s window).
  3. If no signal applies, there is no active repo — every repo polls at
     the background cadence.
  Only ever one active repo at a time. The PollingScheduler holds an
  optional `activeRepoId` updated by the view models.
- A heartbeat tick (default 30 s, equal to the minimum cadence) drives
  the scheduler; on each tick the scheduler computes which repos are
  due and refreshes them in a bounded-concurrency `TaskGroup` (limit 5).
- The titlebar shows a "live" indicator with countdown to the next tick.
- Manual refresh: per-repo button + a global "Refresh all" button.
- Two user-toggleable behaviors (Settings → Advanced):
  - "Refresh immediately when Aerie regains focus" — default on.
  - "Pause polling when Aerie loses focus" — default on.
- App closed = zero activity. No background daemon.

### F6. Multi-account GitHub auth

- On launch, run `gh auth status` and parse the output to learn:
  - Which hostnames are logged in (`github.com`, potentially GHE).
  - Which logins exist under each hostname.
  - The associated token (`gh auth token --hostname <h> --user <u>`).
- Tokens kept in-memory only; never persisted to the app's DB.
- When the user adds a repo, they pick a **primary account** for it.
- For any API call: try the primary account first. On `401`/`403`, automatically
  fall back to other accounts (one by one). If none succeed, mark the repo with
  a "no access" badge.
- If `gh` is not installed or has no logged-in accounts: app shows a blocking
  setup screen prompting the user to run `gh auth login`.

### F7. Settings

Separate window with a sidebar of five sections (design-confirmed):

- **Accounts** — list `gh` identities (login, host, scopes, last used,
  repo count); mark primary; surface a banner showing `gh` CLI version;
  add-account section shows the `gh auth login` command with Copy button
  (sign-in is done in a terminal, not in Aerie).
- **Repositories** — manage configured repos (rename, hide, reorder via
  drag handle, change primary account, remove). Top bar has `Refresh all`
  and `+ Add repository`. Add Repository is a sheet (see §9).
- **MCP** — server status (endpoint, bearer token with reveal/copy,
  discovery file with reveal), Claude Code integration toggle, Recent
  activity table (last N MCP calls, both reads and writes), `Rotate token
  now` action. Sidebar shows a green dot when the server is running.
- **Advanced** — polling cadence (two sliders: Active / Background),
  per-account rate-limit cards, two behavior toggles
  (refresh-on-focus / pause-on-blur), `Reset to defaults`.
- **About** — version, license, build SHA, link to source repo. Minimal.

## Architecture

### Layer overview

```
SwiftUI Views                        MCP HTTP Server (§10)
    │  @Observable / @Published          │  JSON-RPC over HTTP
ViewModels  (one per screen)         MCPRouter
    │  async/await calls                 │
    └────────────┬──────────────────┬────┘
                 ▼                  ▼
Services  (protocol-defined for testing)
    ├── GitHubAPI       (URLSession + Codable, GraphQL + REST)
    ├── GitService      (SwiftGitX wrapper, actor-isolated)
    ├── AuthService     (gh CLI subprocess)
    └── PollingScheduler (actor, owns background Task)
                 │
Persistence  (GRDB / SQLite)
```

Both the SwiftUI view models and the MCP router talk to the **same**
service layer. Write actions go through the same actor-serialized path,
so GUI and MCP cannot race each other.

### Design principles

- **MVVM**. Views never touch services directly.
- **Services protocol-first**. Each service has a `protocol` exposing only the
  async API surface; concrete impls are injected. Mock impls used in tests.
- **Single source of truth**. UI always renders from the local cache (SQLite).
  Live fetches update the cache; the cache notifies subscribers.
- **Actor isolation** for shared mutable state: `PollingScheduler`, `GitService`
  (per-repo working directory access).
- **Cancellable IO**. All long-running tasks are `Task`s; navigating away
  cancels in-flight fetches for the old view.

## Data model

```swift
struct Repository {
    let id: UUID
    var name: String              // display name; defaults to repo
    var localPath: URL            // file URL to working tree
    var githubOwner: String
    var githubRepo: String
    var defaultBranch: String     // "main" / "master" / etc. (see F2)
    var primaryAccountId: UUID
    var sortOrder: Int
    var hidden: Bool
}

struct GitHubAccount {
    let id: UUID
    let login: String             // e.g. "carlos-li"
    let host: String              // "github.com" or GHE host
}

struct LocalGitStatus {
    let repoId: UUID
    let currentBranch: String
    let isDirty: Bool
    let dirtyFileCount: Int       // for the reset dialog's "N modified, M untracked"
    let aheadOfDefault: Int       // current branch vs origin/<defaultBranch>
    let behindOfDefault: Int
    let unpushedCommits: Int      // current branch vs its upstream
    let originDefaultSha: String  // resolved sha of origin/<defaultBranch> (short)
    let fetchedAt: Date
}

struct PullRequest {
    let id: UUID
    let repoId: UUID
    let number: Int
    let title: String
    let authorLogin: String
    let sourceBranch: String      // PR's head.ref — used to resolve PRLocalState
    let isMine: Bool              // author matches any configured account login
    let state: PRState            // open / closed / merged
    let ciState: CIState          // success / failure / pending / none
    let reviewState: ReviewState  // approved / changesRequested / reviewRequired
    let labels: [String]
    let htmlUrl: URL
    let updatedAt: Date
}

/// The local checkout state of a specific PR's source branch — computed
/// per (Repository, PullRequest.head.ref) at fetch time, cached alongside
/// the PR. Lets the PRs view render combined GitHub + local status.
struct PRLocalState {
    let prId: UUID
    let sourceBranch: String       // e.g. "feat/virtual-clock"
    let localBranchExists: Bool    // does this branch exist locally?
    let isCurrentBranch: Bool      // is it the currently checked-out branch?
    // Following are only meaningful when isCurrentBranch == true.
    // When the branch exists locally but isn't checked out, only existence is known.
    let dirty: Bool?
    let ahead: Int?
    let behind: Int?
    let unpushed: Int?
}
```

## Persistence schema

DB location: `~/Library/Application Support/Aerie/db.sqlite`

```sql
CREATE TABLE accounts (
    id TEXT PRIMARY KEY,
    login TEXT NOT NULL,
    host TEXT NOT NULL,
    UNIQUE(login, host)
);

CREATE TABLE repos (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    local_path TEXT NOT NULL,
    owner TEXT NOT NULL,
    repo TEXT NOT NULL,
    default_branch TEXT NOT NULL DEFAULT 'main',
    account_id TEXT NOT NULL REFERENCES accounts(id),
    sort_order INTEGER NOT NULL DEFAULT 0,
    hidden INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE pr_cache (
    repo_id TEXT NOT NULL REFERENCES repos(id),
    number INTEGER NOT NULL,
    payload_json TEXT NOT NULL,     -- serialized PullRequest
    fetched_at REAL NOT NULL,
    PRIMARY KEY (repo_id, number)
);

CREATE TABLE pr_local_state_cache (
    pr_id TEXT PRIMARY KEY,         -- matches pr_cache.payload's id
    repo_id TEXT NOT NULL REFERENCES repos(id),
    payload_json TEXT NOT NULL,     -- serialized PRLocalState
    fetched_at REAL NOT NULL
);

CREATE TABLE git_status_cache (
    repo_id TEXT PRIMARY KEY REFERENCES repos(id),
    payload_json TEXT NOT NULL,
    fetched_at REAL NOT NULL
);

CREATE TABLE mcp_activity (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    at REAL NOT NULL,               -- epoch seconds
    agent_id TEXT,                  -- nullable; "unknown" if header missing
    tool TEXT NOT NULL,             -- e.g. "aerie_merge_pr"
    target TEXT,                    -- e.g. "cems-ui · #1234", nullable for global tools
    is_write INTEGER NOT NULL DEFAULT 0,
    ok INTEGER NOT NULL,            -- 1 success, 0 failure
    error_message TEXT,             -- nullable; populated on failure
    request_json TEXT NOT NULL,     -- raw JSON-RPC request (for View request)
    response_json TEXT NOT NULL     -- raw JSON-RPC response
);

CREATE INDEX idx_mcp_activity_at ON mcp_activity(at DESC);

CREATE TABLE settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
```

The settings table holds user preferences as JSON-encoded values keyed
by name — e.g. `polling.active_seconds`, `polling.background_seconds`,
`behavior.refresh_on_focus`, `behavior.pause_on_blur`,
`mcp.auto_register_claude_code`, `mcp.consent_decision` (one of
`granted` / `declined` / `unset`).

The `mcp_activity` table is bounded — pruned to the last 1000 rows on
every insert past that threshold, so it doesn't grow unbounded.

Note on `payload_json`: storing each entity as JSON makes schema migration
cheap (the app code owns the shape) at the cost of not being able to query
sub-fields with SQL. For this app's scale (~50 repos × ~50 entities each),
the trade-off favors flexibility.

## Polling specifics

`PollingScheduler` is an actor that owns a single recurring `Task` plus
an `activeRepoId: UUID?`:

```
every heartbeatInterval (default 30s):
    let active = self.activeRepoId
    let dueRepos = repos where:
        (id == active && now - fetched_at >= activeCadence)   // 30s default
        OR
        (id != active && now - fetched_at >= backgroundCadence) // 5min default
    refreshConcurrently(dueRepos, limit: 5)
```

Concurrency limit (5) keeps GitHub rate limit usage bounded — at the worst
case (50 repos all overdue at the same minute), the scheduler issues 50
requests across 10 batches, ~5 per second. GitHub's quota is 5000/hr per
authenticated token, so headroom is ample.

When any account's response header reports `≥ 4500/hr` used, the scheduler
doubles both cadences (e.g. 30 s → 60 s, 5 min → 10 min) until the next
hour rolls over and surfaces a yellow rate-limit badge in the UI.

Per refresh of one repo, two parallel lanes execute (scoped to that repo's
primary account, with fallback):
1. `local_git_status` — local only; SwiftGitX reads `.git/`. Never fails
   the lane; the repo's last status is preserved on read error.
2. `prs + per-PR local checkout state` — one GraphQL query gathers all
   open PRs for the repo; for each PR, `PRLocalState` is computed locally
   via SwiftGitX (does the source branch exist? is it current? if so,
   its dirty / ahead / behind / unpushed counts).

Both lanes are awaited together; the repo's `fetched_at` is updated only
when both complete (or each failure is recorded with reason and surfaced
as a per-repo badge).

## Error handling

| Condition | UI surface | Recovery |
|---|---|---|
| `gh` not installed (`gh: command not found` or `which gh` empty) | Full-window first-run setup, state `no-gh`: `brew install gh` block, Copy button, "I've installed it — re-check" + "Quit Aerie" | Auto-recheck every 5 s for state change; manual recheck via button |
| `gh` installed, no accounts logged in (`gh auth status` reports none) | Full-window first-run setup, state `no-auth`: `gh auth login --hostname github.com --git-protocol ssh` block + GHE hint | Same 5 s auto-recheck pattern |
| Per-repo `401`/`403` after all account fallbacks | Repo row shows "no access" icon | Tooltip: how to invite the account / change primary account |
| GitHub `5xx` / network error | Banner: "Offline — showing cached data" | Auto-retry next polling tick |
| GitHub rate-limit nearing exhaustion | Top bar badge with reset time | Auto-throttle (see polling) |
| Local repo path missing | Repo row shows red badge | Action button: "Locate folder…" or "Remove repo" |
| `fetch origin` failure during hard reset | Toast with full git error, log entry | No state change — operation aborted |
| `merge PR` failure (GitHub returns 4xx with reason) | Toast with GitHub's message | No retry; user fixes upstream |
| SwiftGitX `SwiftGitXError` / unexpected libgit2 error | Caught at the GitService boundary, toast + log; service marked degraded | App keeps running |

Destructive actions (hard reset, merge) always go through an explicit
confirmation dialog showing the target.

## Concurrency rules

- All IO functions are `async`.
- All long-running tasks return `Task`s the VM stores; navigating away
  calls `task.cancel()` on outgoing tasks.
- `GitService` is an actor (one operation at a time per working directory
  prevents libgit2 race conditions).
- `PollingScheduler` is an actor (single owner of the tick task).
- DB writes go through a single GRDB `DatabaseQueue` (serialized internally).

## Testing strategy

- **ViewModel tests**: each VM tested with mock services injected; covers
  state transitions (loading → error, loading → success, refresh, cancel).
- **GitHubAPI tests**: `URLProtocol` stubs return canned responses (success,
  401, 403, 404, 5xx, rate-limit headers).
- **GitService integration tests**: scratch directory under
  `TemporaryDirectory()`, real `git init` + commits, asserts on
  `readStatus`/`hardResetToOriginMain` behavior.
- **AuthService tests**: subprocess-runner is protocol'd; mock supplies
  canned `gh auth status` output (single account, multi-account, none).
- **PollingScheduler tests**: scheduler exposes a virtual-clock injection
  point; tests step time and assert which repos got refreshed.
- **Snapshot tests** for SwiftUI views (now that Claude Design has landed
  the screens): one snapshot per view with a deterministic mock data
  fixture, run on every PR via `swift-snapshot-testing`.

## 9. UI Handoff Notes

This section is the captured-from-design contract — what the UI must
look like and behave like, derived from the Claude Design pass.

### Visual system

- **Window chrome**: macOS-style with traffic-light buttons. Main window
  1240 × 880; Settings window 1040 × 760; First-run uses the main window
  size.
- **Material**: glass with `backdrop-filter: blur(40px) saturate(160%)`;
  inner cards `glass-2` background; dialogs `blur(48px) saturate(180%)`.
- **Backdrop behind glass**: dark base (`#0b0b10` / `#131218`) with two
  soft radial gradients (warm amber upper-right, cool blue lower-left)
  plus a faint SVG noise overlay to give the glass something to refract.
- **Accent color**: sodium amber (`oklch(0.86 0.140 78)`) — the **only**
  color used to signal "actionable" (merge-ready, primary buttons, brand
  mark). Status colors are desaturated (`ok` green, `warn` yellow, `err`
  red) and used sparingly.
- **Text on glass**: white with stepped opacity (96 / 72 / 50 / 32 %)
  rather than gray — reads cleaner on the refracting backdrop.
- **Typography**: `Inter` (sans, weights 400/500), `JetBrains Mono` (mono,
  weights 400/500). Display sizes use weight 500 with negative letter
  spacing.

### Two top-level views

- Segmented toggle in the titlebar (center), keyboard `⌘1` / `⌘2`:
  - **Pull Requests** — flat list across all configured repos. Each card
    shows: repo · #num · author · `yours` pill when applicable, big title,
    CI / Review chips, "ready to ship" eyebrow when both pass, then a
    divider, then a `local` strip with: branch tag, `dirty / clean`,
    `↑ahead ↓behind ⤒unpushed` (`⤒` shown in amber when > 0). Right:
    `Merge` (amber when mergeable, dimmed otherwise) + `Open ↗`.
  - **Repositories** — flat card list. Each card shows: name + `owner/name`
    in mono, branch tag, `dirty / clean`, ahead/behind/unpushed. Right:
    `Open ↗` + `Hard reset` (amber tone except when already at clean origin).
- Titlebar right: live polling indicator (`● live · 14s`) + small spinner-style
  icon. No per-repo detail screen — everything fits on the card.

### Settings (separate window)

Sidebar items: **Accounts** · **Repositories** · **MCP** (green dot when
running) · **Advanced** · **About** (footer).

- **Accounts**:
  - `gh` CLI version banner at top (`gh CLI 2.62.0 is authenticated to N hosts`,
    "tokens kept in memory only" footnote).
  - Account cards: avatar (colored radial gradient), `login @ host`,
    `primary` pill, `signed in · N repos · last call X ago · scopes: …`,
    actions: `Make primary` (non-primary only) + `Sign out…`.
  - "Add another account" section: shows the `gh auth login` command with
    Copy. Sign-in is performed in the user's terminal.
- **Repositories**:
  - All repos in one big glass card with row separators.
  - Each row: drag grip · name + local path (mono) · `owner/repo` + branch
    tag with status dot · account avatar+login · `×` remove.
  - Header right: `↻ Refresh all` + amber `+ Add repository`.
  - `+ Add repository` opens a sheet (see below).
- **MCP**:
  - Status row: `● Server running` + `uptime / pid`. Top-right: `Rotate
    token now`.
  - Server card: rows for `endpoint` (mono URL + Copy), `bearer token`
    (masked `aer_••••…` + eye reveal + Copy), `discovery file` (path +
    `Reveal` opens Finder).
  - Claude Code integration card: `Auto-register in ~/.claude/.mcp.json`
    toggle + status pill `aerie entry present · token in sync · last
    written X ago`.
  - Recent activity card: table columns `TIME · AGENT · TOOL · TARGET ·
    RESULT` (`✓` / `✕`). Records **every** MCP call (reads and writes).
    Footer link `View all…` opens a complete log view.
- **Advanced**:
  - Polling cadence card: two slider rows
    - `Active repo` — value `30s`, range `10s — 5m`.
    - `Background repos` — value `5 min`, range `1 min — 30 min`.
    - Warning chip: "Lower values use more of your GitHub API quota
      (5,000 / hr)."
  - Rate limit card: one column per account, each shows the per-account
    remaining quota (e.g. `4823 / 5000`), a small color-graded bar
    (green / amber / red by depletion), and `resets in N min`.
  - Behavior card: two toggle rows for the F5 focus / blur policies.
  - `Reset to defaults` link in the header.
- **About**: minimal — version, license, build SHA, source link.

### Add-repo sheet

Slides down from the Settings titlebar (no separate window). Two states:

- **Empty** — dashed drop zone with `Drag a folder here / or / Browse…`,
  plus a "Recently seen" list of nearby `.git` directories the user might
  want to add (Aerie does not auto-add; it surfaces candidates only).
- **Detected** — after a folder is chosen, shows a card with the folder
  name + absolute path + `Change…`, then a key/value list:
  `github` (from origin URL), `default branch` (with the detection source,
  e.g. `refs/remotes/origin/HEAD`), `current branch` (+ dirty indicator
  if applicable), `account` (a dropdown of known `gh` accounts, inferred
  from origin host).
- Footer: `polling starts within 30s` hint + `Cancel` + amber `Add to fleet`.

### Confirmation dialogs

All use the same shell: dim + blur the parent view, center a glass card.
Each dialog opens with a small accent-tinted icon, title, subtitle, and a
key/value list of what's about to happen.

- **Reset** (danger / red ring) — shows repository, current branch, dirty
  file count, unpushed commit count, and target (`origin/<defaultBranch>
  @ <sha>`). Primary button red.
- **Merge** (amber ring) — shows PR card preview (`+/- lines · N files`,
  checks passed, approvers), then a key/value list of `method` (squash),
  `commit subj` (auto-generated), `account`. Primary button amber.
- **Sign out** (danger) — lists the affected repos that will go into
  no-access state. Footnote: "Tokens were never persisted — gh CLI keeps them".
- **Remove repo** (neutral) — lists display name, path, github, and
  "will delete: nothing — files are untouched".

### First-run gh setup

Full-window takeover (no main views behind), warm radial gradients in
the backdrop, single primary action.

- **State A — `gh` not installed**: title `Aerie needs the GitHub CLI`,
  body explaining gh's role, `$ brew install gh` command line with Copy,
  hint about cli.github.com if no Homebrew, `I've installed it — re-check`
  (amber) + `Quit Aerie` (ghost) + `checking every 5s` indicator (5 s
  auto-recheck polling for state change).
- **State B — `gh` installed, no auth**: title `Sign in to GitHub through gh`,
  command `gh auth login --hostname github.com --git-protocol ssh` with
  Copy, info card about GitHub Enterprise (`--hostname your-ghe-host.com`
  for repeats), same action row.

### MCP consent dialog

Appears once on first launch after `gh` is authenticated and at least one
repo is configured. If declined, never appears again; re-enable in Settings
→ MCP.

- Hero: two pill icons (red C for Claude + amber Aerie orb).
- Title: `Let Claude Code talk to Aerie?`
- Body explains the value (shared cache, queued merges, confirmed resets).
- JSON diff preview block: shows the `aerie` entry that will be added in
  green `+` lines, with a header `~/.claude/.mcp.json · diff` and a Copy
  button.
- Three bulleted footnotes (token rotates per launch / Aerie only touches
  its own entry / can revoke later in Settings).
- Footer: subtle text "You can change this later in Settings" + `Not now`
  (ghost) + `Allow` (amber).

### MCP activity toast

Bottom-right stack of cards (max 3 visible at once). Each card:
- Top row: status icon (green ✓ / red ✕) + `mcp · <tool>` (mono, "mcp"
  in amber) + relative time.
- Target line (e.g. `cems-ui · #1234`).
- Bottom row: `by <agent-id>` (mono) + `success` / `failed` (color-coded).
- If failed: error block with mono red text, monospaced for SHA / paths.
- Footer: `View request` button (mono, ghost) — opens a modal with the
  raw MCP request + response JSON.
- Auto-dismiss after 6 s; mouse hover pauses the countdown.

### Available actions the UI must expose

- Hard reset to `origin/<defaultBranch>` (one repo at a time, GUI confirms)
- Merge PR (one PR at a time, GUI confirms)
- Open in browser: repo home, Pull Requests tab, Code tab, individual PR
- Manual refresh: global, and per-repo
- Add repo / remove repo / hide repo / rename repo / change repo's primary account / reorder repos
- Sign out an account; mark another as primary
- MCP server: rotate token, toggle Claude Code auto-register, reveal discovery file
- Polling: edit active / background cadences, reset to defaults
- Quit Aerie from the first-run blocking screen

### State surfaces

- Per-repo: dirty / clean, ahead / behind / unpushed counts, open PR
  count, GitHub access status (ok / no-access / offline), data freshness,
  primary account (avatar dot).
- Per-PR: CI status, review status, label set, `yours` flag, local
  checkout state of source branch.
- Global: live-polling heartbeat with countdown, rate-limit status,
  offline banner, in-flight refresh, MCP server status (running / off,
  recent agent activity count).

### Constraints to preserve

- Polling cadence (F5) — UI reflects refresh activity but never blocks
  on individual fetches.
- "Open in browser is the only jump" — no editor / terminal launch.
- Confirmation required for destructive ops **in the GUI path** (MCP
  path is confirmation-free; agent actions surface as toasts).
- No filter / search / sort UI for now.

## 10. MCP server (agent interface)

Aerie exposes its cached data and write actions over MCP so that other Claude
Code sessions (and any MCP client) can read repo state and trigger Aerie's
actions programmatically. This removes the need for each agent to maintain
its own GitHub auth and polling — agents share Aerie's cache and central
account fallback.

### Lifecycle

- The MCP server runs **in-process** as a `Task` inside the SwiftUI app.
- Aerie launch: bind an HTTP listener to `127.0.0.1:<random_port>`, write
  the discovery file.
- Aerie quit: stop the listener, delete the discovery file.
- GUI closed = MCP unavailable. Aligns with F5 ("app closed = no activity").

### Transport

- HTTP streamable (the MCP standard transport for non-stdio servers).
- Bound to `127.0.0.1` only. Never listens on a routable interface.

### Discovery file

Path: `~/Library/Application Support/Aerie/mcp.json` (permissions `0600`).

```json
{
  "endpoint": "http://127.0.0.1:47823/mcp",
  "token": "<random 64-char hex>",
  "pid": 12345,
  "started_at": "2026-05-28T14:00:00Z"
}
```

A fresh `token` is generated every launch. Clients connect with
`Authorization: Bearer <token>`.

### Claude Code integration

On **first launch**, Aerie offers to register itself in
`~/.claude/.mcp.json` so Claude Code can discover it without manual setup:

```json
{
  "mcpServers": {
    "aerie": {
      "type": "http",
      "url": "http://127.0.0.1:47823/mcp",
      "headers": { "Authorization": "Bearer <token>" }
    }
  }
}
```

- User accepts → Aerie writes / updates the `aerie` entry on each launch
  and on every token rotation (so Claude Code's view of the token stays
  in sync).
- User declines → recorded in `settings` (`mcp.consent_decision = declined`);
  Aerie does not prompt again. Re-enable from Settings → MCP via the
  "Auto-register in ~/.claude/.mcp.json" toggle.
- The Settings toggle is the canonical control after first run:
  - Toggle off → Aerie removes its own `aerie` entry from
    `~/.claude/.mcp.json` and stops writing it. Existing Claude Code
    sessions will fail until the user toggles back on or restarts.
  - Toggle on → Aerie writes the entry and keeps it in sync.
- Aerie never touches other entries in `~/.claude/.mcp.json`. Parsing is
  permissive (preserves comments / formatting where possible).

### Token rotation

- A fresh token is generated on every launch (default).
- The Settings → MCP page exposes a **Rotate token now** button which:
  1. Generates a new token in memory.
  2. Rewrites the discovery file with the new token (atomic write).
  3. If Claude Code integration is on, rewrites `~/.claude/.mcp.json`'s
     `aerie` entry with the new token.
  4. From that moment, any in-flight or future request bearing the old
     token gets `-32001 Invalid token`.

### Tool catalog

All tools accept a `repo` parameter that resolves against any of:
- Aerie's configured `name` (display name)
- `owner/repo` shorthand (e.g. `nextDriveIoE/cems-ui`)
- The repo's local path

#### Read tools (return cache; include `fetched_at`)

| Tool | Params | Returns |
|---|---|---|
| `aerie_list_repos` | — | `[{ name, owner, repo, hidden, defaultBranch, accountLogin }]` |
| `aerie_get_local_status` | `repo` | `LocalGitStatus` + `fetched_at` |
| `aerie_list_prs` | `repo?`, `state?` (default `open`) | `[PullRequest]` — omit `repo` to get PRs across all configured repos |
| `aerie_get_pr` | `repo`, `number` | `PullRequest` |
| `aerie_get_pr_local_state` | `repo`, `number` | `PRLocalState` (is the PR's source branch checked out, and if so its dirty/ahead/behind/unpushed counts) |

Read tools never trigger an API fetch. They serve whatever the GUI is
currently showing. This matches the user's explicit choice: "return cache
directly, fastest."

#### Write tools (execute immediately; GUI surfaces a toast)

| Tool | Params | Behavior |
|---|---|---|
| `aerie_merge_pr` | `repo`, `number`, `method?` (default `squash`) | Calls GitHub merge API using the repo's primary account (with the same fallback rules as the GUI). Returns the GitHub merge result payload. |
| `aerie_hard_reset_to_default` | `repo` | Runs the same `fetch → checkout default → reset --hard` sequence as the GUI's hard-reset action. Returns a summary including how many uncommitted changes were discarded (if any), so the calling agent cannot silently lose work. |

Write tools do **not** prompt the user for confirmation — this is an
explicit design choice. Instead, every write action raises a GUI toast
that includes the calling agent's identifier and a button to inspect
the raw MCP request JSON for audit.

### Agent identification

MCP requests may include an optional `X-Aerie-Agent-Id` header. Claude Code
sessions are expected to pass their session ID. When the header is absent,
toasts and logs show `unknown agent`.

### Concurrency / write conflict

- Write actions per repo are **serialized** via the same actor that owns
  the GUI's git working directory.
- A second write request on the same repo waits for the first to complete.
- While a write is in flight, the GUI's equivalent button is disabled
  to prevent dual-source races.

### GUI surfaces for MCP activity

Two complementary surfaces:

- **Toast** (transient, write-only): every successful or failed write
  call raises a glass toast in the bottom-right of the active window.
  Stacks up to 3; auto-dismisses after ~6 s (paused on hover). Each
  toast shows status icon, `mcp · <tool>`, target, agent id, success/
  failed badge, and a `View request` action that opens a modal with the
  raw JSON-RPC request + response. See §9 → MCP activity toast for the
  visual contract.
- **Activity log** (persistent, all calls): every MCP call — including
  read tools — is recorded in `mcp_activity` (see Persistence schema)
  and surfaced in Settings → MCP → Recent activity. The activity card
  shows the last N rows (e.g. 6) with columns `TIME · AGENT · TOOL ·
  TARGET · RESULT`; a `View all…` link opens a complete history view.

Rationale: writes need user awareness even if not interrupting flow
(toast), but the audit trail must include reads so the user can see who
called what and when, even for non-write activity (full activity log).

### Errors (JSON-RPC error codes)

| Condition | Code | Message |
|---|---|---|
| `repo` not in Aerie's configured list | `-32602` (invalid params) | `Repo '<id>' not configured in Aerie` |
| Missing or wrong bearer token | `-32001` | `Invalid token; reload from mcp.json` |
| GitHub 401/403 after all account fallbacks | `-32002` | `No account has access to this repo` |
| `merge_pr` rejected by GitHub (not mergeable, conflicts, etc.) | `-32003` | GitHub's original error message |
| `hard_reset` aborted due to working tree state | `-32004` | `Working tree conflict during hard reset` |
| MCP server overloaded (too many concurrent writes) | `-32099` | `Rate limited; retry in N seconds` |

### Security

- Listener bound to `127.0.0.1` only.
- Per-launch token (random 64-char hex) prevents replay across restarts.
- Discovery file mode `0600`; lives in the user's `Application Support` dir.
- All write actions land in the user's GUI history (toasts + activity list)
  — there is no silent write.
- Aerie writes to `~/.claude/.mcp.json` only after explicit consent and
  only modifies its own `aerie` entry.

### Testing

- **Transport tests**: spin up the in-process server, hit it with a
  hand-rolled HTTP client, assert auth + JSON-RPC framing.
- **Tool tests**: each tool method tested with mocked services
  (the same mocks the ViewModel tests use).
- **Concurrency tests**: fire N concurrent write requests at one repo,
  assert serialized execution + correct result ordering.
- **Discovery file lifecycle**: assert file is created on launch,
  deleted on quit, has `0600` mode.
- **Claude Code config writer**: tested with a temp `.mcp.json` fixture;
  assert other entries are preserved.

## Open questions

- App icon — the design pass produced an icon showcase (radar rings +
  amber orb in a dark squircle). Status: art-direction approved; the
  actual `.icns` asset generation is a build-pipeline task. Pending
  during implementation.
- Should the MCP server also expose `aerie_refresh_repo(repo)` to let an
  agent force a fresh fetch when cache is stale? Currently out of scope
  (cache-only by design). — Revisit after first usage.
- Should write tools support a `dry_run` parameter (return what *would*
  happen without doing it)? — Defer until requested.
- Per-account rate-limit display (Advanced) implies Aerie tracks the
  most recent `x-ratelimit-remaining` / `x-ratelimit-reset` header from
  each account. Stored as an in-memory map keyed by account id (no need
  to persist).
- The MCP recent-activity card surfaces calls from "this Aerie session"
  primarily; the persisted `mcp_activity` table makes calls survive
  restart. Confirmed both should be available.
