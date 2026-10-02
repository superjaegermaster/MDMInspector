#!/usr/bin/env python3
"""Capture documentation screenshots of MDM Inspector.

Each view is opened through the app's launch arguments (`-startView`,
`-displayMode`, `-timeRange`) rather than by clicking, so captures are
deterministic and reproducible.

Requires an UNLOCKED screen: `screencapture` otherwise returns the login screen.
The script refuses to run in that case rather than saving a useless picture.

Usage:
    python3 tools/capture_screenshots.py
    python3 tools/capture_screenshots.py --out docs/screenshots --time-range 30m
"""
import argparse
import hashlib
import pathlib
import tempfile
import re
import subprocess
import sys
import time

APP = "/Applications/MDM Inspector.app"
PROC = "MDMInspector"

SHOTS = [
    ("01-dashboard",    [],                                  "Dashboard"),
    ("02-timeline",     ["-startView", "timeline", "-displayMode", "detailed"], "Timeline"),
    ("03-inspector",    ["-startView", "timeline", "-displayMode", "raw"],      "Raw evidence"),
    ("04-capabilities", ["-startView", "capabilities"],                        "Capabilities"),
]

# NOTE: every AppleScript literal must stay on ONE line. `osascript -e` treats a
# wrapped statement as a syntax error, which silently breaks the frontmost check
# and yields screenshots of whatever window happens to be on top.
AS_FRONT = ("osascript -e 'tell application \"System Events\" to tell process "
            + '"' + PROC + '"' + " to set frontmost to true'")
AS_ACTIVATE = "osascript -e 'tell application " + '"' + PROC + '"' + " to activate'"
AS_FRONT_NAME = ("osascript -e 'tell application \"System Events\" to get name of "
                 "first application process whose frontmost is true'")
AS_WINDOW = ("osascript -e 'tell application \"System Events\" to tell process "
             + '"' + PROC + '"' + " to get {position, size} of window 1'")


def sh(cmd, timeout=180):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True,
                          timeout=timeout).stdout


def is_frontmost():
    return PROC.lower() in sh(AS_FRONT_NAME).strip().lower()


def screen_is_locked(probe):
    subprocess.run(["screencapture", "-x", str(probe)], check=True)
    text = subprocess.run(["tesseract", str(probe), "stdout", "--psm", "11"],
                          capture_output=True, text=True).stdout
    return "Enter Password" in text


def wait_idle(timeout=150, stable_checks=2):
    """Wait until the app has genuinely finished loading.

    CPU alone is NOT enough: between collectors the load briefly drops below 5%,
    which made an earlier version capture the dashboard at 2% ("loading...",
    20 000 logs so far) with all stat cards still zero.

    So require two independent signals: low CPU, AND a window whose pixels stop
    changing between consecutive captures. A finished UI is pixel-stable.
    """
    tmp = pathlib.Path(tempfile.gettempdir()) / "mdi_idle.png"
    quiet = 0
    prev = None
    for _ in range(timeout // 3):
        pid = sh("pgrep -x MDMInspector").strip()
        if not pid:
            time.sleep(3)
            continue
        try:
            cpu = float(sh("ps -o %cpu= -p " + pid).strip() or 0)
        except ValueError:
            cpu = 0.0

        if cpu >= 5:
            quiet = 0
            prev = None
            time.sleep(3)
            continue

        quiet += 1
        # Compare the whole screen across two samples ~2s apart.
        # (`screencapture -R` is not usable here — it fails with "could not
        # create image from rect" on this display.)
        try:
            tmp.unlink(missing_ok=True)
        except OSError:
            pass
        subprocess.run(["screencapture", "-x", str(tmp)], capture_output=True)
        digest = (hashlib.sha256(tmp.read_bytes()).hexdigest()
                  if tmp.exists() and tmp.stat().st_size else None)
        unchanged = digest is not None and digest == prev
        prev = digest

        if quiet >= stable_checks and unchanged:
            return True
        time.sleep(2)
    return False


def launch(args):
    subprocess.run(["pkill", "-x", PROC], capture_output=True)
    time.sleep(2)
    cmd = ["open", "-a", APP]
    if args:
        cmd += ["--args"] + list(args)
    subprocess.run(cmd, capture_output=True)
    wait_idle()


def activate(attempts=15):
    """Bring the app forward and confirm it really got there.

    Needed because a crop is taken at the window's coordinates: those pixels
    belong to whatever is drawn there, so if another app is in front the capture
    silently photographs the wrong thing.
    """
    for _ in range(attempts):
        sh(AS_FRONT)
        sh(AS_ACTIVATE)
        time.sleep(1.0)
        if is_frontmost():
            time.sleep(1.0)
            return True
    return False


def window_box():
    geom = sh(AS_WINDOW)
    m = re.search(r"(-?\d+),\s*(-?\d+),\s*(\d+),\s*(\d+)", geom)
    return tuple(int(g) for g in m.groups()) if m else (164, 103, 1400, 860)


def dashboard_has_data(out):
    """OCR the dashboard's status bar: a finished snapshot shows a real event
    count and the absence of the word 'loading'. Guards against committing a
    screenshot of a half-loaded UI."""
    shot = out / "_check.png"
    subprocess.run(["screencapture", "-x", str(shot)], check=True)
    subprocess.run(["sips", "-c", "120", "2800", "--cropOffset",
                    str((103 + 860 - 30) * 2), str(164 * 2),
                    str(shot), "--out", str(out / "_check_c.png")],
                   capture_output=True)
    text = subprocess.run(["tesseract", str(out / "_check_c.png"), "stdout",
                           "--psm", "7"], capture_output=True, text=True).stdout
    text = text.strip().lower()
    (out / "_check_c.png").unlink(missing_ok=True)
    shot.unlink(missing_ok=True)
    if "loading" in text:
        return False
    import re
    counts = [int(n.replace(",", "")) for n in re.findall(r"\d[\d,]*", text)]
    return any(c > 0 for c in counts)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="docs/screenshots")
    ap.add_argument("--time-range", default="30m")
    args = ap.parse_args()

    out = pathlib.Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    probe = out / "_probe.png"

    if screen_is_locked(probe):
        print("ERROR: screen is locked. Unlock it and re-run - a screenshot of "
              "the login screen is useless for documentation.")
        return 2
    probe.unlink(missing_ok=True)

    failures = 0
    for name, extra, label in SHOTS:
        print("-> " + label + " ...", flush=True)
        launch(extra + ["-timeRange", args.time_range])
        if not activate() or not is_frontmost():
            print("  ! " + label + ": could not bring to front, skipping", flush=True)
            failures += 1
            continue
        time.sleep(1)
        wx, wy, w, h = window_box()
        if name == "01-dashboard" and not dashboard_has_data(out):
            print("  ! Dashboard still looks empty/loading, retrying", flush=True)
            for _ in range(2):
                launch(extra + ["-timeRange", args.time_range])
                activate()
                time.sleep(2)
                if dashboard_has_data(out):
                    break
        raw = out / (name + ".raw.png")
        subprocess.run(["screencapture", "-x", str(raw)], check=True)
        subprocess.run(["sips", "-c", str(h * 2), str(w * 2),
                        "--cropOffset", str(wy * 2), str(wx * 2),
                        str(raw), "--out", str(out / (name + ".png"))],
                       capture_output=True, check=True)
        raw.unlink(missing_ok=True)
        print("  wrote " + name + ".png", flush=True)

    if failures:
        print("\n" + str(failures) + " view(s) skipped. Review the images that "
              "were written before committing them.")
    else:
        print("\nDone. Review the images before committing them.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
