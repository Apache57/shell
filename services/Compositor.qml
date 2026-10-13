pragma Singleton

import QtQuick
import Quickshell
import qs.services

// =============================================================================
// WIP — the compositor seam. UNTESTED in this environment (no Quickshell runtime
// and no niri/Hyprland session here). See docs/niri-architecture.md.
//
// Picks a backend at runtime and delegates one stable interface to it, so
// consumers never touch a compositor module directly:
//   * niri      when $NIRI_SOCKET is set        -> services/Niri.qml  (ours)
//   * Hyprland  otherwise                        -> services/Hypr.qml  (upstream)
//
// Backend selection is SHORT-CIRCUITED (`active: isNiri ? Niri : Hypr`), so the
// dormant backend singleton is never referenced and therefore never instantiated
// on the active compositor (AGENTS.md §3.1). This file must not import the
// Quickshell Hyprland module and must not shell out to the Hyprland CLI — it
// reaches Hyprland only through the existing Hypr singleton.
// =============================================================================

Singleton {
    id: root

    readonly property string niriSocket: Quickshell.env("NIRI_SOCKET")
    readonly property string hyprSignature: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")

    readonly property bool isNiri: niriSocket.length > 0
    readonly property bool isHyprland: !isNiri && hyprSignature.length > 0
    // Detection falls back to Hyprland (dormant, inert) when neither is present,
    // matching upstream behaviour on a non-Hyprland session.
    readonly property string backend: isNiri ? "niri" : "hyprland"

    // Short-circuit: only the selected backend singleton is ever referenced here.
    readonly property var active: isNiri ? Niri : Hypr

    // --- delegated state surface (same member names/types as Hypr.qml) -----------
    readonly property var toplevels: active.toplevels
    readonly property var workspaces: active.workspaces
    readonly property var monitors: active.monitors
    readonly property var activeToplevel: active.activeToplevel
    readonly property var focusedWorkspace: active.focusedWorkspace
    readonly property var focusedMonitor: active.focusedMonitor
    readonly property int activeWsId: active.activeWsId
    readonly property bool usingLua: active.usingLua

    readonly property bool capsLock: active.capsLock
    readonly property bool numLock: active.numLock
    readonly property string kbLayout: active.kbLayout
    readonly property string kbLayoutFull: active.kbLayoutFull
    readonly property string defaultKbLayout: active.defaultKbLayout

    readonly property var extras: active.extras
    readonly property var options: active.options
    readonly property var devices: active.devices

    signal configReloaded

    // --- delegated methods -------------------------------------------------------
    function dispatch(request: string): void {
        active.dispatch(request);
    }

    function focusWorkspace(ws: var): void {
        active.focusWorkspace(ws);
    }

    function toggleSpecial(name: string): void {
        active.toggleSpecial(name);
    }

    function cycleSpecialWorkspace(direction: string): void {
        active.cycleSpecialWorkspace(direction);
    }

    function monitorFor(screen: var): var {
        return active.monitorFor(screen);
    }

    function monitorNames(): list<string> {
        return active.monitorNames();
    }

    function trimWsName(name: string): string {
        return active.trimWsName(name);
    }

    function toplevelsForWs(ws: var, ignoredTags = []): list<var> {
        return active.toplevelsForWs(ws, ignoredTags);
    }

    function isToplevelIgnored(toplevel: var, ignoredTags = []): bool {
        return active.isToplevelIgnored(toplevel, ignoredTags);
    }

    // Re-emit the active backend's config-reload signal.
    Connections {
        target: root.active

        function onConfigReloaded(): void {
            root.configReloaded();
        }
    }
}
