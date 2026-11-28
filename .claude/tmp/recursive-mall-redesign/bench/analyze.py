"""Score a mall benchmark run (bench.lua's JSON) against its computed optimum; write an HTML report.

    python analyze.py run.json [other.json ...] -o report.html
"""
import argparse
import html
import json
import math
import sys

WORKING = {"working"}
STARVED = {"waiting_for_source_items", "item_ingredient_shortage", "fluid_ingredient_shortage"}
FULL = {"full_output", "waiting_for_space_in_destination"}
BUCKETS = ["useful", "surplus", "switching", "starved", "full", "other", "none"]

# Categorical slots, fixed order (dataviz reference palette, light mode).
SERIES = ["#257de0", "#f47230", "#00b894", "#f2a600", "#ee7fac", "#008a17", "#6a4ce2", "#ec4647"]
OTHER = "#9c9c9c"
STATE_OPACITY = {"useful": 1.0, "surplus": 1.0, "switching": 0.45, "starved": 0.25, "full": 0.6, "other": 0.25}


def mean_prod(run):
    cells = run["cells"]
    return sum(c["prod"] for c in cells) / len(cells)


def topo(run):
    """Tree items, each after every item that consumes it (target first)."""
    tree, recipes, order, seen = run["tree"], run["recipes"], [], set()

    def visit(item):
        if item in seen or item not in tree:
            return
        seen.add(item)
        for ing, _ in recipes[tree[item]]["ingredients"]:
            visit(ing)
        order.append(item)

    visit(run["target"])
    return order[::-1]


def ideal(run):
    tree, recipes, stock = run["tree"], run["recipes"], run["stock0"]
    prod = mean_prod(run)
    demand = {run["target"]: run["n"]}
    crafts = {}
    for item in topo(run):
        net = max(0, demand.get(item, 0) - stock.get(item, 0))
        r = recipes[tree[item]]
        out = next(a for p, a in r["products"] if p == item)
        k = math.ceil(net / (out * (1 + prod)) - 1e-9)
        if k:
            crafts[tree[item]] = crafts.get(tree[item], 0) + k
        for ing, a in r["ingredients"]:
            demand[ing] = demand.get(ing, 0) + k * a
    speeds = [c["speed"] for c in run["cells"]]
    time = sum(k * recipes[r]["energy"] * 60 for r, k in crafts.items()) / sum(speeds)

    def chain(item):
        if item not in tree:
            return 0
        r = recipes[tree[item]]
        return r["energy"] * 60 / max(speeds) + max([chain(i) for i, _ in r["ingredients"]] or [0])

    raw = {i: a for i, a in demand.items() if i not in tree}
    return {"crafts": crafts, "time": time, "chain": chain(run["target"]), "raw": raw}


def by_cell(run):
    ev = {i: [] for i in range(1, len(run["cells"]) + 1)}
    for e in run["events"]:
        ev[e[1]].append(e)
    return ev


def segments(run):
    """Per cell: [t0, t1, recipe, state], covering 0..t_end."""
    out = []
    for i, evs in by_cell(run).items():
        segs, last, recipe, status, switching = [], 0, "-", "", False

        def close(t):
            if t <= last:
                return
            if recipe == "-":
                st = "none"
            elif status in WORKING:
                st = "useful"
            elif switching:
                st = "switching"
            elif status in STARVED:
                st = "starved"
            elif status in FULL:
                st = "full"
            else:
                st = "other"
            if segs and segs[-1][1] == last and segs[-1][2:] == [recipe, st]:
                segs[-1][1] = t
            else:
                segs.append([last, t, recipe, st])

        for e in evs:
            close(e[0])
            last = max(last, e[0])
            if e[2] == "r":
                recipe, switching = e[3], e[3] != "-"
            elif e[2] == "s":
                status = e[3]
            elif e[2] == "c" and e[3] == recipe:
                switching = False
        close(run["t_end"])
        out.append(segs)
    return out


def cell_buckets(run):
    res = []
    for segs in segments(run):
        b = dict.fromkeys(BUCKETS, 0)
        for t0, t1, _, st in segs:
            b[st] += t1 - t0
        res.append(b)
    left = dict(ideal(run)["crafts"])
    crafts = sorted((e for e in run["events"] if e[2] == "c"), key=lambda e: e[0])
    for t, cell, _, recipe, n in crafts:
        for _ in range(n):
            if left.get(recipe, 0) > 0:
                left[recipe] -= 1
                continue
            ticks = run["recipes"][recipe]["energy"] * 60 / run["cells"][cell - 1]["speed"]
            moved = min(ticks, res[cell - 1]["useful"])
            res[cell - 1]["useful"] -= moved
            res[cell - 1]["surplus"] += moved
    return res


def energy(run):
    first, last = run["samples"][0], run["samples"][-1]
    by_type = {}
    for proto, j in last["j"].items():
        t = run["types"].get(proto, proto)
        by_type[t] = by_type.get(t, 0) + j - first["j"].get(proto, 0)
    rec = run["recipes"]
    consumed = produced = dumped = 0
    for e in run["events"]:
        if e[2] == "c":
            consumed += e[4] * sum(a for _, a in rec[e[3]]["ingredients"])
            produced += e[4] * sum(a for _, a in rec[e[3]]["products"])
        elif e[2] == "d":
            dumped += e[4]
    held = sum(last["held"]) - sum(first["held"])
    robot_items = (consumed + dumped + held) + (produced + dumped)
    prod = mean_prod(run)
    ideal_items = sum(k * (sum(a for _, a in rec[r]["ingredients"]) + (1 + prod) * sum(a for _, a in rec[r]["products"]))
                      for r, k in ideal(run)["crafts"].items())
    robot_j = by_type.get("roboport", 0)
    return {"by_type": by_type, "total": sum(by_type.values()), "robot_j": robot_j, "robot_items": robot_items,
            "dumped": dumped, "ideal_robot_items": ideal_items,
            "ideal_robot_j": robot_j / robot_items * ideal_items if robot_items else None}


def switch_waits(run):
    """Per switch-in during the run: ticks from the recipe being set until its first craft could start.
    Recipes held at t = 0 came loaded, so they don't count. Switches abandoned before a craft are not here."""
    waits = []
    for i, evs in by_cell(run).items():
        since = None
        for e in evs:
            if e[2] == "r":
                since = e[0] if e[0] > 0 and e[3] != "-" else None
            elif e[2] == "c" and since is not None:
                waits.append(max(0, e[0] - since - run["recipes"][e[3]]["energy"] * 60 / run["cells"][i - 1]["speed"]))
                since = None
    return sorted(waits)


def startup(run):
    """The fastest switch-in: the least a recipe change costs in this mall."""
    w = switch_waits(run)
    return w[0] if w else None


def score(run):
    idl, en = ideal(run), energy(run)
    perfect = max(idl["time"], idl["chain"])
    s = startup(run)
    realistic = perfect + (s or 0)
    t = run.get("t_delivered_n")
    mj = 1e6
    made = sum(e[4] for e in run["events"] if e[2] == "c" and e[3] == run["tree"][run["target"]])
    w = switch_waits(run)
    return {
        "t_delivered": t, "t_made": run.get("t_made_n"), "t_end": run["t_end"], "ended": run["ended"], "made": made,
        "perfect": perfect, "realistic": realistic, "startup": s,
        "switches": sum(1 for e in run["events"] if e[2] == "r" and e[0] > 0),
        "switch_wait_median": w[len(w) // 2] if w else None,
        "pct_perfect": 100 * perfect / t if t else None, "pct_realistic": 100 * realistic / t if t else None,
        "mj": en["total"] / mj, "mj_per": en["total"] / mj / made if made else None,
        "robot_mj": en["robot_j"] / mj,
        "ideal_robot_mj": en["ideal_robot_j"] / mj if en["ideal_robot_j"] is not None else None,
        "robot_items": en["robot_items"], "ideal_robot_items": en["ideal_robot_items"], "dumped": en["dumped"],
        "by_type": {k: v / mj for k, v in sorted(en["by_type"].items(), key=lambda kv: -kv[1])},
        "ideal_crafts": idl["crafts"], "raw": idl["raw"],
    }


def recipe_mismatch(run):
    """Recipes the cells used for a tree item that differ from the one the optimum assumed."""
    used = {e[3] for e in run["events"] if e[2] == "r" and e[3] != "-"}
    product_of = {}
    for r in used:
        for p, _ in run["recipes"][r]["products"]:
            product_of.setdefault(p, set()).add(r)
    return {item: sorted(rs - {run["tree"][item]}) for item, rs in product_of.items()
            if item in run["tree"] and rs - {run["tree"][item]}}


# ---------- HTML ----------

def colours(runs):
    """Recipe -> colour. Tree recipes first (target down), then by total crafting time; 8 slots, rest grey."""
    order = []
    for r in runs:
        for item in topo(r):
            if r["tree"][item] not in order:
                order.append(r["tree"][item])
    ticks = {}
    for r in runs:
        for segs in segments(r):
            for t0, t1, rec, _ in segs:
                if rec != "-":
                    ticks[rec] = ticks.get(rec, 0) + t1 - t0
    order = [o for o in order if o in ticks] + sorted((k for k in ticks if k not in order), key=lambda k: -ticks[k])
    return {rec: SERIES[i] if i < len(SERIES) else OTHER for i, rec in enumerate(order)}, order


def pct(v):
    return "n/a" if v is None else f"{v:.0f}%"


def fmt_t(t):
    return "not reached" if t is None else f"{t:,.0f} t ({t / 60:,.0f} s)"


def fmt(v, d=1):
    return "n/a" if v is None else f"{v:,.{d}f}"


def svg_timeline(run, col, t_max, width=1100):
    lane, gap, left, top = 12, 3, 40, 18
    segs = segments(run)
    sx = (width - left - 10) / t_max
    h_lanes = len(segs) * (lane + gap)
    strip = 60
    h = top + h_lanes + 20 + strip + 24
    o = [f'<svg viewBox="0 0 {width} {h}" width="100%" role="img" aria-label="Timeline for {html.escape(run["tag"])}">']
    step = next(st for st in (600, 1200, 1800, 3600, 7200, 18000) if t_max / st <= 15)
    for k in range(0, int(t_max) + 1, step):
        x = left + k * sx
        o.append(f'<line x1="{x:.1f}" y1="{top - 4}" x2="{x:.1f}" y2="{top + h_lanes}" class="grid"/>')
        o.append(f'<text x="{x:.1f}" y="{top - 6}" class="axis" text-anchor="middle">{k // 3600}:{k // 60 % 60:02d}</text>')
    for i, cs in enumerate(segs):
        y = top + i * (lane + gap)
        o.append(f'<text x="{left - 6}" y="{y + lane - 2}" class="axis" text-anchor="end">C{i + 1}</text>')
        prev = None
        for t0, t1, rec, st in cs:
            if rec != prev and prev is not None:
                o.append(f'<line x1="{left + t0 * sx:.1f}" y1="{y - 1}" x2="{left + t0 * sx:.1f}" y2="{y + lane + 1}" class="switch"/>')
            prev = rec
            if st == "none":
                continue
            c = col.get(rec, OTHER)
            tip = f"C{i + 1} {rec}: {st}, {t0}–{t1} ({t1 - t0} t)"
            o.append(f'<rect x="{left + t0 * sx:.1f}" y="{y}" width="{max(0.5, (t1 - t0) * sx):.1f}" height="{lane}" '
                     f'fill="{c}" fill-opacity="{STATE_OPACITY[st]}"><title>{html.escape(tip)}</title></rect>')
    for name, t in (("50 delivered", run.get("t_delivered_n")), ("perfect", score(run)["perfect"])):
        if t:
            x = left + t * sx
            o.append(f'<line x1="{x:.1f}" y1="{top - 4}" x2="{x:.1f}" y2="{top + h_lanes}" class="mark"/>'
                     f'<text x="{x + 3:.1f}" y="{top + h_lanes + 12}" class="axis">{name}</text>')
    # Power strip: total and roboports, MW, from the 60-tick samples.
    y0 = top + h_lanes + 20 + strip
    s = run["samples"]
    pts_all, pts_robo, peak = [], [], 1e-9
    for a, b in zip(s, s[1:]):
        dt = (b["t"] - a["t"]) / 60
        if dt <= 0:
            continue
        tot = sum(b["j"].values()) - sum(a["j"].values())
        robo = sum(v - a["j"].get(p, 0) for p, v in b["j"].items() if run["types"].get(p) == "roboport")
        pts_all.append((b["t"], tot / dt / 1e6))
        pts_robo.append((b["t"], robo / dt / 1e6))
        peak = max(peak, tot / dt / 1e6)
    for pts, cls, label in ((pts_all, "pw-all", "all"), (pts_robo, "pw-robo", "roboports")):
        if pts:
            path = " ".join(f"{left + t * sx:.1f},{y0 - v / peak * strip:.1f}" for t, v in pts)
            o.append(f'<polyline points="{path}" class="{cls}"><title>{label} MW</title></polyline>')
    o.append(f'<text x="{left - 6}" y="{y0 - strip + 8}" class="axis" text-anchor="end">{peak:.0f} MW</text>')
    o.append(f'<text x="{left - 6}" y="{y0}" class="axis" text-anchor="end">0</text>')
    o.append(f'<line x1="{left}" y1="{y0}" x2="{width - 10}" y2="{y0}" class="grid"/>')
    o.append("</svg>")
    return "".join(o)


def render(runs):
    col, order = colours(runs)
    t_max = max(r["t_end"] for r in runs)
    e = html.escape
    o = [STYLE, '<div class="viz-root"><h1>Mall benchmark</h1>']
    o.append('<table><tr><th>run</th><th>delivered</th><th>perfect</th><th>% of perfect</th><th>realistic</th>'
             '<th>% of realistic</th><th>all idle</th><th>MJ</th><th>MJ / item</th><th>robot MJ</th>'
             '<th>ideal robot MJ</th><th>robot items (ideal)</th><th>dumped</th><th>recipe changes</th>'
             '<th>median switch wait</th></tr>')
    for r in runs:
        s = score(r)
        got = fmt_t(s["t_delivered"]) + ("" if s["t_delivered"] else f' ({s["made"]} of {r["n"]} made)')
        o.append(f'<tr><td>{e(r["tag"])}</td><td>{got}</td><td>{fmt_t(s["perfect"])}</td>'
                 f'<td>{pct(s["pct_perfect"])}</td><td>{fmt_t(s["realistic"])}</td><td>{pct(s["pct_realistic"])}</td>'
                 f'<td>{fmt_t(s["t_end"]) if s["ended"] == "idle" else "cap hit at " + fmt_t(s["t_end"])}</td>'
                 f'<td>{fmt(s["mj"], 0)}</td><td>{fmt(s["mj_per"])}</td><td>{fmt(s["robot_mj"], 0)}</td>'
                 f'<td>{fmt(s["ideal_robot_mj"], 0)}</td><td>{s["robot_items"]:,} ({s["ideal_robot_items"]:,.0f})</td>'
                 f'<td>{s["dumped"]:,}</td><td>{s["switches"]:,}</td><td>{fmt(s["switch_wait_median"], 0)} t</td></tr>')
    o.append("</table>")
    o.append('<p class="legend">')
    for rec in order:
        o.append(f'<span><i style="background:{col[rec]}"></i>{e(rec)}</span>')
    o.append('</p><p class="legend">')
    for st in ("useful", "switching", "full", "starved"):
        o.append(f'<span><i style="background:#555;opacity:{STATE_OPACITY[st]}"></i>{st}</span>')
    o.append('<span><i class="sw"></i>recipe change</span><span>blank = no recipe</span>'
             '<span><i style="background:var(--series-1)"></i>power: all</span>'
             '<span><i style="background:var(--series-2)"></i>power: roboports</span></p>')
    for r in runs:
        s = score(r)
        o.append(f'<h2>{e(r["tag"])}</h2>')
        o.append(f'<p>{r["n"]} × {e(r["target"])}. Perfect = {fmt(s["perfect"], 0)} t (all {len(r["cells"])} cells busy on '
                 f'exactly the crafts below, no switches, no travel). Realistic adds the fastest switch-in seen '
                 f'({fmt(s["startup"], 0)} t). Energy by type (MJ): '
                 + ", ".join(f"{e(k)} {v:,.0f}" for k, v in s["by_type"].items()) + "</p>")
        o.append("<p>Ideal crafts: " + ", ".join(f"{e(k)} {v}" for k, v in s["ideal_crafts"].items())
                 + ". From the warehouse: " + ", ".join(f"{e(k)} {v}" for k, v in s["raw"].items()) + "</p>")
        mm = recipe_mismatch(r)
        if mm:
            o.append('<p class="warn">Warning: cells used other recipes than the optimum assumes: '
                     + "; ".join(f"{e(k)}: {', '.join(v)}" for k, v in mm.items()) + "</p>")
        o.append(svg_timeline(r, col, t_max))
        o.append(cell_table(r))
    o.append("</div>")
    return "".join(o)


def cell_table(run):
    e = html.escape
    T = run["t_end"]
    crafts = {}
    for ev in run["events"]:
        if ev[2] == "c":
            crafts.setdefault(ev[1], {}).setdefault(ev[3], 0)
            crafts[ev[1]][ev[3]] += ev[4]
    rows = ['<table class="cells"><tr><th>cell</th>' + "".join(f"<th>{b}</th>" for b in BUCKETS) + "<th>crafts</th></tr>"]
    tot = dict.fromkeys(BUCKETS, 0)
    for i, b in enumerate(cell_buckets(run), 1):
        for k in BUCKETS:
            tot[k] += b[k]
        c = ", ".join(f"{e(k)} {v}" for k, v in sorted(crafts.get(i, {}).items(), key=lambda kv: -kv[1]))
        rows.append(f"<tr><td>C{i}</td>" + "".join(f"<td>{100 * b[k] / T:.0f}%</td>" for k in BUCKETS) + f"<td>{c}</td></tr>")
    n = len(run["cells"])
    rows.append("<tr><th>all</th>" + "".join(f"<th>{100 * tot[k] / T / n:.0f}%</th>" for k in BUCKETS) + "<th></th></tr></table>")
    return "".join(rows)


STYLE = """<!doctype html><meta charset="utf-8"><title>Mall benchmark</title><style>
.viz-root{--surface-1:#fff;--text-primary:#191919;--text-secondary:#666;--grid:#e5e5e5;
--series-1:#257de0;--series-2:#f47230;font:13px system-ui,sans-serif;color:var(--text-primary);background:var(--surface-1);padding:16px}
table{border-collapse:collapse;margin:8px 0}td,th{padding:3px 8px;border-bottom:1px solid var(--grid);text-align:right}
td:first-child,th:first-child{text-align:left}.cells td:last-child{text-align:left;color:var(--text-secondary)}
.legend span{margin-right:14px;white-space:nowrap}.legend i{display:inline-block;width:12px;height:12px;border-radius:2px;margin-right:4px;vertical-align:-2px}
.legend i.sw{width:2px;background:var(--text-primary)}
.axis{font-size:10px;fill:var(--text-secondary)}.grid{stroke:var(--grid);stroke-width:1}
.switch{stroke:var(--text-primary);stroke-width:0.6;stroke-opacity:0.35}.mark{stroke:var(--text-primary);stroke-dasharray:3 3}
.pw-all{fill:none;stroke:var(--series-1);stroke-width:2}.pw-robo{fill:none;stroke:var(--series-2);stroke-width:2}
.warn{color:#b00}</style>"""


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("runs", nargs="+")
    ap.add_argument("-o", "--out", default="report.html")
    a = ap.parse_args(argv)
    runs = []
    for p in a.runs:
        with open(p, encoding="utf-8") as f:
            r = json.load(f)
        # A craft finishing before the cell ever held a recipe in the run has no recipe to credit.
        r["events"] = [e for e in r["events"] if not (e[2] == "c" and e[3] is None)]
        runs.append(r)
    with open(a.out, "w", encoding="utf-8") as f:
        f.write(render(runs))
    for r in runs:
        s = score(r)
        print(f'{r["tag"]}: delivered {fmt_t(s["t_delivered"])} ({s["made"]} made), perfect {fmt_t(s["perfect"])} '
              f'({pct(s["pct_perfect"])}), realistic {pct(s["pct_realistic"])}, ended {s["ended"]} at {s["t_end"]}, '
              f'{fmt(s["mj_per"])} MJ per item, robots {fmt(s["robot_mj"], 0)} MJ vs ideal {fmt(s["ideal_robot_mj"], 0)}')
        for k, v in recipe_mismatch(r).items():
            print(f"  warning: {k} made by {v}, optimum assumes {r['tree'][k]}", file=sys.stderr)
    print("wrote", a.out)


if __name__ == "__main__":
    main()
