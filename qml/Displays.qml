//
// omarchy-displays — macOS-style monitor arrangement for Omarchy
//
// A Quickshell (QML) app. It reads the active Omarchy theme from
// ~/.local/state/omarchy/current/theme/colors.toml and mirrors the shell's
// design tokens (square corners, 1px borders, foreground washes, the mono
// font), so it looks like the rest of Omarchy and re-themes when you switch
// themes. Drag screens to arrange them, set resolution / scale / rotation,
// Apply live, then Save to monitors.lua.
//
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import Quickshell
import Quickshell.Io

ShellRoot {
    id: app

    // ---------------------------------------------------------------- palette
    property string themeName: "omarchy"
    property string uiFont: "monospace"
    property string wallpaper: Quickshell.env("HOME") + "/.local/state/omarchy/current/background"
    property url wallpaperUrl: "file://" + wallpaper

    property var pal: ({
        bg:     "#060B1E",
        popup:  "#04081a",
        text:   "#ffcead",
        muted:  "#6d7db6",
        accent: "#7d82d9",
        danger: "#ED5B5A"
    })

    function parseColors(t) {
        var m = {};
        var re = /^\s*([A-Za-z0-9_-]+)\s*=\s*"?(#[0-9A-Fa-f]{6})/gm, x;
        while ((x = re.exec(t)) !== null) m[x[1]] = x[2];
        if (!m.background && !m.color0) return app.pal;
        return {
            bg:     m.background || m.color0,
            popup:  m.darker_background || m.dark_background || m.background || m.color0,
            text:   m.foreground || m.color7,
            muted:  m.muted || m.dark_foreground || m.color8 || m.foreground,
            accent: m.accent || m.color4 || m.blue,
            danger: m.red || m.color1 || "#ED5B5A"
        };
    }

    // ---- Omarchy shell design tokens (see shell/Commons/Style.qml) ----
    readonly property QtObject sty: QtObject {
        readonly property int radius: 0          // Omarchy is square
        readonly property real borderA: 0.4
        readonly property real hoverBorderA: 0.25
        readonly property real strongBorderA: 0.9
        readonly property real normalFillA: 0.04
        readonly property real hoverFillA: 0.08
        readonly property real pressedFillA: 0.22
        readonly property real selFillA: 0.18
        readonly property real scrimA: 0.5

        readonly property int xs: 3
        readonly property int sm: 4
        readonly property int md: 6
        readonly property int lg: 8
        readonly property int xl: 10
        readonly property int xxl: 12
        readonly property int xxxl: 14
        readonly property int huge: 18
        readonly property int panelPad: 18
        readonly property int panelGap: 14
        readonly property int ctlH: 28
        readonly property int ctlPadX: 10
        readonly property int labelGap: 4

        readonly property int fCaption: 10
        readonly property int fSmall: 11
        readonly property int fBody: 12
        readonly property int fSubtitle: 13
        readonly property int fTitle: 14
        readonly property int fHeading: 16
    }

    function ualpha(c, a) {
        if (typeof c === "string") c = Qt.color(c);
        return Qt.rgba(c.r, c.g, c.b, a);
    }
    // Foreground/accent wash composited over a base, the way the shell paints
    // control fills and borders.
    function wash(base, over, a) { return Qt.tint(base, app.ualpha(over, a)); }

    FileView {
        id: colorsFile
        path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
        watchChanges: true
        printErrors: false
        onLoaded: app.pal = app.parseColors(colorsFile.text())
        onTextChanged: app.pal = app.parseColors(colorsFile.text())
        onFileChanged: reload()
    }
    FileView {
        id: nameFile
        path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
        watchChanges: true
        printErrors: false
        onTextChanged: {
            var s = nameFile.text().trim();
            if (s.length > 0) app.themeName = s;
        }
        onFileChanged: reload()
    }
    Process {
        running: true
        command: ["fc-match", "-f", "%{family[0]}", "monospace"]
        stdout: StdioCollector {
            onStreamFinished: { var s = text.trim(); if (s.length > 0) app.uiFont = s; }
        }
    }

    // --------------------------------------------------------------- monitors
    // Working model: [{name,desc,enabled,x,y,scale,transform,res:{w,h},rr,modes:[{w,h,rr}]}]
    property var monitors: []
    property var baselineMonitors: []
    property int selected: -1
    property int rev: 0
    property bool dirty: false
    property string pendingNote: ""

    function trimNum(s) {
        s = String(s);
        if (s.indexOf(".") >= 0) s = s.replace(/0+$/, "").replace(/\.$/, "");
        return s;
    }
    function fmtScale(s) { return app.trimNum((Math.round(s * 100) / 100).toString()); }

    function logicalSize(m) {
        var w = Math.max(1, Math.round(m.res.w / m.scale));
        var h = Math.max(1, Math.round(m.res.h / m.scale));
        return (m.transform % 2 === 1) ? { w: h, h: w } : { w: w, h: h };
    }

    function nativeArgs(m) {
        if (!m.enabled) return m.name + ",disable";
        return m.name + "," + m.res.w + "x" + m.res.h + "@" + m.rr
             + "," + m.x + "x" + m.y + "," + app.fmtScale(m.scale)
             + ",transform," + m.transform;
    }
    function nativeLines(ms) {
        var out = [];
        for (var i = 0; i < ms.length; i++) out.push("monitor=" + app.nativeArgs(ms[i]));
        return out.join("\n");
    }

    Process { id: readProc; command: ["hyprctl", "-j", "monitors", "all"]
        stdout: StdioCollector { onStreamFinished: app.ingest(text) } }
    // Omarchy rejects `hyprctl keyword`; every write goes through the CLI, which
    // rewrites the managed block in monitors.lua and runs `hyprctl reload`.
    Process { id: runProc
        onRunningChanged: if (!running) { app.dirty = false; toast.show(app.pendingNote); app.refresh(); } }

    function refresh() { readProc.running = true; }
    Component.onCompleted: app.refresh()

    function ingest(json) {
        var arr;
        try { arr = JSON.parse(json); } catch (e) { return; }
        var ms = [];
        for (var i = 0; i < arr.length; i++) {
            var d = arr[i];
            var w = d.width || 1920, h = d.height || 1080;
            var modes = [];
            var am = d.availableModes || [];
            for (var j = 0; j < am.length; j++) {
                var mm = /^(\d+)x(\d+)@([\d.]+)/.exec(am[j]);
                if (mm) modes.push({ w: +mm[1], h: +mm[2], rr: app.trimNum(mm[3]) });
            }
            var curRR = app.trimNum(String(d.refreshRate || 60));
            var have = false;
            for (var k = 0; k < modes.length; k++)
                if (modes[k].w === w && modes[k].h === h && modes[k].rr === curRR) have = true;
            if (!have) modes.push({ w: w, h: h, rr: curRR });
            if (!modes.length) modes.push({ w: w, h: h, rr: "60" });
            ms.push({
                name: d.name,
                desc: d.description || d.model || d.name,
                enabled: !d.disabled,
                x: d.x || 0, y: d.y || 0,
                scale: d.scale || 1,
                transform: d.transform || 0,
                res: { w: w, h: h },
                rr: curRR,
                modes: modes
            });
        }
        app._seedPrimary(ms);
        app.monitors = ms;
        if (app.selected < 0 || app.selected >= ms.length) {
            app.selected = 0;
            for (var s = 0; s < ms.length; s++) if (ms[s].enabled) { app.selected = s; break; }
        }
        if (!confirmBar.active) app.baselineMonitors = JSON.parse(JSON.stringify(ms));
        app.dirty = false;
        app.rev++;
    }

    // ----- model mutations ---------------------------------------------------
    function _clone(ms) { return JSON.parse(JSON.stringify(ms)); }

    // Hyprland has no primary-monitor concept of its own, so the model carries
    // the flag: exactly one enabled monitor is `primary`, and
    // _resolveAndNormalize keeps that one at (0,0).
    function _primaryIndex(ms) {
        for (var i = 0; i < ms.length; i++) if (ms[i].primary && ms[i].enabled) return i;
        return -1;
    }

    // Adopt the primary from a layout that carries no flag yet: whoever holds
    // the origin, else the first enabled output.
    function _seedPrimary(ms) {
        var pick = -1;
        for (var i = 0; i < ms.length; i++) {
            if (!ms[i].enabled) continue;
            if (ms[i].x === 0 && ms[i].y === 0) { pick = i; break; }
            if (pick < 0) pick = i;
        }
        for (var j = 0; j < ms.length; j++) ms[j].primary = (j === pick);
    }

    function isPrimary(m) { return !!(m && m.primary && m.enabled); }

    function _touches(m, s, o, os) {
        var vGap = Math.min(m.y + s.h, o.y + os.h) - Math.max(m.y, o.y);
        var hGap = Math.min(m.x + s.w, o.x + os.w) - Math.max(m.x, o.x);
        var edgeV = Math.abs(m.x + s.w - o.x) <= 1 || Math.abs(o.x + os.w - m.x) <= 1;
        var edgeH = Math.abs(m.y + s.h - o.y) <= 1 || Math.abs(o.y + os.h - m.y) <= 1;
        return (edgeV && vGap > 0) || (edgeH && hGap > 0);
    }
    function _touchesAny(ms, idx) {
        var m = ms[idx], s = app.logicalSize(m);
        for (var i = 0; i < ms.length; i++) {
            if (i === idx || !ms[i].enabled) continue;
            if (app._touches(m, s, ms[i], app.logicalSize(ms[i]))) return true;
        }
        return false;
    }
    function _clampOverlap(v, aLen, bStart, bLen) {
        var k = Math.min(aLen, bLen) * 0.25;
        return Math.max(bStart - aLen + k, Math.min(v, bStart + bLen - k));
    }
    function _pullFlush(ms, idx) {
        var m = ms[idx], s = app.logicalSize(m);
        var bestCost = 1e18, bx = m.x, by = m.y;
        for (var i = 0; i < ms.length; i++) {
            if (i === idx || !ms[i].enabled) continue;
            var o = ms[i], os = app.logicalSize(o);
            var cands = [
                { x: o.x + os.w, y: app._clampOverlap(m.y, s.h, o.y, os.h) },
                { x: o.x - s.w,  y: app._clampOverlap(m.y, s.h, o.y, os.h) },
                { x: app._clampOverlap(m.x, s.w, o.x, os.w), y: o.y + os.h },
                { x: app._clampOverlap(m.x, s.w, o.x, os.w), y: o.y - s.h }
            ];
            for (var c = 0; c < cands.length; c++) {
                var cost = Math.abs(cands[c].x - m.x) + Math.abs(cands[c].y - m.y);
                if (cost < bestCost) { bestCost = cost; bx = cands[c].x; by = cands[c].y; }
            }
        }
        m.x = Math.round(bx); m.y = Math.round(by);
    }

    function _resolveAndNormalize(ms, idx) {
        var enabled = 0;
        for (var e = 0; e < ms.length; e++) if (ms[e].enabled) enabled++;

        for (var round = 0; round < 4; round++) {
            var m = ms[idx], s = app.logicalSize(m);
            for (var pass = 0; pass < 5; pass++) {
                var moved = false;
                for (var i = 0; i < ms.length; i++) {
                    if (i === idx || !ms[i].enabled) continue;
                    var o = ms[i], os = app.logicalSize(o);
                    if (m.x < o.x + os.w && m.x + s.w > o.x && m.y < o.y + os.h && m.y + s.h > o.y) {
                        var penL = m.x + s.w - o.x, penR = o.x + os.w - m.x;
                        var penT = m.y + s.h - o.y, penB = o.y + os.h - m.y;
                        var mn = Math.min(penL, penR, penT, penB);
                        if (mn === penL)      m.x -= penL;
                        else if (mn === penR) m.x += penR;
                        else if (mn === penT) m.y -= penT;
                        else                  m.y += penB;
                        moved = true;
                    }
                }
                if (!moved) break;
            }
            if (enabled < 2 || !ms[idx].enabled || app._touchesAny(ms, idx)) break;
            app._pullFlush(ms, idx);
        }

        // The primary owns the origin; everything else is placed relative to
        // it, negative coordinates included (Hyprland takes those). Anchoring
        // on the layout's top-left is what used to make setPrimary a no-op.
        var ax, ay, p = app._primaryIndex(ms);
        if (p >= 0) {
            ax = ms[p].x; ay = ms[p].y;
        } else {
            ax = 1e9; ay = 1e9;
            for (var a = 0; a < ms.length; a++) if (ms[a].enabled) {
                ax = Math.min(ax, ms[a].x); ay = Math.min(ay, ms[a].y);
            }
            if (ax === 1e9) { ax = 0; ay = 0; }
        }
        for (var b = 0; b < ms.length; b++) { ms[b].x -= ax; ms[b].y -= ay; }
    }

    function moveMonitor(idx, nx, ny) {
        var ms = app._clone(app.monitors);
        var m = ms[idx], s = app.logicalSize(m);
        m.x = nx; m.y = ny;
        var thr = 45, cx = [], cy = [];
        for (var i = 0; i < ms.length; i++) {
            if (i === idx || !ms[i].enabled) continue;
            var o = ms[i], os = app.logicalSize(o);
            cx.push(o.x, o.x + os.w - s.w, o.x + os.w, o.x - s.w);
            cy.push(o.y, o.y + os.h - s.h, o.y + os.h, o.y - s.h);
        }
        for (var p = 0; p < cx.length; p++) if (Math.abs(m.x - cx[p]) < thr) { m.x = Math.round(cx[p]); break; }
        for (var q = 0; q < cy.length; q++) if (Math.abs(m.y - cy[q]) < thr) { m.y = Math.round(cy[q]); break; }
        app._resolveAndNormalize(ms, idx);
        app.monitors = ms; app.dirty = true; app.rev++;
    }

    function updateMon(idx, patch) {
        var ms = app._clone(app.monitors);
        for (var key in patch) ms[idx][key] = patch[key];
        app._resolveAndNormalize(ms, idx);
        app.monitors = ms; app.dirty = true; app.rev++;
    }

    function setResolution(idx, w, h) {
        var m = app.monitors[idx], best = "0";
        for (var i = 0; i < m.modes.length; i++)
            if (m.modes[i].w === w && m.modes[i].h === h)
                if (parseFloat(m.modes[i].rr) >= parseFloat(best)) best = m.modes[i].rr;
        if (best === "0") best = "60";
        app.updateMon(idx, { res: { w: w, h: h }, rr: best });
    }
    function setPrimary(idx) {
        var ms = app._clone(app.monitors);
        if (!ms[idx] || !ms[idx].enabled) return;
        for (var i = 0; i < ms.length; i++) ms[i].primary = (i === idx);
        app._resolveAndNormalize(ms, idx);
        app.monitors = ms; app.dirty = true; app.rev++;
    }
    function enableMon(idx, on) {
        var ms = app._clone(app.monitors);
        ms[idx].enabled = on;
        if (on) {
            var maxr = 0;
            for (var i = 0; i < ms.length; i++) if (i !== idx && ms[i].enabled)
                maxr = Math.max(maxr, ms[i].x + app.logicalSize(ms[i]).w);
            ms[idx].x = maxr; ms[idx].y = 0;
        }
        // The primary has to be an output that's on: disabling it hands the
        // origin to whatever is left, and the first output back on takes it.
        if (app._primaryIndex(ms) < 0) app._seedPrimary(ms);
        app._resolveAndNormalize(ms, idx);
        app.monitors = ms; app.dirty = true; app.rev++;
    }

    // ----- apply / revert ----------------------------------------------------
    function runArrangement(ms, note) {
        app.pendingNote = note;
        runProc.command = ["omarchy-displays", "--from-native", app.nativeLines(ms)];
        runProc.running = true;
    }
    function applyLive() {
        app.runArrangement(app.monitors, "Applied");
        confirmBar.arm();
    }
    function revertLive() {
        confirmBar.disarm();
        app.runArrangement(app.baselineMonitors, "Reverted");
    }
    function keepChanges() {
        confirmBar.disarm();
        app.baselineMonitors = JSON.parse(JSON.stringify(app.monitors));
        toast.show("Kept");
    }
    function save() { app.applyLive(); }

    property var sel: (selected >= 0 && selected < monitors.length) ? monitors[selected] : null
    function uniqRes(m) {
        if (!m) return [];
        var seen = {}, out = [];
        for (var i = 0; i < m.modes.length; i++) {
            var key = m.modes[i].w + "x" + m.modes[i].h;
            if (!seen[key]) { seen[key] = 1; out.push({ w: m.modes[i].w, h: m.modes[i].h, key: key, area: m.modes[i].w * m.modes[i].h }); }
        }
        out.sort(function (a, b) { return b.area - a.area; });
        return out;
    }
    function ratesFor(m) {
        if (!m) return [];
        var out = [];
        for (var i = 0; i < m.modes.length; i++)
            if (m.modes[i].w === m.res.w && m.modes[i].h === m.res.h) out.push(m.modes[i].rr);
        out.sort(function (a, b) { return parseFloat(b) - parseFloat(a); });
        return out;
    }

    // ================================================================== UI
    FloatingWindow {
        id: win
        visible: true
        title: "Displays Arranger"
        implicitWidth: 960
        implicitHeight: 640
        minimumSize: Qt.size(780, 520)
        color: app.pal.bg

        onVisibleChanged: if (!visible) Qt.quit()

        // ---- reusable, token-styled bits --------------------------------
        component FieldLabel: Text {
            color: app.pal.muted
            font.family: app.uiFont
            font.pixelSize: app.sty.fCaption
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 0.5
        }

        component Btn: Rectangle {
            id: btn
            property string label: ""
            property bool primary: false
            property bool danger: false
            signal clicked()
            property color over: primary ? app.pal.accent : (danger ? app.pal.danger : app.pal.text)
            implicitHeight: app.sty.ctlH + 4
            implicitWidth: cap.implicitWidth + app.sty.xxl * 2
            radius: app.sty.radius
            opacity: enabled ? 1 : 0.45
            color: !enabled ? app.pal.bg
                 : bma.pressed        ? app.wash(app.pal.bg, over, app.sty.pressedFillA)
                 : bma.containsMouse  ? app.wash(app.pal.bg, over, app.sty.hoverFillA)
                 : primary            ? app.wash(app.pal.bg, over, app.sty.selFillA)
                 :                      app.wash(app.pal.bg, over, app.sty.normalFillA)
            border.width: 1
            border.color: (primary || danger)
                 ? app.ualpha(over, app.sty.strongBorderA)
                 : app.ualpha(over, bma.containsMouse ? app.sty.hoverBorderA : app.sty.borderA)
            Behavior on color { ColorAnimation { duration: 80 } }
            Text {
                id: cap
                anchors.centerIn: parent
                text: btn.label
                font.family: app.uiFont
                font.pixelSize: app.sty.fBody
                font.bold: btn.primary
                color: btn.primary ? app.pal.accent : (btn.danger ? app.pal.danger : app.pal.text)
            }
            MouseArea {
                id: bma
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: if (btn.enabled) btn.clicked()
            }
        }

        component Combo: ComboBox {
            id: cb
            font.family: app.uiFont
            font.pixelSize: app.sty.fBody
            implicitHeight: app.sty.ctlH
            Layout.fillWidth: true
            background: Rectangle {
                radius: app.sty.radius
                color: app.wash(app.pal.bg, app.pal.text, app.sty.normalFillA)
                border.width: 1
                border.color: app.ualpha(app.pal.text, cb.activeFocus || cb.hovered ? app.sty.hoverBorderA : app.sty.borderA)
            }
            contentItem: Text {
                leftPadding: app.sty.ctlPadX
                text: cb.displayText
                color: app.pal.text
                font: cb.font
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
            indicator: Text {
                x: cb.width - 18
                y: (cb.height - height) / 2
                text: "▾"
                color: app.pal.muted
                font.pixelSize: app.sty.fCaption
            }
            popup: Popup {
                y: cb.height
                width: cb.width
                padding: 1
                background: Rectangle {
                    color: app.pal.popup
                    border.width: 1
                    border.color: app.ualpha(app.pal.text, app.sty.borderA)
                }
                contentItem: ListView {
                    implicitHeight: Math.min(contentHeight, app.sty.ctlH * 8)
                    model: cb.popup.visible ? cb.delegateModel : null
                    clip: true
                    currentIndex: cb.highlightedIndex
                    ScrollIndicator.vertical: ScrollIndicator {}
                }
            }
            delegate: ItemDelegate {
                id: deleg
                required property var modelData
                required property int index
                width: cb.width - 2
                height: app.sty.ctlH
                contentItem: Text {
                    leftPadding: app.sty.ctlPadX
                    text: cb.textRole ? deleg.modelData[cb.textRole] : deleg.modelData
                    color: app.pal.text
                    font.family: app.uiFont
                    font.pixelSize: app.sty.fBody
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    color: (cb.highlightedIndex === deleg.index)
                        ? app.wash(app.pal.popup, app.pal.text, app.sty.hoverFillA)
                        : "transparent"
                }
            }
        }

        component Toggle: Rectangle {
            id: tg
            property bool checked: false
            signal toggled(bool value)
            implicitWidth: 40
            implicitHeight: 22
            radius: app.sty.radius
            color: tg.checked
                ? app.wash(app.pal.bg, app.pal.accent, app.sty.selFillA)
                : app.wash(app.pal.bg, app.pal.text, app.sty.normalFillA)
            border.width: 1
            border.color: app.ualpha(tg.checked ? app.pal.accent : app.pal.text,
                                     tg.checked ? app.sty.strongBorderA : app.sty.borderA)
            Behavior on color { ColorAnimation { duration: 100 } }
            Rectangle {
                width: 14
                height: 14
                radius: 0
                y: 3
                x: tg.checked ? tg.width - width - 3 : 3
                color: tg.checked ? app.pal.accent : app.pal.muted
                Behavior on x { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: tg.toggled(!tg.checked)
            }
        }

        function hline() {}   // marker only

        // ---- layout ---------------------------------------------------
        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // header
            Item {
                Layout.fillWidth: true
                implicitHeight: 58
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: app.sty.huge
                    anchors.rightMargin: app.sty.huge
                    spacing: app.sty.xxl
                    ColumnLayout {
                        spacing: 0
                        Text {
                            text: "Displays"
                            color: app.pal.text
                            font.family: app.uiFont
                            font.pixelSize: app.sty.fHeading
                            font.bold: true
                        }
                        Text {
                            text: "drag to arrange · " + app.themeName
                            color: app.pal.muted
                            font.family: app.uiFont
                            font.pixelSize: app.sty.fSmall
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Btn { label: "Identify"; onClicked: identifyTimer.start() }
                }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: app.ualpha(app.pal.text, app.sty.borderA) }

            // body
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // canvas
                Item {
                    id: canvasWrap
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: app.sty.panelPad

                    property real k: 0.2
                    property real ox: 0
                    property real oy: 0
                    property real minx: 0
                    property real miny: 0

                    Rectangle {
                        anchors.fill: parent
                        radius: app.sty.radius
                        color: app.wash(app.pal.bg, app.pal.text, 0.02)
                        border.width: 1
                        border.color: app.ualpha(app.pal.text, app.sty.borderA)
                    }

                    function relayout() {
                        var en = [];
                        for (var i = 0; i < app.monitors.length; i++) if (app.monitors[i].enabled) en.push(i);
                        if (!en.length) return;
                        var minx = 1e9, miny = 1e9, maxx = -1e9, maxy = -1e9;
                        for (var e = 0; e < en.length; e++) {
                            var m = app.monitors[en[e]], s = app.logicalSize(m);
                            minx = Math.min(minx, m.x); miny = Math.min(miny, m.y);
                            maxx = Math.max(maxx, m.x + s.w); maxy = Math.max(maxy, m.y + s.h);
                        }
                        var bw = Math.max(1, maxx - minx), bh = Math.max(1, maxy - miny);
                        var k = Math.min((width - 90) / bw, (height - 90) / bh);
                        k = Math.max(0.03, Math.min(k, 0.26));
                        canvasWrap.k = k;
                        canvasWrap.minx = minx; canvasWrap.miny = miny;
                        canvasWrap.ox = (width - bw * k) / 2;
                        canvasWrap.oy = (height - bh * k) / 2;
                        for (var r = 0; r < cardRep.count; r++) {
                            var it = cardRep.itemAt(r);
                            if (!it) continue;
                            var mm = app.monitors[r], ss = app.logicalSize(mm);
                            it.visible = mm.enabled;
                            it.width = Math.max(52, ss.w * k);
                            it.height = Math.max(34, ss.h * k);
                            it.x = canvasWrap.ox + (mm.x - minx) * k;
                            it.y = canvasWrap.oy + (mm.y - miny) * k;
                        }
                    }

                    onWidthChanged: relayout()
                    onHeightChanged: relayout()
                    Connections { target: app; function onRevChanged() { canvasWrap.relayout() } }

                    Repeater {
                        id: cardRep
                        model: app.monitors.length

                        Rectangle {
                            id: card
                            required property int index
                            property var m: app.monitors[index]
                            property bool isSel: app.selected === index
                            property bool isPrimary: app.isPrimary(m)
                            property bool dragActive: false
                            z: isSel ? 5 : 1
                            radius: app.sty.radius
                            color: app.pal.bg
                            border.width: 1
                            border.color: isSel ? app.pal.accent : app.ualpha(app.pal.text, app.sty.borderA)
                            clip: true

                            Image {
                                anchors.fill: parent
                                source: app.wallpaperUrl
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                opacity: 0.45
                            }
                            Rectangle {
                                anchors.fill: parent
                                color: card.isSel
                                    ? app.ualpha(app.pal.accent, 0.22)
                                    : Qt.rgba(0, 0, 0, 0.4)
                            }
                            // macOS-style menu-bar strip on the primary display
                            Rectangle {
                                visible: card.isPrimary
                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                height: Math.max(3, parent.height * 0.085)
                                color: app.ualpha(app.pal.text, 0.5)
                            }
                            Column {
                                anchors.centerIn: parent
                                spacing: 0
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: card.m ? card.m.name : ""
                                    color: app.pal.text
                                    font.family: app.uiFont
                                    font.pixelSize: app.sty.fBody
                                    font.bold: true
                                    style: Text.Outline
                                    styleColor: Qt.rgba(0, 0, 0, 0.7)
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: card.m ? (card.m.res.w + "×" + card.m.res.h) : ""
                                    color: app.pal.text
                                    font.family: app.uiFont
                                    font.pixelSize: app.sty.fCaption
                                    style: Text.Outline
                                    styleColor: Qt.rgba(0, 0, 0, 0.7)
                                }
                            }
                            Rectangle {
                                id: flash
                                anchors.fill: parent
                                color: app.pal.accent
                                opacity: 0
                            }

                            MouseArea {
                                anchors.fill: parent
                                drag.target: card
                                drag.axis: Drag.XAndYAxis
                                drag.smoothed: true
                                cursorShape: Qt.SizeAllCursor
                                onPressed: { app.selected = card.index; card.dragActive = true; }
                                onReleased: {
                                    card.dragActive = false;
                                    var k = canvasWrap.k;
                                    var nx = Math.round(((card.x - canvasWrap.ox) / k + canvasWrap.minx) / 10) * 10;
                                    var ny = Math.round(((card.y - canvasWrap.oy) / k + canvasWrap.miny) / 10) * 10;
                                    app.moveMonitor(card.index, nx, ny);
                                    canvasWrap.relayout();
                                }
                            }
                            Behavior on x { enabled: !card.dragActive; NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                            Behavior on y { enabled: !card.dragActive; NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                            Connections {
                                target: identifyTimer
                                function onRunningChanged() {
                                    if (identifyTimer.running) { flash.opacity = 0.5; flashOut.start(); }
                                }
                            }
                            NumberAnimation { id: flashOut; target: flash; property: "opacity"; to: 0; duration: 850 }
                        }
                    }
                    Timer { id: identifyTimer; interval: 1000 }
                }

                Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: app.ualpha(app.pal.text, app.sty.borderA) }

                // inspector
                Rectangle {
                    Layout.preferredWidth: 288
                    Layout.fillHeight: true
                    color: app.wash(app.pal.bg, app.pal.text, 0.02)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: app.sty.panelPad
                        spacing: app.sty.panelGap

                        Text {
                            text: app.sel ? app.sel.name : "No display"
                            color: app.pal.text
                            font.family: app.uiFont
                            font.pixelSize: app.sty.fTitle
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: app.sel ? app.sel.desc : ""
                            color: app.pal.muted
                            font.family: app.uiFont
                            font.pixelSize: app.sty.fSmall
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            visible: text.length > 0
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            visible: app.sel !== null
                            FieldLabel { text: "Enabled"; Layout.fillWidth: true }
                            Toggle {
                                checked: app.sel ? app.sel.enabled : false
                                onToggled: function (v) { app.enableMon(app.selected, v); }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: app.sty.labelGap
                            visible: app.sel !== null && app.sel.enabled
                            FieldLabel { text: "Resolution" }
                            Combo {
                                textRole: "label"
                                model: {
                                    var r = app.uniqRes(app.sel);
                                    return r.map(function (o) { return { label: o.w + " × " + o.h, w: o.w, h: o.h }; });
                                }
                                currentIndex: {
                                    if (!app.sel) return -1;
                                    for (var i = 0; i < model.length; i++)
                                        if (model[i].w === app.sel.res.w && model[i].h === app.sel.res.h) return i;
                                    return -1;
                                }
                                onActivated: function (i) { app.setResolution(app.selected, model[i].w, model[i].h); }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: app.sty.labelGap
                            visible: app.sel !== null && app.sel.enabled
                            FieldLabel { text: "Refresh rate" }
                            Combo {
                                model: {
                                    var rr = app.ratesFor(app.sel);
                                    return rr.map(function (r) { return r + " Hz"; });
                                }
                                currentIndex: {
                                    if (!app.sel) return -1;
                                    var rr = app.ratesFor(app.sel);
                                    for (var i = 0; i < rr.length; i++) if (rr[i] === app.sel.rr) return i;
                                    return 0;
                                }
                                onActivated: function (i) {
                                    var rr = app.ratesFor(app.sel);
                                    app.updateMon(app.selected, { rr: rr[i] });
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: app.sty.labelGap
                            visible: app.sel !== null && app.sel.enabled
                            FieldLabel { text: "Scale" }
                            Combo {
                                property var opts: ["1", "1.25", "1.5", "1.75", "2"]
                                model: opts
                                currentIndex: app.sel ? Math.max(0, opts.indexOf(app.fmtScale(app.sel.scale))) : 0
                                onActivated: function (i) { app.updateMon(app.selected, { scale: parseFloat(opts[i]) }); }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: app.sty.labelGap
                            visible: app.sel !== null && app.sel.enabled
                            FieldLabel { text: "Orientation" }
                            Combo {
                                property var opts: ["0°", "90°", "180°", "270°"]
                                model: opts
                                currentIndex: app.sel ? app.sel.transform % 4 : 0
                                onActivated: function (i) { app.updateMon(app.selected, { transform: i }); }
                            }
                        }

                        Btn {
                            Layout.fillWidth: true
                            label: app.isPrimary(app.sel) ? "Primary display" : "Set as primary"
                            enabled: app.sel !== null && app.sel.enabled && !app.isPrimary(app.sel)
                            onClicked: app.setPrimary(app.selected)
                        }

                        Item { Layout.fillHeight: true }

                        Flow {
                            Layout.fillWidth: true
                            spacing: app.sty.md
                            Repeater {
                                model: app.monitors.length
                                Rectangle {
                                    id: chip
                                    required property int index
                                    property var mm: app.monitors[index]
                                    property bool on: app.selected === index
                                    implicitHeight: app.sty.ctlH - 4
                                    implicitWidth: chipText.implicitWidth + app.sty.xl * 2
                                    radius: app.sty.radius
                                    color: chip.on
                                        ? app.wash(app.pal.bg, app.pal.accent, app.sty.selFillA)
                                        : app.wash(app.pal.bg, app.pal.text, app.sty.normalFillA)
                                    border.width: 1
                                    border.color: app.ualpha(chip.on ? app.pal.accent : app.pal.text,
                                                             chip.on ? app.sty.strongBorderA : app.sty.borderA)
                                    opacity: chip.mm && chip.mm.enabled ? 1 : 0.45
                                    Text {
                                        id: chipText
                                        anchors.centerIn: parent
                                        text: chip.mm ? chip.mm.name : ""
                                        color: chip.on ? app.pal.accent : app.pal.text
                                        font.family: app.uiFont
                                        font.pixelSize: app.sty.fCaption
                                        font.bold: chip.on
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: app.selected = chip.index
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // confirm-revert bar
            Rectangle {
                id: confirmBar
                property bool active: false
                property int secs: 12
                Layout.fillWidth: true
                implicitHeight: active ? app.sty.ctlH + 12 : 0
                clip: true
                visible: active
                color: app.wash(app.pal.bg, app.pal.accent, app.sty.selFillA)
                function arm() { secs = 12; active = true; countdown.restart(); }
                function disarm() { active = false; countdown.stop(); }
                Rectangle { width: parent.width; height: 1; color: app.ualpha(app.pal.accent, app.sty.strongBorderA) }
                Timer {
                    id: countdown
                    interval: 1000
                    repeat: true
                    onTriggered: {
                        confirmBar.secs--;
                        if (confirmBar.secs <= 0) { countdown.stop(); app.revertLive(); }
                    }
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: app.sty.huge
                    anchors.rightMargin: app.sty.xxl
                    spacing: app.sty.lg
                    Text {
                        text: "Keep this arrangement?  reverting in " + confirmBar.secs + "s"
                        color: app.pal.text
                        font.family: app.uiFont
                        font.pixelSize: app.sty.fBody
                    }
                    Item { Layout.fillWidth: true }
                    Btn { label: "Revert now"; danger: true; onClicked: app.revertLive() }
                    Btn { label: "Keep changes"; primary: true; onClicked: app.keepChanges() }
                }
            }

            // footer
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: app.sty.ctlH + 22
                color: app.wash(app.pal.bg, app.pal.text, 0.02)
                Rectangle { width: parent.width; height: 1; color: app.ualpha(app.pal.text, app.sty.borderA) }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: app.sty.huge
                    anchors.rightMargin: app.sty.xxl
                    spacing: app.sty.lg
                    Text {
                        text: app.monitors.length + (app.monitors.length === 1 ? " display" : " displays")
                            + (app.dirty ? "  ·  unsaved" : "")
                        color: app.dirty ? app.pal.text : app.pal.muted
                        font.family: app.uiFont
                        font.pixelSize: app.sty.fSmall
                    }
                    Item { Layout.fillWidth: true }
                    Btn { label: "Revert"; enabled: app.dirty || confirmBar.active; onClicked: app.revertLive() }
                    Btn { label: "Apply"; primary: true; enabled: app.dirty && !confirmBar.active; onClicked: app.applyLive() }
                }
            }
        }

        // toast
        Rectangle {
            id: toast
            property string msg: ""
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: app.sty.ctlH + 40
            radius: app.sty.radius
            color: app.pal.popup
            border.width: 1
            border.color: app.ualpha(app.pal.text, app.sty.borderA)
            implicitWidth: tt.implicitWidth + app.sty.xxl * 2
            implicitHeight: app.sty.ctlH + 4
            opacity: 0
            function show(m) { msg = m; opacity = 1; toastHide.restart(); }
            Text {
                id: tt
                anchors.centerIn: parent
                text: toast.msg
                color: app.pal.text
                font.family: app.uiFont
                font.pixelSize: app.sty.fBody
            }
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Timer { id: toastHide; interval: 1600; onTriggered: toast.opacity = 0 }
        }

        Shortcut { sequence: "Escape"; onActivated: Qt.quit() }
        Shortcut { sequence: "Ctrl+S"; onActivated: app.save() }
        Shortcut { sequence: "Ctrl+Return"; onActivated: if (app.dirty) app.applyLive() }
        Shortcut { sequence: "Ctrl+R"; onActivated: app.revertLive() }
    }
}
