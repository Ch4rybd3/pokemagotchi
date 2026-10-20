#!/usr/bin/env node
// Builds Showdown.mjs: the Pokémon Showdown battle simulator
// (https://github.com/smogon/pokemon-showdown, MIT) as one ES module that runs
// in Quickshell's JavaScript engine (a WorkerScript), with no Node.js at run time.
//
// Usage: tools/gen-showdown.mjs [pokemon-showdown checkout]
// Without a checkout, the pinned commit is cloned into a temporary directory.
// Needs git, Node.js and npm (only to build, not to play). Writes ../Showdown.mjs.
//
// What changes from the server build:
// - The data files are bundled; the sim's dynamic require() calls resolve to them.
// - Node built-ins and server-only modules (SQL, processes, sockets) are stubs.
// - Only the base (Gen 9) data is kept, with the two Battle Tower formats below.
// - Battle texts keep only their messages (no descriptions).
// - Everything is lowered to ES2016: Qt's engine has no async functions.

import { execFileSync } from 'child_process';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { builtinModules, createRequire } from 'module';

const REPO = 'https://github.com/smogon/pokemon-showdown.git';
const COMMIT = '942cda7';
const ROOT = path.dirname(path.dirname(new URL(import.meta.url).pathname));
const OUT = path.join(ROOT, 'Showdown.mjs');

function run(cmd, args, cwd) { execFileSync(cmd, args, { cwd, stdio: ['ignore', 'ignore', 'inherit'] }); }

let ps = process.argv[2];
if (!ps) {
  ps = path.join(os.tmpdir(), 'pokemagotchi-showdown');
  if (!fs.existsSync(path.join(ps, '.git'))) {
    console.error('cloning', REPO);
    run('git', ['clone', '--filter=blob:none', REPO, ps]);
  }
  run('git', ['fetch', '--quiet', 'origin'], ps);
  run('git', ['checkout', '--quiet', COMMIT], ps);
}
ps = path.resolve(ps);
if (!fs.existsSync(path.join(ps, 'node_modules'))) { console.error('npm install'); run('npm', ['install', '--silent'], ps); }
console.error('building pokemon-showdown');
run('node', ['build'], ps);
const commit = execFileSync('git', ['rev-parse', '--short', 'HEAD'], { cwd: ps }).toString().trim();
const dist = path.join(ps, 'dist');
const esbuild = createRequire(path.join(ps, 'package.json'))('esbuild');

// Battle Tower formats: Team Preview, 3 picked out of 6 in singles and 4 in
// doubles, like the VGC. (Everybody fights at Lv. 50: TowerEngine.mjs sets it,
// since Showdown's "Adjust Level" rule only applies in its team validator.)
const FORMATS = `exports.Formats = [
  { name: "[Gen 9] Tower Singles", mod: "gen9", gameType: "singles",
    ruleset: ["Team Preview", "Picked Team Size = 3", "Species Clause", "Item Clause = 1", "Sleep Clause Mod", "Terastal Clause", "Cancel Mod"] },
  { name: "[Gen 9] Tower Doubles", mod: "gen9", gameType: "doubles",
    ruleset: ["Team Preview", "Picked Team Size = 4", "Species Clause", "Item Clause = 1", "Terastal Clause", "Cancel Mod"] },
];`;

// Battle messages only: the descriptions are for the teambuilder.
function textTable(file, exportName) {
  const table = createRequire(import.meta.url)(path.join(dist, 'data/text', file))[exportName];
  const out = {};
  for (const id in table) {
    const entry = {};
    for (const key in table[id]) {
      if (key === 'desc' || key === 'shortDesc' || /^gen\d$/.test(key)) continue;
      entry[key] = table[id][key];
    }
    if (Object.keys(entry).length > (entry.name ? 1 : 0)) out[id] = entry;
  }
  return out;
}
const TEXT = {
  default: textTable('default.js', 'DefaultText'),
  moves: textTable('moves.js', 'MovesText'),
  abilities: textTable('abilities.js', 'AbilitiesText'),
  items: textTable('items.js', 'ItemsText'),
};

const DATA = ['abilities', 'rulesets', 'formats-data', 'items', 'moves', 'natures', 'pokedex',
  'scripts', 'conditions', 'typechart', 'aliases'];
const ENTRY = `
const MODS = {
${DATA.map(d => `  'data/${d}': require(${JSON.stringify(path.join(dist, 'data', d + '.js'))}),`).join('\n')}
  'config/formats': require('virtual:formats'),
};
globalThis.__psReq = function (p) {
  p = String(p).replace(/\\\\/g, '/').replace(/\\.js$/, '');
  for (const k in MODS) if (p.endsWith('/' + k)) return MODS[k];
  const e = new Error('Cannot find module ' + p); e.code = 'MODULE_NOT_FOUND'; throw e;
};
const sim = require(${JSON.stringify(path.join(dist, 'sim/battle.js'))});
const { Teams } = require(${JSON.stringify(path.join(dist, 'sim/teams.js'))});
const { Dex, toID } = require(${JSON.stringify(path.join(dist, 'sim/dex.js'))});
export const Showdown = { Battle: sim.Battle, extractChannelMessages: sim.extractChannelMessages, Teams, Dex, toID,
                          Text: ${JSON.stringify(TEXT)}, version: ${JSON.stringify(commit)} };
`;

const SERVER_ONLY = /\/lib\/(sql|process-manager|net|repl|static-server|postgres|crashlogger)\.js$/;
const STUB = 'module.exports = new Proxy(function () {}, { get: (t, k) => k === "__esModule" ? false : function () { return {}; } });';
const FS_STUB = `
function missing() { const e = new Error('no file system'); e.code = 'ENOENT'; throw e; }
module.exports = { readdirSync: () => [], existsSync: () => false, readFileSync: missing, statSync: missing,
                   writeFileSync() {}, mkdirSync() {}, promises: {} };`;
const PATH_STUB = `
function norm(p) { const out = []; for (const s of p.split('/')) { if (!s || s === '.') continue; if (s === '..') out.pop(); else out.push(s); } return '/' + out.join('/'); }
function basename(p, e) { let b = p.split('/').pop(); if (e && b.endsWith(e)) b = b.slice(0, -e.length); return b; }
module.exports = {
  sep: '/', resolve: (...a) => norm(a.reduce((p, x) => x.startsWith('/') ? x : p + '/' + x, '')),
  join: (...a) => norm(a.join('/')), dirname: p => norm(p + '/..'), basename,
  extname: p => { const b = basename(p); const i = b.lastIndexOf('.'); return i > 0 ? b.slice(i) : ''; },
};`;

const plugin = {
  name: 'pokemagotchi',
  setup(b) {
    b.onResolve({ filter: /^virtual:formats$/ }, () => ({ path: 'formats', namespace: 'virtual' }));
    b.onLoad({ filter: /.*/, namespace: 'virtual' }, () => ({ contents: FORMATS, loader: 'js' }));
    b.onResolve({ filter: /^(node:)?(fs|path)$/ }, a => ({ path: a.path.replace(/^node:/, ''), namespace: 'shim' }));
    b.onLoad({ filter: /.*/, namespace: 'shim' }, a => ({ contents: a.path === 'fs' ? FS_STUB : PATH_STUB, loader: 'js' }));
    b.onResolve({ filter: /.*/ }, a => {
      const n = a.path.replace(/^node:/, '');
      if (builtinModules.includes(n) || /^(better-sqlite3|sqlite|pg|mysql2|sockjs|nodemailer|probe-image-size|ts-chacha20|sucrase|esbuild)$/.test(n)) {
        return { path: n, namespace: 'stub' };
      }
    });
    b.onLoad({ filter: /.*/, namespace: 'stub' }, () => ({ contents: STUB, loader: 'js' }));
    // Server-only modules become empty, and dynamic require() calls go through
    // __psReq (static ones are bundled by esbuild).
    b.onLoad({ filter: /\/dist\/.*\.js$/ }, a => {
      if (SERVER_ONLY.test(a.path)) return { contents: 'module.exports = {};', loader: 'js' };
      const src = fs.readFileSync(a.path, 'utf8').replace(/\brequire\((?!\s*(["'])[^"'`+]*\1\s*\))/g, 'globalThis.__psReq(');
      return { contents: src, loader: 'js', resolveDir: path.dirname(a.path) };
    });
  },
};

const BANNER = `// Generated by tools/gen-showdown.mjs from Pokémon Showdown ${commit}
// (https://github.com/smogon/pokemon-showdown). MIT License, Copyright (c) 2011-2026
// Guangcong Luo and other contributors. See THIRD_PARTY_NOTICES.md.
var globalThis = {}; var global = globalThis;
var require = function (p) { return globalThis.__psReq(p); };
var __dirname = "/showdown/sim", __filename = "/showdown/sim/index.js";
var process = { env: {}, argv: [], platform: "linux", version: "v20.0.0", versions: { node: "20.0.0" },
  nextTick: function (f) { Promise.resolve().then(f); }, cwd: function () { return "/"; },
  hrtime: function () { return [0, 0]; }, memoryUsage: function () { return {}; }, on: function () {} };
// Qt's engine stops at about ES2018: add what the simulator needs from later ones.
function __poly(o, k, f) { if (!o[k]) Object.defineProperty(o, k, { value: f, writable: true, configurable: true }); }
__poly(String.prototype, "matchAll", function (re) {
  var r = new RegExp(re.source, re.flags.indexOf("g") < 0 ? re.flags + "g" : re.flags), s = String(this), out = [], m;
  while ((m = r.exec(s))) { out.push(m); if (m[0] === "") r.lastIndex++; }
  return out[Symbol.iterator]();
});
__poly(String.prototype, "replaceAll", function (a, b) {
  return typeof a === "string" ? String(this).split(a).join(b) : String(this).replace(a, b);
});
__poly(String.prototype, "trimStart", function () { return String(this).replace(/^\\s+/, ""); });
__poly(String.prototype, "trimEnd", function () { return String(this).replace(/\\s+$/, ""); });
__poly(Array.prototype, "flat", function (d) {
  d = d === undefined ? 1 : d;
  return this.reduce(function (a, x) { return a.concat(Array.isArray(x) && d > 0 ? x.flat(d - 1) : [x]); }, []);
});
__poly(Array.prototype, "flatMap", function (f, t) { return this.map(f, t).flat(1); });
__poly(Array.prototype, "at", function (i) { i = Math.trunc(i) || 0; return this[i < 0 ? this.length + i : i]; });
__poly(Array.prototype, "findLast", function (f) { for (var i = this.length - 1; i >= 0; i--) if (f(this[i], i, this)) return this[i]; });
__poly(Object, "fromEntries", function (it) { var o = {}; for (var e of it) o[e[0]] = e[1]; return o; });
__poly(Object, "hasOwn", function (o, k) { return Object.prototype.hasOwnProperty.call(o, k); });
var setTimeout = function (f) { Promise.resolve().then(f); return 0; }, clearTimeout = function () {};`;

const result = await esbuild.build({
  stdin: { contents: ENTRY, resolveDir: ROOT, sourcefile: 'showdown-entry.js', loader: 'js' },
  bundle: true, format: 'esm', platform: 'neutral', mainFields: ['main'], target: 'es2016',
  minifyWhitespace: true, minifySyntax: true, legalComments: 'none', charset: 'utf8',
  plugins: [plugin], banner: { js: BANNER }, write: false, logLevel: 'warning',
});
fs.writeFileSync(OUT, result.outputFiles[0].text);
console.error(`wrote ${OUT} (${(fs.statSync(OUT).size / 1048576).toFixed(2)} MB, Showdown ${commit})`);
