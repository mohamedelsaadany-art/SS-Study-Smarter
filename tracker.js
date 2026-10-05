/* Anonymous usage tracker. Sends only: random visitor id, exam day, counts. No answer text is ever sent.
   Does nothing until config.js has a Supabase url + key. Hooks the app's own localStorage saves, so the
   artifact HTML needs no changes. */
(function () {
  var C = window.SSA || {};
  if (!C.url || !C.key) return;
  var KEY_RE = /^imcamp-exam-day(\d+)-v2$/;

  function vid() {
    try {
      var v = localStorage.getItem("ssa-vid");
      if (!v) { v = (crypto.randomUUID ? crypto.randomUUID() : String(Math.random()).slice(2) + Date.now()); localStorage.setItem("ssa-vid", v); }
      return v;
    } catch (e) { return "anon"; }
  }
  var VID = vid();

  function send(kind, day, n) {
    try {
      fetch(C.url + "/rest/v1/events", {
        method: "POST", keepalive: true,
        headers: { "apikey": C.key, "Authorization": "Bearer " + C.key, "Content-Type": "application/json", "Prefer": "return=minimal" },
        body: JSON.stringify({ vid: VID, kind: kind, exam_day: day == null ? null : day, n: n == null ? 1 : n })
      }).catch(function () {});
    } catch (e) {}
  }

  // page view, once per browser session
  try { if (!sessionStorage.getItem("ssa-view")) { sessionStorage.setItem("ssa-view", "1"); send("view", null, 1); } } catch (e) {}

  function answeredCount(ans) {
    var seen = {};
    Object.keys(ans || {}).forEach(function (k) {
      if (String(ans[k] || "").trim()) seen[k.replace(/_\d$/, "")] = 1;
    });
    return Object.keys(seen).length;
  }

  function onSave(day, raw) {
    var st; try { st = JSON.parse(raw); } catch (e) { return; }
    if (!st || !st.ans) return;
    var memKey = "ssa-sent-" + day, mem;
    try { mem = JSON.parse(localStorage.getItem(memKey)) || {}; } catch (e) { mem = {}; }
    var a = answeredCount(st.ans);
    var p1 = !!(st.done && st.done[1]), p2 = !!(st.done && st.done[2]);
    var sentA = mem.a || 0;
    if (a > sentA) { send("answered", day, a - sentA); mem.a = a; }
    if (p1 && !mem.p1) { send("part_done", day, 1); mem.p1 = 1; }
    if (p2 && !mem.p2) { send("part_done", day, 1); mem.p2 = 1; }
    if (p1 && p2 && !mem.x) { send("exam_done", day, 1); mem.x = 1; }
    try { localStorage.setItem(memKey, JSON.stringify(mem)); } catch (e) {}
  }

  var orig = Storage.prototype.setItem;
  var busy = false;
  Storage.prototype.setItem = function (k, v) {
    var r = orig.apply(this, arguments);
    try {
      if (!busy && this === window.localStorage) {
        var m = KEY_RE.exec(k);
        if (m) { busy = true; try { onSave(+m[1], v); } finally { busy = false; } }
      }
    } catch (e) { busy = false; }
    return r;
  };
})();
