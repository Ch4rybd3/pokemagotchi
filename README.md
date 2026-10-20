# Pokemagotchi

**A tiny Pokémon tamagotchi that lives in your Omarchy bar.**

Raise a partner Pokémon next to your clock, explore the tall grass between two
commits, catch all 905 Pokémon (Gen 1–8), fill their boxes, hunt shinies with
the Nav-Dex, train them against a Substitute doll, teach them their moves, send
them on Mystery Dungeon-style expeditions and take on the Gym Leaders of every
region at the Battle Tower.

![Pokemagotchi](preview.png)

## Features

- **A partner in your bar.** Your Pokémon sits in the bar. Click it to feed, pet
  and play with it. Keep it full and happy and it gains XP over time.
- **Safari encounters.** Up to 3 wild Pokémon every half hour. Throw Poké Balls,
  bait or rocks, or run away. Rarer Pokémon show up less often and are harder to catch.
- **Pokédex and boxes.** Catch the same Pokémon as many times as you like:
  every family has a box of up to **32 Pokémon**. Click a Pokédex entry to open
  its box. You can view each Pokémon's summary, send it to the Day Care,
  release it or manage its moves.
- **Nav-Dex.** Pick any species you have already seen and lock every wild
  encounter on it. Use it to hunt one with better IVs, its hidden ability or a shiny.
- **Shiny Charm.** Catch one Pokémon from every family (469 / 469) to earn the
  Shiny Charm, like completing the Pokédex in the main games. It doubles your
  shiny odds from **1/64** to **1/32**.
- **Moves.** Pokémon learn their real level-up moves (from the latest main-series
  game that has them) as they grow. They keep the four most recent and learn
  more when they evolve. The **Move Reminder** brings back any move they know.
- **Items.** **Search once every half hour** and see everything you found:
  **1 to 5 Poké Balls** (sometimes Great or Ultra Balls, very rarely a Master
  Ball) and 5 items: berries (XP boosts), Exp. Candies, Rare Candies, Mints
  (nature), Bottle Caps (IVs), expedition provisions, every evolution item and
  the **Incense**: light it to get **10 encounters per half hour instead of 3,
  for 1h30**.
- **Expeditions.** Send a team of up to 3 on a Mystery Dungeon-style expedition
  (30 min to 4 h). They fight wild Pokémon from the whole Pokédex with their real
  stats and moves (Showdown damage formula), run into traps, chests, shops,
  bosses and legendaries, live off the provisions you packed, and may come back
  with new friends. Plan them in their own window, then follow the team walking
  down a Mystery Dungeon corridor right in the popup.
- **Evolution.** Pokémon evolve by level, by item, with high friendship, with a
  strong bond, or at a certain time of day. When a Pokémon can evolve in more than
  one way, you choose which.
- **Real stats.** Every Pokémon has IVs, a nature, an ability (with a 1/20
  chance of its hidden ability), EVs and stats computed with the main-series formula.
- **Day Care and training.** Up to 10 of the Pokémon you aren't walking with
  play at the Day Care and slowly gain XP; the others rest. Up to 5 can train
  EVs or levels against the Substitute doll.
- **Shop.** Expeditions pay Poké Dollars: buy Balls, provisions, candies, mints,
  evolution items and TMs, or sell what you don't need.
- **TMs.** All 229 TMs of Scarlet/Violet. Every search finds 1 to 3, expeditions
  bring some home and the shop sells 10 a day. A Pokémon can use a TM if it could
  learn that move from a TM in any main-series game; the TM is used up, the move
  stays at the Move Reminder.
- **Battle Tower.** Challenges of 7 battles at Lv. 50 against Gym Leaders, Elite
  Four, Champions and trainers of all 8 regions, then Pokémon Radical Red's
  toughest trainers. Battles run on the real **Pokémon Showdown** simulator,
  inside the shell (no Node.js needed), in a Gen 3-style window: Singles (pick 3
  of 6) and VGC-style Doubles (pick 4 of 6) after seeing the other team.
- **Battle teams and held items.** Build up to 6 teams of Lv. 50+ Pokémon and give
  them held items (Leftovers, Choice Band, Focus Sash…), only won at the Tower with
  Battle Points.

## Screenshots

| Partner | Box & Nav-Dex | Summary |
| :---: | :---: | :---: |
| ![Partner](screenshots/pet.png) | ![Box](screenshots/box.png) | ![Summary](screenshots/summary.png) |
| **Moves** | **Move Reminder** | **Wild encounter** |
| ![Moves](screenshots/moves.png) | ![Move Reminder](screenshots/relearn.png) | ![Wild encounter](screenshots/wild.png) |
| **Pokédex (Shiny Charm)** | **Bag** | **Day Care** |
| ![Pokédex](screenshots/pokedex.png) | ![Bag](screenshots/bag.png) | ![Day Care](screenshots/daycare.png) |

## Installation

Requires an Omarchy version with shell plugins (tested on Omarchy 4.0.4). No
other dependency: `notify-send` (libnotify, included with Omarchy) is only used
for the evolution and capture notifications.

```bash
omarchy plugin add https://github.com/Ch4rybd3/pokemagotchi.git --enable
```

The command clones the repository into `~/.config/omarchy/plugins/ch4rybd3.pokemagotchi`,
validates it and asks where to put the widget in your bar (right by default).
To move it later:

```bash
omarchy bar move ch4rybd3.pokemagotchi --section left   # left | center | right
```

### Manual installation

```bash
git clone https://github.com/Ch4rybd3/pokemagotchi.git \
  ~/.config/omarchy/plugins/ch4rybd3.pokemagotchi
omarchy plugin enable ch4rybd3.pokemagotchi
```

### Updating

```bash
omarchy plugin update ch4rybd3.pokemagotchi
```

Saves from earlier versions are upgraded automatically the first time the new
version opens.

## Uninstall

```bash
omarchy plugin remove ch4rybd3.pokemagotchi
```

Your save is kept in case you come back. To delete it too:

```bash
rm ~/.local/state/omarchy/pokemagotchi.json
```

## How to play

Click the Pokémon (or the Poké Ball when you have none yet) in your bar.

| Where | What you can do |
| --- | --- |
| Main screen | **Feed**, **Pet**, **Play**, **Wild** (encounter), **Search** (items), **Bag**, **Plan an expedition**, and one line per team out exploring. Click your partner for its summary. |
| Expedition line | Follow that team: the corridor it walks down, HP / PP / fullness, the log (click a fight for the details), **Call the team back**, then its report. |
| Plan an expedition | A window to pick the place, difficulty, team and provisions, plus the **History**. Setting off closes it. |
| Title (`NAME ▾`) | Opens the **menu**: Partner, Pokédex, Bag, Shop, Day Care, Training, Expeditions, Exp. history, Summary, Battle Tower. |
| Pokédex | Search by name, filter to caught families, click an entry to open its **box**. |
| Shop | **Buy** by shelf (Balls, Provisions, Partner, Evolution, TMs) or **Sell** at half price (TMs sell for little). |
| Box | All your Pokémon of that family (⌂ = at the Day Care, ★ = partner) and the **Nav-Dex** for that family. |
| Summary | Stats, IVs, EVs, nature and ability. Buttons for **Evolve**, **Train**, **Moves**, **Make partner**, **To Day Care** and **Release**. |
| Moves | Click a move to see its description. **Move Reminder** brings back an older move, **TMs** teaches one from your bag. |
| Battle Tower | A window with four tabs: **Challenge** (tower, format, tier, team), **Teams** (build teams, give held items), **BP Counter** and **Records**. Battles open in the same window. |
| Day Care | The 10 Pokémon earning XP there, and all the others: click one to send it or take it back. |

### Game rules

| Rule | Value |
| --- | --- |
| Hunger / boredom | −6 fullness and −5 happiness per hour (partner only) |
| Passive XP | 36 XP/h for your partner while fullness and happiness are ≥ 50; 12 XP/h for the 10 Pokémon at the Day Care, none for the others |
| Level | 5 + XP / 10, up to Lv. 100 |
| Wild encounters | 3 per half hour (10 with Incense), refilled at :00 and :30. Wild Pokémon are Lv. 1–40 |
| Search | 1 per half hour: 1–5 Poké Balls, maybe Great (30%), Ultra (8%) or Master (0.3%) Balls, 1–3 apples (Apple 70%, Big Apple 25%, Golden Apple 5%), 5 items and 1–3 TMs |
| TMs | Rarity 1–4 by the move's power (55% / 30% / 12% / 3% of the TMs found). Shop: ₽300 / 800 / 1,500 / 3,000; it buys them back for ₽20 / 50 / 120 / 250 |
| Poké Dollars | Per expedition: (6 per wild Pokémon defeated + 12 per floor + 80 per boss) × 1 / 1.5 / 2.2 / 3 by difficulty, +25% if cleared, half if defeated. Shop sells back at half price |
| Catching | (catch rate × Ball × 7/9 × 1.5 / 255)^0.75 per throw, max 95%; ×2 after a rock, ×0.5 while eating |
| Expeditions | Easy 5 floors / 30 min, Normal 10 / 1 h, Hard 15 / 2 h, Expert 20 / 4 h. Wild Pokémon are 0–5 levels under the team |
| Exploration rank | Normal → Bronze (60 pts) → Silver (250) → Gold (700) → Platinum (1500) → Diamond (3000) → Master (6000): more places, difficulties, provisions (8 → 20) and teams (1 → 3) |
| Shiny odds | 1/64, or 1/32 with the Shiny Charm |
| Box size | 32 Pokémon per family, the Day Care one included |
| Incense | 10 encounters per half hour for 1h30. Lighting another one adds 1h30 |
| Friendship evolutions | Happiness ≥ 80 |
| Fairy (bond) evolutions | 15 rewarded pets |
| Day / night | Day is 8:00–20:00 |
| Training | 60 EVs/h (252 per stat, 510 total) or 40 XP/h; 5 Pokémon at once |

Boxed Pokémon rest: they don't gain XP and can't train. Send one to the Day Care
to swap it with the Pokémon there (your partner, if that's the one).

Wild Pokémon come from the families you haven't caught yet, unless the Nav-Dex
is on. Rare Pokémon (catch rate 45 or less) show up less, legendaries much less.

### Battle Tower

Open **Battle Tower** from the menu. Pick a tower (Kanto, Johto, Hoenn, Sinnoh,
Unova, Kalos, Alola, Galar), Singles or Doubles, a tier and one of your battle
teams, then **Start the challenge**.

- **Who can enter**: your Day Care Pokémon (and your partner) at **Lv. 50 or
  more**. In battle everybody is Lv. 50, with their own IVs, EVs, nature, ability
  and moves. Teams have 3 to 6 Pokémon, one of each species and one of each held
  item (Item Clause).
- **Team Preview**: you see the other trainer's team, then choose 3 Pokémon
  (Singles) or 4 (Doubles) and their order. Trainers bring 3 to 6 Pokémon.
- **A challenge** is 7 battles in a row, the easiest trainers first and a boss
  last. Your Pokémon are healed between battles; no items can be used. Lose once
  and the challenge ends. After 7 wins you can cash out or keep the streak going.
  Close the window whenever you like: the challenge and the battle in progress wait.
- **Tiers**: Novice (Gyms 1–4) ★, Ace (Gyms 5–8) ★★, Elite (Elite Four) ★★★,
  Master (Champions) ★★★★. Clearing a tier opens the next one. Clearing a Master
  tier anywhere opens the **Radical Red Tower** (Kanto League, Johto Leaders,
  Rematch), with teams from the Pokémon Radical Red romhack.
- **Trainers**: every Gym Leader, Elite Four member and Champion of the 8 regions
  (teams in the spirit of their games), generic trainers built from Pokémon
  Showdown's Random Battle sets with the region's Pokémon, and Radical Red's
  bosses and Ace Trainers. Each one has a fixed difficulty rating (1–10) and an AI
  level: Novice trainers sometimes pick a move at random, Masters estimate damage,
  go for KOs, set up, switch out of bad matchups and protect in Doubles.
- **Controls**: mouse, or the keyboard like a GBA: arrows, **Z** / **Enter** = A,
  **X** / **Backspace** = B. Click the text box (or press A) to speed it up.

| Reward | Value |
| --- | --- |
| Win | 1 / 2 / 3 / 4 BP by tier (5 / 6 / 7 at the Radical Red Tower), +1 BP per challenge already cleared in this streak (up to +3) |
| First win against a named trainer | +2 BP |
| Challenge cleared (7 wins) | 3 × the BP of a win, and ₽100 × the tier's level |
| First clear of a tier | 10 × the BP of a win |

The **BP Counter** sells held items (16–48 BP), the Ability Capsule (40) and
Ability Patch (120), Bottle Caps (60, Gold 200), Rare Candies (24), Exp. Candy XL
(20), mints (16), 6 rare TMs a day (32 / 64) and a Master Ball (400). Prices are
set so that an hour at the Tower pays about as much as an Expert expedition.

The window is a normal window: Hyprland tiles it. To make it float, add a window
rule matching the title `Pokemagotchi – Battle Tower`.

### Expeditions

Click **⛰ Plan an expedition**, pick a place, a difficulty, up to 3 Pokémon from
the Day Care and the provisions to pack (**Pack for me** fills the bag for you).
The team then explores on its own; nothing it does needs you. Click its line in
the popup to watch it walk down the corridor, floor after floor.

- Each floor is played out when its time is up: battles, items, traps and events.
  HP and PP carry over from one fight to the next, the team gets hungry while
  walking and recovers a little HP on each floor.
- Provisions are used automatically: food under 40 fullness, potions under 30% HP
  in a fight (50% after), Ethers when PP run low, cures after a fight, a Revive
  the moment someone faints, and an Escape Rope when only one is left standing.
- Defeated wild Pokémon give XP and their real EV yield. Some get up and want to
  join (more often for common ones, three times more for shinies).
- Bosses wait on the last floor (Normal), floors 8 and 15 (Hard) or every 5 floors
  (Expert). A legendary of the place may show up instead: young ones from Normal,
  most of them from Hard, all of them (mythicals too) on Expert. A legendary only
  offers to join, by luck, once you've met it at least twice in that place.
- **Call the team back** to make it walk home (half the time spent, 30 min at most)
  with everything it found. A team that faints loses half of its loot, except what
  it left at a Kangaskhan Storage.
- Your partner can go too, and protects a teammate once. Pokémon on an expedition
  don't play at the Day Care and can't train.

The window is a normal window: Hyprland tiles it. To make it float, add a window
rule matching the title `Pokemagotchi – Expeditions`. Once you've caught every family, they come from every species whose box
still has room.

## Files and privacy

- Code and assets: `~/.config/omarchy/plugins/ch4rybd3.pokemagotchi/`
- Save: `~/.local/state/omarchy/pokemagotchi.json` (plain JSON, written when you
  interact with the widget, or once when an expedition comes home)

The plugin needs no network access and starts no background process. It only
runs `notify-send` for notifications and writes nothing but its save file. Battle
Tower battles run in a worker thread of the shell, loaded the first time you open
the Tower.

## Development

| File | Role |
| --- | --- |
| `BarWidget.qml` | Bar button and popup UI |
| `Pet.js` | Game rules, save format and migrations (rates at the top of the file) |
| `Expedition.js` | Expeditions: places, difficulties, events, provisions, ranks |
| `Combat.js` | Battle engine (Showdown damage formula) |
| `ExpeditionWindow.qml` | The window to plan expeditions, and their history |
| `CorridorScene.qml` | The corridor a team walks down, in the popup |
| `Dex.js`, `Info.js`, `Items.js`, `Moves.js`, `Battle.js` | Generated game data |
| `PokeSprite.qml`, `ItemSprite.qml`, `SubstituteScene.qml` | Sprite helpers |
| `Tower.js` | Battle Tower: towers, tiers, battle teams, challenges, rewards, BP Counter |
| `TowerWindow.qml`, `BattleScene.qml` | The Battle Tower window and its Gen 3-style battle scene |
| `TowerWorker.mjs`, `TowerEngine.mjs` | Battles in a WorkerScript: start, replay, your choices and the trainer's |
| `TowerAI.mjs` | The trainers' AI (levels 1–4) |
| `BattleText.mjs` | Showdown's battle log → the lines and animations of the scene |
| `Showdown.mjs` | Generated: the Pokémon Showdown simulator as one ES module |
| `Trainers.js` | Generated: towers and trainers |
| `tools/gen-showdown.mjs` | Rebuilds `Showdown.mjs` from a Pokémon Showdown checkout (needs Node.js, only to build) |
| `tools/gen-trainers.mjs` | Rebuilds `Trainers.js` from `tools/trainers/*.txt`, Showdown's Random Battle sets and the Radical Red dump |
| `tools/gen-moves.py` | Regenerates `Moves.js` (learnsets, moves, TMs) from the PokeAPI CSV dump |
| `tools/gen-battle.py` | Regenerates `Battle.js` (EV yields, legendaries, type chart, move effects) |

Saving a file reloads the widget. Changes to the `.js` libraries are cached by
the QML engine, so restart the shell to pick them up:

```bash
omarchy restart shell
```

To regenerate the move data:

```bash
python3 tools/gen-moves.py /tmp/pokeapi-csv   # downloads the CSVs it needs
python3 tools/gen-battle.py /tmp/pokeapi-csv  # run it after gen-moves.py
```

To rebuild the Battle Tower data (Node.js, git and npm; the first run clones and
builds Pokémon Showdown in the temporary directory):

```bash
node tools/gen-showdown.mjs                   # Showdown.mjs
node tools/gen-trainers.mjs                   # Trainers.js, run it after gen-showdown.mjs
```

## Credits

- Pokémon sprites: [pokemon-colorscripts](https://gitlab.com/phoneybadger/pokemon-colorscripts)
  (MIT), based on [PokéSprite](https://github.com/msikma/pokesprite).
- Item sprites: [PokeAPI/sprites](https://github.com/PokeAPI/sprites) and
  [PokéSprite](https://github.com/msikma/pokesprite) (MIT).
- Battle Tower battles: [Pokémon Showdown](https://github.com/smogon/pokemon-showdown) (MIT).
- Radical Red Tower trainers: Pokémon Radical Red by soupercell, from the [4.1 trainer data dump](https://gist.github.com/Rudo2204/7f9e4a3ceaf077d623d3c37b1f921601)
  by Rudo2204 (based on luckytyphlosion's).
- Battle Tower font: [Pixelify Sans](https://github.com/eifetx/Pixelify-Sans) (SIL Open Font License 1.1).
- Pokédex entries, stats, abilities, natures, evolutions, items and moves: [PokeAPI](https://pokeapi.co)
  ([BSD-3-Clause](https://github.com/PokeAPI/pokeapi/blob/master/LICENSE.md)).

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Legal

Pokemagotchi is an unofficial fan project, free and non-commercial. It is not
affiliated with, endorsed by or sponsored by Nintendo, Game Freak, Creatures Inc.
or The Pokémon Company. Pokémon and Pokémon character names are trademarks of
Nintendo, Creatures Inc. and Game Freak. All Pokémon images and names are
© Nintendo / Creatures Inc. / GAME FREAK inc.

The plugin's own code is released under the [MIT License](LICENSE).
