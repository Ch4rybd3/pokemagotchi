// WorkerScript for the Battle Tower: runs the Showdown simulator off the UI
// thread. Every message is { op, id, ... } and gets one answer { op, id, ... }.

import * as Engine from "TowerEngine.mjs";

WorkerScript.onMessage = function (msg) {
  let out;
  try {
    if (msg.op === "start") out = Engine.start(msg.battle);
    else if (msg.op === "choose") out = Engine.choose(msg.key, msg.choice);
    else if (msg.op === "forfeit") out = Engine.forfeit(msg.key);
    else if (msg.op === "close") out = Engine.close(msg.key);
    else if (msg.op === "pack") out = { packed: Engine.pack(msg.text) };
    else if (msg.op === "ping") out = { version: Engine.version() };
    else out = { error: "unknown op " + msg.op };
  } catch (e) {
    out = { error: String(e && e.message || e), stack: String(e && e.stack || "") };
  }
  out.op = msg.op;
  out.id = msg.id;
  WorkerScript.sendMessage(out);
};
