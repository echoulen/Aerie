// Mock data for Aerie v2 — pared down to only the fields the design uses.

// PRs: each PR carries its local-repo state so the user can answer
// "is my local branch in sync for this PR" without leaving the PR list.
const V2_PRS = [
  {
    id:'p1', repo:'aerie',            num:142, branch:'feat/virtual-clock',
    title:'PollingScheduler: virtual clock for tests',
    author:'carlos-li',  mine:true,
    ci:'pass',    review:'approved',
    local:{ checkedOut:true,  dirty:false, ahead:2, behind:0, unpushed:0 },
    updated:'12m',
  },
  {
    id:'p2', repo:'aerie',            num:141, branch:'feat/graphql-pagination',
    title:'GitHubAPI: GraphQL pagination for PRs',
    author:'carlos-li',  mine:true,
    ci:'fail',    review:'changes',
    local:{ checkedOut:false, dirty:false, ahead:0, behind:0, unpushed:2 },
    updated:'42m',
  },
  {
    id:'p3', repo:'aerie',            num:139, branch:'ui/dirty-indicator',
    title:'Repo row: dirty/clean indicator with tooltip',
    author:'maja-c',     mine:false,
    ci:'pending', review:'request',
    local:{ checkedOut:false, dirty:false, ahead:0, behind:0, unpushed:0 },
    updated:'1h',
  },
  {
    id:'p4', repo:'shrike-renderer',  num:512, branch:'perf/glyph-cache',
    title:'Glyph cache: LRU eviction by render-bucket',
    author:'carlos-li',  mine:true,
    ci:'pass',    review:'approved',
    local:{ checkedOut:true,  dirty:true,  ahead:4, behind:7, unpushed:1 },
    updated:'8m',
  },
  {
    id:'p5', repo:'orbital-platform', num:8821, branch:'billing/annual-proration',
    title:'feat(billing): proration on annual upgrade',
    author:'priya-r',    mine:false,
    ci:'pass',    review:'approved',
    local:{ checkedOut:false, dirty:false, ahead:0, behind:0, unpushed:0 },
    updated:'24m',
  },
  {
    id:'p6', repo:'orbital-cli',      num:78,  branch:'fix/auth-fallback',
    title:'Token cache: fall back to keychain on no-gh',
    author:'carlos-li',  mine:true,
    ci:'pass',    review:'request',
    local:{ checkedOut:true,  dirty:false, ahead:0, behind:0, unpushed:0 },
    updated:'1h',
  },
  {
    id:'p7', repo:'falcon-edge',      num:241, branch:'security/tls-rotate',
    title:'Edge TLS: rotate session tickets every 6h',
    author:'jens-h',     mine:false,
    ci:'pass',    review:'approved',
    local:{ checkedOut:false, dirty:false, ahead:0, behind:0, unpushed:0 },
    updated:'18m',
  },
];

// Repos: branch + dirty/ahead/behind, plus whether reset is meaningful right now.
const V2_REPOS = [
  { id:'r1',  name:'aerie',           owner:'carlos-li', branch:'feat/virtual-clock',  defaultBranch:'main', dirty:true,  ahead:2,  behind:0, unpushed:0 },
  { id:'r4',  name:'shrike-renderer', owner:'orbital',   branch:'perf/glyph-cache',    defaultBranch:'main', dirty:true,  ahead:4,  behind:7, unpushed:1 },
  { id:'r2',  name:'orbital-platform',owner:'orbital',   branch:'main',                defaultBranch:'main', dirty:false, ahead:0,  behind:0, unpushed:0 },
  { id:'r7',  name:'orbital-cli',     owner:'orbital',   branch:'fix/auth-fallback',   defaultBranch:'main', dirty:false, ahead:0,  behind:0, unpushed:0 },
  { id:'r3',  name:'libgit2-swift',   owner:'orbital',   branch:'rc/0.18',             defaultBranch:'main', dirty:false, ahead:0,  behind:12,unpushed:0 },
  { id:'r5',  name:'falcon-edge',     owner:'orbital',   branch:'main',                defaultBranch:'main', dirty:false, ahead:0,  behind:2, unpushed:0 },
  { id:'r6',  name:'kestrel',         owner:'orbital',   branch:'main',                defaultBranch:'main', dirty:false, ahead:0,  behind:0, unpushed:0 },
  { id:'r8',  name:'aerie-website',   owner:'carlos-li', branch:'main',                defaultBranch:'main', dirty:false, ahead:0,  behind:0, unpushed:0 },
  { id:'r9',  name:'sketchpad',       owner:'carlos-li', branch:'wip-canvas-refactor', defaultBranch:'main', dirty:true,  ahead:18, behind:2, unpushed:18 },
];

Object.assign(window, { V2_PRS, V2_REPOS });
