# Aerie — Design Doc

> macOS dashboard for overseeing many git repos at once — local state, PRs, issues, quick actions.

**Project**: Aerie
**Date**: 2026-05-28
**Author**: carlos
**Status**: draft

> **For downstream Claude Design**: This spec defines the functionality, data
> model, and architecture only. UI layout, screens, visual hierarchy, theming,
> and interaction patterns are deferred to a follow-up design pass by Claude
> Design. See [§9 UI Handoff Notes](#9-ui-handoff-notes) for the contract.

## Goal

A macOS-only desktop app that gives the user a single dashboard for managing
~50 git repos at once — surfacing local git state, open PRs, open issues, and
basic recent history per repo, plus three targeted actions (hard reset to
`origin/main`, merge PR, open in browser).

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

- List **all** open PRs in the repo, not filtered to the user.
- Per PR: number, title, author login, CI status, review status, labels.
- Clicking a PR opens its GitHub HTML URL in the default browser.

### F4. GitHub Issues

- List **all** open issues in the repo.
- Per issue: number, title, author login, labels, assignees.
- Clicking an issue opens its GitHub HTML URL in the default browser.

### F5. Branch / commit history

- Show **current branch only** and the most recent **20 commits** on it.
- Per commit: short SHA, message subject line, author name, relative date.
- No multi-branch view. No stale-branch tracker.

### F6. Actions

| Action | Target | Implementation |
|---|---|---|
| **Hard reset to default branch** | one repo | Sequence: `git fetch origin` → `git checkout <defaultBranch>` → `git reset --hard origin/<defaultBranch>`. If working tree is dirty, the confirmation dialog explicitly warns "this will discard N uncommitted changes". Aborts (does not partially apply) on any error. Implemented via SwiftGit2. |
| **Merge PR** | one PR | GitHub REST `PUT /repos/{owner}/{repo}/pulls/{number}/merge` using the repo's primary account token. Assumes PR is mergeable; surfaces GitHub's error if not. Merge method: `squash` (matches the user's standard workflow). Confirmation dialog required. |

**Confirmation note**: the confirmation dialog applies only to the **GUI**
path. The MCP path (§10) invokes the same underlying service without a
dialog, by design — agents are expected to execute autonomously and
each MCP write surfaces a GUI toast for audit instead.
| **Open in browser** | repo / PR / issue | `NSWorkspace.shared.open(url)` to the entity's GitHub HTML URL. Repo-level shortcuts: open the repo page, the Issues tab, the Pull Requests tab, the Code tab. |

### F7. Smart polling

- App fetches all data on launch.
- Background tick every **30 seconds** decides what to refresh:
  - The **active repo** → refresh every **30 s**.
  - All other configured repos → refresh every **5 min**.

"Active repo" definition: the repo whose detail view is currently mounted.
If the dashboard is showing the global overview (no repo selected), there
is no active repo and all repos use the 5 min cadence.
- Manual refresh button always available (per repo + global).
- When app loses foreground (`NSApplication.didResignActive`): pause polling.
- When app regains foreground (`didBecomeActive`): immediate one-shot refresh, then resume.
- App closed = zero activity. No background daemon.

### F8. Multi-account GitHub auth

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

### F9. Settings

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

struct Issue {
    let id: UUID
    let repoId: UUID
    let number: Int
    let title: String
    let authorLogin: String
    let labels: [String]
    let assigneeLogins: [String]
    let htmlUrl: URL
    let updatedAt: Date
}

struct Commit {
    let sha: String               // short SHA
    let repoId: UUID
    let message: String           // subject line only
    let authorName: String
    let date: Date
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

CREATE TABLE issue_cache (
    repo_id TEXT NOT NULL REFERENCES repos(id),
    number INTEGER NOT NULL,
    payload_json TEXT NOT NULL,
    fetched_at REAL NOT NULL,
    PRIMARY KEY (repo_id, number)
);

CREATE TABLE git_status_cache (
    repo_id TEXT PRIMARY KEY REFERENCES repos(id),
    payload_json TEXT NOT NULL,
    fetched_at REAL NOT NULL
);

CREATE TABLE commits_cache (
    repo_id TEXT NOT NULL REFERENCES repos(id),
    sha TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    fetched_at REAL NOT NULL,
    sort_order INTEGER NOT NULL,    -- 0 = most recent
    PRIMARY KEY (repo_id, sha)
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
every 30s:
    let active = currentlyFocusedRepoId
    let dueRepos = repos where:
        repo.id == active && now - fetched_at >= 30s
        OR
        repo.id != active && now - fetched_at >= 5min
    refreshConcurrently(dueRepos, limit: 5)
```

Concurrency limit (5) keeps GitHub rate limit usage bounded — at the worst
case (50 repos all overdue at the same minute), 50 requests in <30s.
GitHub's quota is 5000/hr authenticated, so headroom is ample.

When `>= 4500/hr` is observed in response headers, the scheduler downgrades
the active-repo interval to 2 minutes and shows a yellow rate-limit badge
in the UI until the next hour rolls over.

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

### What this spec deliberately leaves open

- Layout (master-detail vs grid vs three-pane vs PR-centric vs hybrid).
- Visual hierarchy, color, typography, iconography, density.
- Animation / transition style.
- Empty states, loading states, skeletons.
- Confirmation dialog copy and visual treatment.
- How "primary account" is surfaced per repo (badge? avatar? text?).
- Settings screen layout.
- First-run onboarding flow.

### What the UI must support

Screens / views that need to exist:

1. **Main dashboard** — render the configured repos with their current state
   (F1, F2, F3, F4 at a glance level — exact information density up to design).
2. **Repo detail** — full state for one repo: local git status (F2), PR list
   (F3), Issue list (F4), recent commits (F5).
3. **Add-repo flow** — folder picker + primary account selection (F1, F8).
4. **Settings** — repo list management (rename, hide, reorder, change account),
   polling settings (F9), MCP integration toggle + recent MCP activity list (§10).
5. **First-run / `gh` setup screen** — blocking screen when `gh` is missing or
   unauthenticated (F8).
6. **Confirmation dialogs** — for hard reset and merge PR (F6).
7. **MCP integration consent dialog** — one-time first-run prompt asking
   whether Aerie may add itself to `~/.claude/.mcp.json` (§10).
8. **MCP activity toast** — non-blocking surface shown when an agent calls
   a write tool; includes agent ID, target repo/PR, result, and a "view
   request" affordance (§10).

### Available actions the UI must expose

- Hard reset to `origin/main` (one repo at a time)
- Merge PR (one PR at a time)
- Open in browser: repo home, Issues, Pull Requests, Code, individual PR,
  individual Issue
- Manual refresh: global, and per-repo
- Add repo / remove repo / hide repo / rename repo / change repo's primary account
- Reorder repos

### Data the UI has access to

Anything in the [Data model](#data-model) section, plus per-entity
`fetched_at` timestamps so the UI can show "freshness" if desired.

### State surfaces the UI may want to indicate

- Per-repo: dirty/clean, ahead/behind counts, open PR count, open issue count,
  GitHub access status (ok / no-access / offline), data freshness.
- Per-PR: CI status, review status, label set.
- Per-issue: assignee count, label set.
- Global: rate-limit warning, offline banner, in-flight refresh, `gh` health,
  **MCP server status** (running / port + token, recent agent activity count).

### Constraints to preserve

- Polling cadence (F7) — UI should reflect refresh activity but not block on
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
- GUI closed = MCP unavailable. Aligns with F7 ("app closed = no activity").

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
| `aerie_list_prs` | `repo`, `state?` (default `open`) | `[PullRequest]` |
| `aerie_get_pr` | `repo`, `number` | `PullRequest` |
| `aerie_list_issues` | `repo`, `state?` (default `open`) | `[Issue]` |
| `aerie_get_issue` | `repo`, `number` | `Issue` |
| `aerie_recent_commits` | `repo`, `limit?` (max 20) | `[Commit]` |

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

- Should we surface a per-PR "is this mine?" hint (author == any logged-in
  account) to make scanning easier without adding filters? — Deferred to UI
  design pass.
- App icon. — Deferred.
- App display name / codename. — Deferred.
- Should the MCP server also expose `aerie_refresh_repo(repo)` to let an
  agent force a fresh fetch when cache is stale? Currently out of scope
  (cache-only by design). — Revisit after first usage.
- Should write tools support a `dry_run` parameter (return what *would*
  happen without doing it)? — Defer until requested.
