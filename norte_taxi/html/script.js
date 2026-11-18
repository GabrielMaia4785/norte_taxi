/*
    norte_taxi · NUI
    Contrato com o Lua:
      mensagens  open { player, destinations, waypoint, dest, riding, avgSpeed }, close
      callbacks  close, setDestination { x, y, z, label } -> { ok, message }, stopHere
    O servidor confirma o destino. Aqui só se mostra e se pede.

    O mapa é o do próprio WHIP (whip_core/html/js/map3d/map3d.js com os dados de whip_media_map), visto de cima.
    Sem ele (fora do jogo ou se não carregar), fica uma grelha com a mesma escala, e a lista continua a funcionar.
*/

const $ = (id) => document.getElementById(id);
const IN_GAME = typeof GetParentResourceName === 'function';
const RESOURCE = IN_GAME ? GetParentResourceName() : 'norte_taxi';

const MAP_DATA = 'https://cfx-nui-whip_media_map/map/whip-map3d.js';
const MAP_MODULE = 'https://cfx-nui-whip_core/html/js/map3d/map3d.js';
const K0 = 0.33 / 16;                 // px por metro com zoom 0 (o mesmo do mapa do WHIP)
const ZOOM = { min: 2.2, max: 7.2, start: 4.6 };
const ROAD_FACTOR = 1.3;              // a estrada é mais comprida que a linha reta

/* ------------------------------------------------------------------ ponte */
let busyCount = 0;
function busy(delta) {
    busyCount = Math.max(0, busyCount + delta);
    $('busy').classList.toggle('on', busyCount > 0);
}

function post(endpoint, data) {
    if (!IN_GAME) return Promise.resolve(null);
    return fetch(`https://${RESOURCE}/${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data || {}),
    }).catch(() => null);
}

function ask(endpoint, data) {
    busy(1);
    const req = IN_GAME
        ? fetch(`https://${RESOURCE}/${endpoint}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data || {}),
        }).then((r) => r.json())
        : new Promise((res) => setTimeout(() => res({ ok: true }), 600));     // pré-visualização
    return req
        .catch(() => ({ ok: false, message: 'No answer from the server.' }))
        .finally(() => busy(-1));
}

/* ------------------------------------------------------------------ utilitários */
const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const lite = () => document.documentElement.classList.contains('lite');
const remPx = () => parseFloat(getComputedStyle(document.documentElement).fontSize) || 1;
const dist2 = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);

function km(m) {
    if (m < 1000) return `${Math.round(m / 10) * 10} m`;
    return `${(m / 1000).toLocaleString('en-US', { minimumFractionDigits: 1, maximumFractionDigits: 1 })} km`;
}

function toast(text, kind) {
    const el = document.createElement('div');
    el.className = 'toast';
    el.innerHTML = `<span class="dot ${kind === 'ok' ? 'dot-ok' : kind === 'bad' ? 'dot-bad' : 'dot-accent'}"></span><span class="t-small">${esc(text)}</span>`;
    $('toasts').appendChild(el);
    setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 200); }, 3200);
}

const ICON = {
    gps: '<svg viewBox="0 0 16 16"><path d="M8 1.5a4.6 4.6 0 0 0-4.6 4.6C3.4 9.6 8 14.5 8 14.5s4.6-4.9 4.6-8.4A4.6 4.6 0 0 0 8 1.5zm0 6.4a1.8 1.8 0 1 1 0-3.6 1.8 1.8 0 0 1 0 3.6z"/></svg>',
    place: '<svg viewBox="0 0 16 16"><path d="M4 14.5V2h8.6l-1.8 3.2 1.8 3.2H5.5v6.1z"/></svg>',
};

/* ------------------------------------------------------------------ estado */
const state = {
    open: false,
    player: { x: 0, y: 0, z: 0, heading: 0 },
    destinations: [],       // { label, x, y, z, kind }
    selected: null,         // { label, x, y, z }
    riding: false,
    avgSpeed: 11,
    sending: false,
};
const view = { x: 0, y: 0, zoom: ZOOM.start };
const ppm = () => K0 * 2 ** view.zoom;

/* ------------------------------------------------------------------ mapa */
let map = null;              // WhipMap3D quando carregou
let mapLoad = null;          // a promessa do carregamento (uma só vez)
const canvas = $('mapCanvas');

function loadScript(src) {
    return new Promise((resolve, reject) => {
        const s = document.createElement('script');
        s.src = src;
        s.onload = resolve;
        s.onerror = () => reject(new Error('could not load ' + src));
        document.head.appendChild(s);
    });
}

function loadMap() {
    if (mapLoad) return mapLoad;
    mapLoad = (async () => {
        if (!IN_GAME) throw new Error('not in game');
        await loadScript(MAP_DATA);
        const mod = await import(MAP_MODULE);
        const m = new mod.WhipMap3D(canvas, { data: window.WHIP_MAP3D, antialias: 2 });
        await m.ready;
        window.WHIP_MAP3D = null;      // fica só o mapa construído
        return m;
    })();
    return mapLoad;
}

function mapState(kind, text) {
    const el = $('mapState');
    if (!kind) { el.hidden = true; return; }
    $('mapStateDot').className = `dot ${kind === 'loading' ? 'dot-accent' : 'dot-warn'}`;
    $('mapStateText').textContent = text;
    el.hidden = false;
}

function startMap() {
    if (map) return;
    mapState('loading', 'Loading map');
    busy(1);
    loadMap()
        .then((m) => {
            map = m;
            canvas.hidden = false;
            $('mapGrid').hidden = true;
            mapState(null);
            resize();
        })
        .catch((e) => {
            console.warn('[norte_taxi] 3D map unavailable:', e);
            canvas.hidden = true;
            $('mapGrid').hidden = false;
            mapState('error', 'Map unavailable: pick from the list or use your GPS marker');
            draw();
        })
        .finally(() => busy(-1));
}

function resize() {
    if (map) map.resize(window.innerWidth, window.innerHeight, window.devicePixelRatio || 1);
    draw();
}

// O mapa é desenhado só quando muda: um pedido por frame, no máximo
let drawQueued = false;
function draw() {
    if (drawQueued) return;
    drawQueued = true;
    requestAnimationFrame(() => {
        drawQueued = false;
        if (!state.open) return;
        if (map) {
            map.setView({ x: view.x, y: view.y, pxPerMetre: ppm(), offsetX: 0, offsetY: 0, yaw: 0, pitch: 90 });
            map.render();
        } else {
            const grid = $('mapGrid');
            const cell = 1000 * ppm();
            const o = toScreen(0, 0);
            grid.style.backgroundSize = `${cell}px ${cell}px`;
            grid.style.backgroundPosition = `${o.sx}px ${o.sy}px`;
        }
        placeMarks();
    });
}

function toScreen(x, y) {
    return { sx: window.innerWidth / 2 + (x - view.x) * ppm(), sy: window.innerHeight / 2 - (y - view.y) * ppm() };
}

function toWorld(sx, sy) {
    return { x: view.x + (sx - window.innerWidth / 2) / ppm(), y: view.y - (sy - window.innerHeight / 2) / ppm() };
}

function heightAt(x, y) {
    return map ? map.heightAt(x, y) : 0;
}

// Centra o ponto na área livre à direita da coluna
function focus(x, y, zoom, animate) {
    const to = { zoom: zoom ?? view.zoom };
    const shift = (remPx() * (400 + 40)) / 2;     // metade da coluna e da margem
    to.x = x - shift / (K0 * 2 ** to.zoom);
    to.y = y;
    if (!animate || lite()) { Object.assign(view, to); draw(); return; }
    const from = { ...view }, t0 = performance.now(), ms = 420;
    const step = (now) => {
        const t = Math.min(1, (now - t0) / ms), e = 1 - (1 - t) ** 3;
        view.x = from.x + (to.x - from.x) * e;
        view.y = from.y + (to.y - from.y) * e;
        view.zoom = from.zoom + (to.zoom - from.zoom) * e;
        draw();
        if (t < 1 && state.open) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
}

/* ------------------------------------------------------------------ marcas */
const markEls = [];
function placeMarks() {
    const W = window.innerWidth, H = window.innerHeight;
    const put = (el, x, y) => {
        const p = toScreen(x, y);
        const inside = p.sx > -40 && p.sy > -40 && p.sx < W + 40 && p.sy < H + 40;
        el.style.visibility = inside ? 'visible' : 'hidden';
        if (inside) el.style.transform = `translate(${p.sx}px, ${p.sy}px)`;
        return p;
    };

    // destinos rápidos
    const list = state.destinations;
    while (markEls.length < list.length) {
        const el = document.createElement('div');
        el.className = 'mark';
        $('marks').insertBefore(el, $('meMark'));
        markEls.push(el);
    }
    markEls.forEach((el, i) => {
        const d = list[i];
        el.hidden = !d;
        if (!d) return;
        put(el, d.x, d.y);
        el.classList.toggle('on', !!state.selected && dist2(state.selected, d) < 1);
    });

    // jogador: a seta roda com o heading do GTA (graus para a esquerda a partir do norte)
    const me = $('meMark');
    const p = toScreen(state.player.x, state.player.y);
    me.style.transform = `translate(${p.sx}px, ${p.sy}px) rotate(${-state.player.heading}deg)`;

    const pin = $('pin');
    pin.hidden = !state.selected;
    if (state.selected) put(pin, state.selected.x, state.selected.y);
}

/* ------------------------------------------------------------------ lista e viagem */
function renderRows() {
    const rows = $('rows');
    const list = state.destinations;
    rows.innerHTML = list.map((d, i) => `
        <button class="row" data-i="${i}">
            ${d.kind === 'gps' ? ICON.gps : ICON.place}
            <span class="grow">${esc(d.label)}</span>
            <span class="sub">${km(dist2(state.player, d) * ROAD_FACTOR)}</span>
        </button>`).join('');
    $('rowsEmpty').hidden = list.length > 0;
    rows.hidden = list.length === 0;
    $('destMeta').textContent = `${list.length} ${list.length === 1 ? 'place' : 'places'}`;
    markRows();
}

function markRows() {
    document.querySelectorAll('#rows .row').forEach((el) => {
        const d = state.destinations[Number(el.dataset.i)];
        el.classList.toggle('on', !!state.selected && !!d && dist2(state.selected, d) < 1);
    });
}

function renderTrip() {
    const s = state.selected;
    $('cellDest').textContent = s ? s.label : '—';
    if (s) {
        const road = dist2(state.player, s) * ROAD_FACTOR;
        const min = Math.max(1, Math.round(road / state.avgSpeed / 60));
        $('cellDist').textContent = km(road);
        $('cellEta').textContent = `${min} min`;
        $('tripMeta').textContent = state.riding ? 'On the way' : 'Ready to go';
    } else {
        $('cellDist').textContent = '—';
        $('cellEta').textContent = '—';
        $('tripMeta').textContent = state.riding ? 'On the way' : 'No destination';
    }
    $('goBtn').disabled = !s || state.sending;
}

function select(dest, opts = {}) {
    state.selected = { label: dest.label, x: dest.x, y: dest.y, z: dest.z ?? heightAt(dest.x, dest.y) };
    markRows();
    renderTrip();
    const pin = $('pin');
    pin.classList.remove('drop');
    void pin.offsetWidth;
    pin.classList.add('drop');
    if (opts.fly) focus(dest.x, dest.y, Math.max(view.zoom, 4.2), true);
    else draw();
}

async function confirm() {
    const s = state.selected;
    if (!s || state.sending) return;
    state.sending = true;
    renderTrip();
    const res = await ask('setDestination', { x: s.x, y: s.y, z: s.z, label: s.label });
    state.sending = false;
    if (!res || !res.ok) {
        toast((res && res.message) || 'The taxi did not accept the destination.', 'bad');
        renderTrip();
        return;
    }
    if (!IN_GAME) { toast(`On the way: ${s.label}`, 'ok'); close(true); previewStart(); }
}

/* ------------------------------------------------------------------ abrir e fechar */
function open(d) {
    state.open = true;
    state.player = d.player || state.player;
    state.riding = !!d.riding;
    state.avgSpeed = Number(d.avgSpeed) > 0 ? Number(d.avgSpeed) : 11;
    state.sending = false;

    const list = [];
    if (d.waypoint) list.push({ label: 'GPS marker', x: d.waypoint.x, y: d.waypoint.y, z: d.waypoint.z, kind: 'gps' });
    (d.destinations || []).forEach((x) => list.push({ label: x.label, x: x.x, y: x.y, z: x.z, kind: 'place' }));
    state.destinations = list;
    state.selected = d.dest ? { label: d.dest.label || 'Current destination', x: d.dest.x, y: d.dest.y, z: d.dest.z } : null;

    $('sub').textContent = state.riding && state.selected
        ? `On the way to ${state.selected.label}.`
        : 'Pick a destination from the list or click the map.';
    $('goLabel').textContent = state.riding ? 'Change destination' : 'Go to destination';
    $('stopBtn').hidden = !state.riding;

    renderRows();
    renderTrip();

    const el = $('taxi');
    el.classList.remove('closing');
    el.hidden = false;
    el.classList.remove('open');
    void el.offsetWidth;
    el.classList.add('open');

    const c = state.selected || state.player;
    focus(c.x, c.y, ZOOM.start, false);
    if (map) resize(); else startMap();
}

function close(notifyLua) {
    if (!state.open) return;
    state.open = false;
    const el = $('taxi');
    el.classList.add('closing');
    setTimeout(() => { if (!state.open) { el.hidden = true; el.classList.remove('closing', 'open'); } }, 200);
    if (notifyLua) post('close');
}

/* ------------------------------------------------------------------ entrada */
$('rows').addEventListener('click', (e) => {
    const row = e.target.closest('.row');
    if (!row) return;
    const d = state.destinations[Number(row.dataset.i)];
    if (d) select(d, { fly: true });
});

$('goBtn').addEventListener('click', confirm);
$('stopBtn').addEventListener('click', () => { post('stopHere'); close(false); });

const mapEl = $('map');
let drag = null;
mapEl.addEventListener('pointerdown', (e) => {
    if (e.button !== 0) return;
    drag = { x: e.clientX, y: e.clientY, vx: view.x, vy: view.y, moved: false };
    mapEl.setPointerCapture(e.pointerId);
});
mapEl.addEventListener('pointermove', (e) => {
    if (!drag) return;
    const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
    if (!drag.moved && Math.hypot(dx, dy) < 4) return;
    drag.moved = true;
    mapEl.classList.add('dragging');
    view.x = drag.vx - dx / ppm();
    view.y = drag.vy + dy / ppm();
    draw();
});
mapEl.addEventListener('pointerup', (e) => {
    if (!drag) return;
    const clicked = !drag.moved;
    drag = null;
    mapEl.classList.remove('dragging');
    if (!clicked || state.sending) return;
    const w = toWorld(e.clientX, e.clientY);
    // Perto de um destino rápido: escolhe-o
    const near = state.destinations.find((d) => dist2(d, w) * ppm() < 14 * remPx());
    select(near || { label: 'Point on map', x: w.x, y: w.y });
});
mapEl.addEventListener('wheel', (e) => {
    e.preventDefault();
    const before = toWorld(e.clientX, e.clientY);
    view.zoom = Math.min(ZOOM.max, Math.max(ZOOM.min, view.zoom - e.deltaY * 0.0016));
    // o ponto debaixo do rato fica no mesmo sítio
    view.x = before.x - (e.clientX - window.innerWidth / 2) / ppm();
    view.y = before.y + (e.clientY - window.innerHeight / 2) / ppm();
    draw();
}, { passive: false });

window.addEventListener('resize', () => { if (state.open) resize(); });

window.addEventListener('keydown', (e) => {
    if (!state.open) return;
    if (e.key === 'Escape') close(true);
    else if (e.key === 'Enter' && !$('goBtn').disabled) confirm();
});

/* ------------------------------------------------------------------ aviso do E (World): começar a viagem ou ir mais rápido */
let hintPaying = false;
function hint(d) {
    const el = $('hint');
    if (!d.show) { el.hidden = true; if (hintPaying) { hintPaying = false; busy(-1); } return; }
    $('hintLabel').textContent = d.label || 'Faster';
    $('hintSub').textContent = d.sub || '';
    // sem preço (começar a viagem): o valor não aparece
    $('hintPrice').hidden = d.price == null;
    $('hintPrice').textContent = `$${(Number(d.price) || 0).toLocaleString('en-US')}`;
    $('hintKey').textContent = String(d.key || 'E').slice(0, 6);
    el.classList.toggle('paying', !!d.paying);
    if (!!d.paying !== hintPaying) { hintPaying = !!d.paying; busy(hintPaying ? 1 : -1); }
    if (d.paying) { el.classList.remove('pressed'); void el.offsetWidth; el.classList.add('pressed'); }
    el.hidden = false;
}

window.addEventListener('message', (e) => {
    const d = e.data;
    if (!d || typeof d !== 'object') return;
    if (d.action === 'open') open(d);
    else if (d.action === 'close') close(false);
    else if (d.action === 'hint') hint(d);
});

/* ------------------------------------------------------------------ pré-visualização no browser */
// Na pré-visualização: primeiro o E começa a viagem, depois paga o ritmo seguinte (aqui sem servidor)
function previewStart() {
    hint({ show: true, label: 'Start ride', sub: 'To Legion Square', key: 'E' });
    window.onkeydown = (e) => {
        if (e.key.toLowerCase() !== 'e' || state.open) return;
        hint({ show: true, label: 'Start ride', sub: 'To Legion Square', key: 'E', paying: true });
        setTimeout(() => previewHint(1), 600);
    };
}

function previewHint(level) {
    const tiers = [null, { price: 20, label: 'Fast', sub: 'Obeys the rules, drives fast' }, { price: 50, label: 'Super fast', sub: 'No traffic rules at all' }];
    const t = tiers[level];
    hint(t ? { show: true, level, price: t.price, label: t.label, sub: t.sub, key: 'E' } : { show: false });
    window.onkeydown = !t ? null : (e) => {
        if (e.key.toLowerCase() !== 'e' || state.open) return;
        hint({ show: true, level, price: t.price, label: t.label, sub: t.sub, key: 'E', paying: true });
        setTimeout(() => previewHint(level + 1), 700);
    };
}

if (!IN_GAME) {
    open({
        player: { x: 215, y: -810, z: 30, heading: 70 },
        waypoint: { x: -1037, y: -2737, z: 20 },
        destinations: [
            { label: 'Legion Square', x: 195, y: -934, z: 30.7 },
            { label: 'Pillbox Hospital', x: 298.6, y: -584.5, z: 43.3 },
            { label: 'Mission Row Police', x: 428, y: -981, z: 30.7 },
            { label: 'Vespucci Beach', x: -1223, y: -1491, z: 4.4 },
            { label: 'Sandy Shores', x: 1961, y: 3740, z: 32.3 },
        ],
        riding: false,
        avgSpeed: 11.4,
    });
}
