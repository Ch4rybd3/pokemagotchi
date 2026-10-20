.pragma library
.import "Moves.js" as Moves

// Bag items: id -> [name, kind, search weight, description, parameter].
// Kinds: ball (wild encounters), berry / candy / mint / cap / incense / ability (your partner),
// food / medicine / pp / status / revive / escape (expedition provisions), evolution,
// tm (teaches a move), held (worn in a Battle Tower team).
// Evolution items share EVOLUTION_WEIGHT (see Pet.js) and are only found when missing from the bag.
var items = {"oran-berry":["Oran Berry","berry",24,"Give it to your partner: ×1.5 passive XP for the next 3 hours.",{"mult":1.5,"hours":3}],"sitrus-berry":["Sitrus Berry","berry",16,"Give it to your partner: ×2 passive XP for the next 4 hours.",{"mult":2,"hours":4}],"exp-candy-xs":["Exp. Candy XS","candy",8,"Gives 5 XP to your partner.",{"xp":5}],"exp-candy-s":["Exp. Candy S","candy",6,"Gives 15 XP to your partner.",{"xp":15}],"exp-candy-m":["Exp. Candy M","candy",4.5,"Gives 40 XP to your partner.",{"xp":40}],"exp-candy-l":["Exp. Candy L","candy",3,"Gives 80 XP to your partner.",{"xp":80}],"exp-candy-xl":["Exp. Candy XL","candy",1.5,"Gives 160 XP to your partner.",{"xp":160}],"rare-candy":["Rare Candy","candy",2,"Raises your partner by exactly one level.",{"level":1}],"incense":["Incense","incense",1.2,"Light it to lure Pokémon: 10 wild encounters per half-hour instead of 3, for 1h30.",{"hours":1.5,"encounters":10}],"lonely-mint":["Lonely Mint","mint",0.7142857142857143,"Changes your partner's nature to Lonely. Raises Attack, lowers Defense.",{"nature":"Lonely"}],"adamant-mint":["Adamant Mint","mint",0.7142857142857143,"Changes your partner's nature to Adamant. Raises Attack, lowers Sp. Atk.",{"nature":"Adamant"}],"naughty-mint":["Naughty Mint","mint",0.7142857142857143,"Changes your partner's nature to Naughty. Raises Attack, lowers Sp. Def.",{"nature":"Naughty"}],"brave-mint":["Brave Mint","mint",0.7142857142857143,"Changes your partner's nature to Brave. Raises Attack, lowers Speed.",{"nature":"Brave"}],"bold-mint":["Bold Mint","mint",0.7142857142857143,"Changes your partner's nature to Bold. Raises Defense, lowers Attack.",{"nature":"Bold"}],"impish-mint":["Impish Mint","mint",0.7142857142857143,"Changes your partner's nature to Impish. Raises Defense, lowers Sp. Atk.",{"nature":"Impish"}],"lax-mint":["Lax Mint","mint",0.7142857142857143,"Changes your partner's nature to Lax. Raises Defense, lowers Sp. Def.",{"nature":"Lax"}],"relaxed-mint":["Relaxed Mint","mint",0.7142857142857143,"Changes your partner's nature to Relaxed. Raises Defense, lowers Speed.",{"nature":"Relaxed"}],"modest-mint":["Modest Mint","mint",0.7142857142857143,"Changes your partner's nature to Modest. Raises Sp. Atk, lowers Attack.",{"nature":"Modest"}],"mild-mint":["Mild Mint","mint",0.7142857142857143,"Changes your partner's nature to Mild. Raises Sp. Atk, lowers Defense.",{"nature":"Mild"}],"rash-mint":["Rash Mint","mint",0.7142857142857143,"Changes your partner's nature to Rash. Raises Sp. Atk, lowers Sp. Def.",{"nature":"Rash"}],"quiet-mint":["Quiet Mint","mint",0.7142857142857143,"Changes your partner's nature to Quiet. Raises Sp. Atk, lowers Speed.",{"nature":"Quiet"}],"calm-mint":["Calm Mint","mint",0.7142857142857143,"Changes your partner's nature to Calm. Raises Sp. Def, lowers Attack.",{"nature":"Calm"}],"gentle-mint":["Gentle Mint","mint",0.7142857142857143,"Changes your partner's nature to Gentle. Raises Sp. Def, lowers Defense.",{"nature":"Gentle"}],"careful-mint":["Careful Mint","mint",0.7142857142857143,"Changes your partner's nature to Careful. Raises Sp. Def, lowers Sp. Atk.",{"nature":"Careful"}],"sassy-mint":["Sassy Mint","mint",0.7142857142857143,"Changes your partner's nature to Sassy. Raises Sp. Def, lowers Speed.",{"nature":"Sassy"}],"timid-mint":["Timid Mint","mint",0.7142857142857143,"Changes your partner's nature to Timid. Raises Speed, lowers Attack.",{"nature":"Timid"}],"hasty-mint":["Hasty Mint","mint",0.7142857142857143,"Changes your partner's nature to Hasty. Raises Speed, lowers Defense.",{"nature":"Hasty"}],"jolly-mint":["Jolly Mint","mint",0.7142857142857143,"Changes your partner's nature to Jolly. Raises Speed, lowers Sp. Atk.",{"nature":"Jolly"}],"naive-mint":["Naive Mint","mint",0.7142857142857143,"Changes your partner's nature to Naive. Raises Speed, lowers Sp. Def.",{"nature":"Naive"}],"serious-mint":["Serious Mint","mint",0.7142857142857143,"Changes your partner's nature to Serious. Makes stats grow evenly.",{"nature":"Serious"}],"bottle-cap":["Bottle Cap","cap",6.5,"Hyper Training: raises one IV of your partner to 31.",{"all":false}],"gold-bottle-cap":["Gold Bottle Cap","cap",1.5,"Hyper Training: raises every IV of your partner to 31.",{"all":true}],"black-augurite":["Black Augurite","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"dawn-stone":["Dawn Stone","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"deep-sea-scale":["Deep Sea Scale","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"deep-sea-tooth":["Deep Sea Tooth","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"dragon-scale":["Dragon Scale","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"dubious-disc":["Dubious Disc","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"dusk-stone":["Dusk Stone","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"electirizer":["Electirizer","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"fire-stone":["Fire Stone","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"ice-stone":["Ice Stone","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"kings-rock":["King’s Rock","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"leaf-stone":["Leaf Stone","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"linking-cord":["Linking Cord","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"magmarizer":["Magmarizer","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"metal-coat":["Metal Coat","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"moon-stone":["Moon Stone","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"oval-stone":["Oval Stone","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"peat-block":["Peat Block","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"prism-scale":["Prism Scale","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"protector":["Protector","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"razor-claw":["Razor Claw","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"razor-fang":["Razor Fang","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"reaper-cloth":["Reaper Cloth","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"sachet":["Sachet","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"shiny-stone":["Shiny Stone","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"sun-stone":["Sun Stone","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"sweet-apple":["Sweet Apple","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"tart-apple":["Tart Apple","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"thunder-stone":["Thunder Stone","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"up-grade":["Upgrade","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"water-stone":["Water Stone","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"whipped-dream":["Whipped Dream","evolution",0,"An evolution item. It is used up when a Pokémon that needs it evolves.",{}],"poke-ball":["Poké Ball","ball",0,"A device for catching wild Pokémon. 1 to 5 turn up in every search.",{"mult":1}],"great-ball":["Great Ball","ball",0,"A good Ball with a higher catch rate than a Poké Ball (×1.5).",{"mult":1.5}],"ultra-ball":["Ultra Ball","ball",0,"An ultra-performance Ball with a higher catch rate than a Great Ball (×2).",{"mult":2}],"master-ball":["Master Ball","ball",0,"The best Ball there is: it catches any wild Pokémon without fail.",{"mult":255}],"apple":["Apple","food",0,"Expedition food: fills a Pokémon's belly by 50.",{"food":50}],"big-apple":["Big Apple","food",0,"Expedition food: fills a Pokémon's belly by 100.",{"food":100}],"razz-berry":["Razz Berry","food",3,"Expedition food: a tasty snack. Fullness +25, happiness +3.",{"food":25,"happy":3}],"nanab-berry":["Nanab Berry","food",3,"Expedition food: a sweet snack. Fullness +25, happiness +3.",{"food":25,"happy":3}],"big-malasada":["Big Malasada","food",0.8,"Expedition food: a fried treat. Fullness +60, happiness +8.",{"food":60,"happy":8}],"moomoo-milk":["Moomoo Milk","food",1.5,"Expedition food: fullness +20 and restores 25% HP.",{"food":20,"hp":25}],"potion":["Potion","medicine",5,"Expedition medicine: restores 25% of a Pokémon's HP.",{"hp":25}],"super-potion":["Super Potion","medicine",2.5,"Expedition medicine: restores 50% of a Pokémon's HP.",{"hp":50}],"hyper-potion":["Hyper Potion","medicine",1,"Expedition medicine: restores 75% of a Pokémon's HP.",{"hp":75}],"max-potion":["Max Potion","medicine",0.4,"Expedition medicine: fully restores a Pokémon's HP.",{"hp":100}],"full-restore":["Full Restore","medicine",0.2,"Expedition medicine: fully restores HP and heals any status condition.",{"hp":100,"status":true}],"leppa-berry":["Leppa Berry","pp",2,"Expedition care: restores 10 PP to one move.",{"pp":10}],"ether":["Ether","pp",2.5,"Expedition care: restores 10 PP to one move.",{"pp":10}],"max-ether":["Max Ether","pp",0.6,"Expedition care: fully restores the PP of one move.",{"pp":99}],"elixir":["Elixir","pp",0.8,"Expedition care: restores 10 PP to every move.",{"pp":10,"all":true}],"max-elixir":["Max Elixir","pp",0.25,"Expedition care: fully restores the PP of every move.",{"pp":99,"all":true}],"full-heal":["Full Heal","status",2,"Expedition care: heals poison, burn, paralysis or freezing.",{"status":true}],"lum-berry":["Lum Berry","status",0.8,"Expedition care: heals any status condition.",{"status":true}],"revive":["Revive","revive",0.8,"Expedition care: revives a fainted Pokémon with half its HP, right when it faints.",{"hp":50}],"max-revive":["Max Revive","revive",0.2,"Expedition care: revives a fainted Pokémon with all its HP, right when it faints.",{"hp":100}],"escape-rope":["Escape Rope","escape",0.8,"Expedition care: gets the team out safely, with all its loot, when things go wrong.",{}],"golden-apple":["Golden Apple","food",0,"Expedition food: a legendary treat. Fills the belly, restores 50% HP and makes a Pokémon very happy.",{"food":100,"hp":50,"happy":12}]}

// Shop prices in Poké Dollars. Items sell back for half; 0 = not sold at the shop.
var prices = {"poke-ball":20,"great-ball":60,"ultra-ball":120,"apple":20,"big-apple":60,"golden-apple":0,"razz-berry":15,"nanab-berry":15,"moomoo-milk":40,"big-malasada":120,"potion":30,"super-potion":70,"hyper-potion":150,"max-potion":300,"full-restore":450,"leppa-berry":80,"ether":120,"max-ether":300,"elixir":400,"max-elixir":900,"full-heal":50,"lum-berry":150,"revive":250,"max-revive":600,"escape-rope":100,"oran-berry":60,"sitrus-berry":120,"exp-candy-xs":20,"exp-candy-s":50,"exp-candy-m":120,"exp-candy-l":250,"exp-candy-xl":500,"rare-candy":600,"incense":300,"bottle-cap":1500,"lonely-mint":400,"adamant-mint":400,"naughty-mint":400,"brave-mint":400,"bold-mint":400,"impish-mint":400,"lax-mint":400,"relaxed-mint":400,"modest-mint":400,"mild-mint":400,"rash-mint":400,"quiet-mint":400,"calm-mint":400,"gentle-mint":400,"careful-mint":400,"sassy-mint":400,"timid-mint":400,"hasty-mint":400,"jolly-mint":400,"naive-mint":400,"serious-mint":400,"black-augurite":900,"dawn-stone":500,"deep-sea-scale":900,"deep-sea-tooth":900,"dragon-scale":900,"dubious-disc":900,"dusk-stone":500,"electirizer":900,"fire-stone":500,"ice-stone":500,"kings-rock":900,"leaf-stone":500,"linking-cord":900,"magmarizer":900,"metal-coat":900,"moon-stone":500,"oval-stone":500,"peat-block":900,"prism-scale":900,"protector":900,"razor-claw":900,"razor-fang":900,"reaper-cloth":900,"sachet":900,"shiny-stone":500,"sun-stone":500,"sweet-apple":900,"tart-apple":900,"thunder-stone":500,"up-grade":900,"water-stone":500,"whipped-dream":900,"master-ball":0,"gold-bottle-cap":0}
// What the shop pays for items it doesn't sell.
var sellOnly = {"master-ball":5000,"gold-bottle-cap":4000,"golden-apple":200}

// ---- Battle Tower ----
// Battle Points (BP) are won at the Battle Tower and spent at its counter.
// Held items are only found there; a Pokémon wears one in a battle team and it
// is never used up.

// id: [name, BP price, description]
var held = {
  "leftovers": ["Leftovers", 48, "Held: restores 1/16 of the holder's max HP at the end of every turn."],
  "life-orb": ["Life Orb", 48, "Held: the holder's moves are 30% stronger, but it loses 10% of its max HP each time it attacks."],
  "choice-band": ["Choice Band", 48, "Held: Attack ×1.5, but the holder can only use the first move it picks until it switches out."],
  "choice-specs": ["Choice Specs", 48, "Held: Sp. Atk ×1.5, but the holder can only use the first move it picks until it switches out."],
  "choice-scarf": ["Choice Scarf", 48, "Held: Speed ×1.5, but the holder can only use the first move it picks until it switches out."],
  "assault-vest": ["Assault Vest", 48, "Held: Sp. Def ×1.5, but the holder can only use attacking moves."],
  "focus-sash": ["Focus Sash", 40, "Held: at full HP, the holder survives a hit that would KO it, with 1 HP. Once per battle."],
  "rocky-helmet": ["Rocky Helmet", 32, "Held: an attacker that makes contact with the holder loses 1/6 of its max HP."],
  "heavy-duty-boots": ["Heavy-Duty Boots", 32, "Held: protects the holder from Stealth Rock, Spikes and other entry hazards."],
  "weakness-policy": ["Weakness Policy", 32, "Held: Attack and Sp. Atk sharply rise when the holder is hit by a super-effective move."],
  "expert-belt": ["Expert Belt", 32, "Held: super-effective moves are 20% stronger."],
  "eviolite": ["Eviolite", 32, "Held: Defense and Sp. Def ×1.5 if the holder can still evolve."],
  "black-sludge": ["Black Sludge", 24, "Held: restores 1/16 HP every turn to Poison types; hurts the others."],
  "light-clay": ["Light Clay", 24, "Held: Reflect, Light Screen and Aurora Veil last 8 turns instead of 5."],
  "air-balloon": ["Air Balloon", 24, "Held: the holder floats and dodges Ground moves until it is hit."],
  "scope-lens": ["Scope Lens", 24, "Held: the holder's moves land critical hits more often."],
  "wide-lens": ["Wide Lens", 16, "Held: the holder's moves are 10% more accurate."],
  "zoom-lens": ["Zoom Lens", 16, "Held: moves are 20% more accurate when the holder moves after its target."],
  "quick-claw": ["Quick Claw", 16, "Held: the holder sometimes moves first."],
  "focus-band": ["Focus Band", 16, "Held: the holder sometimes survives a hit that would KO it, with 1 HP."],
  "shell-bell": ["Shell Bell", 16, "Held: the holder restores HP equal to 1/8 of the damage it deals."],
  "big-root": ["Big Root", 16, "Held: draining moves restore 30% more HP."],
  "white-herb": ["White Herb", 16, "Held: once, restores the holder's lowered stats."],
  "mental-herb": ["Mental Herb", 16, "Held: once, cures the holder of Taunt, Encore, Torment, Disable and infatuation."],
  "power-herb": ["Power Herb", 16, "Held: once, a two-turn move happens in a single turn."],
  "flame-orb": ["Flame Orb", 16, "Held: burns the holder at the end of the turn (great with Guts)."],
  "toxic-orb": ["Toxic Orb", 16, "Held: badly poisons the holder at the end of the turn (great with Poison Heal)."],
  "red-card": ["Red Card", 16, "Held: once, forces an attacker that hits the holder to switch out."],
  "eject-button": ["Eject Button", 16, "Held: once, the holder switches out when it is hit."],
  "eject-pack": ["Eject Pack", 16, "Held: once, the holder switches out when its stats are lowered."],
  "throat-spray": ["Throat Spray", 16, "Held: once, Sp. Atk rises after the holder uses a sound move."],
  "room-service": ["Room Service", 16, "Held: once, Speed falls when Trick Room starts."],
  "safety-goggles": ["Safety Goggles", 16, "Held: protects the holder from weather damage and powder moves."],
  "protective-pads": ["Protective Pads", 16, "Held: the holder's contact moves don't trigger the target's contact effects."],
  "damp-rock": ["Damp Rock", 16, "Held: rain started by the holder lasts 8 turns."],
  "heat-rock": ["Heat Rock", 16, "Held: harsh sunlight started by the holder lasts 8 turns."],
  "smooth-rock": ["Smooth Rock", 16, "Held: a sandstorm started by the holder lasts 8 turns."],
  "icy-rock": ["Icy Rock", 16, "Held: snow started by the holder lasts 8 turns."],
  "muscle-band": ["Muscle Band", 16, "Held: physical moves are 10% stronger."],
  "wise-glasses": ["Wise Glasses", 16, "Held: special moves are 10% stronger."],
  "bright-powder": ["Bright Powder", 16, "Held: lowers the accuracy of moves aimed at the holder."],
  "light-ball": ["Light Ball", 24, "Held by Pikachu: doubles its Attack and Sp. Atk."],
  "thick-club": ["Thick Club", 24, "Held by Cubone or Marowak: doubles its Attack."],
  "charcoal": ["Charcoal", 16, "Held: Fire moves are 20% stronger."],
  "mystic-water": ["Mystic Water", 16, "Held: Water moves are 20% stronger."],
  "miracle-seed": ["Miracle Seed", 16, "Held: Grass moves are 20% stronger."],
  "magnet": ["Magnet", 16, "Held: Electric moves are 20% stronger."],
  "never-melt-ice": ["Never-Melt Ice", 16, "Held: Ice moves are 20% stronger."],
  "black-belt": ["Black Belt", 16, "Held: Fighting moves are 20% stronger."],
  "poison-barb": ["Poison Barb", 16, "Held: Poison moves are 20% stronger."],
  "soft-sand": ["Soft Sand", 16, "Held: Ground moves are 20% stronger."],
  "sharp-beak": ["Sharp Beak", 16, "Held: Flying moves are 20% stronger."],
  "twisted-spoon": ["Twisted Spoon", 16, "Held: Psychic moves are 20% stronger."],
  "silver-powder": ["Silver Powder", 16, "Held: Bug moves are 20% stronger."],
  "hard-stone": ["Hard Stone", 16, "Held: Rock moves are 20% stronger."],
  "spell-tag": ["Spell Tag", 16, "Held: Ghost moves are 20% stronger."],
  "dragon-fang": ["Dragon Fang", 16, "Held: Dragon moves are 20% stronger."],
  "black-glasses": ["Black Glasses", 16, "Held: Dark moves are 20% stronger."],
  "silk-scarf": ["Silk Scarf", 16, "Held: Normal moves are 20% stronger."]
}
for (var h in held) items[h] = [held[h][0], "held", 0, held[h][2], {}]

// Other bag items a Pokémon can hold in the Tower (never used up there either).
var alsoHeld = ["oran-berry", "sitrus-berry", "lum-berry", "leppa-berry", "kings-rock", "razor-claw", "razor-fang", "metal-coat"]

items["ability-capsule"] = ["Ability Capsule", "ability", 0, "Switches your partner between its two regular Abilities.", { hidden: false }]
items["ability-patch"] = ["Ability Patch", "ability", 0, "Gives your partner its Hidden Ability, or takes it back.", { hidden: true }]

// TMs: one item per TM of Moves.tms (Scarlet/Violet numbering), used up when taught.
var TM_PRICES = [0, 300, 800, 1500, 3000]          // Poké Dollars, by rarity
var TM_SELL = [0, 20, 50, 120, 250]                // the shop buys them back cheap: searches find plenty
var TM_WEIGHTS = [0, 55, 30, 12, 3]                // how often each rarity turns up
var TM_KINDS = ["Status", "Physical", "Special"]
function tmId(n) { return "tm" + ("00" + n).slice(-3) }
Moves.tms.forEach(function(t) {
  var m = Moves.moves[t[1]]
  var id = tmId(t[0])
  items[id] = ["TM" + id.slice(2) + " " + m[0], "tm", 0,
               "Teaches " + m[0] + " (" + m[1].charAt(0).toUpperCase() + m[1].slice(1) + ", " + TM_KINDS[m[2]]
               + (m[3] ? ", power " + m[3] : "") + ") to a Pokémon that can learn it. Used up once taught.",
               { move: t[1], rarity: t[2], type: m[1] }]
  prices[id] = TM_PRICES[t[2]]
  sellOnly[id] = TM_SELL[t[2]]
})

// BP prices at the Battle Tower counter (TMs: by rarity, see Tower.js). Items
// the shop also sells or buys cost about 1 BP per ₽25, so the Tower pays about
// as much per hour of play as an Expert expedition.
var bp = {
  "ability-capsule": 40, "ability-patch": 120, "bottle-cap": 60, "gold-bottle-cap": 200,
  "rare-candy": 24, "exp-candy-xl": 20, "master-ball": 400
}
for (var hb in held) bp[hb] = held[hb][1]
Object.keys(items).forEach(function(i) { if (items[i][1] === "mint") bp[i] = 16 })

for (var hs in held) sellOnly[hs] = held[hs][1] * 20
sellOnly["ability-capsule"] = 600
sellOnly["ability-patch"] = 2000
