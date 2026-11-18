// WHIP RIDE: a app do whip_phone para chamar o taxi autonomo do norte_taxi.
// NorteRoleplay Design System v3.0, contexto Tablet (app dentro do telemovel), padrao 06 Store and catalog:
// escolher um ritmo (o "produto"), ver o preco e pagar com o botao Primary, confirmado por Modal.
//
// O destino marca-se no mapa da propria app (o mapa 3D do WHIP visto de cima: whip_core/html/js/map3d/map3d.js com os
// dados de whip_media_map), com um toque, ou num dos sitios rapidos. So interface: o preco, a cobranca e o pedido sao
// do servidor (norte_taxi:quote, :request, :cancel), e a viagem acompanha-se por pushes 'status'.
// Mount mode: a app desenha o seu proprio DOM. Registada por client/main.lua com exports.whip_phone:RegisterModule.
(() => {
  const { esc } = window.WhipPhone.kit;

  // O mapa vem de outros recursos. A pre-visualizacao no browser troca estes enderecos por copias locais
  const ASSETS = window.WHIPRIDE_ASSETS || {
    data: 'https://cfx-nui-whip_media_map/map/whip-map3d.js',
    module: 'https://cfx-nui-whip_core/html/js/map3d/map3d.js',
  };
  const K0 = 0.33 / 16;                       // px por metro com zoom 0, como o mapa do WHIP
  const ZOOM = { min: 1.6, max: 6.6, start: 3.6 };

  // ---------------------------------------------------------------- icones (24 box, currentColor)
  const svg = (d, fill) => `<svg viewBox="0 0 24 24" ${fill ? 'fill="currentColor"' : 'fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"'} aria-hidden="true">${d}</svg>`;
  const GLYPH = svg('<path d="M6.6 5.2c.3-.9 1.1-1.5 2-1.5h6.8c.9 0 1.7.6 2 1.5l1.6 4.6c1 .4 1.7 1.4 1.7 2.5v4.8c0 .6-.5 1.1-1.1 1.1h-.8v1.4c0 .6-.5 1.1-1.1 1.1h-1c-.6 0-1.1-.5-1.1-1.1v-1.4H8.4v1.4c0 .6-.5 1.1-1.1 1.1h-1c-.6 0-1.1-.5-1.1-1.1v-1.4h-.8c-.6 0-1.1-.5-1.1-1.1v-4.8c0-1.1.7-2.1 1.7-2.5zm1.5 4.2h7.8l-1.2-3.5c-.1-.3-.4-.5-.7-.5H9.9c-.3 0-.6.2-.7.5zM7 15.2a1.4 1.4 0 1 0 0-2.8 1.4 1.4 0 0 0 0 2.8m10 0a1.4 1.4 0 1 0 0-2.8 1.4 1.4 0 0 0 0 2.8"/>', true);
  const CAR = '<svg viewBox="0 0 48 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round" stroke-linecap="round" aria-hidden="true"><path d="M4 16.5v-3.2c0-1 .6-1.8 1.6-2.1l6.2-1.9 5-4.3c.8-.7 1.8-1 2.8-1h8.8c1.2 0 2.3.5 3.1 1.4l3.6 4 6.3 1.4c1.4.3 2.4 1.5 2.4 2.9v2.8c0 .6-.4 1-1 1h-2.2"/><path d="M15.4 17.5h13.4M8.6 17.5H5c-.6 0-1-.4-1-1"/><circle cx="12" cy="17.5" r="2.9"/><circle cx="35.7" cy="17.5" r="2.9"/><path d="M13.7 9.6h21.1M24.2 5.2v4.4"/></svg>';
  const SPEED = '<path d="M1 9h7M2.5 13h6M1 17h5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>';
  const carIcon = (n) => `<span class="car-ico">${n > 0 ? `<svg class="lines" viewBox="0 0 9 24" aria-hidden="true">${SPEED}</svg>` : ''}${CAR}</span>`;
  const ARROW = '<svg viewBox="0 0 24 24"><path d="M12 2.5 19.5 20.5 12 16.6 4.5 20.5Z"/></svg>';
  const AIM = svg('<circle cx="12" cy="12" r="6.5"/><circle cx="12" cy="12" r="1.6" fill="currentColor"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3"/>');
  const PLUS = svg('<path d="M12 5v14M5 12h14"/>');
  const MINUS = svg('<path d="M5 12h14"/>');
  const FLAG = svg('<path d="M6.2 21V4"/><path d="M6.2 4.6h11.3l-2.3 4.1 2.3 4.1H6.2"/>');
  const BACK = svg('<path d="M15 5l-7 7 7 7"/>');

  const PACE_TEXT = {
    normal: 'Obeys every rule and speed limit',
    fast: 'Obeys the rules, drives fast',
    super: 'No traffic rules at all',
  };
  const STEPS = [
    { label: 'Finding', stages: ['requested', 'spawning'] },
    { label: 'On the way', stages: ['approach'] },
    { label: 'Arrived', stages: ['waiting', 'boarded'] },
    { label: 'Riding', stages: ['riding'] },
  ];
  const STAGE = {
    requested: ['Finding a car', 'The closest self-driving car is being sent.'],
    spawning: ['Finding a car', 'The closest self-driving car is being sent.'],
    approach: ['Your car is on the way', 'It stops on the road closest to you.'],
    waiting: ['Your car is here', 'The back doors are open. Get in.'],
    boarded: ['You are in', 'Press E to start the ride.'],
    riding: ['On the way', 'You arrive when the car enters the destination area.'],
  };
  const ENDED = {
    arrived: ['ok', 'You arrived. Thanks for riding.'], stopped: ['ok', 'Ride ended.'], cancel: ['muted', 'Ride cancelled.'],
    left: ['muted', 'You left the car.'], timeout: ['bad', 'The car left: it waited too long.'], stuck: ['bad', 'The car could not reach you.'],
    nospawn: ['bad', 'No free road near you.'], expired: ['bad', 'The ride ran out of time.'], failed: ['bad', 'No car available.'],
  };

  const money = (n) => '$' + Math.ceil(+n || 0).toLocaleString('en-US');
  const km = (n) => `${(+n || 0).toLocaleString('en-US', { maximumFractionDigits: 1 })} km`;
  const active = (r) => r && r.stage && r.stage !== 'none';
  const sectionHeader = (title, meta) =>
    `<div class="section-header"><span class="t-row-title">${esc(title)}</span><span class="section-line"></span>${meta ? `<span class="t-micro">${esc(meta)}</span>` : ''}</div>`;

  // ---------------------------------------------------------------- o mapa, feito uma vez por pagina
  // Construir o mapa leva alguns segundos e ocupa memoria da placa: fica pronto para a proxima vez que a app abrir.
  const shared = { canvas: null, map: null, load: null };

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
    if (shared.load) return shared.load;
    shared.canvas = document.createElement('canvas');
    shared.canvas.className = 'map-canvas';
    shared.load = (async () => {
      if (!window.WHIP_MAP3D) await loadScript(ASSETS.data);
      const mod = await import(ASSETS.module);
      // preserveDrawingBuffer: a animacao de dobrar o telemovel fotografa o ultimo frame
      const m = new mod.WhipMap3D(shared.canvas, { data: window.WHIP_MAP3D, antialias: 2, preserveDrawingBuffer: true });
      await m.ready;
      window.WHIP_MAP3D = null;      // fica so o mapa construido
      shared.map = m;
      return m;
    })();
    shared.load.catch(() => {});
    return shared.load;
  }

  // ---------------------------------------------------------------- a app aberta
  let ui = null;
  const $ = (sel) => ui.root.querySelector(sel);

  const ppm = () => K0 * 2 ** ui.view.zoom;
  // Tamanho em px do layout: o telemovel esta escalado (e anima a abrir), e o getBoundingClientRect daria o tamanho no ecra
  const size = () => ({ w: ui.mapEl.clientWidth || 1, h: ui.mapEl.clientHeight || 1 });
  const local = (e) => {
    const r = ui.mapEl.getBoundingClientRect();
    const k = r.width ? ui.mapEl.clientWidth / r.width : 1;
    return { sx: (e.clientX - r.left) * k, sy: (e.clientY - r.top) * k, k };
  };
  const toScreen = (x, y) => { const { w, h } = size(); return { sx: w / 2 + (x - ui.view.x) * ppm(), sy: h / 2 - (y - ui.view.y) * ppm() }; };
  const toWorld = (sx, sy) => { const { w, h } = size(); return { x: ui.view.x + (sx - w / 2) / ppm(), y: ui.view.y - (sy - h / 2) / ppm() }; };

  function busy(on) {
    if (!ui) return;
    ui.busyCount = Math.max(0, ui.busyCount + (on ? 1 : -1));
    $('.busy-bar').classList.toggle('on', ui.busyCount > 0);
  }

  function resize() {
    if (!ui) return;
    const { w, h } = size();
    if (shared.map && ui.mapReady) shared.map.resize(w, h, window.devicePixelRatio || 1);
    draw();
  }

  let queued = false;
  function draw() {
    if (queued || !ui) return;
    queued = true;
    requestAnimationFrame(() => {
      queued = false;
      if (!ui) return;
      const z = ppm();
      if (shared.map && ui.mapReady) {
        shared.map.setView({ x: ui.view.x, y: ui.view.y, pxPerMetre: z, offsetX: 0, offsetY: 0, yaw: 0, pitch: 90 });
        shared.map.render();
      } else {
        const o = toScreen(0, 0), cell = 1000 * z;
        ui.gridEl.style.backgroundSize = `${cell}px ${cell}px`;
        ui.gridEl.style.backgroundPosition = `${o.sx}px ${o.sy}px`;
      }
      const put = (el, x, y, rot) => {
        if (x == null) { el.hidden = true; return null; }
        const p = toScreen(x, y);
        el.hidden = false;
        el.style.transform = `translate(${p.sx}px, ${p.sy}px)${rot != null ? ` rotate(${rot}deg)` : ''}`;
        return p;
      };
      const dest = ui.pin || (active(ui.ride) && ui.ride.dest) || null;
      const a = put(ui.meEl, ui.me && ui.me.x, ui.me && ui.me.y, ui.me ? -ui.me.heading : null);
      const b = put(ui.pinEl, dest && dest.x, dest && dest.y);
      // a area de chegada: o circulo no destino, do tamanho real
      if (b && ui.arriveRadius) {
        const d = ui.arriveRadius * 2 * z;
        ui.areaEl.hidden = false;
        ui.areaEl.style.width = ui.areaEl.style.height = `${d}px`;
        ui.areaEl.style.transform = `translate(${b.sx - d / 2}px, ${b.sy - d / 2}px)`;
      } else ui.areaEl.hidden = true;
      // a linha do jogador ao destino
      if (a && b) {
        ui.lineEl.setAttribute('x1', a.sx); ui.lineEl.setAttribute('y1', a.sy);
        ui.lineEl.setAttribute('x2', b.sx); ui.lineEl.setAttribute('y2', b.sy);
        ui.lineEl.removeAttribute('hidden');
      } else ui.lineEl.setAttribute('hidden', '');
    });
  }

  // Centra o ponto na parte do mapa que a folha de baixo nao tapa
  function focus(x, y, zoom) {
    if (zoom != null) ui.view.zoom = zoom;
    const hidden = ui.sheetEl.offsetHeight || size().h * 0.4;
    ui.view.x = x;
    ui.view.y = y - (hidden / 2) / ppm();
    draw();
  }

  // ---------------------------------------------------------------- servidor

  // a viagem do servidor; o destino que a app conhece fica com ela enquanto dura
  function setRide(r) {
    const keepDest = ui.ride && ui.ride.dest;
    ui.ride = r && r.stage ? r : { stage: 'none' };
    if (active(ui.ride)) ui.ride.dest = ui.ride.dest || keepDest;
  }

  async function quote(withPin) {
    const seq = ++ui.seq;
    const args = withPin && ui.pin ? { x: ui.pin.x, y: ui.pin.y } : {};
    busy(true);
    try {
      const r = await ui.app.request('quote', args);
      if (!ui || seq !== ui.seq) return;
      ui.me = r.me || ui.me;
      setRide(r.ride);
      ui.fare = r.fare || ui.fare;
      ui.places = Array.isArray(r.places) ? r.places : [];
      ui.arriveRadius = +r.arriveRadius || ui.arriveRadius;
      if (withPin && ui.pin) {
        ui.pin.paces = Array.isArray(r.paces) ? r.paces : [];
        ui.pin.km = r.km;
      }
      ui.error = null;
    } catch (e) {
      if (!ui || seq !== ui.seq) return;
      ui.error = e.reason || 'WHIP RIDE is not answering';
    } finally { if (ui) busy(false); }
    ui.loaded = true;
    sheet();
    // a folha cresce com os ritmos: o destino passa para a parte do mapa que ela nao tapa
    if (withPin && ui.pin) focus(ui.pin.x, ui.pin.y); else draw();
  }

  function setPin(p) {
    ui.pin = { x: p.x, y: p.y, z: p.z || (shared.map && ui.mapReady ? shared.map.heightAt(p.x, p.y) : 30), label: p.label || 'Point on map' };
    ui.ended = null;
    sheet();
    draw();
    quote(true);
  }

  const chosen = () => (ui.pin && ui.pin.paces ? ui.pin.paces[ui.paceIdx] : null);

  async function request() {
    const p = ui.pin, pace = chosen();
    if (!p || !pace || ui.busyReq) return;
    ui.busyReq = true;
    modal(null);
    sheet();
    busy(true);
    try {
      const r = await ui.app.request('request', { x: p.x, y: p.y, z: p.z, label: p.label, pace: pace.key });
      if (!ui) return;
      ui.ride = { stage: 'requested', label: (r && r.label) || p.label, price: (r && r.price) || pace.price,
        pace: (r && r.pace) || pace.label, dest: { x: p.x, y: p.y } };
      ui.pin = null;
      ui.app.toast(`Paid ${money(ui.ride.price)}. Finding your car.`);
    } catch (e) { if (ui) ui.app.toast(e.reason || 'Could not request a car'); }
    finally { if (ui) { busy(false); ui.busyReq = false; sheet(); draw(); } }
  }

  async function cancel() {
    if (ui.busyReq) return;
    ui.busyReq = true;
    modal(null);
    sheet();
    busy(true);
    try { await ui.app.request('cancel'); } catch (e) { if (ui) ui.app.toast(e.reason || 'Could not cancel'); }
    finally { if (ui) { busy(false); ui.busyReq = false; sheet(); } }
  }

  // ---------------------------------------------------------------- modal (pagar e cancelar passam por aqui)

  function modal(kind) {
    ui.modal = kind;
    const el = $('.scrim');
    if (!kind) { el.hidden = true; el.innerHTML = ''; return; }
    let body;
    if (kind === 'pay') {
      const p = ui.pin, pace = chosen();
      body = sectionHeader('Confirm ride', pace.label) +
        `<div class="kv-list">
          <div class="kv kv-line"><span class="t-micro">Destination</span><span class="t-strong">${esc(p.label)}</span></div>
          <div class="kv kv-line"><span class="t-micro">Pace</span><span class="t-strong">${esc(pace.label)}</span></div>
          <div class="kv kv-line"><span class="t-micro">Trip</span><span class="t-strong">${km(p.km)} · ≈ ${pace.minutes || 1} min</span></div>
          <div class="kv kv-line"><span class="t-micro">Total</span><span class="t-value-xl">${money(pace.price)}</span></div>
        </div>
        <p class="t-small muted">Paid now. Refunded if the ride never starts.</p>
        <div class="modal-actions">
          <button class="btn btn-ghost btn-m" data-a="modal-close">Back</button>
          <button class="btn btn-primary btn-m" data-a="request">Pay <span class="btn-value">${money(pace.price)}</span></button>
        </div>`;
    } else {
      const r = ui.ride;
      body = sectionHeader('Cancel ride', '') +
        `<p class="t-small soft">${r.price ? `The car turns back and you get ${money(r.price)} back.` : 'The car turns back.'}</p>
        <div class="modal-actions">
          <button class="btn btn-ghost btn-m" data-a="modal-close">Keep ride</button>
          <button class="btn btn-danger btn-m" data-a="cancel">Cancel ride</button>
        </div>`;
    }
    el.innerHTML = `<div class="modal">${body}</div>`;
    el.hidden = false;
  }

  // ---------------------------------------------------------------- a folha de baixo

  function stepsHtml(stage) {
    const at = STEPS.findIndex((s) => s.stages.includes(stage));
    return `<div class="steps">${STEPS.map((s, i) => `<span class="step${i <= at ? ' on' : ''}${i === at ? ' now' : ''}"><i></i><b class="t-micro">${esc(s.label)}</b></span>`).join('')}</div>`;
  }

  function sheet() {
    if (!ui) return;
    const r = ui.ride;
    let html;
    if (!ui.loaded) {
      html = '<div class="state state-boxed"><span class="t-row-title">Loading</span><span class="t-small muted">Getting WHIP RIDE ready.</span></div>';
    } else if (ui.error) {
      html = `<div class="state state-boxed"><span class="dot dot-bad"></span><span class="t-row-title">Unavailable</span><span class="t-small muted">${esc(ui.error)}</span>` +
        '<button class="btn btn-ghost btn-m" data-a="retry">Try again</button></div>';
    } else if (active(r)) {
      const [title, text] = STAGE[r.stage] || ['Ride in progress', ''];
      html = sectionHeader('Your ride', r.pace || '') + stepsHtml(r.stage) +
        `<div class="ride-head">${carIcon(0)}<div class="ride-t"><span class="t-section">${esc(title)}</span><span class="t-small muted">${esc(text)}</span></div></div>` +
        `<div class="cells">
          <div class="cell"><span class="t-micro">Car</span><span class="t-strong">Karin Vivanite</span></div>
          <div class="cell"><span class="t-micro">Paid</span><span class="t-value">${r.price ? money(r.price) : 'Free'}</span></div>
          ${r.label ? `<div class="cell cell-wide"><span class="t-micro">Destination</span><span class="t-strong ell">${esc(r.label)}</span></div>` : ''}
        </div>` +
        (r.stage === 'riding' || r.stage === 'boarded' ? '' : `<button class="btn btn-ghost-danger btn-m" data-a="ask-cancel"${ui.busyReq ? ' disabled' : ''}>Cancel ride</button>`);
    } else if (ui.pin) {
      const p = ui.pin;
      const rows = p.paces ? p.paces.map((o, i) => `
        <button class="row option${i === ui.paceIdx ? ' on' : ''}" data-a="pace" data-i="${i}">
          ${carIcon(i)}
          <span class="grow"><span class="t-row-title">${esc(o.label)}</span><span class="sub t-small">≈ ${o.minutes || 1} min · ${esc(PACE_TEXT[o.style] || '')}</span></span>
          <span class="t-value price">${money(o.price)}</span>
        </button>`).join('') : '<div class="state"><span class="t-small muted">Working out the fares.</span></div>';
      const pace = chosen();
      html = `<div class="dest-row"><span class="dest-ico">${FLAG}</span><span class="grow"><span class="t-micro">Destination</span>` +
        `<span class="t-strong ell">${esc(p.label)}</span></span><button class="icon-btn icon-btn-s" data-a="clear" data-hint="Change destination" aria-label="Change destination">${BACK}</button></div>` +
        sectionHeader('Choose a ride', p.km != null ? km(p.km) : '') +
        `<div class="rows">${rows}</div>` +
        (ui.fare ? `<p class="t-micro fine">${money(ui.fare.base)} + ${money(ui.fare.perKm)} per km × pace</p>` : '') +
        `<button class="btn btn-primary btn-l" data-a="ask-pay"${!pace || ui.busyReq ? ' disabled' : ''}>${pace ? `Choose ${esc(pace.label)} · <span class="btn-value">${money(pace.price)}</span>` : 'Choose'}</button>`;
    } else {
      const ended = ui.ended ? `<div class="banner"><span class="dot dot-${ui.ended[0] === 'ok' ? 'ok' : ui.ended[0] === 'bad' ? 'bad' : 'accent'}"></span><span class="t-small">${esc(ui.ended[1])}</span></div>` : '';
      const places = ui.places.map((p, i) => {
        const d = ui.me ? Math.hypot(p.x - ui.me.x, p.y - ui.me.y) * 1.3 / 1000 : null;
        return `<button class="row" data-a="place" data-i="${i}">${FLAG}<span class="grow">${esc(p.label)}</span>${d != null ? `<span class="sub">${km(d)}</span>` : ''}</button>`;
      }).join('');
      html = ended + sectionHeader('Where to?', ui.mapFailed ? 'Pick a place' : 'Tap the map') +
        (places ? `<div class="rows places">${places}</div>`
          : '<div class="state state-boxed"><span class="t-row-title">No quick places</span><span class="t-small muted">Tap the map to mark where you want to go.</span></div>');
    }
    ui.sheetEl.innerHTML = html;
  }

  // ---------------------------------------------------------------- entrada

  function bind(root) {
    const map = ui.mapEl;
    let drag = null;
    const on = (el, type, fn, opts) => { el.addEventListener(type, fn, opts); ui.off.push(() => el.removeEventListener(type, fn, opts)); };

    on(map, 'pointerdown', (e) => {
      if (e.button !== 0) return;
      drag = { x: e.clientX, y: e.clientY, vx: ui.view.x, vy: ui.view.y, moved: false, k: local(e).k };
      map.setPointerCapture(e.pointerId);
    });
    on(map, 'pointermove', (e) => {
      if (!drag) return;
      const dx = (e.clientX - drag.x) * drag.k, dy = (e.clientY - drag.y) * drag.k;
      if (!drag.moved && Math.hypot(dx, dy) < 5) return;
      drag.moved = true;
      ui.view.x = drag.vx - dx / ppm();
      ui.view.y = drag.vy + dy / ppm();
      draw();
    });
    on(map, 'pointerup', (e) => {
      if (!drag) return;
      const tap = !drag.moved;
      drag = null;
      if (!tap || active(ui.ride) || ui.busyReq) return;
      const p = local(e);
      setPin(toWorld(p.sx, p.sy));
    });
    on(map, 'wheel', (e) => {
      e.preventDefault();
      const { sx, sy } = local(e);
      const before = toWorld(sx, sy);
      ui.view.zoom = Math.min(ZOOM.max, Math.max(ZOOM.min, ui.view.zoom - e.deltaY * 0.0018));
      const { w, h } = size();
      ui.view.x = before.x - (sx - w / 2) / ppm();
      ui.view.y = before.y + (sy - h / 2) / ppm();
      draw();
    }, { passive: false });

    on(root, 'click', (e) => {
      const b = e.target.closest('[data-a]');
      if (!b || b.disabled) return;
      const a = b.dataset.a;
      if (a === 'zin' || a === 'zout') {
        ui.view.zoom = Math.min(ZOOM.max, Math.max(ZOOM.min, ui.view.zoom + (a === 'zin' ? 0.6 : -0.6)));
        draw();
      } else if (a === 'me' && ui.me) focus(ui.me.x, ui.me.y);
      else if (a === 'place') {
        const p = ui.places[+b.dataset.i];
        if (p) { setPin(p); requestAnimationFrame(() => focus(p.x, p.y, Math.max(ui.view.zoom, 4))); }
      } else if (a === 'pace') { ui.paceIdx = +b.dataset.i || 0; sheet(); }
      else if (a === 'clear') { ui.pin = null; sheet(); draw(); }
      else if (a === 'ask-pay' && chosen()) modal('pay');
      else if (a === 'ask-cancel') modal('cancel');
      else if (a === 'modal-close') modal(null);
      else if (a === 'request') request();
      else if (a === 'cancel') cancel();
      else if (a === 'retry') { ui.loaded = false; sheet(); quote(!!ui.pin); }
    });

    if (window.ResizeObserver) {
      const ro = new ResizeObserver(() => resize());
      ro.observe(map);
      ui.off.push(() => ro.disconnect());
    }
  }

  // ---------------------------------------------------------------- estilo
  // Os tokens do NorteRoleplay Design System v3.0 (norte_ui/tokens.css), em px: dentro do telemovel a app nao manda
  // no font-size da pagina, por isso 1rem dos tokens passa a 1px aqui, numa escala de telemovel. O resto do CSS so usa
  // var(--...): nenhuma cor escrita a mao fora deste bloco.
  const TOKENS = `
    @font-face { font-family: 'NRP SF'; src: url('https://cfx-nui-norte_whip_theme/fonts/sf-regular-17.ttf'); font-weight: 400; font-stretch: normal; }
    @font-face { font-family: 'NRP SF'; src: url('https://cfx-nui-norte_whip_theme/fonts/sf-medium-17.ttf'); font-weight: 500; font-stretch: normal; }
    @font-face { font-family: 'NRP SF'; src: url('https://cfx-nui-norte_whip_theme/fonts/sf-compressed-regular-17.ttf'); font-weight: 400; font-stretch: extra-condensed; }
    @font-face { font-family: 'NRP SF'; src: url('https://cfx-nui-norte_whip_theme/fonts/sf-compressed-medium-17.ttf'); font-weight: 500 700; font-stretch: extra-condensed; }
    :host {
      --accent: #95b8ce; --focus-ring: rgba(149, 184, 206, 0.18); --area: rgba(149, 184, 206, 0.12);
      --base: #1b1e21; --base-deep: #16191c; --panel: rgba(34, 38, 42, 0.96); --cell: rgba(40, 44, 48, 0.96);
      --row: rgba(45, 50, 55, 0.96); --input: rgba(255, 255, 255, 0.04); --light: #f4f5f6; --white: #ffffff;
      --scrim: rgba(11, 13, 15, 0.8); --text: #f4f5f6; --soft: #c9ced3; --muted: #8e8e93; --dark: #1b1e21; --ink-muted: #3d434a;
      --line: rgba(255, 255, 255, 0.10); --line-input: rgba(255, 255, 255, 0.16); --line-hi: rgba(255, 255, 255, 0.22);
      --track: rgba(255, 255, 255, 0.16); --ok: #7bd88f; --bad: #e5484d; --bad-subtle: rgba(229, 72, 77, 0.2);
      --radius: 6px; --radius-sm: 4px; --radius-round: 999px;
      --s-2: 2px; --s-3: 3px; --s-4: 4px; --s-5: 5px; --s-6: 6px; --s-8: 8px; --s-10: 10px; --s-12: 12px; --s-14: 14px; --s-16: 16px;
      --h-tag: 20px; --h-sm: 28px; --h-control: 38px; --h-lg: 46px; --h-row: 54px;
      --shadow-card: 0 6px 18px rgba(0, 0, 0, 0.6); --shadow-modal: 0 20px 60px rgba(0, 0, 0, 0.8);
      --ease: cubic-bezier(0.22, 1, 0.36, 1); --t-fast: 0.12s; --t-base: 0.18s; --t-enter: 0.3s;
      --sf: 'NRP SF', -apple-system, 'Segoe UI', Arial, sans-serif;
    }`;

  const CSS = `
    :host { background: var(--base); color: var(--text); font: 400 extra-condensed 15px/1.2 var(--sf); letter-spacing: .2px; }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    button { font: inherit; letter-spacing: inherit; color: inherit; border: 0; background: none; cursor: pointer; text-align: left; }
    button:disabled { cursor: default; }
    svg { display: block; }
    [hidden] { display: none !important; }
    .muted { color: var(--muted); } .soft { color: var(--soft); }
    .ell { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }

    /* texto (NRP/*): italico so em titulos e valores */
    .t-brand { font: italic 500 extra-condensed 24px/1 var(--sf); letter-spacing: .5px; text-transform: uppercase; }
    .t-section { font: 500 extra-condensed 19px/1.05 var(--sf); letter-spacing: .4px; text-transform: uppercase; }
    .t-row-title { font: 500 extra-condensed 14px/1 var(--sf); letter-spacing: .7px; text-transform: uppercase; }
    .t-value { font: italic 500 extra-condensed 16px/1 var(--sf); font-variant-numeric: tabular-nums; }
    .t-value-xl { font: italic 500 extra-condensed 24px/1 var(--sf); font-variant-numeric: tabular-nums; }
    .t-strong { font: 500 extra-condensed 15px/1.2 var(--sf); }
    .t-small { font: 400 extra-condensed 13px/1.15 var(--sf); }
    .t-micro { color: var(--muted); font: 500 extra-condensed 11px/1 var(--sf); letter-spacing: .7px; text-transform: uppercase; }

    /* Busy Bar */
    .busy-bar { position: absolute; z-index: 30; inset: 0 0 auto; height: 3px; overflow: hidden; pointer-events: none; opacity: 0; transition: opacity var(--t-base); }
    .busy-bar::after { content: ''; position: absolute; top: 0; bottom: 0; width: 28%; background: var(--accent); transform: translateX(-100%); }
    .busy-bar.on { opacity: 1; }
    .busy-bar.on::after { animation: sweep 1.1s var(--ease) infinite; }

    /* mapa */
    .app { position: absolute; inset: 0; overflow: hidden; user-select: none; }
    .map { position: absolute; inset: 0; overflow: hidden; touch-action: none; cursor: crosshair; background: var(--base-deep); }
    .map-canvas { position: absolute; inset: 0; width: 100%; height: 100%; display: block; }
    .map-grid { position: absolute; inset: 0; background-color: var(--base-deep);
      background-image: linear-gradient(var(--line) 1px, transparent 1px), linear-gradient(90deg, var(--line) 1px, transparent 1px); }
    .marks { position: absolute; inset: 0; pointer-events: none; overflow: visible; }
    .route { position: absolute; inset: 0; width: 100%; height: 100%; pointer-events: none; }
    .route line { stroke: var(--accent); stroke-width: 2.5; stroke-dasharray: 5 6; stroke-linecap: round; }
    .area { position: absolute; top: 0; left: 0; border: 1.5px solid var(--accent); border-radius: var(--radius-round); background: var(--area); }
    .me { position: absolute; top: 0; left: 0; width: 22px; height: 22px; margin: -11px 0 0 -11px; }
    .me svg { width: 100%; height: 100%; fill: var(--light); stroke: var(--dark); stroke-width: 1.6; stroke-linejoin: round; }
    .pin { position: absolute; top: 0; left: 0; width: 24px; height: 24px; margin: -12px 0 0 -12px; display: grid; place-items: center;
      border: 2px solid var(--accent); border-radius: var(--radius-round); }
    .pin::after { content: ''; width: 10px; height: 10px; border: 2px solid var(--dark); border-radius: var(--radius-round); background: var(--accent); }

    /* App Header sobre o mapa */
    .app-head { position: absolute; z-index: 5; left: 0; right: 0; top: 0; display: flex; align-items: flex-end; justify-content: space-between;
      padding: calc(var(--safe-top, 40px) + var(--s-4)) var(--s-16) var(--s-16); pointer-events: none;
      background: linear-gradient(var(--base), transparent); }
    .brand { display: flex; flex-direction: column; gap: var(--s-4); }
    .brand .t-micro span { color: var(--soft); }
    .ctrls { position: absolute; z-index: 5; right: var(--s-12); top: calc(var(--safe-top, 40px) + 54px); display: flex; flex-direction: column; gap: var(--s-6); }

    /* Icon Button */
    .icon-btn { flex: none; display: inline-flex; align-items: center; justify-content: center; width: var(--h-control); height: var(--h-control);
      border: 1px solid var(--line-input); border-radius: var(--radius); background: var(--panel); color: var(--text);
      transition: background-color var(--t-fast), border-color var(--t-fast), color var(--t-fast), transform var(--t-fast); }
    .icon-btn svg { width: 16px; height: 16px; }
    .icon-btn-s { width: var(--h-sm); height: var(--h-sm); background: var(--input); }
    .icon-btn-s svg { width: 13px; height: 13px; }
    .icon-btn:hover:not(:disabled), .icon-btn:focus-visible { background: var(--light); border-color: var(--light); color: var(--dark); outline: none; }
    .icon-btn:active:not(:disabled) { transform: scale(.965); }

    /* folha de baixo: um Card que abre com Section Header */
    .sheet { position: absolute; z-index: 6; left: var(--s-8); right: var(--s-8); bottom: calc(var(--safe-bottom, 20px) + var(--s-6));
      display: flex; flex-direction: column; gap: var(--s-12); max-height: 66%; overflow-y: auto; padding: var(--s-14);
      border: 1px solid var(--line); border-radius: var(--radius); background: var(--panel); box-shadow: var(--shadow-card);
      animation: rise var(--t-enter) var(--ease); }
    .sheet::-webkit-scrollbar { width: 0; }

    /* Section Header */
    .section-header { display: flex; align-items: center; gap: var(--s-10); min-height: var(--h-tag); }
    .section-header > .t-row-title { white-space: nowrap; }
    .section-header > .t-micro { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 50%; }
    .section-line { flex: 1; height: 1px; background: var(--line); }

    /* List Row e opcoes (selecao invertida) */
    .rows { display: flex; flex-direction: column; gap: var(--s-5); }
    .places { max-height: 190px; overflow-y: auto; }
    .row { display: flex; align-items: center; gap: var(--s-10); flex: none; width: 100%; min-height: var(--h-control); padding: 0 var(--s-12);
      border-radius: var(--radius); background: var(--row); color: var(--text); font: 500 extra-condensed 15px/1 var(--sf);
      transition: background-color var(--t-fast), color var(--t-fast); }
    .row > svg { flex: none; width: 15px; height: 15px; color: var(--muted); transition: color var(--t-fast); }
    .row .grow { flex: 1; min-width: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .row .sub { flex: none; color: var(--muted); font-variant-numeric: tabular-nums; transition: color var(--t-fast); }
    .row:hover, .row.on, .row:focus-visible { background: var(--light); color: var(--dark); outline: none; }
    .row:hover .sub, .row.on .sub, .row:hover > svg, .row.on > svg, .row:focus-visible .sub { color: var(--ink-muted); }
    .option { min-height: var(--h-row); padding: var(--s-8) var(--s-12); }
    .option .grow { display: flex; flex-direction: column; gap: var(--s-4); }
    .option .sub { display: block; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .option .price { flex: none; padding-right: var(--s-2); }

    /* icone do carro numa Info Cell */
    .car-ico { flex: none; position: relative; display: flex; align-items: center; justify-content: center; width: 52px; height: 34px;
      border-radius: var(--radius-sm); background: var(--cell); color: var(--soft); transition: background-color var(--t-fast), color var(--t-fast); }
    .car-ico svg { width: 40px; height: 20px; }
    .car-ico .lines { position: absolute; left: 1px; width: 8px; height: 22px; color: var(--accent); }
    .row.on .car-ico, .row:hover .car-ico { background: var(--dark); color: var(--light); }

    /* destino */
    .dest-row { display: flex; align-items: center; gap: var(--s-10); }
    .dest-row .grow { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: var(--s-4); }
    .dest-ico { flex: none; display: grid; place-items: center; width: var(--h-sm); height: var(--h-sm); border-radius: var(--radius-sm); background: var(--cell); color: var(--accent); }
    .dest-ico svg { width: 15px; height: 15px; }
    .fine { text-align: center; }

    /* Info Cell */
    .cells { display: grid; grid-template-columns: 1fr 1fr; gap: var(--s-6); }
    .cell { display: flex; flex-direction: column; gap: var(--s-6); min-width: 0; padding: var(--s-10) var(--s-12); border-radius: var(--radius); background: var(--cell); }
    .cell-wide { grid-column: 1 / -1; }

    /* Step Segments */
    .steps { display: grid; grid-template-columns: repeat(4, 1fr); gap: var(--s-4); }
    .step { display: flex; flex-direction: column; gap: var(--s-5); min-width: 0; }
    .step i { height: 3px; border-radius: var(--radius-sm); background: var(--track); transition: background-color var(--t-base); }
    .step.on i { background: var(--accent); }
    .step.now i { animation: pulse .9s ease-in-out infinite alternate; }
    .step b { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; font-weight: 500; }
    .step.on b { color: var(--soft); }
    .ride-head { display: flex; align-items: center; gap: var(--s-12); }
    .ride-t { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: var(--s-4); }

    /* Botoes */
    .btn { display: inline-flex; align-items: center; justify-content: center; gap: var(--s-8); width: 100%; min-width: 0; padding: 0 var(--s-14);
      border: 1px solid transparent; border-radius: var(--radius); white-space: nowrap; text-transform: uppercase;
      font: 500 extra-condensed 15px/1 var(--sf); letter-spacing: .7px; text-align: center;
      transition: background-color var(--t-fast), border-color var(--t-fast), color var(--t-fast), transform var(--t-fast); }
    .btn-l { height: var(--h-lg); font-size: 17px; }
    .btn-m { height: var(--h-control); }
    .btn:active:not(:disabled) { transform: scale(.965); }
    .btn:disabled { opacity: .45; }
    .btn:focus-visible { box-shadow: 0 0 0 3px var(--focus-ring); outline: none; }
    .btn-primary { background: var(--light); color: var(--dark); }
    .btn-primary:hover:not(:disabled) { background: var(--white); }
    .btn-ghost { background: var(--input); border-color: var(--line-input); color: var(--text); }
    .btn-ghost:hover:not(:disabled) { background: var(--light); border-color: var(--light); color: var(--dark); }
    .btn-danger { background: var(--bad); color: var(--dark); }
    .btn-danger:hover:not(:disabled) { background: var(--white); }
    .btn-ghost-danger { border-color: var(--bad-subtle); color: var(--bad); }
    .btn-ghost-danger:hover:not(:disabled) { background: var(--light); border-color: var(--light); color: var(--dark); }
    .btn-value { font: italic 500 extra-condensed 1em/1 var(--sf); letter-spacing: .2px; text-transform: none; }

    /* Key Value Row, Status Dot, banner, State Block */
    .kv-list { display: flex; flex-direction: column; }
    .kv { display: flex; align-items: baseline; justify-content: space-between; gap: var(--s-12); min-width: 0; }
    .kv > :last-child { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .kv-line { padding: var(--s-8) 0; border-bottom: 1px solid var(--line); }
    .dot { flex: none; width: 8px; height: 8px; border-radius: var(--radius-round); background: var(--track); }
    .dot-ok { background: var(--ok); } .dot-bad { background: var(--bad); } .dot-accent { background: var(--accent); }
    .banner { display: flex; align-items: center; gap: var(--s-10); padding: var(--s-10) var(--s-12); border-radius: var(--radius); background: var(--cell); }
    .state { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: var(--s-8); text-align: center; }
    .state-boxed { padding: var(--s-16) var(--s-12); border: 1px dashed var(--line-hi); border-radius: var(--radius); }
    .state .btn { width: auto; margin-top: var(--s-4); }

    /* Modal */
    .scrim { position: absolute; z-index: 40; inset: 0; display: flex; align-items: flex-end; padding: var(--s-8) var(--s-8) calc(var(--safe-bottom, 20px) + var(--s-6));
      background: var(--scrim); animation: fade var(--t-enter) var(--ease); }
    .modal { display: flex; flex-direction: column; gap: var(--s-12); width: 100%; padding: var(--s-16); border: 1px solid var(--line-hi);
      border-radius: var(--radius); background: var(--panel); box-shadow: var(--shadow-modal); animation: rise var(--t-enter) var(--ease); }
    .modal-actions { display: grid; grid-template-columns: 1fr 1fr; gap: var(--s-8); }

    @keyframes sweep { from { transform: translateX(-100%); } to { transform: translateX(360%); } }
    @keyframes fade { from { opacity: 0; } to { opacity: 1; } }
    @keyframes rise { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: none; } }
    @keyframes pulse { from { opacity: 1; } to { opacity: .35; } }
    .lite * { animation: none !important; transition: none !important; }
  `;

  WhipPhone.module({
    id: 'whipride', name: 'WHIP RIDE', version: '3.0.0', order: 40, icon: GLYPH,
    css: TOKENS + CSS,

    async mount(app, el) {
      el.innerHTML = `<div class="app">
        <div class="busy-bar"></div>
        <div class="map"><div class="map-grid"></div>
          <svg class="route" aria-hidden="true"><line hidden x1="0" y1="0" x2="0" y2="0"/></svg>
          <div class="marks"><div class="area" hidden></div><div class="me">${ARROW}</div><div class="pin" hidden></div></div>
        </div>
        <header class="app-head"><div class="brand"><span class="t-micro">Norte <span>/ Ride</span></span><span class="t-brand">WHIP Ride</span></div></header>
        <div class="ctrls">
          <button class="icon-btn" data-a="zin" data-hint="Zoom in" aria-label="Zoom in">${PLUS}</button>
          <button class="icon-btn" data-a="zout" data-hint="Zoom out" aria-label="Zoom out">${MINUS}</button>
          <button class="icon-btn" data-a="me" data-hint="Where I am" aria-label="Where I am">${AIM}</button>
        </div>
        <section class="sheet"></section>
        <div class="scrim" hidden></div>
      </div>`;
      const root = el.firstElementChild;
      ui = {
        app, root, mapEl: root.querySelector('.map'), gridEl: root.querySelector('.map-grid'),
        meEl: root.querySelector('.me'), pinEl: root.querySelector('.pin'), areaEl: root.querySelector('.area'),
        lineEl: root.querySelector('.route line'), sheetEl: root.querySelector('.sheet'),
        view: { x: 0, y: 0, zoom: ZOOM.start }, me: null, pin: null, ride: { stage: 'none' }, fare: null, places: [],
        loaded: false, error: null, busyReq: false, busyCount: 0, ended: null, paceIdx: 0, seq: 0, off: [],
        mapReady: false, mapFailed: false, arriveRadius: 25, modal: null,
      };
      bind(root);
      sheet();

      const first = quote(false);
      const mine = ui;
      busy(true);
      loadMap().then(() => {
        if (ui !== mine) return;
        ui.mapEl.insertBefore(shared.canvas, ui.mapEl.firstChild);
        ui.gridEl.hidden = true;
        ui.mapReady = true;
        resize();
      }).catch((e) => {
        console.warn('[whipride] map unavailable:', e);
        if (ui !== mine) return;
        ui.mapFailed = true;
        sheet();
      }).finally(() => { if (ui === mine) busy(false); });
      await first;
      if (ui === mine && ui.me) focus(ui.me.x, ui.me.y);
    },

    update(app, el, view, changed) { if (changed) resize(); },

    unmount() {
      if (!ui) return;
      ui.off.forEach((f) => f());
      if (shared.canvas && shared.canvas.parentNode) shared.canvas.parentNode.removeChild(shared.canvas);
      ui = null;
    },

    back() {
      if (!ui) return false;
      if (ui.modal) { modal(null); return true; }
      if (ui.pin && !active(ui.ride)) { ui.pin = null; sheet(); draw(); return true; }
      return false;
    },

    on: {
      status(app, d) {
        const ride = d && d.stage ? d : { stage: 'none' };
        const ended = ride.stage === 'none' && d && d.ended ? (ENDED[d.ended] || ['muted', 'Ride ended.']) : null;
        const text = ended ? ended[1] + (d.refunded ? ' Your money was refunded.' : '') : null;
        if (text && !(ui && app.active)) app.notify({ title: 'WHIP RIDE', text, kind: d.ended === 'arrived' ? 'success' : 'chat' });
        else if (ride.stage === 'waiting' && !(ui && app.active)) app.notify({ title: 'WHIP RIDE', text: 'Your car is here. The back doors are open.', kind: 'success' });
        if (!ui) return;
        setRide(ride);
        if (ride.stage === 'none') {
          ui.pin = null;
          if (ui.modal) modal(null);
          ui.ended = ended ? [ended[0], text] : null;
          quote(false);
        }
        sheet();
        draw();
      },
    },
  });
})();
