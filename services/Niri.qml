pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.I18n

// =============================================================================
// WIP — niri compositor backend. UNTESTED in this environment.
//
// This file could not be run or validated here: there is no Quickshell runtime
// and no niri session in the build environment. It is a grounded first
// implementation (repo idioms + the niri_ipc types), and MUST be validated on a
// live niri session before it is trusted. Do NOT assume it works as-is.
//
// IPC assumptions target niri's `niri_ipc` (Event/Response/Action types as
// documented on docs.rs "latest", verified 2026-10; niri 25.x line). Key shapes:
//   * `niri msg --json event-stream` emits one externally-tagged Event object
//     per line, e.g. {"WorkspacesChanged":{"workspaces":[...]}}. niri sends the
//     complete current state up-front on connect, then live deltas.
//   * `niri msg --json <cmd>` prints the bare payload (array/map/object/null).
//     The docs are not 100% explicit on whether the CLI wraps queries in the
//     Response variant name, so query parsing below defensively unwraps a
//     {"<Variant>": …} envelope if present (see _unwrap). VERIFY on a real box.
//   * There is no output/monitor event in the stream, so outputs are queried and
//     refreshed on WorkspacesChanged (covers monitor hotplug).
//
// Interface parity with services/Hypr.qml is intentional (see AGENTS.md §3.2 and
// docs/niri-architecture.md). Honest gaps are degraded, never faked:
//   * special/scratchpad workspaces: none on niri → toggleSpecial /
//     cycleSpecialWorkspace are no-ops.
//   * capsLock / numLock: not in niri IPC → always false.
//   * runtime compositor-config writes (extras/options/devices): no niri
//     equivalent → neutral no-op surface.
// Per-object field shapes are niri-native (app_id, workspace_id, …); the Hypr
// consumers that still read Hyprland-only fields (lastIpcObject.class, .wayland,
// .tags, special workspaces) are migrated/adapted in later milestones (M2–M6),
// not here.
// =============================================================================

Singleton {
    id: root

    // --- reactive models (each exposes a plain JS array `values`, like Hypr.*.values) ---
    readonly property alias workspaces: workspacesModel
    readonly property alias toplevels: toplevelsModel
    readonly property alias monitors: monitorsModel

    // --- authoritative raw state fed from the event stream (+ query fallback) ---
    property var _rawWorkspaces: []
    property var _rawWindows: []
    property var _rawOutputs: ({})
    property int _focusedWindowId: -1
    property var _kbNames: []
    property int _kbCurrentIdx: 0
    // Once the event stream has seeded a domain it is authoritative; late query
    // results for that domain are dropped so they can never resurrect stale state.
    property var _seeded: ({
            workspaces: false,
            windows: false,
            focused: false,
            layouts: false
        })

    // --- derived focus/active surface (mirrors Hypr member names) ---
    readonly property string _focusedOutput: focusedWorkspace?.output ?? ""
    readonly property var focusedWorkspace: workspacesModel.values.find(w => w.focused) ?? null
    readonly property var focusedMonitor: monitorsModel.values.find(m => m.name === _focusedOutput) ?? monitorsModel.values.find(m => m.focused) ?? monitorsModel.values[0] ?? null
    readonly property var activeToplevel: toplevelsModel.values.find(t => t.id === _focusedWindowId) ?? null
    readonly property int activeWsId: focusedWorkspace?.id ?? 1

    // Hyprland-only; present for interface parity. niri has no Lua dispatch, so
    // consumers' `usingLua ? "hl.dsp…" : "…"` branches take the text path.
    readonly property bool usingLua: false

    // niri's IPC does not expose keyboard lock state — report false, never faked.
    readonly property bool capsLock: false
    readonly property bool numLock: false

    // Keyboard layout from `keyboard-layouts` (names + current_idx) and the
    // KeyboardLayoutSwitched / KeyboardLayoutsChanged events. niri reports
    // human-readable xkb names (e.g. "English (US)"); the short code is derived.
    readonly property string kbLayoutFull: _kbNames[_kbCurrentIdx] ?? Tr.trCtx("Unknown", "keyboard layout")
    readonly property string kbLayout: _shortLayout(kbLayoutFull)
    readonly property string defaultKbLayout: _kbNames.length > 0 ? _shortLayout(_kbNames[0]) : "??"

    // Runtime compositor-config surface — no niri equivalent (see parity doc ⛔).
    readonly property alias extras: extrasObj
    readonly property alias options: extrasObj.options
    readonly property alias devices: extrasObj.devices

    // Interface parity only; niri has no special workspaces.
    property string lastSpecialWorkspace: ""

    signal configReloaded

    // --- dispatch / actions ------------------------------------------------------

    function dispatch(request: string): void {
        // niri actions are structured. Forward whitespace-separated tokens to
        // `niri msg action`. Hyprland dispatcher strings do NOT translate 1:1 — a
        // migrated consumer should call a structured helper (focusWorkspace, …) or
        // a real niri action name. Best-effort passthrough; see docs/niri-parity.md.
        const parts = (request ?? "").trim().split(/\s+/).filter(Boolean);
        if (parts.length === 0)
            return;
        _action(parts);
    }

    function focusWorkspace(ws: var): void {
        // niri reads a numeric reference as the workspace *index* (1-based) and a
        // non-numeric one as a workspace name. Workspace identity differs from
        // Hyprland (per-output, dynamic ids) — see docs/niri-parity.md.
        _action(["focus-workspace", String(ws)]);
    }

    function toggleSpecial(name: string): void {
        // niri has no special/scratchpad workspaces — no-op (parity doc ⛔).
    }

    function cycleSpecialWorkspace(direction: string): void {
        // niri has no special/scratchpad workspaces — no-op (parity doc ⛔).
    }

    // --- helpers consumers read off the Hypr service (parity) --------------------

    function monitorFor(screen: var): var {
        return monitorsModel.values.find(m => m.name === screen?.name) ?? null;
    }

    function monitorNames(): list<string> {
        return monitorsModel.values.map(m => m.name);
    }

    function trimWsName(name: string): string {
        // niri workspace names carry no "special:" prefix; nothing to trim.
        return name ?? "";
    }

    function toplevelsForWs(ws: var, ignoredTags = []): list<var> {
        return toplevelsModel.values.filter(t => t.lastIpcObject.workspace_id === ws && !isToplevelIgnored(t, ignoredTags));
    }

    function isToplevelIgnored(toplevel: var, ignoredTags = []): bool {
        const ipc = toplevel?.lastIpcObject;
        if (!ipc)
            return true;
        // niri has no window tags; mirror Hypr's "no class" guard with app_id.
        return !ipc.app_id;
    }

    // --- internals ---------------------------------------------------------------

    function _shortLayout(name: string): string {
        if (!name)
            return "??";
        // "English (US)" -> "US"; "Russian" -> "ru".
        const m = name.match(/\(([^)]+)\)\s*$/);
        if (m) {
            const inner = m[1].trim();
            return (inner.split(/[,\s-]/)[0] || inner).slice(0, 2).toUpperCase();
        }
        return name.slice(0, 2).toLowerCase();
    }

    function _run(cmd: list<string>, cb: var): void {
        const p = cmdProc.createObject(root, {
            done: cb
        });
        if (!p) {
            console.warn(lc, "Failed to create niri msg process");
            return;
        }
        p.exec(cmd);
    }

    function _action(args: list<string>): void {
        _run(["niri", "msg", "action", ...args], (code, out, err) => {
            if (code !== 0)
                console.warn(lc, `niri action '${args.join(" ")}' failed (${code}): ${(err ?? "").trim()}`);
        });
    }

    function _unwrap(json: var, key: string): var {
        // Defensive: accept both the bare payload and a {"<Variant>": payload}
        // envelope, since the CLI's exact query shape is unverified here.
        if (json && typeof json === "object" && !Array.isArray(json) && json.hasOwnProperty(key))
            return json[key];
        return json;
    }

    function _query(cmd: string, apply: var): void {
        _run(["niri", "msg", "--json", cmd], (code, out, err) => {
            if (code !== 0) {
                console.warn(lc, `niri msg ${cmd} failed (${code}): ${(err ?? "").trim()}`);
                return;
            }
            let json;
            try {
                json = JSON.parse(out);
            } catch (e) {
                console.warn(lc, `Unable to parse 'niri msg ${cmd}': ${e}`);
                return;
            }
            apply(json);
        });
    }

    // Initial state via explicit queries (as a fast first paint); the event stream
    // re-seeds and is authoritative thereafter. Outputs have no event, so they are
    // always applied and refreshed on workspace changes.
    function queryOutputs(): void {
        _query("outputs", j => _applyOutputs(_unwrap(j, "Outputs")));
    }

    function queryWorkspaces(): void {
        _query("workspaces", j => {
            if (root._seeded.workspaces)
                return;
            root._rawWorkspaces = _unwrap(j, "Workspaces") ?? [];
            _syncWorkspaces();
        });
    }

    function queryWindows(): void {
        _query("windows", j => {
            if (root._seeded.windows)
                return;
            root._rawWindows = _unwrap(j, "Windows") ?? [];
            _syncWindows();
        });
    }

    function queryFocusedWindow(): void {
        _query("focused-window", j => {
            if (root._seeded.focused)
                return;
            const w = _unwrap(j, "FocusedWindow");
            root._focusedWindowId = w ? w.id : -1;
        });
    }

    function queryKeyboardLayouts(): void {
        _query("keyboard-layouts", j => {
            if (root._seeded.layouts)
                return;
            const kl = _unwrap(j, "KeyboardLayouts");
            root._kbNames = kl?.names ?? [];
            root._kbCurrentIdx = kl?.current_idx ?? 0;
        });
    }

    // --- event-stream handling ---------------------------------------------------

    function _handleEvent(line: string): void {
        const s = (line ?? "").trim();
        if (!s)
            return;

        let ev;
        try {
            ev = JSON.parse(s);
        } catch (e) {
            console.warn(lc, `Unable to parse niri event: ${e}`);
            return;
        }

        const type = Object.keys(ev)[0];
        const p = ev[type] ?? {};

        switch (type) {
        case "WorkspacesChanged":
            root._rawWorkspaces = p.workspaces ?? [];
            root._seeded.workspaces = true;
            _syncWorkspaces();
            // No output event exists; a monitor hotplug changes the workspace set,
            // so refresh outputs here (debounced to collapse bursts).
            outputsDebounce.restart();
            break;
        case "WorkspaceActivated":
            _activateWorkspace(p.id, p.focused === true);
            break;
        case "WorkspaceActiveWindowChanged":
            // Focused-window changes are tracked via WindowFocusChanged; nothing to do.
            break;
        case "WindowsChanged":
            root._rawWindows = p.windows ?? [];
            root._seeded.windows = true;
            _syncWindows();
            break;
        case "WindowOpenedOrChanged":
            _upsertWindow(p.window);
            break;
        case "WindowClosed":
            _removeWindow(p.id);
            break;
        case "WindowFocusChanged":
            root._focusedWindowId = (p.id === null || p.id === undefined) ? -1 : p.id;
            root._seeded.focused = true;
            break;
        case "KeyboardLayoutsChanged":
            root._kbNames = p.keyboard_layouts?.names ?? [];
            root._kbCurrentIdx = p.keyboard_layouts?.current_idx ?? 0;
            root._seeded.layouts = true;
            break;
        case "KeyboardLayoutSwitched":
            root._kbCurrentIdx = p.idx ?? 0;
            break;
        case "ConfigLoaded":
            if (p.failed !== true)
                root.configReloaded();
            break;
        case "OverviewOpenedOrClosed":
            break;
        default:
            break;
        }
    }

    function _activateWorkspace(id: var, focused: bool): void {
        const act = root._rawWorkspaces.find(w => w.id === id);
        if (!act) {
            root.queryWorkspaces();
            return;
        }
        const output = act.output;
        // Rebuild with fresh objects so wrapper bindings re-evaluate (same-object
        // in-place mutation would not emit lastIpcObjectChanged).
        root._rawWorkspaces = root._rawWorkspaces.map(w => {
            const n = Object.assign({}, w);
            if (n.output === output)
                n.is_active = n.id === id;
            if (focused)
                n.is_focused = n.id === id;
            return n;
        });
        _syncWorkspaces();
    }

    function _upsertWindow(win: var): void {
        if (!win)
            return;
        const next = root._rawWindows.slice();
        const idx = next.findIndex(w => w.id === win.id);
        if (idx >= 0)
            next[idx] = win;
        else
            next.push(win);
        root._rawWindows = next;
        if (win.is_focused) {
            root._focusedWindowId = win.id;
            root._seeded.focused = true;
        }
        _syncWindows();
    }

    function _removeWindow(id: var): void {
        root._rawWindows = root._rawWindows.filter(w => w.id !== id);
        if (root._focusedWindowId === id)
            root._focusedWindowId = -1;
        _syncWindows();
    }

    function _applyOutputs(map: var): void {
        const m = map ?? ({});
        root._rawOutputs = m;
        const list = [];
        let i = 0;
        for (const key of Object.keys(m)) {
            const o = Object.assign({
                name: key,
                _index: i
            }, m[key]);
            if (!o.name)
                o.name = key;
            list.push(o);
            i++;
        }
        _sync(monitorsModel, monComp, list, r => r.name);
    }

    function _syncWorkspaces(): void {
        _sync(workspacesModel, wsComp, root._rawWorkspaces, r => r.id);
    }

    function _syncWindows(): void {
        _sync(toplevelsModel, tlComp, root._rawWindows, r => r.id);
    }

    // Keyed reconcile (same shape as Nmcli.getNetworks): reuse wrappers by key so
    // object identity/bindings stay stable, update their lastIpcObject in place,
    // destroy removed ones, and reassign `values` to notify collection consumers.
    function _sync(model: var, comp: Component, rawList: var, keyOf: var): void {
        const existing = new Map();
        for (const it of model.values)
            existing.set(keyOf(it.lastIpcObject), it);

        const next = [];
        const seen = new Set();
        for (const raw of rawList) {
            const k = keyOf(raw);
            if (seen.has(k))
                continue;
            seen.add(k);

            const cur = existing.get(k);
            if (cur) {
                cur.lastIpcObject = raw;
                next.push(cur);
            } else {
                next.push(comp.createObject(root, {
                    lastIpcObject: raw
                }));
            }
        }

        for (const [k, it] of existing)
            if (!seen.has(k))
                it.destroy();

        model.values = next;
    }

    Component.onCompleted: {
        // Event stream (below) delivers the full current state up-front and keeps
        // it live; these queries are a fast initial seed (guarded so the stream
        // always wins). Outputs have no event and are refreshed here + on changes.
        queryOutputs();
        queryWorkspaces();
        queryWindows();
        queryFocusedWindow();
        queryKeyboardLayouts();
    }

    QtObject {
        id: extrasObj

        // Neutral defaults so QML never sees null. niri cannot be reconfigured
        // over IPC, so every write degrades to a no-op (parity doc ⛔).
        readonly property var options: ({})
        readonly property QtObject devices: QtObject {
            readonly property var keyboards: []
        }

        function applyOptions(opts: var): void {}
        function message(msg: var): void {}
        function batchMessage(msgs: var): void {}
        function refreshOptions(): void {}
        function refreshDevices(): void {}
    }

    QtObject {
        id: workspacesModel

        property var values: []
    }

    QtObject {
        id: toplevelsModel

        property var values: []
    }

    QtObject {
        id: monitorsModel

        property var values: []
    }

    // Long-lived event-stream reader. One externally-tagged Event per line.
    Process {
        id: eventStream

        running: true
        command: ["niri", "msg", "--json", "event-stream"]
        stdout: SplitParser {
            onRead: data => root._handleEvent(data)
        }
        onExited: (code, status) => {
            // qmllint disable signal-handler-parameters
            // niri may have exited/restarted; reconnect. On reconnect the stream
            // re-sends full state, so seeded flags are reset to accept it.
            root._seeded = {
                workspaces: false,
                windows: false,
                focused: false,
                layouts: false
            };
            console.warn(lc, `niri event-stream exited (${code}); reconnecting`);
            streamRestart.start();
        }
    }

    Timer {
        id: streamRestart

        interval: 2000
        onTriggered: eventStream.running = true
    }

    Timer {
        id: outputsDebounce

        interval: 150
        onTriggered: root.queryOutputs()
    }

    Component {
        id: cmdProc

        Process {
            id: proc

            property var done: null

            stdout: StdioCollector {
                id: outCollector
            }
            stderr: StdioCollector {
                id: errCollector
            }

            onExited: code => {
                // qmllint disable signal-handler-parameters
                Qt.callLater(() => {
                    const cb = proc.done;
                    const out = outCollector.text ?? "";
                    const err = errCollector.text ?? "";
                    proc.destroy();
                    cb?.(code, out, err);
                });
            }
        }
    }

    Component {
        id: wsComp

        Workspace {}
    }

    Component {
        id: tlComp

        Toplevel {}
    }

    Component {
        id: monComp

        Monitor {}
    }

    LoggingCategory {
        id: lc

        name: "caelestia.qml.services.niri"
        defaultLogLevel: LoggingCategory.Info
    }

    // --- wrapper types (niri-native fields; see header for Hypr-shape notes) -----

    component Workspace: QtObject {
        required property var lastIpcObject
        readonly property int id: lastIpcObject.id ?? -1
        readonly property int idx: lastIpcObject.idx ?? -1
        readonly property string name: lastIpcObject.name ?? ""
        readonly property string output: lastIpcObject.output ?? ""
        readonly property bool active: lastIpcObject.is_active ?? false
        readonly property bool focused: lastIpcObject.is_focused ?? false
        readonly property bool urgent: lastIpcObject.is_urgent ?? false
        readonly property var activeWindowId: lastIpcObject.active_window_id ?? null
        // Hypr-compatible conveniences.
        readonly property var toplevels: ({
                values: root.toplevelsForWs(id)
            })
        readonly property var monitor: root.monitors.values.find(m => m.name === output) ?? null
    }

    component Toplevel: QtObject {
        required property var lastIpcObject
        readonly property int id: lastIpcObject.id ?? -1
        readonly property string title: lastIpcObject.title ?? ""
        readonly property string appId: lastIpcObject.app_id ?? ""
        readonly property int workspaceId: lastIpcObject.workspace_id ?? -1
        readonly property bool focused: lastIpcObject.is_focused ?? false
        readonly property bool floating: lastIpcObject.is_floating ?? false
        readonly property bool urgent: lastIpcObject.is_urgent ?? false
    }

    component Monitor: QtObject {
        required property var lastIpcObject
        readonly property string name: lastIpcObject.name ?? ""
        // niri has no monitor id; synthesized positional index for parity.
        readonly property int id: lastIpcObject._index ?? -1
        readonly property string make: lastIpcObject.make ?? ""
        readonly property string model: lastIpcObject.model ?? ""
        readonly property bool focused: name.length > 0 && root._focusedOutput === name
        readonly property var logical: lastIpcObject.logical ?? null
        readonly property var activeWorkspace: root.workspaces.values.find(w => w.output === name && w.active) ?? null
    }
}
