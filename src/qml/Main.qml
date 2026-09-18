import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

Item {
    id: root
    objectName: "monerodRoot"

    readonly property var backend: (typeof logos !== "undefined" && logos) ? logos.module("monerod_ui") : null
    readonly property bool ready: backend !== null
    readonly property var networks: ["mainnet", "stagenet", "testnet"]

    function j(raw, fallback) { try { return raw ? JSON.parse(raw) : fallback } catch (e) { return fallback } }
    readonly property var st: ready ? j(backend.statusJson, ({})) : ({})
    readonly property var cfg: ready ? j(backend.configJson, ({})) : ({})
    readonly property string nodeState: ready ? backend.state : "unavailable"
    readonly property bool running: nodeState === "running"
    readonly property bool stopped: nodeState === "stopped" || nodeState === "failed" || nodeState === "unavailable"
    readonly property bool active: nodeState === "starting" || running

    readonly property int height_: st.height || 0
    readonly property int target_: st.targetHeight || 0
    // monerod reports no target until a peer announces its height.
    readonly property bool targetKnown: target_ > height_
    readonly property real progress: st.synchronized ? 1 : (targetKnown ? height_ / target_ : 0)

    function stateColour(s) {
        if (s === "running") return Theme.palette.success
        if (s === "starting" || s === "stopping") return Theme.palette.info
        if (s === "failed" || s === "unavailable") return Theme.palette.error
        return Theme.palette.textTertiary
    }
    function fmtUptime(s) {
        s = s || 0
        var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60)
        return h > 0 ? (h + "h " + m + "m") : (m + "m " + (s % 60) + "s")
    }
    function fmtBytes(str) {
        var b = parseFloat(str || "0")
        if (b >= 1e9) return (b / 1e9).toFixed(1) + " GB"
        if (b >= 1e6) return (b / 1e6).toFixed(0) + " MB"
        return b.toFixed(0) + " B"
    }

    function loadForm() {
        pruneBox.checked = !!cfg.pruneBlockchain
        igdBox.checked = !!cfg.noIgd
        offlineBox.checked = !!cfg.offline
        dataDirField.text = cfg.dataDir || ""
        rpcPortField.text = cfg.rpcBindPort !== undefined ? String(cfg.rpcBindPort) : ""
        p2pPortField.text = cfg.p2pBindPort !== undefined ? String(cfg.p2pBindPort) : ""
        outPeersField.text = cfg.outPeers !== undefined ? String(cfg.outPeers) : "-1"
        inPeersField.text = cfg.inPeers !== undefined ? String(cfg.inPeers) : "-1"
        upField.text = cfg.limitRateUp !== undefined ? String(cfg.limitRateUp) : "-1"
        downField.text = cfg.limitRateDown !== undefined ? String(cfg.limitRateDown) : "-1"
        logLevelField.text = cfg.logLevel !== undefined ? String(cfg.logLevel) : "0"
        proxyField.text = cfg.proxy || ""
    }
    onCfgChanged: loadForm()

    function saveForm() {
        backend.saveConfig(JSON.stringify({
            pruneBlockchain: pruneBox.checked, noIgd: igdBox.checked, offline: offlineBox.checked,
            dataDir: dataDirField.text.trim(),
            rpcBindPort: parseInt(rpcPortField.text), p2pBindPort: parseInt(p2pPortField.text),
            outPeers: parseInt(outPeersField.text), inPeers: parseInt(inPeersField.text),
            limitRateUp: parseInt(upField.text), limitRateDown: parseInt(downField.text),
            logLevel: parseInt(logLevelField.text), proxy: proxyField.text.trim()
        }))
    }

    Connections {
        target: (typeof logos !== "undefined") ? logos : null
        ignoreUnknownSignals: true
        function onIntentRequested(requestId, intent, params, requesterName) {
            if (intent !== "monero.node.configure") return
            var n = params && params.network ? String(params.network) : ""
            if (n !== "" && root.networks.indexOf(n) < 0) { logos.respond(requestId, false, ({}), "bad_request"); return }
            if (n !== "" && root.stopped) backend.selectNetwork(n)
            logos.respond(requestId, true, ({}), "")
        }
    }

    Rectangle { anchors.fill: parent; color: Theme.palette.background }

    LogosScrollView {
        anchors.fill: parent
        anchors.margins: 20

        ColumnLayout {
            width: root.width - 40
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                LogosText { text: "Monero node"; font.pixelSize: 22; font.weight: Theme.typography.weightBold }
                LogosBadge { objectName: "stateBadge"; text: root.nodeState || "checking"; color: root.stateColour(root.nodeState) }
                Item { Layout.fillWidth: true }
                LogosText { text: "Network"; color: Theme.palette.textTertiary }
                LogosComboBox {
                    objectName: "networkCombo"
                    model: root.networks
                    enabled: root.ready && root.stopped && !backend.busy
                    currentIndex: Math.max(0, root.networks.indexOf(root.ready ? backend.network : "stagenet"))
                    onActivated: function(index) { backend.selectNetwork(root.networks[index]) }
                }
            }

            LogosFrame {
                Layout.fillWidth: true
                backgroundColor: Theme.palette.surfaceRaised
                borderColor: Theme.palette.borderSecondary
                radius: Theme.spacing.radiusLarge
                padding: Theme.spacing.large

                contentItem: ColumnLayout {
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        LogosText {
                            objectName: "heightText"
                            textFormat: Text.PlainText
                            text: root.running ? "Height " + root.height_ + (root.targetKnown ? " / " + root.target_ : "")
                                  : root.nodeState === "starting" ? "Starting…"
                                  : root.nodeState === "stopping" ? "Stopping…"
                                  : root.nodeState === "" ? "Checking…" : "Not running"
                            font.weight: Theme.typography.weightBold
                        }
                        Item { Layout.fillWidth: true }
                        LogosText {
                            objectName: "syncText"
                            textFormat: Text.PlainText
                            color: Theme.palette.textTertiary
                            text: !root.running ? "" : st.synchronized ? "Synchronized"
                                  : root.targetKnown ? "Syncing" : "Waiting for peers"
                        }
                        LogosText {
                            objectName: "syncPercent"
                            visible: root.running && root.targetKnown && !st.synchronized
                            textFormat: Text.PlainText
                            text: (Math.floor(root.progress * 1000) / 10) + "%"
                        }
                    }

                    Rectangle {
                        objectName: "syncBar"
                        Layout.fillWidth: true
                        Layout.preferredHeight: 8
                        radius: 4
                        color: Theme.palette.borderSecondary
                        Rectangle {
                            objectName: "syncBarFill"
                            width: parent.width * root.progress
                            height: parent.height
                            radius: 4
                            color: st.synchronized ? Theme.palette.success : Theme.palette.info
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 4
                        columnSpacing: 20
                        rowSpacing: 4
                        LogosText { text: "Peers"; color: Theme.palette.textTertiary }
                        LogosText { objectName: "peersText"; textFormat: Text.PlainText; text: (st.peersOut || 0) + " out · " + (st.peersIn || 0) + " in" }
                        LogosText { text: "Uptime"; color: Theme.palette.textTertiary }
                        LogosText { textFormat: Text.PlainText; text: root.running ? root.fmtUptime(st.uptimeSecs) : "—" }
                        LogosText { text: "Database"; color: Theme.palette.textTertiary }
                        LogosText { textFormat: Text.PlainText; text: root.running ? root.fmtBytes(st.databaseSize) : "—" }
                        LogosText { text: "Version"; color: Theme.palette.textTertiary }
                        LogosText { textFormat: Text.PlainText; text: st.version || "—" }
                    }

                    LogosText {
                        Layout.fillWidth: true
                        visible: text !== ""
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        color: Theme.palette.error
                        text: root.ready ? (backend.lastError || st.lastError || "") : "The node module is not available."
                    }

                    RowLayout {
                        spacing: 10
                        LogosButton {
                            objectName: "startButton"
                            text: "Start"
                            enabled: root.ready && root.stopped && !backend.busy
                            onClicked: backend.start()
                        }
                        LogosButton {
                            objectName: "stopButton"
                            text: "Stop"
                            enabled: root.ready && root.active && !backend.busy
                            onClicked: backend.stop()
                        }
                        LogosSpinner { visible: root.ready && backend.busy; running: visible }
                    }
                }
            }

            LogosText {
                objectName: "mainnetNotice"
                Layout.fillWidth: true
                visible: root.ready && backend.network === "mainnet" && root.stopped
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                color: Theme.palette.warning
                text: "A mainnet node downloads the whole chain: about 60 GB pruned, 250 GB unpruned. "
                    + "The first sync takes hours to days."
            }

            LogosFrame {
                Layout.fillWidth: true
                backgroundColor: Theme.palette.surfaceRaised
                borderColor: Theme.palette.borderSecondary
                radius: Theme.spacing.radiusLarge
                padding: Theme.spacing.large

                contentItem: GridLayout {
                    columns: 2
                    columnSpacing: 12
                    rowSpacing: 8
                    enabled: root.ready && root.stopped && !backend.busy

                    LogosText { Layout.columnSpan: 2; text: "Settings (apply on next start)"; font.weight: Theme.typography.weightBold }
                    LogosText { text: "Data directory"; color: Theme.palette.textTertiary }
                    LogosTextField { id: dataDirField; Layout.fillWidth: true }
                    LogosText { text: "RPC port"; color: Theme.palette.textTertiary }
                    LogosTextField { id: rpcPortField; Layout.fillWidth: true }
                    LogosText { text: "P2P port"; color: Theme.palette.textTertiary }
                    LogosTextField { id: p2pPortField; Layout.fillWidth: true }
                    LogosText { text: "Peers out / in"; color: Theme.palette.textTertiary }
                    RowLayout {
                        Layout.fillWidth: true
                        LogosTextField { id: outPeersField; Layout.fillWidth: true; placeholderText: "-1 = default" }
                        LogosTextField { id: inPeersField; Layout.fillWidth: true; placeholderText: "-1 = default" }
                    }
                    LogosText { text: "Rate up / down (KB/s)"; color: Theme.palette.textTertiary }
                    RowLayout {
                        Layout.fillWidth: true
                        LogosTextField { id: upField; Layout.fillWidth: true; placeholderText: "-1 = default" }
                        LogosTextField { id: downField; Layout.fillWidth: true; placeholderText: "-1 = default" }
                    }
                    LogosText { text: "Proxy"; color: Theme.palette.textTertiary }
                    LogosTextField { id: proxyField; Layout.fillWidth: true; placeholderText: "e.g. 127.0.0.1:9050 (empty for none)" }
                    LogosText { text: "Log level"; color: Theme.palette.textTertiary }
                    LogosTextField { id: logLevelField; Layout.fillWidth: true; placeholderText: "0-4" }
                    LogosText { text: ""; opacity: 0 }
                    LogosCheckbox { id: pruneBox; text: "Prune the blockchain" }
                    LogosText { text: ""; opacity: 0 }
                    LogosCheckbox { id: igdBox; text: "Disable UPnP port mapping" }
                    LogosText { text: ""; opacity: 0 }
                    LogosCheckbox { id: offlineBox; text: "Offline (do not connect to peers)" }
                    LogosText { text: ""; opacity: 0 }
                    RowLayout {
                        LogosButton { objectName: "saveButton"; text: "Save settings"; onClicked: root.saveForm() }
                        LogosButton { text: "Revert"; onClicked: root.loadForm() }
                    }
                }
            }

            LogosFrame {
                Layout.fillWidth: true
                backgroundColor: Theme.palette.surfaceRaised
                borderColor: Theme.palette.borderSecondary
                radius: Theme.spacing.radiusLarge
                padding: Theme.spacing.large

                contentItem: ColumnLayout {
                    spacing: 6
                    LogosText { text: "Node log"; font.weight: Theme.typography.weightBold }
                    LogosText {
                        objectName: "logText"
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        wrapMode: Text.WrapAnywhere
                        font.family: Theme.typography.mono
                        font.pixelSize: 11
                        color: Theme.palette.textTertiary
                        text: root.ready && backend.logText ? backend.logText : "No log yet."
                    }
                }
            }
        }
    }
}
