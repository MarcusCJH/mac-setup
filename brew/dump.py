#!/usr/bin/env python3
"""Update a Brewfile to match what Homebrew has installed on this Mac.

    make dump-work  ->  brew/dump.py brew/Brewfile.work
    make dump-home  ->  brew/dump.py brew/Brewfile.home

Unlike `brew bundle dump`, your sections and comments stay. Entries that are no
longer installed are removed, along with any section they leave empty. Newly
installed packages go under a "New" section at the end, with Homebrew's
description, for you to move into the right section; new taps go with the
other taps. Only tap, brew, cask and vscode entries are synced; any other line
is left alone. Review the result with `git diff`.
"""
import json
import re
import subprocess
import sys

ENTRY = re.compile(r'(tap|brew|cask|vscode)\s+"([^"]+)"')
SECTION = "# ─── "
NEW_SECTION = "# ─── New: move these into a section ───────────────────"


def brew(*args):
    return subprocess.run(["brew", *args], check=True, capture_output=True, text=True).stdout


def full_names():
    """Map every name an installed formula or cask goes by (alias, old name,
    name without its tap) to the full name `brew bundle dump` writes."""
    info = json.loads(brew("info", "--json=v2", "--installed"))
    names = {}
    for f in info["formulae"]:
        for name in [f["full_name"], f["name"], *f["aliases"], *f["oldnames"]]:
            names["brew", name] = f["full_name"]
    for c in info["casks"]:
        for name in [c["full_token"], c["token"], *c.get("old_tokens", [])]:
            names["cask", name] = c["full_token"]
    return names


def trim(lines):
    """Drop blank lines from both ends."""
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    return lines


def main(path):
    with open(path) as f:
        original = f.read()
    names = full_names()

    def key(line):
        """(type, full name) for an entry line, None for anything else."""
        m = ENTRY.match(line)
        if m:
            kind, name = m.groups()
            return kind, names.get((kind, name), name).lower()

    # What's installed, as Brewfile lines with Homebrew's description
    installed = {}
    desc = ""
    dump = brew("bundle", "dump", "--file=-", "--tap", "--formula", "--cask", "--vscode")
    for line in dump.splitlines():
        if line.startswith("#"):
            desc = line.lstrip("# ")
        elif key(line):
            installed[key(line)] = f"{line:<26} # {desc}" if desc else line
            desc = ""

    # Each section is a "# ─── " header and the lines up to the next one
    sections = [[]]
    for line in original.splitlines():
        if line.startswith(SECTION):
            sections.append([])
        sections[-1].append(line)

    out, removed = [], []
    for section in sections:
        keep = [l for l in section if not key(l) or key(l) in installed]
        removed += [l for l in section if l not in keep]
        # Drop a section whose entries are all gone, header and all
        if any(key(l) for l in section) and not any(key(l) for l in keep):
            continue
        out.append(trim(keep))

    listed = {key(l) for s in out for l in s}
    added = [line for k, line in installed.items() if k not in listed]
    taps = [l for l in added if key(l)[0] == "tap"]
    others = [l for l in added if key(l)[0] != "tap"]

    # New taps go after the last tap, or with the other new entries if there is none
    for s in out:
        tap_lines = [i for i, l in enumerate(s) if key(l) and key(l)[0] == "tap"]
        if taps and tap_lines:
            s[tap_lines[-1] + 1:tap_lines[-1] + 1] = taps
            taps = []
    others = taps + others

    if others:
        new = next((s for s in out if s and s[0] == NEW_SECTION), None)
        if new is None:
            new = [NEW_SECTION]
            out.append(new)
        new += others

    text = "\n\n".join("\n".join(s) for s in out if s) + "\n"
    if text != original:
        with open(path, "w") as f:
            f.write(text)

    for line in removed:
        print("-", ENTRY.match(line).group(0))
    for line in added:
        print("+", ENTRY.match(line).group(0))
    if not removed and not added:
        print(f"{path} already matches what's installed")
    elif others:
        print(f'Move the new entries in {path} from "New" into the right sections.')


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(f"usage: {sys.argv[0]} <Brewfile>")
    try:
        main(sys.argv[1])
    except FileNotFoundError as e:
        sys.exit(f"Not found: {e.filename}")
    except subprocess.CalledProcessError as e:
        sys.exit(e.stderr.strip())
