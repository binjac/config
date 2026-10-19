#!/usr/bin/env python3
"""Live display (rich) for install_update_zsh.sh. Reads tab-separated events on stdin:
H title<TAB>subtitle<TAB>detail | P phase<TAB>total | B phase<TAB>key<TAB>label
E phase<TAB>key<TAB>state<TAB>seconds<TAB>note (state: done|have|skip|fail) | W message | N next step | L log path
"""

import sys
import threading
import time
from collections import deque

from rich.console import Console, Group
from rich.live import Live
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

BAR_WIDTH = 30
SYMBOL = {"done": ("✓", "green"), "have": ("✓", "green"), "skip": ("–", "yellow"), "fail": ("✗", "red")}


def fmt_s(seconds: float) -> str:
    seconds = int(seconds)
    return f"{seconds // 60}m{seconds % 60:02d}" if seconds >= 60 else f"{seconds}s"


class Display:
    def __init__(self):
        self.console = Console()
        self.lock = threading.RLock()
        self.header = {}
        self.phases = {}
        self.running = {}
        self.recent = deque(maxlen=8)
        self.issues = []
        self.next_steps = []
        self.log = ""
        self.counts = {"done": 0, "have": 0, "skip": 0, "fail": 0}
        self.t0 = time.time()
        self.live = Live(get_renderable=self.render, console=self.console, refresh_per_second=6, transient=False)

    def handle(self, line: str) -> None:
        kind, _, rest = line.partition("\t")
        f = rest.split("\t")
        with self.lock:
            if kind == "H":
                self.header = {"title": f[0], "sub": f[1] if len(f) > 1 else "", "detail": f[2] if len(f) > 2 else ""}
            elif kind == "P":
                self.phases[f[0]] = {"done": 0, "total": int(f[1]), "failed": 0, "skipped": 0, "t0": None, "t1": None}
            elif kind == "B":
                p = self.phases.get(f[0])
                if p and p["t0"] is None:
                    p["t0"] = time.time()
                self.running[f"{f[0]}:{f[1]}"] = (f[1], f[2] if len(f) > 2 else "", time.time())
            elif kind == "E":
                phase, key, state, secs = f[0], f[1], f[2], float(f[3] or 0)
                note = f[4] if len(f) > 4 else ""
                self.running.pop(f"{phase}:{key}", None)
                p = self.phases[phase]
                p["done"] += 1
                p["failed"] += state == "fail"
                p["skipped"] += state == "skip"
                if p["done"] >= p["total"]:
                    p["t1"] = time.time()
                self.counts[state] += 1
                if state in ("skip", "fail"):
                    self.issues.append((state, phase, key, note or state))
                self.recent.append((state, key, secs))
            elif kind == "W":
                self.live.console.print(f"[yellow]⚠️  {rest}[/]")
            elif kind == "N":
                self.next_steps.append(rest)
            elif kind == "L":
                self.log = rest

    def bar(self, p) -> Text:
        total = p["total"]
        filled = min(BAR_WIDTH, round(BAR_WIDTH * p["done"] / total)) if total else 0
        style = "red" if p["failed"] else "yellow" if p["skipped"] else "cyan"
        bar = Text("━" * filled, style=style)
        bar.append("━" * (BAR_WIDTH - filled), style="grey37")
        return bar

    def render(self):
        with self.lock:
            h = self.header
            lines = [Text()]
            if h:
                title = Text(f"🧰 {h['title']}", style="bold")
                title.append(f"  {h['sub']}", style="dim")
                lines.append(title)
                if h["detail"]:
                    lines.append(Text(f"   {h['detail']}", style="dim"))
                lines.append(Text())
            for name, p in self.phases.items():
                row = Text(f" {name:<14} ")
                row.append_text(self.bar(p))
                row.append(f"  {p['done']}/{p['total']}")
                running = sum(1 for k in self.running if k.startswith(name + ":"))
                if p["t1"] is None and running:
                    row.append(f"  · {running} running", style="cyan")
                if p["skipped"]:
                    row.append(f"  · {p['skipped']} skipped", style="yellow")
                if p["failed"]:
                    row.append(f"  · {p['failed']} failed", style="red")
                if p["t0"]:
                    row.append(f"  {fmt_s((p['t1'] or time.time()) - p['t0'])}", style="dim")
                if p["t1"]:
                    row.append("  ✓", style="green")
                lines.append(row)
            if self.running:
                lines.append(Text())
                now = time.time()
                for key, label, t in list(self.running.values())[:6]:
                    lines.append(Text(f"   ⠿ {key:<18} {label[:48]:<48} {fmt_s(now - t):>6}", style="cyan"))
            if self.recent:
                lines.append(Text())
                recent = Text("   ")
                for state, key, secs in self.recent:
                    sym, color = SYMBOL[state]
                    recent.append(f"{sym} {key} {fmt_s(secs)}   ", style=color)
                lines.append(recent)
            return Group(*lines)

    def results(self) -> None:
        c = self.console
        n = sum(self.counts.values())
        if not n:
            return
        ok = self.counts["done"] + self.counts["have"]
        color = "red" if self.counts["fail"] else "yellow" if self.counts["skip"] else "green"
        width = 48
        w_ok = round(width * ok / n)
        w_skip = round(width * self.counts["skip"] / n)
        bar = Text("█" * w_ok, style="green")
        bar.append("█" * w_skip, style="yellow")
        bar.append("█" * max(width - w_ok - w_skip, 0), style="red" if self.counts["fail"] else "grey23")
        head = Text()
        head.append(f"{ok}/{n}", style=f"bold {color}")
        head.append("  steps ok  ", style="dim")
        head.append(f"{self.counts['done']} applied", style="green")
        head.append(" · ")
        head.append(f"{self.counts['have']} already there", style="cyan")
        head.append(" · ")
        head.append(f"{self.counts['skip']} skipped", style="yellow")
        head.append(" · ")
        head.append(f"{self.counts['fail']} failed", style="red")
        c.print()
        c.print(Panel(Group(head, bar), title="[bold]Terminal setup[/]", title_align="left", border_style=color, padding=(1, 2)))
        for state, label, style in (("skip", "Skipped", "bold yellow"), ("fail", "Failed", "bold red")):
            rows = [i for i in self.issues if i[0] == state]
            if not rows:
                continue
            t = Table(title=label, title_justify="left", title_style=style, box=None, padding=(0, 2), show_edge=False)
            t.add_column("Step", style="dim")
            t.add_column("Item", style="bold")
            t.add_column("Why", overflow="ellipsis", no_wrap=True, max_width=90)
            for _, phase, key, note in rows:
                t.add_row(phase, key, note)
            c.print(t)
            c.print()
        foot = Table.grid(padding=(0, 2))
        foot.add_column(style="dim")
        foot.add_column(overflow="fold")
        for step in self.next_steps:
            foot.add_row("next", step)
        if self.log:
            foot.add_row("log", self.log)
        c.print(foot)
        c.print()


def main() -> None:
    d = Display()
    d.live.__enter__()
    try:
        for raw in sys.stdin:
            line = raw.rstrip("\n")
            if line:
                d.handle(line)
    finally:
        d.live.__exit__(None, None, None)
    d.results()


if __name__ == "__main__":
    main()
