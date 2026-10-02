#!/usr/bin/env python3
"""Capture documentation screenshots of MDM Inspector.

Every view is opened via the app's launch arguments rather than by clicking, so
the capture is deterministic and does not depend on the window being in a
particular position or on synthetic clicks landing.

Requires an UNLOCKED screen — screencapture returns the login screen otherwise.

Usage:
    python3 tools/capture_screenshots.py
    python3 tools/capture_screenshots.py --out docs/screenshots --time-range 30m
"""
import argparse
import pathlib
import re
import subprocess
import sys
import time

APP = "/Applications/MDM Inspector.app"
PROC = "MDMInspector"

# (filename, launch args, human description)
SHOTS = [
    ("01-dashboard",   [],                       "Dashboard"),
    ("02-timeline",    ["-startView", "timeline", "-displayMode", "detailed"], "Timeline"),
    ("03-inspector",   ["-startView", "timeline", "-displayMode", "raw"],      "Raw evidence"),
    ("04-capabilities", ["-startView", "capabilities"],                        "Capabilities"),
]


def sh(cmd, timeout=180):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True,
                          timeout=timeout).stdout


def screen_is_locked(probe):
    subprocess.run(["screencapture", "-x", str(probe)], check=True)
    text = subprocess.run(["tesseract", str(probe), "stdout", "--psm", "11"],
                          capture_output=True, text=True).stdout
    return "Enter Password" in text


def launch(args):
    subprocess.run(["pkill", "-x", PROC], capture_output=True)
    time.sleep(2)
    cmd = ["open", "-a", APP]
    if args:
        cmd += ["--args"] + list(args)
    subprocess.run(cmd, capture_output=True)
    wait_idle()


def wait_idle(timeout=120):
    """The app loads the whole snapshot before showing a window; wait for the
    CPU to settle so the capture never catches a half-drawn view."""
    for _ in range(timeout // 3):
        pid = sh("pgrep -x MDMInspector").strip()
        if not pid:
            time.sleep(3)
            continue
        try:
            cpu = float(sh(f"ps -o %cpu= -p {pid}").strip() or 0)
        except ValueError:
            cpu = 0.0
        if cpu < 5:
            return True
        time.sleep(3)
    return False


def window_box():
    """Logical (x, y, w, h) of the app window, falling back to the default."""
    geom = sh(f"""osascript -e 'tell application "System Events" to tell process
        "{PROC}" to get {{position, size}} of window 1'""")
    m = re.search(r"(-?\d+),\s*(-?\d+),\s*(\d+),\s*(\d+)", geom)
    return tuple(int(g) for g in m.groups()) if m else (164, 103, 1400, 860)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="docs/screenshots")
    ap.add_argument("--time-range", default="30m")
    args = ap.parse_args()

    out = pathlib.Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    probe = out / "_probe.png"

    if screen_is_locked(probe):
        print("ERROR: the screen is locked. Unlock it and re-run — screenshots "
              "of the login screen are useless.")
        return 2
    probe.unlink(missing_ok=True)

    for name, launch_args, label in SHOTS:
        full = launch_args + ["-timeRange", args.time_range]
        print(f"→ {label} …", flush=True)
        launch(full)
        time.sleep(2)
        wx, wy, w, h = window_box()
        raw = out / f"{name}.raw.png"
        subprocess.run(["screencapture", "-x", str(raw)], check=True)
        subprocess.run(["sips", "-c", str(h * 2), str(w * 2),
                        "--cropOffset", str(wy * 2), str(wx * 2),
                        str(raw), "--out", str(out / f"{name}.png")],
                       capture_output=True, check=True)
        raw.unlink(missing_ok=True)
        print(f"  wrote {name}.png", flush=True)

    print("\nDone. Review the images before committing them.")
    return 0


if __name__ == "__main__":
    sys.exit(main())