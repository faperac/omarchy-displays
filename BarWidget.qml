import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Bar button for the Displays plugin. Mirrors the first-party bar-widget
// boilerplate (see melonamin.fast / chyld.easy-capture): an icon button that
// toggles a popup loaded from Panel.qml.
BarWidget {
    id: root
    moduleName: "faperac.displays"

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
    readonly property bool popoutSwitchClosing: panelLoader.item
        ? panelLoader.item.popoutSwitchClosing === true : false

    function injectPanel() {
        var p = panelLoader.item;
        if (!p) return;
        if ("bar" in p) p.bar = root.bar;
        if ("settings" in p) p.settings = root.settings;
        if ("anchorItem" in p) p.anchorItem = button;
        if ("hostWidget" in p) p.hostWidget = root;
    }
    function open() { if (panelLoader.item) panelLoader.item.open() }
    function close() { if (panelLoader.item) panelLoader.item.close() }
    function togglePanel() { if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle() }
    function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

    onBarChanged: injectPanel()
    onSettingsChanged: injectPanel()

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
        onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel); }
    }

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: "󰍹"                       // nf-md-monitor
        slotSize: Style.bar.statusSlot
        tooltipText: "Displays Arranger"
        onPressed: function (b) { if (b === Qt.LeftButton) root.togglePanel() }
    }
}
