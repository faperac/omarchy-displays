import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "logic.js" as L

// Displays plugin popup. Native Omarchy chrome (KeyboardPanel + Style/Color +
// Dropdown/Toggle/Button); the drag canvas and monitor model are ours.
//
// Omarchy has no live monitor IPC (`hyprctl keyword` is rejected by the Lua
// parser), so "Apply" writes the managed block into monitors.lua and runs
// `hyprctl reload`, exactly like the CLI's Save. A 12s auto-revert guards it.
Panel {
    id: root
    moduleName: "faperac.displays"
    ipcTarget: "faperac.displays"
    manageIpc: false

    property var anchorItem: null
    property var hostWidget: null
    readonly property var barIdentity: hostWidget || root

    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
    readonly property color fg: Color.popups.text
    readonly property color muted: Util.alpha(fg, 0.55)

    // The CLI is bundled in the plugin (installed by `omarchy plugin add`), so
    // the plugin never depends on anything being on PATH.
    readonly property string cli: Quickshell.env("HOME")
        + "/.config/omarchy/plugins/faperac.displays/bin/omarchy-displays"

    // ---- model ------------------------------------------------------------
    property var model: []
    property var baselineModel: []
    property int selIdx: -1
    property int rev: 0
    property bool dirty: false
    property string pendingNote: ""
    readonly property var sel: (selIdx >= 0 && selIdx < model.length) ? model[selIdx] : null

    function open() { controller.show(); refresh(); }
    function close() { controller.hide(); }
    function toggle() { opened ? close() : open(); }
    function switchPanel(direction) {
        if (bar && typeof bar.switchPanelFrom === "function")
            return bar.switchPanelFrom(barIdentity, direction);
        return false;
    }

    function refresh() { readProc.running = true; }

    function ingest(txt) {
        var ms = L.parseMonitors(txt);
        if (!ms) return;
        root.model = ms;
        if (root.selIdx < 0 || root.selIdx >= ms.length) {
            root.selIdx = 0;
            for (var i = 0; i < ms.length; i++) if (ms[i].enabled) { root.selIdx = i; break; }
        }
        if (!confirm.armed) root.baselineModel = L.clone(ms);
        root.dirty = false;
        root.rev++;
    }

    function mutate(newModel) { root.model = newModel; root.dirty = true; root.rev++; }

    // Every write goes through the CLI: it backs up monitors.lua, rewrites the
    // managed block and runs `hyprctl reload`.
    function runArrangement(ms, note) {
        root.pendingNote = note;
        runProc.command = [root.cli, "--from-native", L.nativeLines(ms)];
        runProc.running = true;
    }
    function applyLive() {
        runArrangement(root.model, "Applied");
        confirm.arm();
    }
    function revertLive() {
        confirm.disarm();
        runArrangement(root.baselineModel, "Reverted");
    }
    function keepChanges() {
        confirm.disarm();
        root.baselineModel = L.clone(root.model);
        flash.show("Kept");
    }

    Process { id: readProc; command: ["hyprctl", "-j", "monitors", "all"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.ingest(text) } }
    Process { id: runProc
        onExited: { root.dirty = false; flash.show(root.pendingNote); root.refresh(); } }

    IpcHandler {
        target: root.ipcTarget
        function open(): void { root.open() }
        function close(): void { root.close() }
        function show(): void { root.open() }
        function hide(): void { root.close() }
        function toggle(): void { root.toggle() }
    }

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        bar: root.bar
        owner: root.barIdentity
        open: root.opened
        focusTarget: keys
        contentWidth: panel.fittedContentWidth(Style.space(440))
        contentHeight: panel.fittedContentHeight(body.implicitHeight)

        PanelKeyCatcher {
            id: keys
            anchors.fill: parent
            onCloseRequested: root.close()
            onTabRequested: function (direction) { root.switchPanel(direction); }

            Column {
                id: body
                width: parent.width
                spacing: Style.space(10)

                // ---- header ----
                Item {
                    width: parent.width
                    implicitHeight: Math.max(hdr.implicitHeight, idBtn.implicitHeight)
                    Row {
                        id: hdr
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(6)
                        Text {
                            text: "Displays"
                            color: root.fg
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.subtitle
                            font.bold: true
                        }
                        Text {
                            anchors.baseline: parent.children[0].baseline
                            text: root.sel ? "— " + root.sel.name : ""
                            color: root.muted
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                        }
                    }
                    Button {
                        id: idBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Identify"
                        bordered: true
                        fontFamily: root.fontFamily
                        fontSize: Style.font.caption
                        horizontalPadding: Style.space(8)
                        verticalPadding: Style.space(3)
                        onClicked: identifyTimer.start()
                    }
                }

                Rectangle { width: parent.width; height: Math.max(1, Style.spacing.hairline)
                    color: Util.alpha(root.fg, 0.14) }

                // ---- drag canvas ----
                Item {
                    id: canvas
                    width: parent.width
                    height: Style.space(168)

                    property real k: 0.2
                    property real ox: 0
                    property real oy: 0
                    property real minx: 0
                    property real miny: 0

                    Rectangle {
                        anchors.fill: parent
                        radius: Style.cornerRadius
                        color: Util.alpha(root.fg, 0.03)
                        border.width: 1
                        border.color: Util.alpha(root.fg, 0.4)
                    }

                    function relayout() {
                        var en = [];
                        for (var i = 0; i < root.model.length; i++) if (root.model[i].enabled) en.push(i);
                        if (!en.length) return;
                        var minx = 1e9, miny = 1e9, maxx = -1e9, maxy = -1e9;
                        for (var e = 0; e < en.length; e++) {
                            var m = root.model[en[e]], s = L.logicalSize(m);
                            minx = Math.min(minx, m.x); miny = Math.min(miny, m.y);
                            maxx = Math.max(maxx, m.x + s.w); maxy = Math.max(maxy, m.y + s.h);
                        }
                        var bw = Math.max(1, maxx - minx), bh = Math.max(1, maxy - miny);
                        var k = Math.min((width - 48) / bw, (height - 48) / bh);
                        k = Math.max(0.02, Math.min(k, 0.22));
                        canvas.k = k; canvas.minx = minx; canvas.miny = miny;
                        canvas.ox = (width - bw * k) / 2;
                        canvas.oy = (height - bh * k) / 2;
                        for (var r = 0; r < cardRep.count; r++) {
                            var it = cardRep.itemAt(r);
                            if (!it) continue;
                            var mm = root.model[r], ss = L.logicalSize(mm);
                            it.visible = mm.enabled;
                            it.width = Math.max(40, ss.w * k);
                            it.height = Math.max(26, ss.h * k);
                            it.x = canvas.ox + (mm.x - minx) * k;
                            it.y = canvas.oy + (mm.y - miny) * k;
                        }
                    }
                    onWidthChanged: relayout()
                    onHeightChanged: relayout()
                    Connections { target: root; function onRevChanged() { canvas.relayout(); } }

                    Repeater {
                        id: cardRep
                        model: root.model.length

                        Rectangle {
                            id: card
                            required property int index
                            property var m: root.model[index]
                            property bool isSel: root.selIdx === index
                            property bool isPrimary: L.isPrimary(m)
                            property bool dragActive: false
                            z: isSel ? 5 : 1
                            radius: Style.cornerRadius
                            color: Util.alpha(root.fg, isSel ? 0.16 : 0.07)
                            border.width: 1
                            border.color: isSel ? Color.accent : Util.alpha(root.fg, 0.4)

                            Rectangle {
                                visible: card.isPrimary
                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                height: Math.max(2, parent.height * 0.1)
                                color: Util.alpha(root.fg, 0.45)
                            }
                            Column {
                                anchors.centerIn: parent
                                spacing: 0
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: card.m ? card.m.name : ""
                                    color: card.isSel ? Color.accent : root.fg
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    visible: parent.height > 34
                                    text: card.m ? (card.m.res.w + "×" + card.m.res.h) : ""
                                    color: root.muted
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                }
                            }
                            Rectangle {
                                id: cardFlash
                                anchors.fill: parent
                                color: Color.accent
                                opacity: 0
                            }

                            MouseArea {
                                anchors.fill: parent
                                drag.target: card
                                drag.axis: Drag.XAndYAxis
                                drag.smoothed: true
                                cursorShape: Qt.SizeAllCursor
                                onPressed: { root.selIdx = card.index; card.dragActive = true; }
                                onReleased: {
                                    card.dragActive = false;
                                    var k = canvas.k;
                                    var nx = Math.round(((card.x - canvas.ox) / k + canvas.minx) / 10) * 10;
                                    var ny = Math.round(((card.y - canvas.oy) / k + canvas.miny) / 10) * 10;
                                    root.mutate(L.moveMonitor(root.model, card.index, nx, ny));
                                    canvas.relayout();
                                }
                            }
                            Behavior on x { enabled: !card.dragActive; NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                            Behavior on y { enabled: !card.dragActive; NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

                            Connections {
                                target: identifyTimer
                                function onRunningChanged() {
                                    if (identifyTimer.running) { cardFlash.opacity = 0.5; cardFlashOut.start(); }
                                }
                            }
                            NumberAnimation { id: cardFlashOut; target: cardFlash; property: "opacity"; to: 0; duration: 850 }
                        }
                    }
                    Timer { id: identifyTimer; interval: 1000 }
                }

                // ---- controls (2-up grid) ----
                Grid {
                    width: parent.width
                    columns: 2
                    columnSpacing: Style.space(8)
                    rowSpacing: Style.space(6)
                    enabled: root.sel !== null
                    property real cell: (width - columnSpacing) / 2

                    Dropdown {
                        width: parent.cell
                        label: "Resolution"
                        fontFamily: root.fontFamily
                        options: {
                            var r = L.uniqRes(root.sel), out = [];
                            for (var i = 0; i < r.length; i++)
                                out.push({ label: r[i].w + " × " + r[i].h, value: r[i].w + "x" + r[i].h });
                            return out;
                        }
                        value: root.sel ? (root.sel.res.w + "x" + root.sel.res.h) : ""
                        onChanged: function (v) {
                            var p = v.split("x");
                            root.mutate(L.setResolution(root.model, root.selIdx, +p[0], +p[1]));
                        }
                    }
                    Dropdown {
                        width: parent.cell
                        label: "Refresh"
                        fontFamily: root.fontFamily
                        options: {
                            var rr = L.ratesFor(root.sel), out = [];
                            for (var i = 0; i < rr.length; i++) out.push({ label: rr[i] + " Hz", value: rr[i] });
                            return out;
                        }
                        value: root.sel ? root.sel.rr : ""
                        onChanged: function (v) { root.mutate(L.updateMon(root.model, root.selIdx, { rr: v })); }
                    }
                    Dropdown {
                        width: parent.cell
                        label: "Scale"
                        fontFamily: root.fontFamily
                        options: [
                            { label: "1.00", value: "1" }, { label: "1.25", value: "1.25" },
                            { label: "1.50", value: "1.5" }, { label: "1.75", value: "1.75" },
                            { label: "2.00", value: "2" }
                        ]
                        value: root.sel ? L.fmtScale(root.sel.scale) : "1"
                        onChanged: function (v) { root.mutate(L.updateMon(root.model, root.selIdx, { scale: parseFloat(v) })); }
                    }
                    Dropdown {
                        width: parent.cell
                        label: "Orientation"
                        fontFamily: root.fontFamily
                        options: [
                            { label: "0°", value: "0" }, { label: "90°", value: "1" },
                            { label: "180°", value: "2" }, { label: "270°", value: "3" }
                        ]
                        value: root.sel ? String(root.sel.transform % 4) : "0"
                        onChanged: function (v) { root.mutate(L.updateMon(root.model, root.selIdx, { transform: parseInt(v) })); }
                    }
                }

                Row {
                    width: parent.width
                    spacing: Style.space(8)
                    property real cell: (width - spacing) / 2
                    Button {
                        width: parent.cell
                        bordered: true
                        fontFamily: root.fontFamily
                        fontSize: Style.font.caption
                        text: (root.sel && root.sel.enabled) ? "Disable output" : "Enable output"
                        enabled: root.sel !== null
                        onClicked: if (root.sel) root.mutate(L.enableMon(root.model, root.selIdx, !root.sel.enabled))
                    }
                    Button {
                        width: parent.cell
                        bordered: true
                        fontFamily: root.fontFamily
                        fontSize: Style.font.caption
                        text: L.isPrimary(root.sel) ? "Primary" : "Set as primary"
                        enabled: root.sel !== null && root.sel.enabled && !L.isPrimary(root.sel)
                        onClicked: root.mutate(L.setPrimary(root.model, root.selIdx))
                    }
                }

                // ---- confirm-revert ----
                Rectangle {
                    id: confirm
                    property bool armed: false
                    property int secs: 12
                    width: parent.width
                    visible: armed
                    height: armed ? confirmRow.implicitHeight + Style.space(10) : 0
                    color: Util.alpha(Color.accent, 0.14)
                    border.width: 1
                    border.color: Util.alpha(Color.accent, 0.6)
                    function arm() { secs = 12; armed = true; countdown.restart(); }
                    function disarm() { armed = false; countdown.stop(); }
                    Timer {
                        id: countdown
                        interval: 1000
                        repeat: true
                        onTriggered: { confirm.secs--; if (confirm.secs <= 0) { countdown.stop(); root.revertLive(); } }
                    }
                    Row {
                        id: confirmRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Style.space(10)
                        anchors.rightMargin: Style.space(10)
                        spacing: Style.space(6)
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - keepBtn.width - Style.space(6)
                            elide: Text.ElideRight
                            text: "Keep it? reverting in " + confirm.secs + "s"
                            color: root.fg
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                        }
                        Button { id: keepBtn; text: "Keep"; bordered: true; active: true; fontFamily: root.fontFamily
                            fontSize: Style.font.caption; horizontalPadding: Style.space(8); verticalPadding: Style.space(3)
                            onClicked: root.keepChanges() }
                    }
                }

                // ---- footer ----
                Item {
                    width: parent.width
                    implicitHeight: footerRow.implicitHeight
                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            var n = 0;
                            for (var i = 0; i < root.model.length; i++) if (root.model[i].enabled) n++;
                            return n + (n === 1 ? " active" : " active") + (root.dirty ? "  ·  unsaved" : "");
                        }
                        color: root.dirty ? root.fg : root.muted
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                    }
                    Row {
                        id: footerRow
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(6)
                        Button { text: "Revert"; bordered: true; fontFamily: root.fontFamily
                            fontSize: Style.font.caption; horizontalPadding: Style.space(10); verticalPadding: Style.space(4)
                            enabled: root.dirty || confirm.armed; onClicked: root.revertLive() }
                        Button { text: "Apply"; bordered: true; active: true; fontFamily: root.fontFamily
                            fontSize: Style.font.caption; horizontalPadding: Style.space(10); verticalPadding: Style.space(4)
                            enabled: root.dirty && !confirm.armed; onClicked: root.applyLive() }
                    }
                }
            }

            // toast
            Rectangle {
                id: flash
                property string msg: ""
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                radius: Style.cornerRadius
                color: Color.popups.background
                border.width: 1
                border.color: Util.alpha(root.fg, 0.4)
                width: flashText.implicitWidth + Style.space(20)
                height: flashText.implicitHeight + Style.space(10)
                opacity: 0
                function show(m) { if (!m) return; msg = m; opacity = 1; flashHide.restart(); }
                Text {
                    id: flashText
                    anchors.centerIn: parent
                    text: flash.msg
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                }
                Behavior on opacity { NumberAnimation { duration: 150 } }
                Timer { id: flashHide; interval: 1500; onTriggered: flash.opacity = 0 }
            }
        }
    }
}
