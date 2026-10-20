#!/usr/bin/env python3
"""Generates Moves.js (level-up learnsets, TMs and move data) from the PokeAPI CSV dump.

Usage: tools/gen-moves.py [csv-dir]
Missing CSV files are downloaded from github.com/PokeAPI/pokeapi into csv-dir
(default: a temporary directory). Run from anywhere; writes ../Moves.js.
"""
import csv, json, os, re, sys, tempfile, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = "https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv/"
FILES = ["pokemon_moves", "moves", "move_names", "move_flavor_text", "pokemon", "types", "machines"]
ENGLISH = "9"
LEVEL_UP = "1"
MACHINE = "4"
TM_GROUPS = ["25", "26", "27"]   # Scarlet/Violet and its DLCs: TM001 to TM229

# TM rarity, 1 (common) to 4 (very rare): it sets how often a TM turns up and
# its price. Damaging moves go by power; these moves are worth more (or less)
# than their power says.
RARITY = {
    "earthquake": 4, "close-combat": 4, "swords-dance": 4, "nasty-plot": 4, "dragon-dance": 4,
    "calm-mind": 4, "bulk-up": 4, "trick-room": 4, "shell-smash": 4, "quiver-dance": 4,
    "knock-off": 3, "u-turn": 3, "volt-switch": 3, "flip-turn": 3, "will-o-wisp": 3, "toxic": 3,
    "stealth-rock": 3, "spikes": 3, "toxic-spikes": 3, "tailwind": 3, "substitute": 3, "taunt": 3,
    "encore": 3, "iron-defense": 3, "agility": 3, "amnesia": 3, "light-screen": 3, "reflect": 3,
    "sucker-punch": 3, "extreme-speed": 4, "draco-meteor": 4, "leaf-storm": 4, "overheat": 4,
    "hyper-beam": 2, "giga-impact": 2, "self-destruct": 2, "explosion": 3,
}


def rarity(identifier, category, power):
    if identifier in RARITY:
        return RARITY[identifier]
    if category == 0:
        return 2
    if power >= 120:
        return 4
    if power >= 90:
        return 3
    if power >= 65:
        return 2
    return 1

# Most recent main-series games first. A species takes its learnset from the
# first group that teaches it any level-up move (Scarlet/Violet and its DLCs
# count as one group). Spin-offs such as Legends: Arceus are left out.
GROUPS = [["25", "26", "27"], ["20", "21", "22"], ["23"], ["18"], ["17"], ["16"], ["15"],
          ["14"], ["11"], ["10"], ["9"], ["8"], ["7"], ["6"], ["5"], ["4"], ["3"], ["2"], ["1"]]
CATEGORY = {"1": 0, "2": 1, "3": 2}   # status, physical, special


def rows(folder, name):
    path = os.path.join(folder, name + ".csv")
    if not os.path.exists(path):
        print("downloading", name, file=sys.stderr)
        urllib.request.urlretrieve(BASE + name + ".csv", path)
    with open(path, newline="", encoding="utf-8") as f:
        yield from csv.DictReader(f)


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else tempfile.mkdtemp()
    os.makedirs(folder, exist_ok=True)

    # Our slugs come from pokemon-colorscripts; match them by National Dex number.
    info = open(os.path.join(ROOT, "Info.js"), encoding="utf-8").read()
    species = json.loads(re.search(r"^var species = (\{.*\})$", info, re.M).group(1))
    slug_of = {str(v[0]): k for k, v in species.items()}
    pokemon_of = {}
    for r in rows(folder, "pokemon"):
        if r["is_default"] == "1" and r["species_id"] in slug_of:
            pokemon_of[r["id"]] = slug_of[r["species_id"]]

    by_slug, by_machine = {}, {}
    for r in rows(folder, "pokemon_moves"):
        slug = pokemon_of.get(r["pokemon_id"])
        if slug and r["pokemon_move_method_id"] == MACHINE:
            by_machine.setdefault(slug, set()).add(int(r["move_id"]))
        if slug and r["pokemon_move_method_id"] == LEVEL_UP:
            by_slug.setdefault(slug, {}).setdefault(r["version_group_id"], []).append(
                (int(r["level"] or 0), int(r["order"] or 0), int(r["move_id"])))

    learnsets, used = {}, set()
    for slug in species:
        groups = by_slug.get(slug, {})
        for group in GROUPS:
            entries = [e for g in group for e in groups.get(g, [])]
            if entries:
                break
        seen, flat = set(), []
        for level, _, move in sorted(entries):
            if move not in seen:
                seen.add(move)
                flat += [level, move]
                used.add(move)
        learnsets[slug] = flat

    # TMs: Scarlet/Violet's numbering. A Pokémon can use a TM if it could learn
    # that move from a TM or TR in any main-series game.
    tm_moves = {}
    for r in rows(folder, "machines"):
        if r["version_group_id"] in TM_GROUPS:
            tm_moves[int(r["machine_number"])] = int(r["move_id"])
    used |= set(tm_moves.values())
    tm_numbers = sorted(tm_moves)
    machines = {}
    for slug in species:
        known = by_machine.get(slug, set())
        nums = [n for n in tm_numbers if tm_moves[n] in known]
        if nums:
            machines[slug] = "".join(format(n, "x").rjust(2, "0") for n in nums)

    types = {r["id"]: r["identifier"] for r in rows(folder, "types")}
    names = {r["move_id"]: r["name"] for r in rows(folder, "move_names") if r["local_language_id"] == ENGLISH}
    order = {g: i for i, group in enumerate(GROUPS) for g in group}
    texts = {}
    for r in rows(folder, "move_flavor_text"):
        if r["language_id"] != ENGLISH:
            continue
        rank = order.get(r["version_group_id"], 99)
        if r["move_id"] not in texts or rank < texts[r["move_id"]][0]:
            texts[r["move_id"]] = (rank, " ".join(r["flavor_text"].replace("\xad\n", "").split()))

    moves, identifiers = {}, {}
    for r in rows(folder, "moves"):
        identifiers[int(r["id"])] = r["identifier"]
        if int(r["id"]) not in used:
            continue
        moves[int(r["id"])] = [names.get(r["id"], r["identifier"]), types[r["type_id"]],
                               CATEGORY.get(r["damage_class_id"], 0), int(r["power"] or 0),
                               int(r["accuracy"] or 0), int(r["pp"] or 0), texts.get(r["id"], (0, ""))[1]]

    tms = [[n, tm_moves[n], rarity(identifiers[tm_moves[n]], moves[tm_moves[n]][2], moves[tm_moves[n]][3])]
           for n in tm_numbers]

    missing = [s for s, l in learnsets.items() if not l]
    if missing:
        print("no learnset for:", ", ".join(missing), file=sys.stderr)

    with open(os.path.join(ROOT, "Moves.js"), "w", encoding="utf-8") as f:
        f.write(".pragma library\n\n")
        f.write("// Generated by tools/gen-moves.py from PokeAPI (latest main-series learnsets).\n")
        f.write("// slug: [level, move id, level, move id, ...]; level 0 = learned on evolution.\n")
        f.write("var learnsets = " + json.dumps(learnsets, separators=(",", ":")) + "\n\n")
        f.write("// move id: [name, type, category (0 status, 1 physical, 2 special), power, accuracy, PP, text]\n")
        f.write("var moves = " + json.dumps(moves, separators=(",", ":"), ensure_ascii=False) + "\n\n")
        f.write("// TMs, Scarlet/Violet numbering: [number, move id, rarity 1 (common) to 4 (very rare)]\n")
        f.write("var tms = " + json.dumps(tms, separators=(",", ":")) + "\n\n")
        f.write("// slug: the TMs it can use, two hex digits per TM number\n")
        f.write("var machines = " + json.dumps(machines, separators=(",", ":")) + "\n")
    print("wrote Moves.js:", len(learnsets), "learnsets,", len(moves), "moves,", len(tms), "TMs", file=sys.stderr)


if __name__ == "__main__":
    main()
