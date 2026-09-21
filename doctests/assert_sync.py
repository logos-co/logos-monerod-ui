#!/usr/bin/env python3
# Drives monerod_ui start -> sync -> stop over the QML inspector on 3768 and checks the numbers
# a doctest cannot: the height rises, and the bar stays empty until a peer reports a target.
import base64, json, socket, sys, time
from pathlib import Path

OUT = Path.cwd() / "shots"
OUT.mkdir(exist_ok=True)
FAIL = []
_id = 0

def call(cmd, params=None, timeout=30):
    global _id
    _id += 1
    s = socket.create_connection(("127.0.0.1", 3768), timeout=timeout)
    s.sendall((json.dumps({"id": _id, "command": cmd, "params": params or {}}) + "\n").encode())
    buf = b""
    while b"\n" not in buf:
        c = s.recv(1 << 22)
        if not c:
            break
        buf += c
    s.close()
    return json.loads(buf.decode().splitlines()[0]) if buf else {}

def oid(name):
    m = call("findByProperty", {"property": "objectName", "value": name}).get("matches") or []
    return m[0]["id"] if m else None

def props(name):
    i = oid(name)
    if i is None:
        return {}
    raw = call("getProperties", {"objectId": i}).get("properties") or {}
    return {d["name"]: d.get("value") for d in raw} if isinstance(raw, list) else raw

def ev(expr):
    r = call("evaluate", {"objectId": oid("monerodRoot"), "expression": expr})
    if "error" in r:
        raise RuntimeError(f"eval({expr}): {r['error']}")
    return r.get("result")

def click(name):
    i = oid(name)
    if i is None:
        raise RuntimeError(f"no {name}")
    call("callMethod", {"objectId": i, "method": "clicked", "args": []})

def shot(name):
    r = call("screenshot", {}, timeout=60)
    if not r.get("image"):
        print(f"  screenshot {name}: {r.get('error', 'no image')}")
        return
    (OUT / name).write_bytes(base64.b64decode(r["image"]))
    print(f"  screenshot {name} ({r.get('width')}x{r.get('height')})")

def check(label, ok, got=None):
    print(("  PASS  " if ok else "  FAIL  ") + label + ("" if ok else f"   got={got!r}"))
    if not ok:
        FAIL.append(label)

def wait(fn, what, timeout, interval=2):
    end = time.time() + timeout
    last = None
    while time.time() < end:
        try:
            v = fn()
            if v:
                return v
        except Exception as e:
            last = e
        time.sleep(interval)
    raise TimeoutError(f"timed out waiting for {what} ({last})")

def snap():
    return {
        "state": ev("nodeState"),
        "height": ev("height_"),
        "target": ev("target_"),
        "heightText": props("heightText").get("text"),
        "syncText": props("syncText").get("text"),
        "pct": props("syncPercent").get("text") if props("syncPercent").get("visible") else None,
        "known": ev("targetKnown"),
        "synced": bool(ev("st.synchronized")),
        "fill": props("syncBarFill").get("width"),
        "peers": props("peersText").get("text"),
    }

print("1) the view comes up bound to its backend")
wait(lambda: oid("monerodRoot") is not None and ev("ready"), "view ready", 120)
wait(lambda: ev("nodeState") != "", "first status()", 30)
check("view is ready", ev("ready") is True, ev("ready"))
check("node starts stopped", ev("nodeState") == "stopped", ev("nodeState"))
check("heightText says Not running", props("heightText").get("text") == "Not running",
      props("heightText").get("text"))
if ev("backend.network") != "stagenet":
    ev('backend.selectNetwork("stagenet")')
    wait(lambda: ev("backend.network") == "stagenet", "network stagenet", 30)
check("network is stagenet", ev("backend.network") == "stagenet", ev("backend.network"))
wait(lambda: ev("cfg.rpcBindPort") is not None, "config loaded", 30)
check("config form loaded (rpc 38081)", ev("cfg.rpcBindPort") == 38081, ev("cfg.rpcBindPort"))
check("Start enabled, Stop disabled",
      props("startButton").get("enabled") is True and props("stopButton").get("enabled") is False,
      (props("startButton").get("enabled"), props("stopButton").get("enabled")))
shot("01-stopped.png")

print("1b) the sync label never calls a peerless node Synchronized")
# syncLabel is pure, so every state can be checked without holding a node in it.
for label, args, want in [
    ("peers + synchronized", "true, 2, false", "Synchronized"),
    ("synchronized but no peers", "true, 0, false", "No peers"),
    ("behind with a known target", "false, 2, true", "Syncing"),
    ("no target yet", "false, 0, false", "Waiting for peers"),
]:
    got = ev(f"syncLabel({args})")
    check(f"{label} -> {want}", got == want, got)

print("2) Start -> running")
t0 = time.time()
click("startButton")
wait(lambda: ev("nodeState") in ("running", "failed"), "running", 120)
check("state reaches running", ev("nodeState") == "running",
      (ev("nodeState"), ev("backend.lastError"), ev("st.lastError")))
print(f"    running after {time.time() - t0:.1f}s")
check("Stop enabled while running", props("stopButton").get("enabled") is True,
      props("stopButton").get("enabled"))

print("3) the sync bar advances")
samples = []
def advanced():
    s = snap()
    samples.append((round(time.time() - t0), s))
    print(f"    t+{samples[-1][0]:>4}s  {s['heightText']!s:<24} {s['syncText']!s:<18} {s['pct']!s:<6} fill={s['fill']} peers={s['peers']}")
    heights = [x[1]["height"] or 0 for x in samples]
    rises = sum(1 for a, b in zip(heights, heights[1:]) if b > a)
    return s["height"] and s["height"] > 1 and rises >= 2 and (s["fill"] or 0) > 0
wait(advanced, "height to rise twice with a non-empty bar", 900, interval=10)
first = next(s for _, s in samples if s["height"] is not None)
last = samples[-1][1]
check("height rose", (last["height"] or 0) > (first["height"] or 0), (first, last))
check("bar fill grew above zero", (last["fill"] or 0) > 0, last["fill"])
check("heightText is 'Height h / t'",
      last["heightText"] == f"Height {last['height']} / {last['target']}", last["heightText"])
check("status says Syncing with a percentage beside it",
      last["syncText"] == "Syncing" and (last["pct"] or "").endswith("%"), (last["syncText"], last["pct"]))
blind = [x for x in samples if not x[1]["known"] and not x[1]["synced"]]
print(f"    {len(blind)} sample(s) with no target yet")
check("with no target the bar is empty", all((x[1]["fill"] or 0) == 0 for x in blind),
      [x for x in blind if (x[1]["fill"] or 0) != 0][:2])
check("with no target it says Waiting for peers",
      all(x[1]["syncText"] == "Waiting for peers" and " / " not in x[1]["heightText"]
          and x[1]["pct"] is None for x in blind),
      [x for x in blind if x[1]["syncText"] != "Waiting for peers"][:2])
check("peers shown", "out" in (last["peers"] or ""), last["peers"])
log = props("logText").get("text") or ""
check("log pane has daemon output", len(log.strip().splitlines()) > 3, log[:200])
shot("02-syncing.png")

print("4) Stop -> stopped")
t1 = time.time()
click("stopButton")
wait(lambda: ev("nodeState") != "running", "leaving running", 30)
check("the card says Stopping… while it winds down, not Not running",
      props("heightText").get("text") in ("Stopping…", "Not running") and
      (ev("nodeState") != "stopping" or props("heightText").get("text") == "Stopping…"),
      (ev("nodeState"), props("heightText").get("text")))
wait(lambda: ev("nodeState") == "stopped", "stopped", 90)
check("state returns to stopped", ev("nodeState") == "stopped", ev("nodeState"))
print(f"    stopped after {time.time() - t1:.1f}s")
check("heightText back to Not running", props("heightText").get("text") == "Not running",
      props("heightText").get("text"))
check("Start re-enabled", props("startButton").get("enabled") is True,
      props("startButton").get("enabled"))
shot("03-stopped-again.png")

print("\n" + (f"{len(FAIL)} FAILED: {FAIL}" if FAIL else "all passed"))
sys.exit(1 if FAIL else 0)
