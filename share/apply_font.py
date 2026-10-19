#!/usr/bin/env python3
"""Sets MesloLGS Nerd Font Mono Regular 13 in iTerm2 profiles or VS Code-like settings.
Usage: apply_font.py iterm | terminal | vscode. Prints a short status; exit 0 = changed, 3 = already set, 2 = skipped, 1 = error."""

import json
import plistlib
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

FONT_PS = "MesloLGSNFM-Regular"
FONT_ITERM = f"{FONT_PS} 13"
FAMILY = "MesloLGS Nerd Font Mono"
SIZE = 13
HOME = Path.home()
STAMP = time.strftime("%Y%m%d-%H%M%S")

CHANGED, ERROR, SKIPPED, SAME = 0, 1, 2, 3


def font_files():
    return [f for d in (HOME / "Library/Fonts", Path("/Library/Fonts")) for f in d.glob("MesloLGS*NerdFont*.ttf")]


def font_resolves() -> bool:
    script = 'ObjC.import("AppKit"); $.NSFont.fontWithNameSize("%s", 13).isNil() ? "no" : "yes"' % FONT_PS
    out = subprocess.run(["osascript", "-l", "JavaScript", "-e", script], capture_output=True, text=True)
    return out.stdout.strip() == "yes"


def ensure_font() -> str:
    """Empty string when macOS resolves the font, else the reason. Quarantined or unregistered files make apps fall back to Menlo."""
    if not font_files():
        return "MesloLGS Nerd Font Mono not installed"
    if font_resolves():
        return ""
    for f in font_files():
        subprocess.run(["xattr", "-d", "com.apple.quarantine", str(f)], capture_output=True)
    subprocess.run(["atsutil", "databases", "-removeUser"], capture_output=True)
    subprocess.run(["killall", "fontd"], capture_output=True)
    for _ in range(10):
        time.sleep(1)
        if font_resolves():
            return ""
    return "macOS does not resolve MesloLGSNFM-Regular (Font Book may show why)"


def iterm():
    prefs = HOME / "Library/Preferences/com.googlecode.iterm2.plist"
    dynamic = HOME / "Library/Application Support/iTerm2/DynamicProfiles/Custom.json"
    if subprocess.run(["pgrep", "-x", "iTerm2"], capture_output=True).returncode == 0:
        return SKIPPED, "iTerm2 is running: quit it (Cmd-Q) and rerun"
    changed = 0
    if prefs.exists():
        # go through cfprefsd: writing the file directly gets overwritten by its cache
        exported = subprocess.run(["defaults", "export", "com.googlecode.iterm2", "-"], capture_output=True)
        data = plistlib.loads(exported.stdout)
        for profile in data.get("New Bookmarks", []):
            if profile.get("Normal Font") != FONT_ITERM:
                profile["Normal Font"] = FONT_ITERM
                changed += 1
        if changed:
            shutil.copy2(prefs, f"{prefs}.bak.{STAMP}")
            done = subprocess.run(["defaults", "import", "com.googlecode.iterm2", "-"], input=plistlib.dumps(data), capture_output=True)
            if done.returncode != 0:
                print(done.stderr.decode().strip() or "defaults import failed")
                return ERROR, "defaults import failed"
    if dynamic.exists():
        doc = json.loads(dynamic.read_text())
        for profile in doc.get("Profiles", []):
            if profile.get("Normal Font") != FONT_ITERM:
                profile["Normal Font"] = FONT_ITERM
                changed += 1
        if changed:
            dynamic.write_text(json.dumps(doc, indent=2) + "\n")
    if not prefs.exists() and not dynamic.exists():
        return SKIPPED, "no iTerm2 profile yet"
    return (CHANGED, f"{changed} profile(s) set to {FONT_ITERM}") if changed else (SAME, "already set")


def terminal():
    running = subprocess.run(["pgrep", "-x", "Terminal"], capture_output=True).returncode == 0
    if running:
        # scripting works on the live app; its in-memory settings would overwrite the preferences file
        script = (f'tell application "Terminal"\nrepeat with s in settings sets\n'
                  f'set font name of s to "{FONT_PS}"\nset font size of s to {SIZE}\nend repeat\nend tell')
        done = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
        if done.returncode != 0:
            return ERROR, done.stderr.strip() or "osascript failed"
        return CHANGED, f"all profiles set to {FONT_PS} {SIZE} (live)"
    exported = subprocess.run(["defaults", "export", "com.apple.Terminal", "-"], capture_output=True)
    data = plistlib.loads(exported.stdout) if exported.stdout else {}
    profiles = data.get("Window Settings", {})
    if not profiles:
        return SKIPPED, "no Terminal.app profile yet"
    archive = plistlib.loads((Path(__file__).resolve().parent.parent / "terminal_config/Custom.terminal").read_bytes())["Font"]
    changed = 0
    for profile in profiles.values():
        if profile.get("Font") != archive:
            profile["Font"] = archive
            changed += 1
    if not changed:
        return SAME, "already set"
    done = subprocess.run(["defaults", "import", "com.apple.Terminal", "-"], input=plistlib.dumps(data), capture_output=True)
    if done.returncode != 0:
        return ERROR, done.stderr.decode().strip() or "defaults import failed"
    return CHANGED, f"{changed} profile(s) set to {FONT_PS} {SIZE}"


def set_key(text: str, key: str, value) -> str:
    literal = json.dumps(value)
    pattern = re.compile(r'("' + re.escape(key) + r'"\s*:\s*)("(?:[^"\\]|\\.)*"|[^,}\s]+)')
    if pattern.search(text):
        return pattern.sub(lambda m: m.group(1) + literal, text, count=1)
    if "{" not in text:
        return "{\n  " + f'"{key}": {literal}' + "\n}\n"
    head, tail = text.split("{", 1)
    rest = re.sub(r"//[^\n]*|/\*.*?\*/", "", tail, flags=re.S).strip()
    sep = "" if rest.startswith("}") else ","
    return head + "{\n  " + f'"{key}": {literal}{sep}' + tail


def vscode():
    base = HOME / "Library/Application Support"
    results = []
    for name in ("Code", "Code - Insiders", "Cursor", "VSCodium"):
        user = base / name / "User"
        if not user.is_dir():
            continue
        path = user / "settings.json"
        old = path.read_text() if path.exists() else ""
        new = set_key(set_key(old, "terminal.integrated.fontFamily", FAMILY), "terminal.integrated.fontSize", SIZE)
        if new == old:
            results.append((SAME, name))
            continue
        if path.exists():
            shutil.copy2(path, f"{path}.bak.{STAMP}")
        path.write_text(new)
        results.append((CHANGED, name))
    if not results:
        return SKIPPED, "no VS Code settings directory found"
    changed = [n for s, n in results if s == CHANGED]
    return (CHANGED, f"terminal font set in {', '.join(changed)}") if changed else (SAME, "already set")


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in ("iterm", "terminal", "vscode"):
        print(__doc__)
        return ERROR
    problem = ensure_font()
    if problem:
        print(problem)
        return SKIPPED if "not installed" in problem else ERROR
    code, msg = {"iterm": iterm, "terminal": terminal, "vscode": vscode}[sys.argv[1]]()
    print(msg)
    return code


if __name__ == "__main__":
    sys.exit(main())
