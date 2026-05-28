# Aerie — Design Doc

> macOS dashboard for overseeing many git repos at once — local git state, PRs, quick actions.

**Project**: Aerie
**Date**: 2026-05-28
**Author**: carlos
**Status**: draft

> **Design status**: Claude Design has produced the **PRs view**, **Repos view**,
> **Settings (Accounts + Repositories)**, **Add-repo sheet**, and the four
> primary **confirmation dialogs** (reset, merge, sign-out, remove). Five
> screens are still being designed in a follow-up pass — see [§9 UI Handoff
> Notes](#9-ui-handoff-notes) for the contract and what is still open.

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
| Local git | `SwiftGit2` (libgit2 bindings) | Read state + run hard reset |
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
| **Hard reset to default branch** | one repo | Sequence: `git fetch origin` → `git checkout <defaultBranch>` → `git reset --hard origin/<defaultBranch>`. If working tree is dirty, the confirmation dialog explicitly warns "this will discard N uncommitted changes". Aborts (does not partially apply) on any error. Implemented via SwiftGit2. |
| **Merge PR** | one PR | GitHub REST `PUT /repos/{owner}/{repo}/pulls/{number}/merge` using the repo's primary account token. Assumes PR is mergeable; surfaces GitHub's error if not. Merge method: `squash` (matches the user's standard workflow). Confirmation dialog required. |

| **Open in browser** | repo / PR | `NSWorkspace.shared.open(url)` to the entity's GitHub HTML URL. Repo-level shortcuts: open the repo page, the Pull Requests tab, the Code tab. (The Issues tab is also a valid jump target even though Aerie itself does not list issues.) |

**Confirmation note**: the confirmation dialog applies only to the **GUI**
path. The MCP path (§10) invokes the same underlying service without a
dialog, by design — agents are expected to execute autonomously and
each MCP write surfaces a GUI toast for audit instead.

### F5. Polling

- App fetches all data on launch.
- Single global cadence: every configured repo is refreshed every **5 minutes**.
  Cadence is user-configurable (1–30 min) in Settings. Default chosen so that
  50 repos × 12 fetches/hour = 600 GitHub API calls/hour — well under the
  5000/hour quota per token, with headroom for multi-account fallback.
- A heartbeat tick (default every 30 s) drives the scheduler; on each tick
  the scheduler computes which repos are due and refreshes them in a
  bounded-concurrency `TaskGroup` (limit 5).
- The titlebar shows a "live" indicator with countdown to the next tick.
- Manual refresh: per-repo button + a global "refresh all" button.
- When app loses foreground (`NSApplication.didResignActive`): pause the
  scheduler entirely.
- When app regains foreground (`didBecomeActive`): one-shot refresh of every
  repo, then resume the normal cadence.
- App closed = zero activity. No background daemon.

The active-vs-background distinction from earlier drafts is dropped — without
a per-repo detail view, there is no "currently focused" repo, and a single
cadence keeps the scheduler easier to reason about.

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

- Manage repo list (add / remove / hide / reorder / rename / change primary account).
- Polling interval overrides (advanced; default values exposed but rarely touched).
- Show `gh` accounts in use (read-only; managed via `gh` CLI).

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
    ├── GitService      (SwiftGit2 wrapper, actor-isolated)
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
    let aheadOfDefault: Int       // current branch vs origin/<defaultBranch>
    let behindOfDefault: Int
    let unpushedCommits: Int      // current branch vs its upstream
    let fetchedAt: Date
}

struct PullRequest {
    let id: UUID
    let repoId: UUID
    let number: Int
    let title: String
    let authorLogin: String
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

CREATE TABLE settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
```

Note on `payload_json`: storing each entity as JSON makes schema migration
cheap (the app code owns the shape) at the cost of not being able to query
sub-fields with SQL. For this app's scale (~50 repos × ~50 entities each),
the trade-off favors flexibility.

## Polling specifics

`PollingScheduler` is an actor that owns a single recurring `Task`:

```
every <heartbeat>s (default 30):
    let dueRepos = repos where now - fetched_at >= <cadence>   // default 5 min
    refreshConcurrently(dueRepos, limit: 5)
```

Concurrency limit (5) keeps GitHub rate limit usage bounded — at the worst
case (50 repos all overdue at the same minute), the scheduler issues 50
requests across 10 batches, ~5 per second. GitHub's quota is 5000/hr per
authenticated token, so headroom is ample.

When the response header reports `≥ 4500/hr` used on any account, the
scheduler doubles the cadence (e.g. 5 min → 10 min) until the next hour
rolls over and surfaces a yellow rate-limit badge in the UI.

Per refresh of one repo, three independent fetches happen in parallel
(scoped to that repo's primary account, with fallback):
1. `local_git_status` (no network — SwiftGit2 reads `.git/`)
2. `prs + their_local_state` (one GraphQL query covers PRs;
   `PRLocalState` per PR comes from SwiftGit2)
3. (no other network calls — issues and commit history were dropped from v1)

The three lanes are awaited together; the repo's `fetched_at` is updated
only when all three complete (or any failure is recorded with reason).

## Error handling

| Condition | UI surface | Recovery |
|---|---|---|
| `gh` not installed | Blocking setup screen | Link to install instructions |
| `gh` has no accounts logged in | Blocking setup screen | "Copy command" button: `gh auth login` |
| Per-repo `401`/`403` after all account fallbacks | Repo row shows "no access" icon | Tooltip: how to invite the account / change primary account |
| GitHub `5xx` / network error | Banner: "Offline — showing cached data" | Auto-retry next polling tick |
| GitHub rate-limit nearing exhaustion | Top bar badge with reset time | Auto-throttle (see polling) |
| Local repo path missing | Repo row shows red badge | Action button: "Locate folder…" or "Remove repo" |
| `fetch origin` failure during hard reset | Toast with full git error, log entry | No state change — operation aborted |
| `merge PR` failure (GitHub returns 4xx with reason) | Toast with GitHub's message | No retry; user fixes upstream |
| SwiftGit2 panic / unexpected error | Caught, toast + log; service marked degraded | App keeps running |

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
- **Snapshot tests** for SwiftUI views: deferred until Claude Design lands
  the screens.

## 9. UI Handoff Notes

This section is a contract for the follow-up UI design pass.

### Decided in design pass 1

- Two top-level views: **Pull Requests** and **Repos**, switched by a
  segmented control in the titlebar (also `⌘1` / `⌘2`).
- No per-repo detail screen — everything fits on the card.
- Main window: 1240 × 880. Settings window: 1040 × 760.
- Aesthetic: dark glass material with sodium amber as the only accent color.
- Typography: Inter (sans), JetBrains Mono (mono).
- Settings is a separate window with its own sidebar.
- Add-repo is a sheet that slides from the settings titlebar, with
  drag-and-drop, Browse button, and "Recently seen" suggestions
  (suggestions only — Aerie still does not auto-add repos).
- Confirmation dialogs use a dimmed-parent glass card with a key/value
  list of what's about to happen; danger ops use a red accent ring.
- Titlebar shows a live polling heartbeat (`live · 14s`).

### Still open — pending design pass 2

These are the five screens going back to Claude Design (see the user's
handoff list):

- MCP integration consent dialog (first-run prompt).
- MCP activity toast (raised on every agent write).
- Settings → MCP section (server status, Claude Code integration toggle,
  recent activity table).
- First-run `gh` setup screen (gh missing vs. signed-out states).
- Settings → Advanced (polling cadence slider + rate-limit status).

### What the UI must support

Screens / views that need to exist:

1. **PRs view** — flat list across all configured repos of every open PR;
   each row carries both GitHub status (CI, review, labels) and the local
   checkout state of the PR's source branch (F2, F3).
2. **Repos view** — flat list of cards, one per configured repo, showing
   current branch + dirty / ahead / behind / unpushed counts (F1, F2).
   No separate detail screen — everything fits on the card.
3. **Add-repo flow** — folder picker (or recently-seen suggestions) + the
   detected origin/owner/repo/default-branch fields + primary account
   selection (F1, F6).
4. **Settings** — sidebar with Accounts (manage gh accounts, mark primary),
   Repositories (rename, hide, reorder, change account, remove), MCP
   (server status, Claude Code integration toggle, recent activity), and
   Advanced (polling cadence) (F7, §10).
5. **First-run / `gh` setup screen** — blocking screen when `gh` is missing
   or unauthenticated (F6).
6. **Confirmation dialogs** — for hard reset, merge PR, sign-out account,
   remove repo (F4).
7. **MCP integration consent dialog** — one-time first-run prompt asking
   whether Aerie may add itself to `~/.claude/.mcp.json` (§10).
8. **MCP activity toast** — non-blocking surface shown when an agent calls
   a write tool; includes agent ID, target repo/PR, result, and a "view
   request" affordance (§10).

### Available actions the UI must expose

- Hard reset to `origin/<defaultBranch>` (one repo at a time)
- Merge PR (one PR at a time)
- Open in browser: repo home, Pull Requests tab, Code tab, individual PR
- Manual refresh: global, and per-repo
- Add repo / remove repo / hide repo / rename repo / change repo's primary account
- Reorder repos

### Data the UI has access to

Anything in the [Data model](#data-model) section, plus per-entity
`fetched_at` timestamps so the UI can show "freshness" if desired.

### State surfaces the UI may want to indicate

- Per-repo: dirty/clean, ahead/behind counts, open PR count,
  GitHub access status (ok / no-access / offline), data freshness.
- Per-PR: CI status, review status, label set, local checkout state of
  the PR's source branch (not checked out / checked out & clean / checked
  out & dirty / checked out with ahead/behind/unpushed).
- Global: rate-limit warning, offline banner, in-flight refresh, `gh` health,
  **MCP server status** (running / port + token, recent agent activity count).

### Constraints to preserve

- Polling cadence (F5) — UI should reflect refresh activity but not block on
  individual fetches.
- "Open in browser is the only jump" — no editor / terminal launch.
- Confirmation required for destructive ops **in the GUI path** (MCP path
  is confirmation-free; agent actions surface as toasts).
- No filter / search / sort UI for now (per spec).

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
  (so the token rotation stays in sync).
- User declines → Aerie remembers; there is a re-enable toggle in Settings.
- Aerie never touches other entries in `~/.claude/.mcp.json`.

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

### Toasts (GUI surface for MCP activity)

Each write call raises a toast:

```
Aerie MCP: aerie_merge_pr on cems-ui (#1234)
by agent: cc-session-7f2a
✅ Merged (squash) at 14:23:01
[ view request ]
```

Toasts persist for ~6 s then collapse into a "recent MCP activity" list
in the Settings view.

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

- Per-PR "is this mine?" hint — the design adds a `yours` pill when
  `pr.mine === true`. Spec: author login matches any of the configured
  accounts' login. Trivial to compute. Closed.
- App icon — deferred.
- Should the MCP server also expose `aerie_refresh_repo(repo)` to let an
  agent force a fresh fetch when cache is stale? Currently out of scope
  (cache-only by design). — Revisit after first usage.
- Should write tools support a `dry_run` parameter (return what *would*
  happen without doing it)? — Defer until requested.
- The Reset confirmation dialog in the design shows the target commit
  SHA (`origin/main @ a91f3c2`). To populate this, Aerie needs the
  resolved commit at fetch time; cheap to add to `LocalGitStatus` once
  needed. — Capture during implementation.
