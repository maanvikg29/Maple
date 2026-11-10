#!/usr/bin/env python3
"""Writes MapleCore's reward table, rewards.json, for the focus design.

Spec: docs/superpowers/specs/2026-10-11-focus-hours-saved-design.md §4. Deterministic: the same inputs always give
the same table. Inputs:
  - MapleKit/Sources/MapleCore/Resources/species.json, with each assessed species' IUCN `conservation`
  - docs/design/rewards-2026-10-10.json, the table this one replaces, for each species' journey order
Run from the repo root: python3 -I Scripts/generate-rewards.py
"""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPECIES = ROOT / "MapleKit/Sources/MapleCore/Resources/species.json"
OLD = ROOT / "docs/design/rewards-2026-10-10.json"
OUT = ROOT / "MapleKit/Sources/MapleCore/Resources/rewards.json"

HOURS = [1, 2, 3, 5, 7, 10, 13, 16, 20, 24, 28, 32, 36, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100, 110,
         120, 130, 140, 150, 160, 168, 180, 190, 200, 210, 220, 230, 240, 250, 265, 280, 295, 310, 325, 340, 355, 370,
         385, 400, 420, 440, 460, 480, 500, 520, 540, 560, 580, 600, 620, 640, 660, 680, 700, 720, 740, 760, 780, 800,
         825, 850, 875, 900, 925, 950, 975, 1000, 1025, 1050, 1075, 1100, 1125, 1150, 1175, 1200, 1225, 1250, 1275,
         1300, 1325, 1350, 1375, 1400, 1425, 1450, 1475, 1500, 1530, 1560, 1590, 1620, 1650, 1680, 1710, 1740, 1770,
         1800, 1840, 1880, 1920, 1960, 2000]
LANDMARKS = {24: "A day back", 168: "A week back", 720: "A month back", 2000: "A working year back"}

# id, name, metric, unit, data source, release, ladder, design pace (units per day; RewardCategoryInfo.designPace)
CATEGORIES = [
    ("first_leaf", "First leaf",
     "One-time: planting the maple at the end of onboarding. Counts once, ever.",
     "step", "Onboarding", "M1", [1], 1.0),
    ("hours_saved", "Hours saved",
     "Hours your chosen apps stayed locked while you were awake: verified locked intervals (counted once where they "
     "overlap) inside the awake window, minus overrides and phone breaks, at most 6 h a day and 2 h from blocks that "
     "started on their own. Focus spec §3.",
     "hours", "Maple's session ledger (its own shield events), never Screen Time usage", "F1", HOURS, 1.9),
    ("sessions_finished", "Sessions finished",
     "Sessions the member started, planned at 20 minutes or more, that reached their planned end. At most 4 a day.",
     "sessions", "Maple's session ledger", "F1", [1, 10, 25, 50, 100, 250, 500, 1000], 1.0),
    ("focus_streak", "Focus streak",
     "The best run of days with a finished session. Any 2 rest days per calendar week are built in; Away pauses it.",
     "days", "Maple's session ledger", "F1", [3, 7, 14, 30, 50, 75, 100, 150, 250, 365], 0.8),
    ("phone_free_mornings", "Phone-free mornings",
     "Mornings whose Morning block ran to its end with no override, early end or phone break.",
     "mornings", "Maple's session ledger (scheduled blocks)", "F2", [1, 7, 25, 50, 100, 200, 365], 0.5),
    ("bedtime_kept", "Bedtime kept",
     "Nights whose wind-down block ran to bedtime with no override, early end or phone break.",
     "nights", "Maple's session ledger (scheduled blocks)", "F2", [1, 7, 25, 50, 100, 200, 365], 0.5),
    ("rested_nights", "Rested nights",
     "Nights Apple Health shows the member asleep no later than 30 minutes after the scheduled bedtime (NightLedger "
     "on time).",
     "nights", "Apple Health sleep (HealthKit), never self-report", "M1", [3, 14, 30, 60, 100, 175, 250, 365], 0.6),
]
ORDER = {c[0]: index for index, c in enumerate(CATEGORIES)}
LADDER = {c[0]: c[6] for c in CATEGORIES}
PACE = {c[0]: c[7] for c in CATEGORIES}
CONSISTENCY = ("focus_streak", "phone_free_mornings", "bedtime_kept")
SECONDARY = ("sessions_finished", "focus_streak", "phone_free_mornings", "bedtime_kept", "rested_nights")
PINS = {
    ("first_leaf", 1): "saccharum",       # Sugar maple, Maple's emblem (D12)
    ("hours_saved", 1): "rubrum",         # Red maple
    ("hours_saved", 24): "palmatum",      # Japanese maple: "A day back"
    ("hours_saved", 168): "griseum",      # Paperbark maple: "A week back"
    ("hours_saved", 720): "japonicum",    # Fullmoon maple: "A month back"
    ("sessions_finished", 1): "buergerianum",  # Trident maple
    ("rested_nights", 3): "saccharinum",  # Silver maple
}
SEVERITY = {"CR": 0, "EN": 1, "VU": 2}
OLD_TIERS = ["first-steps", "common", "uncommon", "rare", "legendary"]
OLD_PACE = {
    "first_steps": 1, "nights_tracked": 0.9, "on_time_bedtimes": 0.7, "bedtime_run": 0.7, "steady_weeks": 0.1,
    "seasons_in_rhythm": 1 / 91, "steady_mornings": 0.6, "full_nights": 0.6, "focus_hours": 0.75, "focus_days": 0.6,
    "focus_weeks": 0.1, "sound_winddowns": 0.5, "scroll_free_winddowns": 0.6, "phone_free_mornings": 0.5,
    "bedtime_shield_kept": 0.6, "reflection_weeks": 0.1, "caffeine_curfew": 0.5, "wind_down_rituals": 0.5,
    "community_challenges": 1 / 30,
}


def days(category, threshold):
    """Days to the rung for a committed member at the category's design pace."""
    return 0 if category == "first_leaf" else threshold / PACE[category]


def tier(category, threshold):
    """Journey tier from the design days (rewards.md): up to 8, 45, 180, more; the top of a ladder over a year."""
    if category == "first_leaf":
        return "first-steps"
    d = days(category, threshold)
    if threshold == LADDER[category][-1] and d > 365:
        return "legendary"
    if d <= 8:
        return "first-steps"
    if d <= 45:
        return "common"
    if d <= 180:
        return "uncommon"
    return "rare"


def unlock_text(category, n):
    if category == "first_leaf":
        return "Plant your maple"
    if category == "hours_saved":
        text = "Save 1 hour" if n == 1 else f"Save {n:,} hours"
        return f"{text} · {LANDMARKS[n]}" if n in LANDMARKS else text
    if category == "sessions_finished":
        return "Finish your first session" if n == 1 else f"Finish {n:,} sessions"
    if category == "focus_streak":
        return f"A {n}-day focus streak"
    if category == "phone_free_mornings":
        return "Your first phone-free morning" if n == 1 else f"{n} phone-free mornings"
    if category == "bedtime_kept":
        return "Keep your first bedtime" if n == 1 else f"Keep {n} bedtimes"
    if category == "rested_nights":
        return f"{n} rested nights"
    raise ValueError(category)


def first_sentence(text):
    head = text.split(". ")[0].rstrip(".")
    return head + "."


def main():
    species = json.loads(SPECIES.read_text())
    by_id = {s["id"]: s for s in species}
    old = json.loads(OLD.read_text())["assignments"]
    rank = {a["species_id"]: (OLD_TIERS.index(a["tier"]), a["threshold"] / OLD_PACE[a["category_id"]], a["species_id"])
            for a in old}
    about = {a["species_id"]: first_sentence(a["rationale"]) for a in old}
    rungs = [(c[0], t) for c in CATEGORIES for t in c[6]]
    assert len(rungs) == len(species) == len(set(rungs)) == 155, (len(rungs), len(species))
    assert set(rank) == set(by_id), set(rank) ^ set(by_id)

    placed = {}
    used = set()

    def place(rung, species_id, reason):
        assert rung not in placed and species_id not in used, (rung, species_id)
        placed[rung] = (species_id, reason)
        used.add(species_id)

    for rung, species_id in PINS.items():
        assert species_id in by_id, species_id
        place(rung, species_id, "a well-known garden maple on an early or landmark rung")

    top = [("hours_saved", t) for t in HOURS[-10:]] + [(c, LADDER[c][-1]) for c in SECONDARY]
    top.sort(key=lambda r: (-days(*r), ORDER[r[0]]))
    threatened = sorted(
        (s for s in species if (s.get("conservation") or {}).get("category") in SEVERITY and s["id"] not in used),
        key=lambda s: (SEVERITY[s["conservation"]["category"]], tuple(-x if isinstance(x, (int, float)) else x
                                                                       for x in rank[s["id"]][:2]), s["id"]),
    )
    for rung, s in zip(top, threatened):
        status = s["conservation"]
        place(rung, s["id"], f"IUCN {status['category']} ({status['year']}) on one of the hardest rungs")
    unfilled = top[len(threatened):]

    consistency = sorted((r for r in rungs if r[0] in CONSISTENCY and r not in placed and r[1] != LADDER[r[0]][-1]),
                         key=lambda r: (days(*r), ORDER[r[0]]))
    # u-confidence evergreens stay out: they belong on late rungs (D3).
    evergreens = sorted((s for s in species if s["evergreen"] and s["confidence"] != "u" and s["id"] not in used),
                        key=lambda s: rank[s["id"]])
    for rung, s in zip(consistency, evergreens):
        place(rung, s["id"], "an evergreen on a consistency ladder: it stays green, like the habit")

    rest_rungs = sorted((r for r in rungs if r not in placed), key=lambda r: (days(*r), ORDER[r[0]], r[1]))
    rest_species = sorted((s for s in species if s["id"] not in used),
                          key=lambda s: (s["confidence"] == "u", rank[s["id"]]))
    assert len(rest_rungs) == len(rest_species)
    for rung, s in zip(rest_rungs, rest_species):
        reason = "u-confidence, kept on a late rung (D3)" if s["confidence"] == "u" else "in journey order"
        place(rung, s["id"], reason)

    assignments = []
    for (category, threshold) in sorted(placed, key=lambda r: (ORDER[r[0]], r[1])):
        species_id, reason = placed[(category, threshold)]
        assignments.append({
            "species_id": species_id,
            "category_id": category,
            "threshold": threshold,
            "unlock_text": unlock_text(category, threshold),
            "tier": tier(category, threshold),
            "rationale": f"{about[species_id]} Re-cut 2026-10-11: {reason}.",
        })
    categories = [{"id": c[0], "name": c[1], "metric": c[2], "unit": c[3], "data_source": c[4],
                   "available_from": c[5], "ladder": c[6]} for c in CATEGORIES]
    OUT.write_text(json.dumps({"categories": categories, "assignments": assignments}, indent=1, ensure_ascii=False) + "\n")

    tiers = {}
    for a in assignments:
        tiers[a["tier"]] = tiers.get(a["tier"], 0) + 1
    print(f"{len(assignments)} leaves; tiers {dict(sorted(tiers.items()))}")
    print(f"{len(threatened[:len(top)])} of {len(top)} top rungs hold threatened species")
    if unfilled:
        print(f"note: {len(unfilled)} top rungs had no threatened species left and took the general order: {unfilled}")


if __name__ == "__main__":
    main()
