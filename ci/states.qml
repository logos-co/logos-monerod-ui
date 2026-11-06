import QtQuick

// Drives the view through the txProxy states against a fake backend: the switch per network, what
// Save stores, the live Tor row and why payments wait, Restart, and a module too old to know txProxy.
// Prints STATES-OK, or STATES-FAIL with the cases that disagree.
Item {
    id: scene
    width: 1024; height: 900

    // The host injects `logos`; the view finds this one by name up its context chain.
    property QtObject logos: QtObject {
        signal intentRequested(string requestId, string intent, var params, string requesterName)
        function module(name) { return fake }
        function respond(id, ok, result, error) {}
    }

    QtObject {
        id: fake
        property string state: "stopped"
        property string network: "mainnet"
        property string statusJson: JSON.stringify({ state: "stopped", txProxy: "off" })
        property string configJson: "{}"
        property string logText: ""
        property string lastError: ""
        property bool busy: false
        property var calls: []
        function note(name, args) { calls = calls.concat([[name].concat(args)]) }
        function last(name) {
            for (var i = calls.length - 1; i >= 0; i--) if (calls[i][0] === name) return calls[i]
            return null
        }
        function selectNetwork(n) { note("selectNetwork", [n]) }
        function saveConfig(c) { note("saveConfig", [JSON.parse(c)]) }
        function start() { note("start", []) }
        function stop() { note("stop", []) }
        function restart() { note("restart", []) }
        function refresh() {}
    }

    readonly property var mainnetCfg: ({ dataDir: "/d", rpcBindPort: 18081, p2pBindPort: 18080, pruneBlockchain: true,
        outPeers: -1, inPeers: -1, limitRateUp: -1, limitRateDown: -1, noIgd: true, offline: false,
        logLevel: 0, proxy: "", txProxy: true })
    function cfg(o) { var c = JSON.parse(JSON.stringify(mainnetCfg)); for (var k in o) c[k] = o[k]; return c }
    function show(network, c) { fake.network = network; fake.configJson = JSON.stringify(c) }
    function run(st) {
        st.state = st.state || "running"
        fake.state = st.state
        fake.statusJson = JSON.stringify(st)
    }

    property var bad: []
    function expect(name, got, want) {
        if (JSON.stringify(got) !== JSON.stringify(want)) bad.push(name + ": got " + JSON.stringify(got) + ", want " + JSON.stringify(want))
    }
    function find(obj, name, depth) {
        if (!obj || (depth || 0) > 80) return null
        if (obj.objectName === name) return obj
        var kids = []
        if (obj.data) for (var i = 0; i < obj.data.length; i++) kids.push(obj.data[i])
        if (obj.contentItem && kids.indexOf(obj.contentItem) < 0) kids.push(obj.contentItem)
        for (var k = 0; k < kids.length; k++) {
            var r = find(kids[k], name, (depth || 0) + 1)
            if (r) return r
        }
        return null
    }
    function prop(name, p) {
        var o = find(view.item, name, 0)
        return o ? o[p] : "<no " + name + ">"
    }
    // `visible` is false too when an ancestor is hidden.
    function shown(name) { return prop(name, "visible") }
    function saved() { return (fake.last("saveConfig") || [])[1] || {} }

    readonly property var steps: [
        function (v) { show("mainnet", cfg({})) },
        function (v) {
            expect("mainnet: the switch shows, on and usable", [shown("txProxySwitch"), prop("txProxySwitch", "checked"), prop("txProxySwitch", "enabled")],
                   [true, true, true])
            expect("...named for payments", prop("txProxySwitch", "text"), "Send payments over Tor only")
            var note = prop("txProxyNote", "text")
            expect("...saying where payments go", note.indexOf("go to Tor peers only") >= 0, true)
            expect("...that they wait for Tor, even with Tor down", note.indexOf("Tor down included, the node holds them and retries over Tor") >= 0, true)
            expect("...never in the clear", note.indexOf("nothing goes out over the regular network") >= 0, true)
            expect("...and what switching it off does", note.indexOf("Switched off, a payment still waiting goes out over the regular network, from this computer's IP address, when the node next starts.") >= 0, true)
            expect("stopped: no live Tor row, no Restart", [shown("txProxyText"), shown("txProxyDetail"), prop("restartButton", "enabled")], [false, false, false])
            find(view.item, "saveButton", 0).clicked()
        },
        function (v) {
            expect("Save stores txProxy on", saved().txProxy, true)
            find(view.item, "txProxySwitch", 0).toggle()
            find(view.item, "saveButton", 0).clicked()
        },
        function (v) {
            expect("...and off once switched off", saved().txProxy, false)
            show("stagenet", cfg({ rpcBindPort: 38081, p2pBindPort: 38080, pruneBlockchain: false, txProxy: false }))
        },
        function (v) {
            expect("stagenet: shown off, not usable", [shown("txProxySwitch"), prop("txProxySwitch", "checked"), prop("txProxySwitch", "enabled")],
                   [true, false, false])
            expect("...with the reason", prop("txProxyNote", "text"),
                   "Mainnet only: Monero ships no Tor peers for stagenet, so a transaction sent this way would never leave the node.")
            find(view.item, "saveButton", 0).clicked()
        },
        function (v) {
            expect("...Save stores it off", saved().txProxy, false)
            show("testnet", cfg({ txProxy: false }))
        },
        function (v) {
            expect("testnet: off with its name", [prop("txProxySwitch", "enabled"), prop("txProxyNote", "text").indexOf("for testnet,") > 0], [false, true])
            show("mainnet", cfg({}))
            run({ network: "mainnet", txProxy: "on", txProxySocks: "127.0.0.1:9250", txProxyPeers: 3,
                  txProxyWaiting: false, txProxyReason: "", txProxyRestart: false })
        },
        function (v) {
            expect("running on: the Tor row names the port and the peers", [shown("txProxyText"), prop("txProxyText", "text")],
                   [true, "On · 127.0.0.1:9250 · 3 Tor peers"])
            expect("...nothing to add", shown("txProxyDetail"), false)
            expect("...the switch locked while it runs", prop("txProxySwitch", "enabled"), false)
            run({ network: "mainnet", txProxy: "on", txProxySocks: "127.0.0.1:9250", txProxyPeers: -1, txProxyWaiting: true,
                  txProxyRestart: false,
                  txProxyReason: "Tor is not available: tor_module is not loaded. Payments wait in the node until it is and a Tor peer connects." })
        },
        function (v) {
            expect("Tor down: still On, peers not known yet", prop("txProxyText", "text"), "On · 127.0.0.1:9250")
            expect("...and why payments wait", [shown("txProxyDetail"), prop("txProxyDetail", "text")],
                   [true, "Tor is not available: tor_module is not loaded. Payments wait in the node until it is and a Tor peer connects."])
            run({ network: "mainnet", txProxy: "on", txProxySocks: "127.0.0.1:9250", txProxyPeers: 0, txProxyWaiting: true,
                  txProxyRestart: false, txProxyReason: "No Tor peer yet. Payments wait in the node until one connects." })
        },
        function (v) {
            expect("no Tor peer yet", [prop("txProxyText", "text"), prop("txProxyDetail", "text")],
                   ["On · 127.0.0.1:9250 · 0 Tor peers", "No Tor peer yet. Payments wait in the node until one connects."])
            run({ network: "mainnet", txProxy: "on", txProxySocks: "127.0.0.1:9250", txProxyPeers: 1, txProxyWaiting: false,
                  txProxyRestart: false, txProxyReason: "" })
        },
        function (v) {
            expect("one Tor peer", [prop("txProxyText", "text"), shown("txProxyDetail")], ["On · 127.0.0.1:9250 · 1 Tor peer", false])
            run({ network: "mainnet", txProxy: "on", txProxySocks: "127.0.0.1:9250", txProxyPeers: 2, txProxyWaiting: true,
                  txProxyRestart: true,
                  txProxyReason: "Tor moved to 127.0.0.1:41234. Restart the node to use it; until then payments wait in the node." })
        },
        function (v) {
            expect("Tor moved: the module's restart hint", prop("txProxyDetail", "text"),
                   "Tor moved to 127.0.0.1:41234. Restart the node to use it; until then payments wait in the node.")
            expect("...and Restart is there", [shown("restartButton"), prop("restartButton", "enabled"), prop("restartButton", "text")], [true, true, "Restart"])
            find(view.item, "restartButton", 0).clicked()
        },
        function (v) {
            expect("Restart asks the backend to restart", (fake.last("restart") || [])[0], "restart")
            run({ network: "stagenet", txProxy: "off", txProxySocks: "", txProxyPeers: -1, txProxyWaiting: false,
                  txProxyReason: "", txProxyRestart: false })
            show("stagenet", cfg({ txProxy: false }))
        },
        function (v) {
            expect("stagenet running: Off", [prop("txProxyText", "text"), shown("txProxyDetail")], ["Off", false])
            run({ state: "stopped" })
            fake.statusJson = JSON.stringify({ state: "stopped" })
            var old = cfg({}); delete old.txProxy
            show("mainnet", old)
        },
        function (v) {
            expect("an older module: no switch", shown("txProxySwitch"), false)
            find(view.item, "saveButton", 0).clicked()
        },
        function (v) {
            expect("...and Save leaves the key out", saved().hasOwnProperty("txProxy"), false)
            expect("...but saves the rest", saved().proxy, "")
            fake.state = "running"
            fake.statusJson = JSON.stringify({ state: "running", network: "mainnet" })
        },
        function (v) {
            expect("...and no Tor row", [shown("txProxyText"), shown("txProxyDetail")], [false, false])
            expect("...Restart still works", prop("restartButton", "enabled"), true)
        }
    ]
    property int step: 0
    Timer {
        id: driver
        interval: 30
        repeat: true
        onTriggered: {
            try { scene.steps[scene.step](view.item) } catch (e) { bad.push("step " + scene.step + " threw " + e) }
            scene.step += 1
            if (scene.step >= scene.steps.length) {
                driver.stop()
                console.log(bad.length ? "STATES-FAIL " + bad.join("; ") : "STATES-OK " + scene.steps.length + " steps")
                Qt.quit()
            }
        }
    }

    Loader {
        id: view
        anchors.fill: parent
        source: "../src/qml/Main.qml"
        onStatusChanged: {
            if (status === Loader.Error) { console.log("STATES-FAIL load"); Qt.quit(); return }
            if (status === Loader.Ready) driver.start()
        }
    }
}
