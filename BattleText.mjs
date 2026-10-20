// Turns the battle log (Pokémon Showdown protocol, seen by player 1) into the
// steps the Battle Tower window plays one after the other: a line in the text
// box, an HP bar going down, a Pokémon sent out or fainting…
//
// The messages come from Showdown's battle texts (Showdown.Text); names are
// written the Gen 3 way: "Foe GEODUDE used TACKLE!".
//
// A step: { t: kind, text, side (0 you, 1 foe), slot, ... }
//   "text"    a line, nothing else
//   "switch"  { mon: { species, name, level, gender, shiny, hp, maxhp, status } } sent out
//   "move"    { move } the attacker lunges
//   "hp"      { hp, maxhp, status } damage or healing
//   "faint"   the Pokémon goes down
//   "status"  { status } a status condition starts or ends ("" = cured)
//   "boost"   { up } a stat goes up or down
//   "species" { species } Mega Evolution or a forme change
//   "weather" { weather } ("" = clear)
//   "turn"    { turn }
//   "win"     { winner } 0 you, 1 foe, -1 tie

import { Showdown } from "Showdown.mjs";

const T = Showdown.Text;
const toID = Showdown.toID;
const STATS = { atk: "Attack", def: "Defense", spa: "Sp. Atk", spd: "Sp. Def", spe: "Speed",
                accuracy: "accuracy", evasion: "evasiveness", spc: "Special" };
const WEATHERS = { sunnyday: "sun", desolateland: "sun", raindance: "rain", primordialsea: "rain",
                   sandstorm: "sand", hail: "hail", snowscape: "hail", snow: "hail", deltastream: "wind" };

export function upper(s) { return String(s || "").toUpperCase(); }

// "p2a: Geodude" -> { side: 1, slot: 0, name: "Geodude" }
export function parseIdent(ident) {
  const m = /^p([12])([a-c]?)(?::\s*(.*))?$/.exec(String(ident || "").trim());
  if (!m) return null;
  return { side: Number(m[1]) - 1, slot: m[2] ? m[2].charCodeAt(0) - 97 : -1, name: m[3] || "" };
}

// "Garchomp-Mega, L50, M, shiny" -> { species, level, gender, shiny }
export function parseDetails(details) {
  const parts = String(details || "").split(", ");
  const out = { species: parts[0], level: 100, gender: "", shiny: false };
  for (let i = 1; i < parts.length; i++) {
    const p = parts[i];
    if (/^L\d+$/.test(p)) out.level = Number(p.slice(1));
    else if (p === "M" || p === "F") out.gender = p;
    else if (p === "shiny") out.shiny = true;
  }
  return out;
}

// "123/180 brn" -> { hp, maxhp, status }; "0 fnt" -> hp 0
export function parseHP(text) {
  const m = /^(\d+)(?:\/(\d+))?(?:\s+(\w+))?/.exec(String(text || ""));
  if (!m) return { hp: 0, maxhp: 0, status: "" };
  const status = m[3] || "";
  return { hp: Number(m[1]), maxhp: m[2] ? Number(m[2]) : 0, status: status === "fnt" ? "fnt" : status };
}

// "move: Protect" / "ability: Intimidate" / "item: Leftovers" / "Stealth Rock"
export function parseEffect(text) {
  const s = String(text || "").replace(/^\[from\]\s*/, "");
  const m = /^(move|ability|item):\s*(.*)$/.exec(s);
  if (m) return { kind: m[1], name: m[2], id: toID(m[2]) };
  return { kind: "", name: s, id: toID(s) };
}

// A message template: the effect's own text, else the default one.
function lookup(table, id, key) {
  let entry = table[id];
  for (let guard = 0; entry && guard < 4; guard++) {
    const v = entry[key];
    if (typeof v !== "string") return "";
    if (v.charAt(0) !== "#") return v;
    entry = table[v.slice(1)] || T.default[v.slice(1)] || T.moves[v.slice(1)];
  }
  return "";
}

export function template(effect, key, fallback) {
  if (effect && effect.id) {
    const tables = effect.kind === "move" ? [T.moves, T.default]
      : effect.kind === "ability" ? [T.abilities, T.default]
      : effect.kind === "item" ? [T.items, T.default]
      : [T.default, T.moves, T.abilities, T.items];
    for (const table of tables) {
      const v = lookup(table, effect.id, key);
      if (v) return v;
    }
  }
  return fallback === undefined ? T.default.default[key] || "" : fallback;
}

function tidy(text) {
  return String(text || "").split("\n").map(function (l) {
    l = l.replace(/\*\*/g, "").trim();
    // Showdown puts minor details in parentheses; the games just say them.
    if (/^\(.*\)$/.test(l)) l = l.slice(1, -1);
    return l;
  }).filter(Boolean).join("\n");
}

function capitalize(text) { return text ? text.charAt(0).toUpperCase() + text.slice(1) : text; }

export class Narrator {
  // names: ["RED", "Leader BROCK"]
  constructor(names) {
    this.names = names || ["You", "Foe"];
    this.nick = [{}, {}];          // "p1a" -> nickname of who stands there
    this.lastMove = "";
    this.weather = "";
  }

  pokemon(ident) {
    const p = typeof ident === "string" ? parseIdent(ident) : ident;
    if (!p) return "";
    const name = upper(p.name);
    return p.side === 1 ? "Foe " + name : name;
  }

  fill(tpl, vals) {
    let out = String(tpl || "");
    out = out.replace(/\{INFLECT:(\w+):s=([^:}]*):p=([^}]*)\}/g, function (_, key, one, many) {
      return Number(vals[key]) === 1 || (key === "STAT" && !vals.PLURAL) ? one : many;
    });
    out = out.replace(/\{(\w+)\}/g, function (all, key) { return vals[key] !== undefined ? vals[key] : all; });
    return capitalize(tidy(out).replace(/(^|\n)([a-z])/g, function (_, a, b) { return a + b.toUpperCase(); }));
  }

  // One protocol line -> steps (often one, sometimes none).
  line(line) {
    if (!line || line.charAt(0) !== "|") return [];
    const raw = line.slice(1).split("|");
    const cmd = raw[0];
    const args = [], kw = {};
    for (let i = 1; i < raw.length; i++) {
      const m = /^\[(\w+)\]\s*(.*)$/.exec(raw[i]);
      if (m) kw[m[1]] = m[2] === undefined || m[2] === "" ? true : m[2];
      else args.push(raw[i]);
    }
    const fn = this["on_" + cmd.replace(/^-/, "_")];
    if (!fn) return [];
    const out = fn.call(this, args, kw) || [];
    return Array.isArray(out) ? out : [out];
  }

  lines(text) {
    let out = [];
    for (const l of String(text || "").split("\n")) out = out.concat(this.line(l));
    return out;
  }

  // ---- Helpers for steps ----

  step(t, ident, extra, text) {
    const p = ident ? parseIdent(ident) : null;
    const s = Object.assign({ t: t, text: text || "" }, extra || {});
    if (p) { s.side = p.side; s.slot = Math.max(0, p.slot); }
    return s;
  }

  vals(ident, extra) {
    const v = Object.assign({}, extra || {});
    if (ident) {
      v.POKEMON = this.pokemon(ident);
      v.NICKNAME = upper((parseIdent(ident) || {}).name);
    }
    return v;
  }

  sourceVals(v, kw) {
    if (kw.of) v.SOURCE = this.pokemon(kw.of);
    if (kw.from) {
      const e = parseEffect(kw.from);
      if (e.kind === "item") v.ITEM = e.name;
      if (e.kind === "ability") v.ABILITY = e.name;
      if (e.kind === "move") v.MOVE = upper(e.name);
      v.EFFECT = e.name;
    }
    return v;
  }

  // "[Intimidate]"-style announcement when an ability triggers something.
  abilityLine(kw) {
    const e = kw.from ? parseEffect(kw.from) : null;
    if (!e || e.kind !== "ability") return null;
    const who = kw.of || this.lastIdent;
    if (!who) return null;
    return this.step("text", who, {}, this.pokemon(who) + "'s " + e.name + "!");
  }

  // ---- Battle flow ----

  on_turn(args) { return { t: "turn", turn: Number(args[0]), text: "" }; }

  // The players are named "p1" and "p2" in the sim, so the winner is easy to tell.
  on_win(args) { return { t: "win", winner: args[0] === "p1" ? 0 : args[0] === "p2" ? 1 : -1, text: "" }; }
  on_tie() { return { t: "win", winner: -1, text: "The battle ended in a draw!" }; }

  on_switch(args, kw) { return this.sendOut(args, kw, false); }
  on_drag(args, kw) { return this.sendOut(args, kw, true); }
  on_replace(args, kw) { return this.sendOut(args, kw, true); }

  sendOut(args, kw, dragged) {
    const p = parseIdent(args[0]);
    const d = parseDetails(args[1]);
    const hp = parseHP(args[2]);
    this.lastIdent = args[0];
    const mon = { species: d.species, name: p.name, level: d.level, gender: d.gender, shiny: d.shiny,
                  hp: hp.hp, maxhp: hp.maxhp || 100, status: hp.status === "fnt" ? "" : hp.status };
    const name = upper(p.name);
    const text = dragged ? this.fill(T.default.default.drag, { FULLNAME: (p.side ? "Foe " : "") + name })
      : p.side === 0 ? "Go! " + name + "!"
      : this.names[1] + " sent out " + name + "!";
    return this.step("switch", args[0], { mon: mon }, text);
  }

  on_detailschange(args) {
    const d = parseDetails(args[1]);
    return this.step("species", args[0], { species: d.species }, "");
  }
  on__formechange(args, kw) {
    const d = parseDetails(args[1]);
    const v = this.sourceVals(this.vals(args[0]), kw);
    const tpl = kw.from ? template(parseEffect(kw.from), "transform", "") : "";
    return this.step("species", args[0], { species: d.species }, tpl ? this.fill(tpl, v) : "");
  }
  on__mega(args) {
    const v = this.vals(args[0], { ITEM: args[2] || "", TRAINER: this.names[(parseIdent(args[0]) || {}).side || 0], SPECIES: args[1] });
    return [this.step("text", args[0], {}, this.fill(T.default.default.mega, v)),
            this.step("text", args[0], {}, this.fill(T.default.default.transformMega, v))];
  }

  on_move(args, kw) {
    this.lastIdent = args[0];
    this.lastMove = args[1];
    this.spread = !!kw.spread;
    const steps = [];
    if (kw.from) {
      const e = parseEffect(kw.from);
      const pre = template(e, "move", "");
      if (pre && e.kind !== "move") steps.push(this.step("text", args[0], {}, this.fill(pre, this.vals(args[0], { MOVE: upper(args[1]) }))));
    }
    const user = this.pokemon(args[0]);
    const s = this.step("move", args[0], { move: args[1], target: args[2] ? parseIdent(args[2]) : null },
                        user + " used " + upper(args[1]) + "!");
    steps.push(s);
    if (kw.miss && args[2]) steps.push(this.step("text", args[2], {}, this.fill(T.default.default.miss, this.vals(args[2]))));
    if (kw.notarget) steps.push({ t: "text", text: "But there was no target..." });
    return steps;
  }

  on_cant(args) {
    const reason = parseEffect(args[1]);
    const v = this.vals(args[0], { MOVE: upper(args[2] || "") });
    let tpl = template(reason, "cant", "");
    if (!tpl) tpl = args[2] ? T.default.default.cant : T.default.default.cantNoMove;
    return this.step("text", args[0], {}, this.fill(tpl, v));
  }

  on_faint(args) {
    return this.step("faint", args[0], {}, this.fill(T.default.default.faint, this.vals(args[0])));
  }

  // ---- HP ----

  hpStep(args, kw, key) {
    const hp = parseHP(args[1]);
    const v = this.sourceVals(this.vals(args[0]), kw);
    let text = "";
    if (kw.from) {
      const e = parseEffect(kw.from);
      if (e.id === "drain" && kw.of) text = this.fill(template(e, "heal"), Object.assign(v, { SOURCE: this.pokemon(kw.of) }));
      else if (e.kind === "item") text = this.fill(template(e, key, "") || (key === "damage" ? T.default.default.damageFromItem : T.default.default.healFromEffect), v);
      else if (e.kind === "ability") text = this.fill(template(e, key, "") || (key === "damage" ? T.default.default.damage : T.default.default.healFromEffect), v);
      else text = this.fill(template(e, key, "") || (key === "damage" ? "" : T.default.default.heal), v);
    } else if (key === "heal") {
      text = kw.silent ? "" : this.fill(T.default.default.heal, v);
    }
    const out = [this.step("hp", args[0], { hp: hp.hp, maxhp: hp.maxhp, status: hp.status }, text)];
    return out;
  }
  on__damage(args, kw) { return this.hpStep(args, kw, "damage"); }
  on__heal(args, kw) { return this.hpStep(args, kw, "heal"); }
  on__sethp(args, kw) {
    const hp = parseHP(args[1]);
    return this.step("hp", args[0], { hp: hp.hp, maxhp: hp.maxhp, status: hp.status }, kw.from ? this.fill(template(parseEffect(kw.from), "activate", "") , this.vals(args[0])) : "");
  }

  // ---- Status ----

  on__status(args, kw) {
    const e = kw.from ? parseEffect(kw.from) : null;
    const v = this.sourceVals(this.vals(args[0]), kw);
    let tpl = "";
    if (e && e.id === "rest") tpl = template({ id: "slp" }, "startFromRest");
    else if (e && e.kind === "item") tpl = template({ id: args[1] }, "startFromItem", "") || template({ id: args[1] }, "start");
    else tpl = template({ id: args[1] }, "start");
    const steps = [];
    const a = this.abilityLine(kw);
    if (a && (!e || e.kind === "ability")) steps.push(a);
    steps.push(this.step("status", args[0], { status: args[1] }, this.fill(tpl, v)));
    return steps;
  }
  on__curestatus(args, kw) {
    const v = this.sourceVals(this.vals(args[0]), kw);
    const e = kw.from ? parseEffect(kw.from) : null;
    let tpl = e && e.kind === "item" ? template({ id: args[1] }, "endFromItem", "") : "";
    if (!tpl && e && e.kind === "move") tpl = template({ id: args[1] }, "endFromMove", "");
    if (!tpl) tpl = template({ id: args[1] }, "end");
    return this.step("status", args[0], { status: "" }, kw.silent || kw.msg ? "" : this.fill(tpl, v));
  }
  on__cureteam(args, kw) {
    return { t: "text", text: "The team was cured of its status problems!", cureTeam: (parseIdent(args[0]) || {}).side };
  }

  // ---- Stats ----

  boostStep(args, kw, up) {
    const amount = Number(args[2]);
    const stat = STATS[args[1]] || args[1];
    const v = this.sourceVals(this.vals(args[0], { STAT: stat }), kw);
    const e = kw.from ? parseEffect(kw.from) : null;
    let key = (up ? "boost" : "unboost") + (amount === 0 ? "0" : amount >= 3 ? "3" : amount === 2 ? "2" : "");
    let tpl = "";
    if (e && e.kind === "item") tpl = T.default.default[key + "FromItem"] || "";
    if (!tpl) tpl = T.default.default[key];
    const steps = [];
    const a = this.abilityLine(kw);
    if (a) steps.push(a);
    if (kw.zeffect) return steps;
    steps.push(this.step("boost", args[0], { up: up, amount: amount }, kw.silent ? "" : this.fill(tpl, v)));
    return steps;
  }
  on__boost(args, kw) { return this.boostStep(args, kw, true); }
  on__unboost(args, kw) { return this.boostStep(args, kw, false); }
  on__setboost(args, kw) {
    const v = this.sourceVals(this.vals(args[0]), kw);
    const tpl = kw.from ? template(parseEffect(kw.from), "boost", "") : "";
    return this.step("boost", args[0], { up: true }, tpl ? this.fill(tpl, v) : "");
  }
  on__clearboost(args) { return this.step("boost", args[0], { up: false }, this.fill(T.default.default.clearBoost, this.vals(args[0]))); }
  on__clearallboost() { return { t: "text", text: tidy(T.default.default.clearAllBoost) }; }
  on__clearnegativeboost(args, kw) {
    const tpl = kw.from ? template(parseEffect(kw.from), "activate", "") : "";
    return tpl ? this.step("boost", args[0], { up: true }, this.fill(tpl, this.vals(args[0]))) : [];
  }
  on__swapboost(args, kw) { return this.step("text", args[0], {}, this.fill(T.default.default.swapBoost, this.vals(args[0]))); }
  on__copyboost(args) { return this.step("text", args[0], {}, this.fill(T.default.default.copyBoost, this.vals(args[0], { TARGET: this.pokemon(args[1]) }))); }
  on__invertboost(args) { return this.step("text", args[0], {}, this.fill(T.default.default.invertBoost, this.vals(args[0]))); }

  // ---- Hits ----

  // In Doubles, a move that hits both foes says who each message is about.
  hitText(args, key) {
    const d = T.default.default;
    return this.spread && args[0] ? this.fill(d[key + "Spread"], this.vals(args[0])) : tidy(d[key]);
  }
  on__crit(args) { return { t: "text", text: this.hitText(args, "crit") }; }
  on__supereffective(args) { return { t: "text", text: this.hitText(args, "superEffective") }; }
  on__resisted(args) { return { t: "text", text: this.hitText(args, "resisted") }; }
  on__immune(args, kw) {
    const steps = [];
    const e = kw.from ? parseEffect(kw.from) : null;
    if (e && e.kind === "ability") {
      steps.push(this.step("text", args[0], {}, this.pokemon(args[0]) + "'s " + e.name + "!"));
      const tpl = template(e, "block", "");
      if (tpl) { steps.push(this.step("text", args[0], {}, this.fill(tpl, this.vals(args[0])))); return steps; }
    }
    steps.push(this.step("text", args[0], {}, this.fill(kw.ohko ? T.default.default.immuneOHKO : T.default.default.immune, this.vals(args[0]))));
    return steps;
  }
  on__miss(args) {
    return args[1] ? this.step("text", args[1], {}, this.fill(T.default.default.miss, this.vals(args[1])))
                   : { t: "text", text: this.fill(T.default.default.missNoPokemon, { SOURCE: this.pokemon(args[0]) }) };
  }
  on__fail(args, kw) {
    const v = this.sourceVals(this.vals(args[0]), kw);
    const steps = [];
    const a = this.abilityLine(kw);
    if (a) steps.push(a);
    const e = kw.from ? parseEffect(kw.from) : args[1] ? parseEffect(args[1]) : null;
    let tpl = e ? template(e, "fail", "") : "";
    if (!tpl && args[1] === "unboost") tpl = kw.msg ? "" : T.default.unboost.failNoStat;
    if (!tpl && e && /^(brn|par|psn|tox|slp|frz)$/.test(e.id)) tpl = template(e, "alreadyStarted", "");
    if (!tpl) tpl = T.default.default.fail;
    steps.push(this.step("text", args[0], {}, this.fill(tpl, v)));
    return steps;
  }
  on__block(args, kw) {
    const e = parseEffect(args[1]);
    const v = this.sourceVals(this.vals(args[0], { MOVE: upper(args[2] || "") }), kw);
    const tpl = template(e, "block", "") || template(e, "activate", "");
    return tpl ? this.step("text", args[0], {}, this.fill(tpl, v)) : [];
  }
  on__notarget() { return { t: "text", text: "But there was no target..." }; }
  on__ohko() { return { t: "text", text: "It's a one-hit KO!" }; }
  on__hitcount(args) {
    const n = Number(args[1]);
    return { t: "text", text: "The Pokémon was hit " + n + (n === 1 ? " time!" : " times!") };
  }
  on__nothing() { return { t: "text", text: "But nothing happened!" }; }
  on__center() { return []; }
  on__combine() { return { t: "text", text: tidy(T.default.default.combine) }; }

  // ---- Effects ----

  on__weather(args, kw) {
    const id = toID(args[0]);
    if (kw.upkeep) return [];
    const steps = [];
    const a = this.abilityLine(kw);
    if (a) steps.push(a);
    if (id === "none" || !id) {
      const prev = this.weather;
      this.weather = "";
      steps.push({ t: "weather", weather: "", text: prev ? this.fill(template({ id: prev }, "end"), {}) : "" });
      return steps;
    }
    this.weather = id;
    steps.push({ t: "weather", weather: WEATHERS[id] || id, text: this.fill(template({ id: id }, "start"), {}) });
    return steps;
  }

  fieldStep(args, kw, key) {
    const e = parseEffect(args[0]);
    const v = this.sourceVals({}, kw);
    if (kw.of) v.POKEMON = this.pokemon(kw.of);
    const tpl = template(e, key, "") || T.default.default[key === "start" ? "startFieldEffect" : "endFieldEffect"];
    return { t: "text", text: this.fill(tpl, Object.assign({ EFFECT: e.name }, v)), field: e.id, on: key === "start" };
  }
  on__fieldstart(args, kw) { return this.fieldStep(args, kw, "start"); }
  on__fieldend(args, kw) { return this.fieldStep(args, kw, "end"); }
  on__fieldactivate(args, kw) {
    const e = parseEffect(args[0]);
    const tpl = template(e, "activate", "");
    return tpl ? { t: "text", text: this.fill(tpl, this.sourceVals({}, kw)) } : [];
  }

  sideStep(args, key) {
    const side = /^p2/.test(args[0]) ? 1 : 0;
    const e = parseEffect(args[1]);
    const team = side === 1 ? "the opposing team" : "your team";
    const tpl = template(e, key, "") || T.default.default[key === "start" ? "startTeamEffect" : "endTeamEffect"];
    return { t: "text", text: this.fill(tpl, { TEAM: team, PARTY: side === 1 ? "the opposing Pokémon" : "your ally Pokémon", EFFECT: e.name }),
             sideEffect: e.id, side: side, on: key === "start" };
  }
  on__sidestart(args) { return this.sideStep(args, "start"); }
  on__sideend(args) { return this.sideStep(args, "end"); }

  on__start(args, kw) {
    const e = parseEffect(args[1]);
    const v = this.sourceVals(this.vals(args[0], { EFFECT: e.name, TYPE: args[2] || "", MOVE: upper(args[2] || "") }), kw);
    if (e.id === "typechange") {
      return this.step("text", args[0], {}, this.fill(kw.from ? T.default.default.typeChangeFromEffect : T.default.default.typeChange, v));
    }
    if (e.id === "typeadd") return this.step("text", args[0], {}, this.fill(T.default.default.typeAdd, v));
    if (kw.silent) return [];
    let tpl = "";
    if (kw.fatigue) tpl = template(e, "startFromFatigue", "");
    if (!tpl && kw.from) tpl = template(e, "startFromItem", "");
    if (!tpl) tpl = template(e, "start", "");
    if (!tpl) tpl = T.default.default.start;
    const steps = [];
    const a = this.abilityLine(kw);
    if (a) steps.push(a);
    steps.push(this.step("text", args[0], { volatile: e.id, on: true }, this.fill(tpl, v)));
    return steps;
  }
  on__end(args, kw) {
    const e = parseEffect(args[1]);
    if (kw.silent) return [];
    const v = this.sourceVals(this.vals(args[0], { EFFECT: e.name }), kw);
    let tpl = kw.from ? template(e, "endFromItem", "") : "";
    if (!tpl) tpl = template(e, "end", "");
    if (!tpl) tpl = T.default.default.end;
    return this.step("text", args[0], { volatile: e.id, on: false }, this.fill(tpl, v));
  }

  on__activate(args, kw) {
    const e = parseEffect(args[1]);
    const v = this.sourceVals(this.vals(args[0], { TARGET: kw.of ? this.pokemon(kw.of) : "", ITEM: kw.item || "",
                                                    MOVE: upper(args[2] || kw.move || ""), NUMBER: args[3] || "" }), kw);
    if (kw.of) v.TARGET = this.pokemon(kw.of);
    if (args[2] && /^p[12]/.test(args[2])) v.TARGET = this.pokemon(args[2]);
    const steps = [];
    if (e.kind === "ability") steps.push(this.step("text", args[0], {}, this.pokemon(args[0]) + "'s " + e.name + "!"));
    const tpl = template(e, "activate", "");
    if (tpl) steps.push(this.step("text", args[0], {}, this.fill(tpl, v)));
    return steps;
  }
  on__singleturn(args, kw) {
    const e = parseEffect(args[1]);
    const tpl = template(e, "start", "");
    return tpl ? this.step("text", args[0], {}, this.fill(tpl, this.sourceVals(this.vals(args[0]), kw))) : [];
  }
  on__singlemove(args, kw) { return this.on__singleturn(args, kw); }
  on__prepare(args) {
    const e = { kind: "move", id: toID(args[1]) };
    const tpl = template(e, "prepare", "");
    return tpl ? this.step("text", args[0], {}, this.fill(tpl, this.vals(args[0], { TARGET: args[2] ? this.pokemon(args[2]) : "" }))) : [];
  }
  on__mustrecharge() { return []; }

  on__item(args, kw) {
    const v = this.sourceVals(this.vals(args[0], { ITEM: args[1] }), kw);
    const e = kw.from ? parseEffect(kw.from) : null;
    let tpl = "";
    if (e && e.kind === "ability") {
      const steps = [this.step("text", kw.of || args[0], {}, this.pokemon(kw.of || args[0]) + "'s " + e.name + "!")];
      tpl = template(e, "activate", "") || ("{POKEMON} is holding {ITEM}!");
      if (kw.of) { v.TARGET = this.pokemon(args[0]); v.POKEMON = this.pokemon(kw.of); }
      steps.push(this.step("text", args[0], {}, this.fill(tpl.replace("{POKEMON}", "{TARGET}").replace("{SOURCE}", "{POKEMON}"), Object.assign({}, v, { POKEMON: this.pokemon(args[0]), SOURCE: v.SOURCE }))));
      return steps;
    }
    if (e && e.kind === "move") tpl = template(e, "takeItem", "") || template(e, "addItem", "") || T.default.default.addItem;
    if (!tpl) tpl = template({ kind: "item", id: toID(args[1]) }, "start", "");
    return tpl ? this.step("text", args[0], {}, this.fill(tpl, v)) : [];
  }
  on__enditem(args, kw) {
    const v = this.sourceVals(this.vals(args[0], { ITEM: args[1] }), kw);
    const item = { kind: "item", id: toID(args[1]) };
    if (kw.eat) return this.step("text", args[0], {}, this.fill(template(item, "eatItem", "") || T.default.default.eatItem, v));
    if (kw.weaken) return this.step("text", args[0], {}, this.fill(T.default.default.activateWeaken, v));
    if (kw.from) {
      const e = parseEffect(kw.from);
      if (e.kind === "move" || e.id === "stealeat") {
        const tpl = template(e, "removeItem", "") || T.default.default.removeItem;
        return this.step("text", args[0], {}, this.fill(tpl, v));
      }
    }
    if (kw.silent) return [];
    const tpl = template(item, "end", "") || template(item, "activate", "") || "";
    return tpl ? this.step("text", args[0], {}, this.fill(tpl, v)) : [];
  }

  on__ability(args, kw) {
    const e = { kind: "ability", id: toID(args[1]), name: args[1] };
    const steps = [this.step("text", args[0], {}, this.pokemon(args[0]) + "'s " + args[1] + "!")];
    if (kw.from && parseEffect(kw.from).kind !== "ability") {
      const m = parseEffect(kw.from);
      const tpl = template(m, "changeAbility", "") || T.default.default.changeAbility;
      steps[0] = this.step("text", args[0], {}, this.fill(tpl, this.vals(args[0], { ABILITY: args[1] })));
      return steps;
    }
    const tpl = template(e, "start", "");
    if (tpl) steps.push(this.step("text", args[0], {}, this.fill(tpl, this.sourceVals(this.vals(args[0]), kw))));
    return steps;
  }
  on__endability(args) { return []; }

  on__transform(args) {
    return this.step("species", args[0], { species: "", transform: args[1] },
                     this.fill(template({ kind: "move", id: "transform" }, "transform", "") || T.default.default.transform,
                               this.vals(args[0], { SPECIES: args[1], TARGET: this.pokemon(args[1]) })));
  }

  on__message(args) { return { t: "text", text: args[0] || "" }; }
  on_message(args) { return { t: "text", text: args[0] || "" }; }
}
