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
    return ms;
}

function clone(ms) { return JSON.parse(JSON.stringify(ms)); }

// Push `ms[idx]` off every monitor it overlaps, then shift the whole set so the
// top-left enabled monitor sits at (0,0). Mutates `ms` in place.
function resolveAndNormalize(ms, idx) {
    var m = ms[idx], s = logicalSize(m);
    for (var pass = 0; pass < 5; pass++) {
        var moved = false;
        for (var i = 0; i < ms.length; i++) {
            if (i === idx || !ms[i].enabled) continue;
            var o = ms[i], os = logicalSize(o);
            if (m.x < o.x + os.w && m.x + s.w > o.x && m.y < o.y + os.h && m.y + s.h > o.y) {
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
    var minx = 1e9, miny = 1e9;
    for (var a = 0; a < ms.length; a++) if (ms[a].enabled) {
        minx = Math.min(minx, ms[a].x); miny = Math.min(miny, ms[a].y);
    }
    if (minx === 1e9) { minx = 0; miny = 0; }
    for (var b = 0; b < ms.length; b++) { ms[b].x -= minx; ms[b].y -= miny; }
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
    var px = ms[idx].x, py = ms[idx].y;
    for (var i = 0; i < ms.length; i++) { ms[i].x -= px; ms[i].y -= py; }
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

function isPrimary(m) { return m && m.x === 0 && m.y === 0; }

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
