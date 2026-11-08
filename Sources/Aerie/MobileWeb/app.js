// Aerie · iPhone PWA. A thin skin over Aerie.app on the Mac: everything here
// talks to /m/api/* (see docs/superpowers/specs/2026-11-02-mobile-pwa/api.md).
// Vanilla JS, no build step, strict CSP (no inline scripts / handlers).
"use strict";

(() => {
  // ── Small DOM helpers ──────────────────────────────────────────────
  const root = document.getElementById("app");
  const SVGNS = "http://www.w3.org/2000/svg";

  /** h("div", {class, style, onClick, ...attrs}, ...children). Strings become text nodes (never HTML). */
  function h(tag, props, ...kids) {
    const el = document.createElement(tag);
    applyProps(el, props);
    append(el, kids);
    return el;
  }
  function svg(tag, attrs, ...kids) {
    const el = document.createElementNS(SVGNS, tag);
    for (const [k, v] of Object.entries(attrs || {})) el.setAttribute(k, v);
    append(el, kids);
    return el;
  }
  function applyProps(el, props) {
    if (!props) return;
    for (const [k, v] of Object.entries(props)) {
      if (v == null || v === false) continue;
      if (k === "class") el.className = v;
      else if (k === "style") {
        if (typeof v === "string") el.style.cssText = v; else Object.assign(el.style, v);
      } else if (k.startsWith("on") && typeof v === "function") el.addEventListener(k.slice(2).toLowerCase(), v);
      else if (k === "disabled") el.disabled = !!v;
      else if (v === true) el.setAttribute(k, "");
      else el.setAttribute(k, String(v));
    }
  }
  function append(el, kids) {
    for (const kid of kids.flat(Infinity)) {
      if (kid == null || kid === false || kid === true) continue;
      el.append(kid instanceof Node ? kid : document.createTextNode(String(kid)));
    }
  }
  const spacer = () => h("span", { class: "flex1" });
  const spinner = (size = 13) => h("span", { class: "spinner", style: { width: size + "px", height: size + "px" } });
  const progress = (extra = "") => h("div", { class: "progress-track " + extra }, h("span"));
  const appIcon = (size) => h("img", { class: "app-icon", src: "icon.png", alt: "", width: size, height: size, draggable: "false" });

  // ── base64url (WebAuthn) ───────────────────────────────────────────
  const b64uToBytes = (s) =>
    Uint8Array.from(atob(String(s).replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(String(s).length / 4) * 4, "=")), (c) => c.charCodeAt(0));
  function bytesToB64u(buf) {
    const bytes = new Uint8Array(buf);
    let bin = "";
    for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
    return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  }

  // ── Formatting ─────────────────────────────────────────────────────
  function ago(iso) {
    const t = Date.parse(iso);
    if (!Number.isFinite(t)) return "";
    const s = Math.max(0, (Date.now() - t) / 1000);
    if (s < 60) return "now";
    if (s < 3600) return `${Math.floor(s / 60)}m`;
    if (s < 86400) return `${Math.floor(s / 3600)}h`;
    if (s < 86400 * 365) return `${Math.floor(s / 86400)}d`;
    return `${Math.floor(s / (86400 * 365))}y`;
  }
  const ciDot = (ci) => ({ success: "ok", failure: "err", pending: "warn" })[ci] || "muted";
  const pad2 = (n) => String(n).padStart(2, "0");
  const delta = (add, del) =>
    h("span", { class: "mono delta" }, h("span", { class: "add" }, "+" + (add ?? "–")), " ", h("span", { class: "del" }, "−" + (del ?? "–")));
  const loginOf = (account) => String(account || "").split(" · ")[0];

  // ── Storage ────────────────────────────────────────────────────────
  const store = {
    get deviceId() { return localStorage.getItem("aerie.deviceId"); },
    set deviceId(v) { v ? localStorage.setItem("aerie.deviceId", v) : localStorage.removeItem("aerie.deviceId"); },
    get session() { return localStorage.getItem("aerie.session"); },
    set session(v) { v ? localStorage.setItem("aerie.session", v) : localStorage.removeItem("aerie.session"); },
  };

  // ── State ──────────────────────────────────────────────────────────
  const freshData = () => ({
    state: null,            // /m/api/state
    nextPollAt: 0,          // local deadline derived from nextPollInSeconds
    lists: {},              // filter -> [PRRow]
    listLoaded: {},         // filter -> bool
    detail: {},             // key -> {data, notFound, error}
    files: {},              // key -> {files, error}
    expanded: {},           // key -> Set(file index)
    repos: null,            // /m/api/repos
    settings: null,         // /m/api/settings
    repoFilter: null,       // [RepoFilterRow]
  });
  const S = {
    gate: "boot",           // boot | insecure | install | pair | launch | offline | ready
    hello: null,
    pair: { phase: "idle", error: null, pending: null }, // idle | waiting | approved | creating
    launch: { busy: false, error: null, needTap: false },
    route: { name: "prs" },
    filter: null,           // null | ready | you | blocked — the PR list summary tiles
    data: freshData(),
    sheet: null,            // {kind: "approve"|"merge", running, error}
    merged: null,           // {pr, merge, result}
    ptr: { state: "idle" }, // pull to refresh: idle | pull | ready | syncing
    toast: null,
  };
  const scrollMemory = new Map();
  let touching = false;
  let pendingRender = false;

  // ── API ────────────────────────────────────────────────────────────
  class HttpError extends Error {
    constructor(status, body) { super((body && body.error) || `HTTP ${status}`); this.status = status; this.body = body; }
  }
  class OfflineError extends Error {}

  async function api(path, { method = "GET", body, auth = true, timeout = 10000 } = {}) {
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), timeout);
    let res, data;
    try {
      const headers = {};
      if (body !== undefined) headers["content-type"] = "application/json";
      if (auth && store.session) headers.authorization = "Bearer " + store.session;
      res = await fetch(path, { method, headers, signal: ctl.signal, cache: "no-store", body: body !== undefined ? JSON.stringify(body) : undefined });
      if (res.status === 502 || res.status === 503 || res.status === 504) throw new OfflineError("gateway " + res.status);
      data = res.status === 204 ? {} : await res.json().catch(() => ({}));
    } catch (err) {
      if (err instanceof OfflineError) throw err;
      throw new OfflineError(err && err.name === "AbortError" ? "timeout" : "network");
    } finally {
      clearTimeout(timer);
    }
    if (!res.ok) {
      if (res.status === 401 && auth) onUnauthorized();
      throw new HttpError(res.status, data);
    }
    return data;
  }

  const prPath = (repoId, number) => `m/api/prs/${encodeURIComponent(repoId)}/${encodeURIComponent(number)}`;

  /** Shared catch: offline → offline screen; 401 → already locking; else a toast. */
  function fail(err, what) {
    if (err instanceof OfflineError) return goOffline();
    if (err instanceof HttpError && err.status === 401) return;
    toast(what ? `${what}: ${err.message}` : err.message);
  }

  function goOffline() {
    if (S.gate === "offline") return;
    S.gate = "offline";
    S.data = freshData(); // never show stale data
    S.sheet = null;
    stopPolling();
    render();
  }

  function onUnauthorized() {
    store.session = null;
    if (S.gate !== "ready") return;
    S.data = freshData();
    S.sheet = null;
    stopPolling();
    S.gate = "launch";
    S.launch = { busy: false, error: null, needTap: false };
    render();
    unlock();
  }

  // ── Boot & gates ───────────────────────────────────────────────────
  const isStandalone = () => navigator.standalone === true || window.matchMedia("(display-mode: standalone)").matches;
  const isSecure = () => window.isSecureContext === true || location.protocol === "https:" || ["localhost", "127.0.0.1", "[::1]"].includes(location.hostname);

  async function boot() {
    stopPolling();
    if (!isSecure()) { S.gate = "insecure"; return render(); }
    if (!isStandalone() && sessionStorage.getItem("aerie.browser") !== "1") { S.gate = "install"; return render(); }
    S.gate = "boot";
    render();
    try {
      S.hello = await api("m/api/hello", { auth: false });
    } catch (err) {
      if (err instanceof OfflineError) return goOffline();
      S.hello = null;
    }
    if (!store.deviceId) { S.gate = "pair"; S.pair = { phase: "idle", error: null, pending: null }; return render(); }
    if (store.session) {
      try {
        S.data = freshData();
        setState(await api("m/api/state"));
        return enterApp();
      } catch (err) {
        if (err instanceof OfflineError) return goOffline();
        // 401 (or anything else): fall through to unlock.
        store.session = null;
      }
    }
    S.gate = "launch";
    S.launch = { busy: false, error: null, needTap: false };
    render();
    unlock();
  }

  function deviceName() {
    const ua = navigator.userAgent;
    let name = /iPhone/.test(ua) ? "iPhone" : /iPad/.test(ua) ? "iPad" : /Android/.test(ua) ? "Android" : /Macintosh/.test(ua) ? "Mac browser" : "Browser";
    const m = /OS (\d+)[_.](\d+)/.exec(ua);
    if (m && /iPhone|iPad/.test(ua)) name += ` · iOS ${m[1]}.${m[2]}`;
    return name;
  }

  async function startPairing() {
    S.pair = { phase: "waiting", error: null, pending: null };
    render();
    let res;
    try {
      res = await api("m/api/pair/start", { method: "POST", auth: false, body: { deviceName: deviceName() }, timeout: 75000 });
    } catch (err) {
      let msg = "Couldn't reach your Mac. Try again.";
      if (err instanceof HttpError && err.status === 403) msg = "Denied on your Mac.";
      else if (err instanceof HttpError && err.status === 408) msg = "Nobody answered on your Mac in time. Try again.";
      else if (err instanceof HttpError) msg = err.message;
      else if (err instanceof OfflineError && err.message === "timeout") msg = "Nobody answered on your Mac in time. Try again.";
      S.pair = { phase: "idle", error: msg, pending: null };
      return render();
    }
    S.pair = { phase: "creating", error: null, pending: res };
    render();
    createPasskey();
  }

  /** Runs navigator.credentials.create. Safari may refuse it without a fresh tap
   *  (the approval wait outlives the original gesture), so on NotAllowedError we
   *  offer a button that retries inside a new gesture. */
  async function createPasskey() {
    const { pairingId, options } = S.pair.pending;
    S.pair.phase = "creating";
    S.pair.error = null;
    render();
    let cred;
    try {
      const pk = {
        ...options,
        challenge: b64uToBytes(options.challenge),
        user: { ...options.user, id: b64uToBytes(options.user.id) },
        excludeCredentials: (options.excludeCredentials || []).map((c) => ({ ...c, id: b64uToBytes(c.id) })),
      };
      cred = await navigator.credentials.create({ publicKey: pk });
      if (!cred) throw Object.assign(new Error("no credential"), { name: "NotAllowedError" });
    } catch (err) {
      S.pair.phase = "approved";
      S.pair.error = err && err.name === "NotAllowedError"
        ? "Face ID didn't complete. Tap to try again."
        : `Couldn't create a passkey (${(err && err.message) || "unknown error"}).`;
      return render();
    }
    try {
      const credential = {
        id: cred.id, rawId: bytesToB64u(cred.rawId), type: cred.type,
        response: {
          clientDataJSON: bytesToB64u(cred.response.clientDataJSON),
          attestationObject: bytesToB64u(cred.response.attestationObject),
        },
      };
      const { deviceId, sessionToken } = await api("m/api/pair/finish", { method: "POST", auth: false, body: { pairingId, credential } });
      store.deviceId = deviceId;
      store.session = sessionToken;
      S.pair = { phase: "idle", error: null, pending: null };
      S.data = freshData();
      try { setState(await api("m/api/state")); } catch (err) { if (err instanceof OfflineError) return goOffline(); }
      enterApp();
    } catch (err) {
      if (err instanceof OfflineError) return goOffline();
      S.pair = { phase: "idle", error: `Pairing failed: ${err.message}. Start again.`, pending: null };
      render();
    }
  }

  async function unlock() {
    if (S.launch.busy) return;
    const tapped = !!S.launch.tapped;
    S.launch = { busy: true, error: null, needTap: false, tapped };
    render();
    let options;
    try {
      ({ options } = await api("m/api/unlock/options", { method: "POST", auth: false, body: { deviceId: store.deviceId } }));
    } catch (err) {
      S.launch.busy = false;
      if (err instanceof OfflineError) return goOffline();
      if (err instanceof HttpError && err.status === 404) return forgetDevice();
      S.launch = { busy: false, error: `Couldn't unlock: ${err.message}`, needTap: true };
      return render();
    }
    let cred;
    try {
      const pk = {
        ...options,
        challenge: b64uToBytes(options.challenge),
        allowCredentials: (options.allowCredentials || []).map((c) => ({ ...c, id: b64uToBytes(c.id) })),
      };
      cred = await navigator.credentials.get({ publicKey: pk });
      if (!cred) throw Object.assign(new Error("no credential"), { name: "NotAllowedError" });
    } catch (err) {
      S.launch = {
        busy: false, needTap: true, tapped,
        // The first, automatic attempt has no user gesture: a plain button, no red text.
        error: err && err.name === "NotAllowedError" ? (tapped ? "Face ID didn't complete. Try again." : null) : `Face ID failed: ${(err && err.message) || "unknown error"}`,
      };
      return render();
    }
    try {
      const credential = {
        id: cred.id, rawId: bytesToB64u(cred.rawId), type: cred.type,
        response: {
          clientDataJSON: bytesToB64u(cred.response.clientDataJSON),
          authenticatorData: bytesToB64u(cred.response.authenticatorData),
          signature: bytesToB64u(cred.response.signature),
          userHandle: cred.response.userHandle ? bytesToB64u(cred.response.userHandle) : null,
        },
      };
      const { sessionToken } = await api("m/api/unlock/verify", { method: "POST", auth: false, body: { deviceId: store.deviceId, credential } });
      store.session = sessionToken;
      S.launch = { busy: false, error: null, needTap: false };
      S.data = freshData();
      setState(await api("m/api/state"));
      enterApp();
    } catch (err) {
      if (err instanceof OfflineError) return goOffline();
      if (err instanceof HttpError && err.status === 404) return forgetDevice();
      S.launch = { busy: false, error: `Couldn't unlock: ${err.message}`, needTap: true };
      render();
    }
  }

  function forgetDevice() {
    store.deviceId = null;
    store.session = null;
    S.data = freshData();
    S.gate = "pair";
    S.pair = { phase: "idle", error: "This iPhone is no longer linked. Link it again.", pending: null };
    render();
  }

  function enterApp() {
    S.gate = "ready";
    if (!location.hash || location.hash === "#" || location.hash === "#/") history.replaceState(null, "", "#/prs");
    applyRoute();
  }

  // ── Routing ────────────────────────────────────────────────────────
  function parseRoute() {
    const parts = location.hash.replace(/^#\/?/, "").split("/").map((p) => { try { return decodeURIComponent(p); } catch { return p; } });
    switch (parts[0]) {
      case "pr": return parts[1] && parts[2] ? { name: "pr", repoId: parts[1], number: parts[2], key: parts[1] + "/" + parts[2] } : { name: "prs" };
      case "merged": return { name: "merged" };
      case "repos": return { name: "repos" };
      case "settings": return parts[1] === "repos" ? { name: "repofilter" } : { name: "settings" };
      default: return { name: "prs" };
    }
  }
  const routeId = (r = S.route) => r.name + (r.key ? ":" + r.key : "");
  const go = (hash) => { if (location.hash === hash) applyRoute(); else location.hash = hash; };

  function applyRoute() {
    if (S.gate !== "ready") return;
    S.route = parseRoute();
    S.sheet = null;
    S.ptr = { state: "idle" };
    if (S.route.name === "merged" && !S.merged) { history.replaceState(null, "", "#/prs"); S.route = { name: "prs" }; }
    render();
    poll(true);
  }
  window.addEventListener("hashchange", () => { saveScroll(); applyRoute(); });

  // ── Data loading / polling ─────────────────────────────────────────
  function setState(st) {
    S.data.state = st;
    S.data.nextPollAt = Date.now() + Math.max(0, Number(st.nextPollInSeconds) || 0) * 1000;
  }
  const sameJSON = (a, b) => JSON.stringify(a) === JSON.stringify(b);
  const stateSig = (st) => st && JSON.stringify({ ...st, nextPollInSeconds: 0 });

  let pollTimer = null;
  let pollSeq = 0;
  function stopPolling() { clearTimeout(pollTimer); pollTimer = null; pollSeq++; }

  function pollDelay() {
    if (S.route.name === "pr") {
      const d = S.data.detail[S.route.key] && S.data.detail[S.route.key].data;
      if (d && (d.aiReview.phase === "running" || d.actions.approve.phase === "running" || d.actions.merge.phase === "running")) return 2000;
    }
    return 5000;
  }
  function schedulePoll() {
    clearTimeout(pollTimer);
    if (S.gate !== "ready" || document.hidden) return;
    pollTimer = setTimeout(() => poll(false), pollDelay());
  }

  /** Loads what the current route shows. `first` = route just opened. */
  async function poll(first) {
    if (S.gate !== "ready") return;
    clearTimeout(pollTimer);
    const seq = ++pollSeq;
    const route = S.route;
    const rid = routeId(route);
    let changed = false;
    try {
      const jobs = [];
      if (route.name === "prs" || route.name === "repos" || route.name === "settings" || route.name === "repofilter") {
        jobs.push(api("m/api/state").then((st) => {
          if (stateSig(st) !== stateSig(S.data.state)) changed = true;
          setState(st);
        }));
      }
      if (route.name === "prs") {
        // The verdict tiles filter client-side, so the list is always the full one.
        const f = "all";
        jobs.push(api("m/api/prs?filter=" + f).then((r) => {
          if (!S.data.listLoaded[f] || !sameJSON(r.prs, S.data.lists[f])) changed = true;
          S.data.lists[f] = r.prs || [];
          S.data.listLoaded[f] = true;
        }));
      } else if (route.name === "pr") {
        jobs.push(loadDetail(route).then((c) => { if (c) changed = true; }));
        if (first || !S.data.files[route.key]) jobs.push(loadFiles(route).then(() => { changed = true; }));
      } else if (route.name === "repos") {
        jobs.push(api("m/api/repos").then((r) => { if (!sameJSON(r, S.data.repos)) changed = true; S.data.repos = r; }));
      } else if (route.name === "settings") {
        jobs.push(api("m/api/settings").then((r) => { if (!sameJSON(r, S.data.settings)) changed = true; S.data.settings = r; }));
      } else if (route.name === "repofilter" && first) {
        jobs.push(api("m/api/settings/repos").then((r) => { S.data.repoFilter = r.repos || []; changed = true; }));
      }
      await Promise.all(jobs);
    } catch (err) {
      if (seq !== pollSeq) return;
      fail(err);
      if (S.gate !== "ready") return;
    }
    if (seq !== pollSeq) return;
    if ((changed || first) && routeId() === rid) {
      // Under an open sheet the screen behind it isn't visible; repainting it
      // would also rebuild the sheet mid-merge. Closing the sheet repaints
      // with whatever the polls loaded meanwhile.
      if (!S.sheet || first) render();
    } else updateCountdown();
    schedulePoll();
  }

  async function loadDetail(route) {
    const slot = S.data.detail[route.key] || (S.data.detail[route.key] = {});
    try {
      const d = await api(prPath(route.repoId, route.number));
      const changed = !sameJSON(d, slot.data) || slot.notFound;
      slot.data = d; slot.notFound = false; slot.error = null;
      return changed;
    } catch (err) {
      if (err instanceof HttpError && err.status === 404) {
        const changed = !slot.notFound;
        slot.notFound = true; slot.data = null;
        return changed;
      }
      throw err;
    }
  }

  async function loadFiles(route) {
    try {
      const r = await api(prPath(route.repoId, route.number) + "/files", { timeout: 30000 });
      S.data.files[route.key] = { files: r.files || [], error: null };
      if (!S.data.expanded[route.key]) S.data.expanded[route.key] = new Set([0]);
    } catch (err) {
      if (err instanceof HttpError && err.status === 404) { S.data.files[route.key] = { files: [], error: null }; return; }
      if (err instanceof HttpError) { S.data.files[route.key] = { files: [], error: err.message }; return; }
      throw err;
    }
  }

  document.addEventListener("visibilitychange", () => {
    if (document.hidden) { clearTimeout(pollTimer); return; }
    if (S.gate === "ready") poll(false);
    else if (S.gate === "offline") boot();
  });
  setInterval(() => { if (!document.hidden && S.gate === "offline") boot(); }, 15000);

  // Countdown "42S" ticks locally between state refreshes.
  function countdownText() {
    if (!S.data.state) return "—";
    return Math.max(0, Math.ceil((S.data.nextPollAt - Date.now()) / 1000)) + "S";
  }
  function updateCountdown() {
    for (const el of root.querySelectorAll("[data-countdown]")) el.textContent = countdownText();
  }
  setInterval(updateCountdown, 1000);

  // ── Toast ──────────────────────────────────────────────────────────
  let toastTimer = null;
  function toast(msg) {
    S.toast = msg;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { S.toast = null; renderToast(); }, 4500);
    renderToast();
  }
  function renderToast() {
    const old = document.getElementById("toast");
    if (old) old.remove();
    if (S.toast) document.body.append(h("div", { id: "toast", class: "toast", role: "alert" }, S.toast));
  }

  // ── Render ─────────────────────────────────────────────────────────
  function saveScroll() {
    const el = root.querySelector(".scroll");
    if (el) scrollMemory.set(el.dataset.sid, el.scrollTop);
  }

  // The backdrop never leaves the DOM: a fresh node, or even re-inserting the
  // same one (replaceChildren detaches it first), restarts the nebula and
  // starfield animations, so every re-render made the background jump.
  // Only the nodes after it are swapped. index.html ships it as #app's child.
  let backdropEl = root.querySelector(".backdrop");
  if (!backdropEl) root.prepend(backdropEl = h("div", { class: "backdrop" }));
  function render() {
    if (touching) { pendingRender = true; return; }
    pendingRender = false;
    saveScroll();
    const view = renderView();
    while (backdropEl.nextSibling) backdropEl.nextSibling.remove();
    append(root, [view]);
    const sc = root.querySelector(".scroll");
    if (sc && scrollMemory.has(sc.dataset.sid)) sc.scrollTop = scrollMemory.get(sc.dataset.sid);
    if (sc && S.route.name === "prs" && S.gate === "ready") attachPullToRefresh(sc);
    renderToast();
  }

  function renderView() {
    switch (S.gate) {
      case "insecure": return viewInsecure();
      case "install": return viewInstall();
      case "pair": return viewPair();
      case "launch": return viewLaunch();
      case "offline": return viewOffline();
      case "ready": return viewApp();
      default: return viewLaunch(true);
    }
  }

  // Header (SEHeader)
  function header({ eyebrow, title, right, back }) {
    return h("div", { class: "hdr" },
      h("div", { class: "row hdr-row" },
        back ? h("button", { class: "btn ghost back", "aria-label": "Back", onClick: back }, "←") : null,
        h("div", { class: "col hdr-text" },
          h("span", { class: "section-eyebrow hdr-eyebrow" }, eyebrow),
          h("span", { class: "hdr-title" }, title)),
        right || null));
  }

  const TABS = [
    ["prs", "PRs", "#/prs", "M4 4v8M12 6v6M12 6a2 2 0 00-2-2H7"],
    ["repos", "Repos", "#/repos", "M2 4h4l1.5 1.5H14V12H2z"],
    ["settings", "Settings", "#/settings", "M8 5.5a2.5 2.5 0 100 5 2.5 2.5 0 000-5zM8 1v2M8 13v2M1 8h2M13 8h2"],
  ];
  function tabbar(active) {
    // Same rule as the "for you" tile once the list is loaded; the server's
    // count (not mine + review requested) until then.
    const review = S.data.listLoaded.all
      ? S.data.lists.all.filter((pr) => prVerdict(pr).k === "you").length
      : (S.data.state && S.data.state.counts ? S.data.state.counts.review : 0);
    return h("nav", { class: "tabbar" }, TABS.map(([id, label, hash, d]) =>
      h("button", { class: "tab" + (id === active ? " on" : ""), "aria-label": label, onClick: () => go(hash) },
        svg("svg", { viewBox: "0 0 16 16", fill: "none", stroke: "currentColor", "stroke-width": "1.4", "stroke-linecap": "round", "stroke-linejoin": "round" }, svg("path", { d })),
        h("span", { class: "tab-label" }, label),
        id === "prs" && review > 0 ? h("span", { class: "mono tab-badge" }, review > 99 ? "99+" : review) : null)));
  }

  function screen(main, { tab, bar, overlay } = {}) {
    return [
      h("div", { class: "app-main" }, main),
      bar ? h("div", { class: "app-bar" }, bar) : null,
      tab ? tabbar(tab) : null,
      overlay || null,
    ];
  }

  function loadingBlock(label) {
    return h("div", { class: "loading" }, progress(), label ? h("span", { class: "hud-note" }, label) : null);
  }
  function emptyBlock(title, body) {
    return h("div", { class: "empty" }, h("div", { class: "empty-title" }, title), body ? h("div", { class: "empty-body" }, body) : null);
  }

  function viewApp() {
    switch (S.route.name) {
      case "pr": return viewReview();
      case "merged": return viewMerged();
      case "repos": return viewRepos();
      case "settings": return viewSettings();
      case "repofilter": return viewRepoFilter();
      default: return viewPRList();
    }
  }

  // ── Gate views ─────────────────────────────────────────────────────
  function viewInsecure() {
    return h("div", { class: "gate" },
      h("div", { class: "gate-rings err" }, h("span", { class: "a" }), h("span", { class: "b" })),
      h("div", { class: "gate-icon" }, appIcon(92)),
      h("div", { class: "wordmark" }, "AERIE"),
      h("div", { class: "tagline" }, "Needs HTTPS via Tailscale"),
      h("div", { class: "card gate-card" },
        h("span", { class: "hud-note" }, "on your mac"),
        h("p", null, "Face ID and offline support only work over HTTPS. Publish Aerie on your tailnet:"),
        h("div", { class: "cmd" }, "tailscale serve --bg --https=8443 8791"),
        h("p", { style: { marginTop: "12px" } }, "Then open ", h("b", { class: "mono", style: { fontSize: "12px" } }, "https://<mac>.ts.net:8443"), " on this iPhone.")),
      h("div", { class: "gate-spacer" }),
      h("span", { class: "hud-note" }, location.host || "insecure origin"));
  }

  function viewInstall() {
    const steps = [["01", "Tap", "Share", "⇪"], ["02", "Choose", "Add to Home Screen", "⊞"], ["03", "Open Aerie from", "your Home Screen", "◉"]];
    return [
      h("div", { class: "gate" },
        h("div", { class: "gate-rings" }, h("span", { class: "a" }), h("span", { class: "b" })),
        h("div", { class: "gate-icon" }, appIcon(92)),
        h("div", { class: "wordmark" }, "AERIE"),
        h("div", { class: "tagline" }, "Your PR queue, in your pocket."),
        h("div", { class: "col steps" }, steps.map(([n, a, b, g]) =>
          h("div", { class: "card row step" },
            h("span", { class: "mono n" }, n),
            h("span", { class: "t" }, a, " ", h("b", null, b)),
            spacer(),
            h("span", { class: "g" }, g)))),
        h("div", { class: "gate-spacer" }),
        h("div", { class: "col gate-foot" },
          h("button", { class: "text-link", onClick: () => { sessionStorage.setItem("aerie.browser", "1"); boot(); } }, "Continue in Safari"),
          h("span", { class: "hud-note" }, "safari only"))),
      h("div", { class: "share-pointer" }, h("span", null, "▼")),
    ];
  }

  function viewPair() {
    const p = S.pair;
    const mac = S.hello && S.hello.macName ? S.hello.macName : "your Mac";
    let body;
    if (p.phase === "waiting") {
      body = h("div", { class: "col pair-wait" },
        h("span", { class: "t" }, "Approve on your Mac…"),
        h("span", { class: "tagline", style: { marginTop: 0 } }, `Aerie on ${mac} is asking whether to allow this iPhone.`),
        progress(),
        h("span", { class: "hud-note" }, "waiting up to 60s"));
    } else if (p.phase === "creating") {
      body = h("div", { class: "col pair-wait" },
        h("span", { class: "t" }, "Setting up Face ID…"),
        progress(),
        h("span", { class: "hud-note" }, "passkey · this iphone"));
    } else if (p.phase === "approved") {
      body = h("div", { class: "col gate-actions", style: { marginTop: "28px" } },
        h("div", { class: "tagline", style: { alignSelf: "center" } }, `Approved on ${mac}. Face ID keeps this link private to you.`),
        p.error ? h("div", { class: "gate-error" }, p.error) : null,
        h("button", { class: "btn amber", onClick: () => { createPasskey(); } }, "SET UP FACE ID"),
        h("button", { class: "text-link", onClick: () => { S.pair = { phase: "idle", error: null, pending: null }; render(); } }, "Start over"));
    } else {
      body = h("div", { class: "col gate-actions", style: { marginTop: "28px" } },
        h("div", { class: "card gate-card", style: { marginTop: 0 } },
          h("span", { class: "hud-note" }, "how linking works"),
          h("p", null, "Aerie on your Mac asks you to allow this iPhone. Then Face ID creates a passkey, so only you can open it."),
          h("p", null, "GitHub tokens stay on the Mac.")),
        p.error ? h("div", { class: "gate-error" }, p.error) : null,
        h("button", { class: "btn amber", onClick: startPairing }, p.error ? "TRY AGAIN" : "LINK THIS IPHONE"));
    }
    return h("div", { class: "gate" },
      h("div", { class: "gate-rings" }, h("span", { class: "a" }), h("span", { class: "b" })),
      h("div", { class: "gate-icon" }, appIcon(92)),
      h("div", { class: "wordmark" }, "AERIE"),
      h("div", { class: "tagline" }, `Link this iPhone to ${mac}.`),
      body,
      h("div", { class: "gate-spacer" }),
      h("span", { class: "hud-note" }, "pairing · " + (location.host || "")));
  }

  function viewLaunch(booting) {
    const L = S.launch;
    const mac = S.hello && S.hello.macName ? S.hello.macName : "your mac";
    const stuck = !booting && L.needTap;
    return h("div", { class: "gate center" },
      h("div", { class: "launch-ring" + (stuck ? " still" : "") }, h("span", { class: "o" }), h("span", { class: "s" }), appIcon(104)),
      h("div", { class: "col launch-word" },
        h("span", { class: "w" }, "AERIE"),
        h("span", { class: "hud-note" }, "handshake · " + mac.toLowerCase())),
      stuck
        ? h("div", { class: "col gate-actions", style: { maxWidth: "320px" } },
          L.error ? h("div", { class: "gate-error" }, L.error) : null,
          h("button", { class: "btn amber", onClick: () => { S.launch.tapped = true; unlock(); } }, "UNLOCK WITH FACE ID"))
        : h("div", { class: "launch-progress" }, progress()));
  }

  function viewOffline() {
    const mac = S.hello && S.hello.macName ? S.hello.macName : "your Mac";
    return h("div", { class: "gate center" },
      h("div", { class: "launch-ring err" }, h("span", { class: "o" }), h("span", { class: "s" }), h("div", { class: "gate-icon dim", style: { marginTop: 0 } }, appIcon(104))),
      h("div", { class: "col launch-word" },
        h("span", { class: "w" }, "MAC OFFLINE"),
        h("span", { class: "tagline" }, `Aerie isn't reachable. ${mac === "your Mac" ? "Your Mac" : mac} may be asleep, Aerie may be closed, or Tailscale is off on this iPhone.`)),
      h("div", { class: "col gate-actions", style: { maxWidth: "320px" } },
        h("button", { class: "btn amber", onClick: boot }, "RETRY")),
      h("span", { class: "hud-note" }, location.host || ""));
  }

  // ── PR list (SEPRList) ─────────────────────────────────────────────
  // Each row leads with ONE verdict — what the PR needs next — then the two
  // signals that produced it (CI, review). Rows are sorted by verdict so the
  // actionable ones sit on top; the summary tiles double as the filter.
  function prVerdict(pr) {
    const ciOK = pr.ci === "success" || pr.ci === "none";
    if (pr.isDraft) return { k: "draft", label: "Draft", tone: "muted", rank: 4 };
    if (pr.ci === "failure") return { k: "blocked", label: "CI failing", tone: "err", rank: 2 };
    if (pr.review === "changesRequested") return { k: "blocked", label: "Changes requested", tone: "err", rank: 2 };
    if (ciOK && pr.review === "approved") return { k: "ready", label: "Ready to merge", tone: "amber", rank: 0 };
    if (pr.review === "reviewRequired" && !pr.isMine) return { k: "you", label: "Needs your review", tone: "you", rank: 1 };
    if (pr.ci === "pending") return { k: "running", label: "CI running", tone: "arc", rank: 3 };
    return { k: "waiting", label: "Waiting for review", tone: "muted", rank: 3 };
  }

  const SUMMARY = [["ready", "ready"], ["you", "for you"], ["blocked", "blocked"]];

  function signal(label, state) {
    const glyph = { ok: "✓", err: "✕", run: "◌", wait: "·" }[state];
    return h("span", { class: "row pr-signal " + state }, h("span", { class: "glyph" }, glyph), label);
  }

  function prRow(pr) {
    const v = prVerdict(pr);
    const ciState = { success: "ok", failure: "err", pending: "run" }[pr.ci] || "wait";
    const rvState = { approved: "ok", changesRequested: "err" }[pr.review] || "wait";
    const rvLabel = { approved: "approved", changesRequested: "changes", reviewRequired: "review requested" }[pr.review] || "no review";
    return h("button", { class: "card pr-row tone-" + v.tone, onClick: () => go(`#/pr/${encodeURIComponent(pr.repoId)}/${encodeURIComponent(pr.number)}`) },
      h("span", { class: "verdict-bar" }),
      h("div", { class: "row r1" },
        h("span", { class: "row verdict" }, v.tone === "arc" ? spinner(8) : null, v.label),
        // GitHub will merge it by itself once requirements pass.
        pr.autoMerge ? h("span", { class: "row automerge-tag" }, h("span", { class: "glyph" }, "⑂"), "auto-merge") : null,
        spacer(),
        h("span", { class: "mono pr-updated" }, ago(pr.updatedAt))),
      h("div", { class: "pr-title" }, pr.title),
      h("div", { class: "row r3" },
        h("span", { class: "mono pr-meta" }, `${pr.repo} #${pr.number}`),
        signal("CI", ciState),
        signal(rvLabel, rvState),
        spacer(),
        h("span", { class: "chev" }, "›")));
  }

  function viewPRList() {
    const st = S.data.state;
    const all = S.data.lists.all || [];
    const rows = all.map((pr, i) => ({ pr, v: prVerdict(pr), i }))
      .sort((x, y) => x.v.rank - y.v.rank || x.i - y.i);
    const counts = rows.reduce((m, r) => (m[r.v.k] = (m[r.v.k] || 0) + 1, m), {});
    const f = S.filter;
    const shown = f ? rows.filter((r) => r.v.k === f) : rows;
    const ptrText = { pull: "pull to sync", ready: "release to sync", syncing: "syncing on your mac" }[S.ptr.state];
    let content;
    if (!S.data.listLoaded.all) content = loadingBlock("loading");
    else if (!shown.length) {
      const label = f ? { ready: "Nothing ready to merge", you: "Nothing needs your review", blocked: "Nothing blocked" }[f] : "No open pull requests";
      content = emptyBlock(label,
        st && st.reposShown < st.reposTotal ? `Showing ${st.reposShown} of ${st.reposTotal} repositories — change it in Settings.` : "Pull down to sync now.");
    } else content = h("div", { class: "stack" }, shown.map((r) => prRow(r.pr)));
    return screen([
      header({
        eyebrow: "AERIE · REMOTE", title: "Pull Requests",
        right: h("div", { class: "row live-clock" }, h("span", { class: "dot ok live" }), h("span", { class: "mono", "data-countdown": "" }, countdownText())),
      }),
      h("div", { class: "row summary-row" }, SUMMARY.map(([k, label]) =>
        h("button", {
          class: "col summary-tile " + k + (f === k ? " active" : ""),
          "aria-pressed": f === k ? "true" : "false",
          onClick: () => { saveScroll(); S.filter = S.filter === k ? null : k; render(); },
        },
          h("span", { class: "mono n" }, String(S.data.listLoaded.all ? counts[k] || 0 : "–")),
          h("span", { class: "l" }, label)))),
      h("div", { class: "scroll", "data-sid": "prs:" + (f || "all") },
        h("div", { class: "ptr" + (S.ptr.state === "syncing" ? "" : ""), style: { height: S.ptr.state === "syncing" ? "40px" : "0px" } },
          S.ptr.state === "syncing" ? spinner(11) : null,
          h("span", { class: "hud-note" }, ptrText || "")),
        content),
    ], { tab: "prs" });
  }

  function attachPullToRefresh(sc) {
    const ind = sc.querySelector(".ptr");
    const label = ind && ind.querySelector(".hud-note");
    if (!ind) return;
    let startY = null, dy = 0;
    sc.addEventListener("touchstart", (e) => {
      touching = true;
      startY = sc.scrollTop <= 0 && S.ptr.state === "idle" ? e.touches[0].clientY : null;
      dy = 0;
    }, { passive: true });
    sc.addEventListener("touchmove", (e) => {
      if (startY == null) return;
      dy = e.touches[0].clientY - startY;
      if (dy <= 0 || sc.scrollTop > 0) { ind.style.height = "0px"; return; }
      e.preventDefault();
      ind.classList.add("dragging");
      ind.style.height = Math.min(dy * 0.5, 80) + "px";
      if (label) label.textContent = dy > 120 ? "release to sync" : "pull to sync";
    }, { passive: false });
    const end = () => {
      touching = false;
      ind.classList.remove("dragging");
      if (startY != null && dy > 120) {
        startY = null;
        return pullRefresh();
      }
      startY = null;
      ind.style.height = S.ptr.state === "syncing" ? "40px" : "0px";
      if (pendingRender) render();
    };
    sc.addEventListener("touchend", end);
    sc.addEventListener("touchcancel", end);
  }

  async function pullRefresh() {
    S.ptr = { state: "syncing" };
    render();
    try {
      await api("m/api/refresh", { method: "POST" });
      await new Promise((r) => setTimeout(r, 2000));
    } catch (err) {
      S.ptr = { state: "idle" };
      fail(err, "Sync failed");
      if (S.gate === "ready") render();
      return;
    }
    S.ptr = { state: "idle" };
    if (S.route.name === "prs") await poll(false);
    render();
  }

  // ── Review (SEReview) ──────────────────────────────────────────────
  function backToList() { go("#/prs"); }

  function ciPill(ci) {
    const tone = { success: "ok", failure: "err", pending: "warn" }[ci];
    return h("span", { class: "pill hdr-pill" + (tone ? " " + tone : "") }, h("span", { class: "dot " + ciDot(ci) }), ci === "none" ? "NO CI" : "CI");
  }

  function viewReview() {
    const route = S.route;
    const slot = S.data.detail[route.key];
    const d = slot && slot.data;
    const back = backToList;
    if (slot && slot.notFound) {
      return screen([
        header({ back, eyebrow: `PR · #${route.number}`, title: "Review" }),
        h("div", { class: "scroll", "data-sid": "pr:" + route.key },
          emptyBlock("This pull request is no longer open", "It was merged or closed elsewhere, or your Mac stopped tracking it."),
          h("div", { class: "row", style: { justifyContent: "center" } }, h("button", { class: "btn", style: { height: "48px", padding: "0 22px" }, onClick: back }, "Back to Pull Requests"))),
      ]);
    }
    if (!d) {
      return screen([header({ back, eyebrow: `PR · #${route.number}`, title: "Review" }), loadingBlock("loading")]);
    }
    const pr = d.pr;
    const files = S.data.files[route.key];
    const nFiles = pr.changedFiles != null ? pr.changedFiles : files ? files.files.length : null;
    const body = h("div", { class: "stack-lg" },
      h("div", { class: "rv-title" }, pr.title),
      h("div", { class: "row rv-meta" },
        delta(pr.additions, pr.deletions),
        h("span", { class: "mono who" }, (nFiles != null ? `${nFiles} file${nFiles === 1 ? "" : "s"} · ` : "") + pr.author)),
      aiCard(d, route),
      filesBlock(route, files));
    const overlay = S.sheet ? (S.sheet.kind === "merge" ? mergeSheet(d, route) : approveSheet(d, route)) : null;
    return screen([
      header({ back, eyebrow: `${pr.repo} · #${pr.number}`.toUpperCase(), title: "Review", right: ciPill(pr.ci) }),
      h("div", { class: "scroll", "data-sid": "pr:" + route.key }, body),
    ], { bar: actionBar(d, route), overlay });
  }

  function summaryLines(md) {
    return String(md || "").split(/\r?\n/)
      .map((l) => l.replace(/^\s*(?:[-*+]|\d+[.)])\s+/, "").replace(/^#{1,6}\s+/, "").replace(/\*\*([^*]+)\*\*/g, "$1").replace(/`([^`]+)`/g, "$1").trim())
      .filter(Boolean);
  }

  function aiCard(d, route) {
    const ai = d.aiReview;
    if (ai.phase === "running") {
      const actor = ai.actedAs || d.approve.approver;
      const lines = (ai.lines || []).slice(-6);
      return h("div", { class: "card ai-card" },
        h("div", { class: "row ai-head" }, h("span", { class: "arc-ring" }), h("span", { class: "ai-head-label" }, "CLAUDE ON YOUR MAC")),
        h("div", { class: "console" },
          actor ? h("div", { class: "ln-arc console-line" }, "› acting as " + actor) : null,
          lines.map((l) => h("div", { class: "console-line" }, "› " + l)),
          h("div", null, h("span", { class: "caret" }))));
    }
    if (ai.phase === "done") {
      const ok = ai.verdict === "approve";
      const tone = ok ? "ok" : "err";
      return h("div", { class: "card ai-card " + tone },
        h("div", { class: "verdict " + tone }, ok ? "✓ AI REVIEW · APPROVED" : "⚠ AI REVIEW · ISSUES FOUND"),
        ai.summary ? h("div", { class: "ai-summary" }, summaryLines(ai.summary).map((l) => h("div", null, l))) : null,
        (ai.issues || []).map((issue, i) =>
          h("div", { class: "row ai-issue" },
            h("span", { class: "mono num " + (ok ? "c-ok" : "c-err") }, pad2(i + 1)),
            h("span", { class: "txt" }, issue))),
        ai.actedAs ? h("div", { class: "hud-note", style: { marginTop: "10px" } }, "as " + ai.actedAs) : null);
    }
    if (ai.phase === "failed") {
      return h("div", { class: "card ai-card err" },
        h("div", { class: "verdict err" }, "✕ AI REVIEW · FAILED"),
        h("div", { class: "ai-summary" }, h("div", null, ai.error || "The review didn't finish.")),
        h("div", { class: "row ai-foot" }, h("button", { class: "btn ghost sm", style: { boxShadow: "inset 0 0 0 1px var(--glass-line)" }, onClick: () => aiStop(route) }, "Dismiss")));
    }
    return null;
  }

  function filesBlock(route, files) {
    if (!files) return h("div", { class: "card", style: { padding: "18px 14px" } }, progress(), h("div", { class: "hud-note", style: { marginTop: "10px" } }, "loading diff"));
    if (files.error) return h("div", { class: "card diff-note" }, "Couldn't load the diff: " + files.error);
    if (!files.files.length) return h("div", { class: "card diff-note" }, "No file changes.");
    const open = S.data.expanded[route.key] || new Set();
    return files.files.map((f, i) => fileCard(route, f, i, open.has(i)));
  }

  const MAX_LINES_PER_FILE = 1500;
  function fileCard(route, f, i, isOpen) {
    const name = String(f.filename || "");
    const slash = name.lastIndexOf("/");
    const base = slash >= 0 ? name.slice(slash + 1) : name;
    const dir = slash >= 0 ? name.slice(0, slash + 1) : "";
    const statusPill = f.status === "added" ? h("span", { class: "pill ok file-status" }, "new")
      : f.status === "removed" ? h("span", { class: "pill err file-status" }, "deleted")
        : f.status === "renamed" ? h("span", { class: "pill file-status" }, "renamed") : null;
    const head = h("button", {
      class: "row file-head", "aria-expanded": isOpen ? "true" : "false",
      onClick: () => {
        const set = S.data.expanded[route.key] || (S.data.expanded[route.key] = new Set());
        if (set.has(i)) set.delete(i); else set.add(i);
        render();
      },
    },
    h("span", { class: "file-caret" }, isOpen ? "▾" : "▸"),
    h("span", { class: "col file-names" },
      h("span", { class: "mono file-name" }, base),
      dir ? h("span", { class: "mono file-dir" }, dir) : null),
    spacer(),
    statusPill,
    h("span", { class: "mono n add" }, "+" + (f.additions ?? 0)),
    h("span", { class: "mono n del" }, "−" + (f.deletions ?? 0)));
    const kids = [head];
    if (isOpen) {
      const hunks = f.hunks || [];
      if (f.binary || !hunks.length) kids.push(h("div", { class: "diff-note" }, "No textual diff"));
      else {
        let budget = MAX_LINES_PER_FILE, cut = 0;
        for (const hk of hunks) {
          if (budget <= 0) { cut += (hk.lines || []).length; continue; }
          kids.push(h("div", { class: "diff-hunk sm" }, hk.header));
          for (const ln of hk.lines || []) {
            if (budget-- <= 0) { cut++; continue; }
            kids.push(diffLine(ln));
          }
        }
        if (cut > 0) kids.push(h("div", { class: "diff-note" }, `${cut} more lines — open it on your Mac.`));
      }
    }
    return h("div", { class: "card file-card" + (isOpen ? " open" : "") }, kids);
  }

  function diffLine(ln) {
    const add = ln.kind === "addition", del = ln.kind === "deletion";
    const no = del ? ln.oldNo : ln.newNo;
    return h("div", { class: "dl" + (add ? " add-ln" : del ? " del-ln" : "") },
      h("span", { class: "no" }, no != null ? no : ""),
      h("span", { class: "code" }, (add ? "+ " : del ? "- " : "  ") + (ln.text ?? "")));
  }

  function actionBar(d, route) {
    const pr = d.pr, ai = d.aiReview;
    const notes = [];
    let btns;
    if (pr.review === "approved") {
      const merging = d.actions.merge.phase === "running";
      if (d.merge.blockReason && !merging) notes.push(d.merge.blockReason);
      if (d.actions.merge.phase === "failed" && d.actions.merge.error) notes.push({ warn: d.actions.merge.error });
      btns = [
        h("div", { class: "row approved-chip" }, "✓ APPROVED"),
        h("button", { class: "btn amber wide", disabled: !!d.merge.blockReason || merging, onClick: () => openSheet("merge") },
          merging ? [spinner(), " MERGING…"] : "⑂ MERGE"),
      ];
    } else {
      const running = ai.phase === "running";
      const approving = d.actions.approve.phase === "running";
      if (!d.approve.canApprove && d.approve.blockedReason && !approving) notes.push(d.approve.blockedReason);
      if (!running && !ai.available && ai.unavailableReason) notes.push(ai.unavailableReason);
      if (d.actions.approve.phase === "failed" && d.actions.approve.error) notes.push({ warn: d.actions.approve.error });
      btns = [
        running
          ? h("button", { class: "btn arc", disabled: !ai.canStop, onClick: () => aiStop(route), "aria-label": ai.canStop ? "Stop AI review" : "AI review running" }, spinner(), " REVIEWING")
          : h("button", { class: "btn", disabled: !ai.available, onClick: () => aiStart(route) }, "✦ AI REVIEW"),
        h("button", { class: "btn amber", disabled: !d.approve.canApprove || approving, onClick: () => openSheet("approve") },
          approving ? [spinner(), " APPROVING"] : "✓ APPROVE"),
      ];
    }
    return h("div", { class: "actionbar" },
      notes.length ? h("div", { class: "bar-notes" }, notes.map((n) => typeof n === "string" ? h("div", { class: "bar-note" }, n) : h("div", { class: "bar-note warn" }, n.warn))) : null,
      h("div", { class: "row bar-btns" }, btns));
  }

  async function aiStart(route) {
    const slot = S.data.detail[route.key];
    try {
      const ai = await api(prPath(route.repoId, route.number) + "/ai-review", { method: "POST" });
      if (slot && slot.data && ai && ai.phase) slot.data.aiReview = ai;
      render();
      poll(false);
    } catch (err) { fail(err, "AI review"); }
  }
  async function aiStop(route) {
    const slot = S.data.detail[route.key];
    try {
      const ai = await api(prPath(route.repoId, route.number) + "/ai-review", { method: "DELETE" });
      if (slot && slot.data && ai && ai.phase) slot.data.aiReview = ai;
      render();
      poll(false);
    } catch (err) { fail(err, "AI review"); }
  }

  // ── Sheets (approve / merge) ───────────────────────────────────────
  function openSheet(kind) { S.sheet = { kind, running: false, error: null, shown: false }; render(); }
  function closeSheet() { if (S.sheet && S.sheet.running) return; S.sheet = null; render(); }

  function sheetShell(kids) {
    // Only the first paint of an opening animates in; repaints (running,
    // error) keep it still instead of sliding it up again.
    const settled = S.sheet && S.sheet.shown;
    if (S.sheet) S.sheet.shown = true;
    return h("div", { class: "sheet-wrap" + (settled ? " settled" : "") },
      h("div", { class: "sheet-dim", onClick: closeSheet }),
      h("div", { class: "sheet", role: "dialog", "aria-modal": "true" }, h("div", { class: "sheet-grip" }), kids));
  }
  const kv = (k, v) => h("div", { class: "row kv" }, h("span", { class: "mono k" }, k), h("span", { class: "mono v" }, v));

  function approveSheet(d, route) {
    const sh = S.sheet, pr = d.pr;
    const who = d.approve.approver || "the resolved account";
    return sheetShell([
      h("div", { class: "section-eyebrow hdr-eyebrow" }, `${pr.repo} · #${pr.number}`.toUpperCase()),
      h("div", { class: "sheet-title" }, "Approve pull request?"),
      h("div", { class: "sheet-body" }, `Approve as ${who}.`),
      h("div", { class: "kvs" },
        kv("pr", pr.title),
        kv("author", pr.author),
        kv("account", who)),
      sh.running ? h("div", { class: "col sheet-running" }, progress(), h("span", { class: "hud-note" }, "approving on " + (d.merge.host || "github"))) : null,
      sh.error ? h("div", { class: "sheet-error" }, sh.error) : null,
      h("div", { class: "row sheet-btns" },
        h("button", { class: "btn ghost cancel", disabled: sh.running, onClick: closeSheet }, "Cancel"),
        h("button", { class: "btn amber go", disabled: sh.running, onClick: () => doApprove(route) },
          sh.running ? [spinner(), " APPROVING…"] : "✓ APPROVE")),
    ]);
  }

  function mergeSheet(d, route) {
    const sh = S.sheet, pr = d.pr, m = d.merge;
    const host = m.host || "github.com";
    const checks = pr.ci === "success" ? h("span", { class: "c-ok" }, "✓ checks")
      : pr.ci === "failure" ? h("span", { class: "c-err" }, "✕ checks failing")
        : pr.ci === "pending" ? h("span", { class: "c-warn" }, "◷ checks running")
          : h("span", { class: "c-dim" }, "no checks");
    return sheetShell([
      h("div", { class: "section-eyebrow hdr-eyebrow" }, `${pr.repo} · #${pr.number}`.toUpperCase()),
      h("div", { class: "sheet-title" }, "Merge pull request?"),
      h("div", { class: "sheet-body" }, `Squash and merge as ${loginOf(m.account)}. The source branch is deleted on ${host} afterwards.`),
      h("div", { class: "row sheet-checks" },
        checks,
        pr.review === "approved" ? h("span", { class: "c-ok" }, "✓ approved") : null,
        delta(pr.additions, pr.deletions)),
      h("div", { class: "kvs" },
        kv("method", m.method === "squash" ? "squash + merge" : String(m.method || "")),
        kv("commit", m.commitTitle || `${pr.title} (#${pr.number})`),
        kv("account", m.account || "")),
      sh.running ? h("div", { class: "col sheet-running" }, progress(), h("span", { class: "hud-note" }, "squashing on " + host)) : null,
      sh.error ? h("div", { class: "sheet-error" }, sh.error) : null,
      h("div", { class: "row sheet-btns" },
        h("button", { class: "btn ghost cancel", disabled: sh.running, onClick: closeSheet }, "Cancel"),
        h("button", { class: "btn amber go", disabled: sh.running, onClick: () => doMerge(route) },
          sh.running ? [spinner(), " MERGING…"] : "⑂ SQUASH & MERGE")),
    ]);
  }

  async function doApprove(route) {
    if (!S.sheet || S.sheet.running) return;
    S.sheet.running = true; S.sheet.error = null;
    render();
    try {
      await api(prPath(route.repoId, route.number) + "/approve", { method: "POST", body: {}, timeout: 90000 });
    } catch (err) {
      if (err instanceof HttpError && err.status === 401) return;
      if (!S.sheet) return;
      S.sheet.running = false;
      S.sheet.error = err instanceof OfflineError ? "Lost the connection to your Mac. Check the PR before trying again." : err.message;
      return render();
    }
    S.sheet = null;
    try { await loadDetail(route); } catch (err) { fail(err); }
    render();
    schedulePoll();
  }

  async function doMerge(route) {
    if (!S.sheet || S.sheet.running) return;
    S.sheet.running = true; S.sheet.error = null;
    render();
    const slot = S.data.detail[route.key];
    let result;
    try {
      result = await api(prPath(route.repoId, route.number) + "/merge", { method: "POST", timeout: 120000 });
    } catch (err) {
      if (err instanceof HttpError && err.status === 401) return;
      if (!S.sheet) return;
      S.sheet.running = false;
      S.sheet.error = err instanceof OfflineError ? "Lost the connection to your Mac. Check the PR before trying again." : err.message;
      return render();
    }
    S.merged = { pr: slot && slot.data ? slot.data.pr : { repo: "", number: route.number }, result };
    S.sheet = null;
    delete S.data.detail[route.key];
    S.data.listLoaded = {};
    go("#/merged");
  }

  // ── Merged (SEMerged) ──────────────────────────────────────────────
  function viewMerged() {
    const { pr, result } = S.merged;
    const back = () => { S.merged = null; go("#/prs"); };
    const sha = String(result.sha || "").slice(0, 7);
    return screen([
      header({ back, eyebrow: `${pr.repo} · #${pr.number}`.toUpperCase(), title: "Merged", right: h("span", { class: "pill ok hdr-pill" }, "closed") }),
      h("div", { class: "merged-hero" },
        h("span", { class: "ring r1" }), h("span", { class: "ring r2" }),
        h("div", { class: "merged-badge" }, "⑂"),
        h("div", { class: "col merged-text" },
          h("span", { class: "t" }, "Squashed into " + (result.base || "base")),
          h("span", { class: "mono" }, [sha, result.branchDeleted === false ? "branch kept" : "branch deleted"].filter(Boolean).join(" · ")))),
      h("div", { class: "col merged-foot" },
        result.macHasBranchCheckedOut
          ? h("div", { class: "row arc-banner" },
            h("span", { class: "dot arc live" }),
            h("span", { class: "txt" }, "Your Mac will offer to reset ", h("span", { class: "mono" }, result.branch || pr.branch || "the branch"), " next time it’s open"))
          : null,
        h("button", { class: "btn", onClick: back }, "Back to Pull Requests")),
    ]);
  }

  // ── Repos (SERepos) ────────────────────────────────────────────────
  function viewRepos() {
    const r = S.data.repos;
    const st = S.data.state;
    const mac = (r && r.macName) || (st && st.macName) || "your Mac";
    let content;
    if (!r) content = loadingBlock("loading");
    else if (!r.repos.length) content = emptyBlock("No repositories shown", "Turn some on in Settings › Repositories shown.");
    else {
      content = h("div", { class: "stack" }, r.repos.map((repo) => {
        const noStatus = repo.branch == null;
        return h("div", { class: "card repo-card" },
          h("div", { class: "row r1" },
            h("span", { class: "dot " + (noStatus ? "muted" : repo.dirty ? "err" : "ok") }),
            h("span", { class: "repo-name" }, repo.name),
            spacer(),
            repo.behind > 0 ? h("span", { class: "mono ab c-warn" }, "↓" + repo.behind) : null,
            repo.ahead > 0 ? h("span", { class: "mono ab c-ok" }, "↑" + repo.ahead) : null),
          h("div", { class: "row r2" },
            noStatus
              ? h("span", { class: "mono repo-branch none" }, "no local status yet")
              : [
                h("span", { class: "mono repo-branch" }, repo.branch),
                repo.defaultBranch && repo.branch !== repo.defaultBranch ? h("span", { class: "pill amber mini-pill" }, "off default") : null,
                repo.dirty ? h("span", { class: "pill err mini-pill" }, repo.dirtyCount ? `dirty · ${repo.dirtyCount}` : "dirty") : null,
              ]));
      }));
    }
    return screen([
      header({ eyebrow: "AERIE · REMOTE", title: "Repositories", right: r ? h("span", { class: "pill hdr-pill" }, r.repos.length) : null }),
      h("div", { class: "row arc-banner repos-banner" },
        h("span", { class: "dot arc live" }),
        h("span", { class: "txt" }, "Linked to ", h("b", null, mac), " · checkout and reset run there")),
      h("div", { class: "scroll", "data-sid": "repos" }, content),
    ], { tab: "repos" });
  }

  // ── Settings (SESettings) ──────────────────────────────────────────
  function srow(k, v, { tone, onClick } = {}) {
    const kids = [
      h("span", { class: "k" }, k),
      h("span", { class: "mono v", style: tone ? { color: tone } : null }, v),
      onClick ? h("span", { class: "chev-s" }, "›") : null,
    ];
    return onClick ? h("button", { class: "srow", onClick }, kids) : h("div", { class: "srow" }, kids);
  }
  const group = (label, card, amber) =>
    h("div", { class: "col group" }, h("span", { class: "hud-note" }, label), h("div", { class: "card" + (amber ? " amber-edge" : "") }, card));

  function viewSettings() {
    const s = S.data.settings, st = S.data.state;
    if (!s) return screen([header({ eyebrow: "AERIE · REMOTE", title: "Settings" }), loadingBlock("loading")], { tab: "settings" });
    const poll = s.pollSeconds != null ? s.pollSeconds : st && st.pollSeconds;
    return screen([
      header({ eyebrow: "AERIE · REMOTE", title: "Settings" }),
      h("div", { class: "scroll", "data-sid": "settings" },
        h("div", { class: "settings" },
          group("linked mac", [
            srow(s.macName || (st && st.macName) || "Mac", "online", { tone: "var(--arc)" }),
            srow("Polling", poll != null ? poll + "s" : "—"),
          ]),
          group("lists", [
            srow("Repositories shown", st ? `${st.reposShown} of ${st.reposTotal}` : "…", { tone: "var(--amber)", onClick: () => go("#/settings/repos") }),
          ], true),
          group("ai review", [
            srow("Model", s.model || "—", { tone: "var(--amber)" }),
            srow("Approve as", s.approveAs || "—"),
          ]),
          group("this device", [
            srow("Device", s.deviceName || deviceName()),
            srow("Version", s.version || (st && st.version) || "—"),
          ]),
          h("button", { class: "btn danger signout", onClick: signOut }, "Sign out this device"))),
    ], { tab: "settings" });
  }

  async function signOut() {
    if (!window.confirm("Sign out this iPhone? You'll need to approve it on your Mac and set up Face ID again.")) return;
    try {
      await api("m/api/logout", { method: "POST" });
    } catch (err) {
      if (err instanceof OfflineError) return toast("Couldn't reach your Mac to sign out. Try again when it's online.");
      // 401: the session is already gone on the Mac; clear locally anyway.
    }
    stopPolling();
    store.deviceId = null;
    store.session = null;
    S.data = freshData();
    S.merged = null;
    S.sheet = null;
    history.replaceState(null, "", "#/prs");
    S.gate = "pair";
    S.pair = { phase: "idle", error: null, pending: null };
    render();
  }

  // ── Settings › Repositories shown (SERepoFilter) ───────────────────
  let filterSeq = 0;
  async function saveFilter(next) {
    const prev = S.data.repoFilter;
    S.data.repoFilter = next;
    render();
    const seq = ++filterSeq;
    try {
      const r = await api("m/api/settings/repos", { method: "PUT", body: { hiddenRepoIds: next.filter((x) => !x.shown).map((x) => x.id) } });
      if (seq !== filterSeq) return;
      S.data.repoFilter = r.repos || next;
      S.data.listLoaded = {};
      S.data.repos = null;
      try { setState(await api("m/api/state")); } catch { /* next poll */ }
      render();
    } catch (err) {
      if (seq !== filterSeq) return;
      S.data.repoFilter = prev;
      fail(err, "Couldn't save");
      if (S.gate === "ready") render();
    }
  }

  function viewRepoFilter() {
    const rows = S.data.repoFilter;
    const back = () => go("#/settings");
    const shown = rows ? rows.filter((r) => r.shown).length : 0;
    let content;
    if (!rows) content = loadingBlock("loading");
    else if (!rows.length) content = emptyBlock("No repositories", "Add repositories in Aerie on your Mac.");
    else {
      content = h("div", { class: "rf-list" }, h("div", { class: "card" }, rows.map((r) =>
        h("button", {
          class: "rf-row" + (r.shown ? " on" : ""), role: "switch", "aria-checked": r.shown ? "true" : "false",
          onClick: () => saveFilter(rows.map((x) => (x.id === r.id ? { ...x, shown: !x.shown } : x))),
        },
        h("span", { class: "dot " + (r.shown ? (r.dirty ? "err" : "ok") : "muted") }),
        h("span", { class: "col rf-text" },
          h("span", { class: "rf-name" }, r.name),
          h("span", { class: "mono rf-slug" }, r.slug)),
        h("span", { class: "toggle" })))));
    }
    return screen([
      header({ back, eyebrow: "SETTINGS", title: "Repositories", right: rows ? h("span", { class: "pill amber hdr-pill" }, `${shown} / ${rows.length}`) : null }),
      h("div", { class: "row rf-intro" }, h("span", null, "Choose which repos appear in Pull Requests and Repos on this phone.")),
      h("div", { class: "row rf-btns" },
        h("button", { class: "btn sm", disabled: !rows, onClick: () => saveFilter(rows.map((x) => ({ ...x, shown: true }))) }, "Show all"),
        h("button", { class: "btn ghost sm", disabled: !rows, onClick: () => saveFilter(rows.map((x) => ({ ...x, shown: !!x.hasMyOpenPR }))) }, "Only mine")),
      h("div", { class: "scroll", "data-sid": "repofilter" }, content),
    ], { tab: "settings" });
  }

  // ── Start ──────────────────────────────────────────────────────────
  if ("serviceWorker" in navigator && isSecure()) {
    navigator.serviceWorker.register("sw.js").catch(() => {});
  }
  boot();
})();
