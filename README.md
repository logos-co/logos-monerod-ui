# logos-monerod-ui

`monerod_ui` manages the Monero node that
[`monerod_module`](../logos-monerod-module) runs in-process: start and stop it, watch it
sync, change its settings, and read its log.

```bash
nix build .#install        # -dev variant, for logos-standalone-app
nix build .#ui-dev         # then: ./result/bin/run-logos-standalone-ui
```

Settings are per network and apply on the next start. The network and the settings form
are locked while the node runs. RPC binds to `127.0.0.1` only, so nothing else on the
network can reach the node. A mainnet node downloads about 60 GB pruned, 250 GB unpruned;
the view warns about it before a mainnet start.

The view polls `status()` every 2 s instead of subscribing to `monerodStateChanged`: a UI
plugin's subscription is refused if it is armed before the registry handshake settles, and
a panel built on it silently shows nothing.

## Intents

The app **provides** `monero.node.configure` (handoff). A request may carry
`{"network": "stagenet"}`; if the node is stopped the view switches to that network.

## Doctests

`doctests/run.sh` runs `monerod-ui-app.test.yaml` under `logos-doctest`: it starts a fresh
stagenet node from the UI, waits for **Syncing**, and stops it. It needs outbound P2P to
stagenet peers; the first one has taken anywhere from 10 s to 4 minutes to appear.

`doctests/assert_sync.py` checks what a spec cannot compare: that the height rises, and that
the bar stays empty and reads **Waiting for peers** until a peer reports the chain height.
Run it against an app started with `QT_QPA_PLATFORM=offscreen QML_INSPECTOR_PORT=3768`.
