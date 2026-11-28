import unittest

import analyze


def run(**over):
    r = {
        "tag": "t", "target": "A", "n": 2, "cap": 1000, "t_end": 100, "ended": "idle",
        "t_made_n": 80, "t_delivered_n": 90,
        "cells": [{"x": 0, "y": 0, "speed": 1, "prod": 0}, {"x": 0, "y": 3, "speed": 1, "prod": 0}],
        "recipes": {
            "A": {"energy": 1, "ingredients": [["B", 2]], "products": [["A", 1]]},
            "B": {"energy": 0.5, "ingredients": [["P", 1]], "products": [["B", 1]]},
        },
        "tree": {"A": "A", "B": "B"},
        "stock0": {"A": 0, "B": 2},
        "events": [],
        "samples": [{"t": 0, "j": {}, "held": [0, 0]}, {"t": 100, "j": {}, "held": [0, 0]}],
        "types": {},
    }
    r.update(over)
    return r


class Ideal(unittest.TestCase):
    def test_ideal_net_of_stock(self):
        # 2 A need 4 B; 2 B are in stock, so 2 B crafts remain (1 B per craft).
        self.assertEqual(analyze.ideal(run())["crafts"], {"A": 2, "B": 2})

    def test_ideal_time_spreads_over_all_cells(self):
        # 2 × 1 s + 2 × 0.5 s = 3 s = 180 ticks over 2 cells at speed 1.
        self.assertAlmostEqual(analyze.ideal(run())["time"], 90)

    def test_chain_is_longest_path(self):
        # A (60 ticks) on top of B (30 ticks), at the fastest speed 1.
        self.assertAlmostEqual(analyze.ideal(run())["chain"], 90)

    def test_productivity_reduces_crafts(self):
        cells = [{"x": 0, "y": 0, "speed": 1, "prod": 1.0}]
        # +100%: 1 A craft yields 2 A and eats 2 B; 1 B craft yields 2 B.
        self.assertEqual(analyze.ideal(run(cells=cells, stock0={}))["crafts"], {"A": 1, "B": 1})


class Buckets(unittest.TestCase):
    def test_switching_until_first_craft(self):
        ev = [[10, 1, "r", "B"], [10, 1, "s", "waiting_for_source_items"], [40, 1, "s", "working"],
              [40, 1, "c", "B", 1]]
        b = analyze.cell_buckets(run(events=ev))[0]
        self.assertEqual(b["none"], 10)
        self.assertEqual(b["switching"], 30)
        self.assertEqual(b["useful"], 60)

    def test_surplus_after_need(self):
        # Ideal needs 2 B crafts; the third one is surplus (0.5 s = 30 ticks).
        ev = [[0, 2, "r", "B"], [0, 2, "s", "working"],
              [30, 2, "c", "B", 1], [60, 2, "c", "B", 1], [90, 2, "c", "B", 1], [90, 2, "r", "-"]]
        b = analyze.cell_buckets(run(events=ev))[1]
        self.assertEqual(b["surplus"], 30)
        self.assertEqual(b["useful"], 60)
        self.assertEqual(b["none"], 10)


class Energy(unittest.TestCase):
    def test_energy_by_type(self):
        samples = [{"t": 0, "j": {"roboport": 0, "fast-inserter": 0}, "held": [0, 0]},
                   {"t": 100, "j": {"roboport": 600, "fast-inserter": 60}, "held": [0, 0]}]
        e = analyze.energy(run(samples=samples, types={"roboport": "roboport", "fast-inserter": "inserter"}))
        self.assertEqual(e["by_type"], {"roboport": 600, "inserter": 60})

    def test_robot_items_count_in_out_and_dumps(self):
        # 1 craft of B: 1 P in, 1 B out; a dump of 3 P goes in and back out.
        ev = [[0, 1, "r", "B"], [30, 1, "c", "B", 1], [40, 1, "d", "P", 3]]
        e = analyze.energy(run(events=ev))
        self.assertEqual(e["robot_items"], 1 + 1 + 3 + 3)
        self.assertEqual(e["dumped"], 3)


class Startup(unittest.TestCase):
    def test_startup_is_fastest_switch_in(self):
        # C1 still holds B with ingredients from before the run: its craft at 5 says nothing.
        # C2 switches to B at 100 and finishes at 430 (30 t craft): 300 t waiting for delivery.
        ev = [[0, 1, "r", "B"], [5, 1, "c", "B", 1], [0, 2, "r", "-"], [100, 2, "r", "B"], [430, 2, "c", "B", 1]]
        self.assertEqual(analyze.startup(run(events=ev)), 300)


class Capped(unittest.TestCase):
    def test_capped_run_reports_not_reached(self):
        # Lua's table_to_json drops nil fields, so a capped run has no t_delivered_n at all.
        r = run(ended="cap")
        del r["t_delivered_n"], r["t_made_n"]
        s = analyze.score(r)
        self.assertIsNone(s["t_delivered"])
        self.assertIsNone(s["pct_perfect"])
        self.assertIn("not reached", analyze.render([r]))


class Render(unittest.TestCase):
    def test_render_smoke(self):
        ev = [[0, 1, "r", "B"], [0, 1, "s", "working"], [30, 1, "c", "B", 1]]
        html = analyze.render([run(events=ev), run(tag="other")])
        for s in ("C1", "C2", ">t<", "other"):
            self.assertIn(s, html)


if __name__ == "__main__":
    unittest.main()
