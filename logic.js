// Shared, pure display-model helpers for omarchy-displays.
// Used by both the standalone Quickshell app (qml/Displays.qml) and the
// Omarchy bar plugin (Panel.qml). No QML, no state — functions in, values out.
.pragma library

function trimNum(s) {
    s = String(s);
    if (s.indexOf(".") >= 0) s = s.replace(/0+$/, "").replace(/\.$/, "");
    return s;
}

function fmtScale(s) {
    return trimNum((Math.round(s * 100) / 100).toString());
}

// One monitor's on-screen logical size, accounting for scale and rotation.
function logicalSize(m) {
    var w = Math.max(1, Math.round(m.res.w / m.scale));
    var h = Math.max(1, Math.round(m.res.h / m.scale));
    return (m.transform % 2 === 1) ? { w: h, h: w } : { w: w, h: h };
}

// Hyprland `monitor=` argument string for one monitor.
function nativeArgs(m) {
    if (!m.enabled) return m.name + ",disable";
    return m.name + "," + m.res.w + "x" + m.res.h + "@" + m.rr
         + "," + m.x + "x" + m.y + "," + fmtScale(m.scale)
         + ",transform," + m.transform;
}

// `hyprctl --batch` payload that applies the whole arrangement live.
function batch(ms) {
    var parts = [];
    for (var i = 0; i < ms.length; i++)
        parts.push("keyword monitor " + nativeArgs(ms[i]));
    return parts.join(" ; ");
}

// `monitor=` lines for `omarchy-displays --from-native`.
function nativeLines(ms) {
    var out = [];
    for (var i = 0; i < ms.length; i++) out.push("monitor=" + nativeArgs(ms[i]));
    return out.join("\n");
}

// Parse `hyprctl -j monitors all` into the working model.
function parseMonitors(jsonText) {
    var arr;
    try { arr = JSON.parse(jsonText); } catch (e) { return null; }
    var ms = [];
    for (var i = 0; i < arr.length; i++) {
        var d = arr[i];
        var w = d.width || 1920, h = d.height || 1080;
        var modes = [];
        var am = d.availableModes || [];
        for (var j = 0; j < am.length; j++) {
            var mm = /^(\d+)x(\d+)@([\d.]+)/.exec(am[j]);
            if (mm) modes.push({ w: +mm[1], h: +mm[2], rr: trimNum(mm[3]) });
        }
        var curRR = trimNum(String(d.refreshRate || 60));
        var have = false;
        for (var k = 0; k < modes.length; k++)
            if (modes[k].w === w && modes[k].h === h && modes[k].rr === curRR) have = true;
        if (!have) modes.push({ w: w, h: h, rr: curRR });
        if (!modes.length) modes.push({ w: w, h: h, rr: "60" });
        ms.push({
            name: d.name,
            desc: d.description || d.model || d.name,
            enabled: !d.disabled,
            x: d.x || 0, y: d.y || 0,
            scale: d.scale || 1,
            transform: d.transform || 0,
            res: { w: w, h: h },
            rr: curRR,
            modes: modes
        });
    }
    _seedPrimary(ms);
    return ms;
}

function clone(ms) { return JSON.parse(JSON.stringify(ms)); }

function _overlaps(m, s, o, os) {
    return m.x < o.x + os.w && m.x + s.w > o.x && m.y < o.y + os.h && m.y + s.h > o.y;
}

// True when m shares an edge with o (with real overlap along that edge), i.e.
// the cursor can cross between them. Positions from hyprctl aren't always round,
// so allow a 1px seam.
function _touches(m, s, o, os) {
    var vGap = Math.min(m.y + s.h, o.y + os.h) - Math.max(m.y, o.y);
    var hGap = Math.min(m.x + s.w, o.x + os.w) - Math.max(m.x, o.x);
    var edgeV = Math.abs(m.x + s.w - o.x) <= 1 || Math.abs(o.x + os.w - m.x) <= 1;
    var edgeH = Math.abs(m.y + s.h - o.y) <= 1 || Math.abs(o.y + os.h - m.y) <= 1;
    return (edgeV && vGap > 0) || (edgeH && hGap > 0);
}

function _touchesAny(ms, idx) {
    var m = ms[idx], s = logicalSize(m);
    for (var i = 0; i < ms.length; i++) {
        if (i === idx || !ms[i].enabled) continue;
        if (_touches(m, s, ms[i], logicalSize(ms[i]))) return true;
    }
    return false;
}

// Slide v (start of an A-range of length aLen) so it overlaps the B-range
// [bStart, bStart+bLen] by at least a quarter of the smaller side.
function _clampOverlap(v, aLen, bStart, bLen) {
    var k = Math.min(aLen, bLen) * 0.25;
    return Math.max(bStart - aLen + k, Math.min(v, bStart + bLen - k));
}

// Move ms[idx] the shortest distance that puts it flush against some other
// enabled monitor. Mutates in place.
function _pullFlush(ms, idx) {
    var m = ms[idx], s = logicalSize(m);
    var bestCost = 1e18, bx = m.x, by = m.y;
    for (var i = 0; i < ms.length; i++) {
        if (i === idx || !ms[i].enabled) continue;
        var o = ms[i], os = logicalSize(o);
        var cands = [
            { x: o.x + os.w, y: _clampOverlap(m.y, s.h, o.y, os.h) },  // right of o
            { x: o.x - s.w,  y: _clampOverlap(m.y, s.h, o.y, os.h) },  // left of o
            { x: _clampOverlap(m.x, s.w, o.x, os.w), y: o.y + os.h },  // below o
            { x: _clampOverlap(m.x, s.w, o.x, os.w), y: o.y - s.h }    // above o
        ];
        for (var c = 0; c < cands.length; c++) {
            var cost = Math.abs(cands[c].x - m.x) + Math.abs(cands[c].y - m.y);
            if (cost < bestCost) { bestCost = cost; bx = cands[c].x; by = cands[c].y; }
        }
    }
    m.x = Math.round(bx); m.y = Math.round(by);
}

// Hyprland has no primary-monitor concept of its own, so the model carries the
// flag: exactly one enabled monitor is `primary`, and resolveAndNormalize keeps
// that one at (0,0). Returns -1 when no enabled monitor claims it.
function _primaryIndex(ms) {
    for (var i = 0; i < ms.length; i++) if (ms[i].primary && ms[i].enabled) return i;
    return -1;
}

// Adopt the primary from a layout that carries no flag yet: whoever holds the
// origin, else the first enabled output.
function _seedPrimary(ms) {
    var pick = -1;
    for (var i = 0; i < ms.length; i++) {
        if (!ms[i].enabled) continue;
        if (ms[i].x === 0 && ms[i].y === 0) { pick = i; break; }
        if (pick < 0) pick = i;
    }
    for (var j = 0; j < ms.length; j++) ms[j].primary = (j === pick);
}

// Push ms[idx] off everything it overlaps, guarantee it still touches the rest
// (no gap the cursor can't cross), then shift the whole set so the primary
// monitor sits at (0,0). Mutates ms in place.
function resolveAndNormalize(ms, idx) {
    var enabled = 0;
    for (var e = 0; e < ms.length; e++) if (ms[e].enabled) enabled++;

    for (var round = 0; round < 4; round++) {
        var m = ms[idx], s = logicalSize(m);
        for (var pass = 0; pass < 5; pass++) {
            var moved = false;
            for (var i = 0; i < ms.length; i++) {
                if (i === idx || !ms[i].enabled) continue;
                var o = ms[i], os = logicalSize(o);
                if (_overlaps(m, s, o, os)) {
                    var penL = m.x + s.w - o.x, penR = o.x + os.w - m.x;
                    var penT = m.y + s.h - o.y, penB = o.y + os.h - m.y;
                    var mn = Math.min(penL, penR, penT, penB);
                    if (mn === penL)      m.x -= penL;
                    else if (mn === penR) m.x += penR;
                    else if (mn === penT) m.y -= penT;
                    else                  m.y += penB;
                    moved = true;
                }
            }
            if (!moved) break;
        }
        // No gaps allowed: if this monitor floats free of every other, pull it
        // back until it's flush, then re-check for overlap.
        if (enabled < 2 || !ms[idx].enabled || _touchesAny(ms, idx)) break;
        _pullFlush(ms, idx);
    }

    // The primary owns the origin; everything else is placed relative to it,
    // negative coordinates included (Hyprland takes those). Anchoring on the
    // layout's top-left instead is what used to make setPrimary a no-op.
    var ax, ay, p = _primaryIndex(ms);
    if (p >= 0) {
        ax = ms[p].x; ay = ms[p].y;
    } else {
        ax = 1e9; ay = 1e9;
        for (var a = 0; a < ms.length; a++) if (ms[a].enabled) {
            ax = Math.min(ax, ms[a].x); ay = Math.min(ay, ms[a].y);
        }
        if (ax === 1e9) { ax = 0; ay = 0; }
    }
    for (var b = 0; b < ms.length; b++) { ms[b].x -= ax; ms[b].y -= ay; }
}

// Drop `ms[idx]` at logical (nx,ny): snap its edges to neighbours, then
// de-overlap and normalize. Returns a new array.
function moveMonitor(ms, idx, nx, ny) {
    ms = clone(ms);
    var m = ms[idx], s = logicalSize(m);
    m.x = nx; m.y = ny;
    var thr = 45, cx = [], cy = [];
    for (var i = 0; i < ms.length; i++) {
        if (i === idx || !ms[i].enabled) continue;
        var o = ms[i], os = logicalSize(o);
        cx.push(o.x, o.x + os.w - s.w, o.x + os.w, o.x - s.w);
        cy.push(o.y, o.y + os.h - s.h, o.y + os.h, o.y - s.h);
    }
    for (var p = 0; p < cx.length; p++) if (Math.abs(m.x - cx[p]) < thr) { m.x = Math.round(cx[p]); break; }
    for (var q = 0; q < cy.length; q++) if (Math.abs(m.y - cy[q]) < thr) { m.y = Math.round(cy[q]); break; }
    resolveAndNormalize(ms, idx);
    return ms;
}

function updateMon(ms, idx, patch) {
    ms = clone(ms);
    for (var key in patch) ms[idx][key] = patch[key];
    resolveAndNormalize(ms, idx);
    return ms;
}

function setPrimary(ms, idx) {
    ms = clone(ms);
    if (!ms[idx] || !ms[idx].enabled) return ms;
    for (var i = 0; i < ms.length; i++) ms[i].primary = (i === idx);
    resolveAndNormalize(ms, idx);
    return ms;
}

function enableMon(ms, idx, on) {
    ms = clone(ms);
    ms[idx].enabled = on;
    if (on) {
        var maxr = 0;
        for (var i = 0; i < ms.length; i++) if (i !== idx && ms[i].enabled)
            maxr = Math.max(maxr, ms[i].x + logicalSize(ms[i]).w);
        ms[idx].x = maxr; ms[idx].y = 0;
    }
    // The primary has to be an output that's on: disabling it hands the origin
    // to whatever is left, and the first output back on takes it.
    if (_primaryIndex(ms) < 0) _seedPrimary(ms);
    resolveAndNormalize(ms, idx);
    return ms;
}

function setResolution(ms, idx, w, h) {
    var m = ms[idx], best = "0";
    for (var i = 0; i < m.modes.length; i++)
        if (m.modes[i].w === w && m.modes[i].h === h)
            if (parseFloat(m.modes[i].rr) >= parseFloat(best)) best = m.modes[i].rr;
    if (best === "0") best = "60";
    return updateMon(ms, idx, { res: { w: w, h: h }, rr: best });
}

function isPrimary(m) { return !!(m && m.primary && m.enabled); }

function uniqRes(m) {
    if (!m) return [];
    var seen = {}, out = [];
    for (var i = 0; i < m.modes.length; i++) {
        var key = m.modes[i].w + "x" + m.modes[i].h;
        if (!seen[key]) { seen[key] = 1; out.push({ w: m.modes[i].w, h: m.modes[i].h, key: key, area: m.modes[i].w * m.modes[i].h }); }
    }
    out.sort(function (a, b) { return b.area - a.area; });
    return out;
}

function ratesFor(m) {
    if (!m) return [];
    var out = [];
    for (var i = 0; i < m.modes.length; i++)
        if (m.modes[i].w === m.res.w && m.modes[i].h === m.res.h) out.push(m.modes[i].rr);
    out.sort(function (a, b) { return parseFloat(b) - parseFloat(a); });
    return out;
}
