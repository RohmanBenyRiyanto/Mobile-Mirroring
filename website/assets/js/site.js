/* Page behaviour. © 2026 Rohman Beny Riyanto */
(function () {
  'use strict';
  var doc = document.documentElement;
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };
  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
  var langHooks = [];

  function lang() { return doc.getAttribute('data-lang') === 'en' ? 'en' : 'id'; }
  function t(id, en) { return lang() === 'en' ? en : id; }
  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }
  function read(key) { try { return JSON.parse(localStorage.getItem(key) || '{}') || {}; } catch (e) { return {}; } }
  function write(key, value) { try { localStorage.setItem(key, JSON.stringify(value)); } catch (e) { /* not available */ } }
  function pref(k, v) { var p = read('bm.prefs'); p[k] = v; write('bm.prefs', p); }
  function seen(node, fn, opts) {
    if (!('IntersectionObserver' in window)) { fn(true); return; }
    new IntersectionObserver(function (es) { fn(es[es.length - 1].isIntersecting); }, opts || {}).observe(node);
  }

  /* ---------- language and theme ---------- */
  function applyLang() {
    var l = lang();
    doc.lang = l;
    $$('[data-label-' + l + ']').forEach(function (n) { n.setAttribute('aria-label', n.getAttribute('data-label-' + l)); });
    $$('[data-ph-' + l + ']').forEach(function (n) { n.placeholder = n.getAttribute('data-ph-' + l); });
    document.title = t('Benz Mirror: cerminkan dan kendalikan Android dari Mac', 'Benz Mirror: mirror and control Android from your Mac');
    langHooks.forEach(function (f) { f(); });
  }
  $('#langBtn').addEventListener('click', function () {
    var next = lang() === 'id' ? 'en' : 'id';
    doc.setAttribute('data-lang', next); pref('lang', next); applyLang();
  });
  $('#themeBtn').addEventListener('click', function () {
    var cur = doc.getAttribute('data-theme') || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
    var next = cur === 'dark' ? 'light' : 'dark';
    doc.setAttribute('data-theme', next); pref('theme', next);
  });

  /* ---------- navigation ---------- */
  var menuBtn = $('#menuBtn'), links = $('#links');
  function menu(open) { links.classList.toggle('open', open); menuBtn.setAttribute('aria-expanded', String(open)); }
  menuBtn.addEventListener('click', function () { menu(!links.classList.contains('open')); });
  links.addEventListener('click', function (e) { if (e.target.closest('a')) menu(false); });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && links.classList.contains('open')) { menu(false); menuBtn.focus(); }
  });
  $$('a', links).forEach(function (a) {
    var s = $(a.getAttribute('href'));
    if (s) seen(s, function (on) { if (on) a.setAttribute('aria-current', 'true'); else a.removeAttribute('aria-current'); },
      { rootMargin: '-45% 0px -50% 0px' });
  });

  /* ---------- scroll: progress bar and the icon coming apart ---------- */
  var progress = $('#progress'), icon = $('#heroIcon'), ticking = false;
  function onScroll() {
    ticking = false;
    var max = doc.scrollHeight - innerHeight;
    progress.style.transform = 'scaleX(' + (max > 0 ? Math.min(1, scrollY / max) : 0) + ')';
    if (!reduced.matches) {
      var x = Math.min(1, Math.max(0, scrollY / (innerHeight * 0.6)));
      icon.style.setProperty('--x', x.toFixed(3));
      if (!pointerOnHero) { tilt.style.setProperty('--ry', (-26 * x) + 'deg'); tilt.style.setProperty('--rx', (10 * x) + 'deg'); }
    }
  }
  var tilt = $('#tilt'), hero = $('.hero'), pointerOnHero = false;
  hero.addEventListener('pointermove', function (e) {
    if (reduced.matches || e.pointerType === 'touch') return;
    pointerOnHero = true;
    var r = icon.getBoundingClientRect();
    var dx = Math.max(-1, Math.min(1, (e.clientX - r.left - r.width / 2) / (innerWidth / 2)));
    var dy = Math.max(-1, Math.min(1, (e.clientY - r.top - r.height / 2) / (innerHeight / 2)));
    tilt.style.setProperty('--ry', (dx * 28) + 'deg');
    tilt.style.setProperty('--rx', (-dy * 22) + 'deg');
    icon.style.setProperty('--x', Math.min(1, Math.abs(dx) * .45 + Math.abs(dy) * .25).toFixed(3));
  });
  hero.addEventListener('pointerleave', function () {
    pointerOnHero = false;
    tilt.style.setProperty('--ry', '0deg'); tilt.style.setProperty('--rx', '0deg'); icon.style.setProperty('--x', '0');
    onScroll();
  });
  addEventListener('scroll', function () { if (!ticking) { ticking = true; requestAnimationFrame(onScroll); } }, { passive: true });

  /* ---------- icon colour ---------- */
  var variantBtns = $$('.variants button');
  function setVariant(v, save) {
    doc.setAttribute('data-variant', v);
    variantBtns.forEach(function (b) {
      var on = b.getAttribute('data-v') === v;
      b.setAttribute('aria-checked', String(on)); b.tabIndex = on ? 0 : -1;
    });
    $$('[data-layer]').forEach(function (i) { i.src = 'assets/img/icon-' + v + '-' + i.getAttribute('data-layer') + '.webp'; });
    $$('[data-icon]').forEach(function (i) { i.src = 'assets/img/icon-' + v + '-256.webp'; });
    $('meta[name=theme-color]').content = { a: '#020a1c', b: '#0a5fd0', c: '#e4edfa' }[v];
    if (save) pref('variant', v);
  }
  variantBtns.forEach(function (b) { b.addEventListener('click', function () { setVariant(b.getAttribute('data-v'), true); }); });
  arrows($('.variants'), variantBtns, function (b) { b.click(); });

  function arrows(group, items, pick) {
    group.addEventListener('keydown', function (e) {
      var i = items.indexOf(document.activeElement);
      var d = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[e.key];
      if (i < 0 || !d) return;
      e.preventDefault();
      var n = items[(i + d + items.length) % items.length];
      n.focus(); pick(n);
    });
  }

  /* ---------- tabs ---------- */
  $$('[data-tabs]').forEach(function (list) {
    var tabs = $$('[role=tab]', list);
    function select(tab) {
      tabs.forEach(function (x) {
        var on = x === tab;
        x.setAttribute('aria-selected', String(on)); x.tabIndex = on ? 0 : -1;
        document.getElementById(x.getAttribute('aria-controls')).hidden = !on;
      });
    }
    tabs.forEach(function (x) { x.addEventListener('click', function () { select(x); }); });
    arrows(list, tabs, select);
    select(tabs.filter(function (x) { return x.getAttribute('aria-selected') === 'true'; })[0]);
  });

  /* ---------- reveal and scroll story ---------- */
  $$('.reveal').forEach(function (n) {
    if (!('IntersectionObserver' in window)) { n.classList.add('in'); return; }
    var o = new IntersectionObserver(function (es) {
      if (es.some(function (e) { return e.isIntersecting; })) { n.classList.add('in'); o.disconnect(); }
    }, { rootMargin: '0px 0px -8% 0px' });
    o.observe(n);
  });
  var stage = $('#stage'), steps = $$('.steps li');
  function setStep(li) {
    stage.setAttribute('data-step', li.getAttribute('data-step'));
    steps.forEach(function (s) { s.classList.toggle('on', s === li); });
  }
  setStep(steps[0]);
  if ('IntersectionObserver' in window) {
    var stepObserver;
    var watch = function () {
      if (stepObserver) stepObserver.disconnect();
      /* on narrow screens the stage covers the top, so the active band sits lower */
      var band = innerWidth <= 860 ? '-68% 0px -24% 0px' : '-48% 0px -48% 0px';
      stepObserver = new IntersectionObserver(function (es) {
        es.forEach(function (e) { if (e.isIntersecting) setStep(e.target); });
      }, { rootMargin: band });
      steps.forEach(function (s) { stepObserver.observe(s); });
    };
    watch();
    matchMedia('(max-width: 860px)').addEventListener('change', watch);
  }

  /* ---------- copy ---------- */
  function copy(text, button) {
    function done(ok) {
      if (!button) return;
      var old = button.getAttribute('data-old') || button.innerHTML;
      button.setAttribute('data-old', old);
      button.textContent = ok ? t('Tersalin', 'Copied') : t('Gagal menyalin', 'Copy failed');
      clearTimeout(button._t);
      button._t = setTimeout(function () { button.innerHTML = old; button.removeAttribute('data-old'); }, 1600);
    }
    function fallback() {
      var a = el('textarea'); a.value = text; a.style.position = 'fixed'; a.style.opacity = '0';
      document.body.appendChild(a); a.select();
      var ok = false; try { ok = document.execCommand('copy'); } catch (e) {}
      a.remove(); done(ok);
    }
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(function () { done(true); }, fallback);
    else fallback();
  }
  document.addEventListener('click', function (e) {
    var b = e.target.closest('[data-copy],[data-copy-sum]');
    if (!b) return;
    copy(b.hasAttribute('data-copy') ? b.getAttribute('data-copy') : $('[data-sum-cmd]').textContent, b);
  });

  /* ---------- playground ---------- */
  (function () {
    var sim = $('#sim'), canvas = $('#game'), ctx = canvas.getContext('2d');
    var statsBox = $('#simStats'), hint = $('#simHint'), toast = $('#simToast'), recBox = $('#simRec'), recT = $('#simRecT');
    var W = 960, H = 440, keys = {}, shots = [], ripples = [], targets = [], score = 0;
    var me = { x: 480, y: 220, vx: 0, vy: 0, a: -Math.PI / 2 };
    var drag = null, visible = false, raf = 0, last = 0, cool = 0, frames = 0, fpsAt = 0, fps = 0, recAt = 0, used = false, toastTimer;

    function size() {
      var portrait = sim.classList.contains('portrait');
      W = portrait ? 440 : 960; H = portrait ? 820 : 440;
      canvas.width = W; canvas.height = H;
      me.x = W / 2; me.y = H / 2; shots = []; ripples = [];
      targets = [];
      for (var i = 0; i < 5; i++) targets.push(spawn());
    }
    function spawn() {
      var p;
      do { p = { x: 60 + Math.random() * (W - 120), y: 60 + Math.random() * (H - 120), r: 17, t: Math.random() * 6 }; }
      while (Math.hypot(p.x - me.x, p.y - me.y) < 140);
      return p;
    }
    function say(msg) {
      toast.textContent = msg; toast.classList.add('show');
      clearTimeout(toastTimer); toastTimer = setTimeout(function () { toast.classList.remove('show'); }, 2200);
    }
    function fire() {
      if (cool > 0) return;
      cool = 0.18;
      var best = null, d = 1e9;
      targets.forEach(function (g) { var k = Math.hypot(g.x - me.x, g.y - me.y); if (k < d) { d = k; best = g; } });
      var a = best ? Math.atan2(best.y - me.y, best.x - me.x) : me.a;
      shots.push({ x: me.x, y: me.y, vx: Math.cos(a) * 760, vy: Math.sin(a) * 760, life: 1 });
    }
    function step(dt) {
      var ax = (keys.d ? 1 : 0) - (keys.a ? 1 : 0), ay = (keys.s ? 1 : 0) - (keys.w ? 1 : 0);
      if (drag && drag.moved) { ax = (drag.x - drag.sx) / 70; ay = (drag.y - drag.sy) / 70; }
      var m = Math.hypot(ax, ay); if (m > 1) { ax /= m; ay /= m; }
      var k = Math.min(1, dt * 10);
      me.vx += (ax * 310 - me.vx) * k; me.vy += (ay * 310 - me.vy) * k;
      me.x = Math.max(24, Math.min(W - 24, me.x + me.vx * dt));
      me.y = Math.max(24, Math.min(H - 24, me.y + me.vy * dt));
      if (m > .05) me.a = Math.atan2(me.vy, me.vx);
      cool -= dt; if (keys.space) fire();
      shots.forEach(function (s) {
        s.x += s.vx * dt; s.y += s.vy * dt; s.life -= dt;
        targets.forEach(function (g, i) {
          if (s.life > 0 && Math.hypot(g.x - s.x, g.y - s.y) < g.r + 5) {
            s.life = 0; score++; ripples.push({ x: g.x, y: g.y, t: 0, c: '255,209,102' }); targets[i] = spawn();
          }
        });
      });
      shots = shots.filter(function (s) { return s.life > 0; });
      ripples.forEach(function (r) { r.t += dt; });
      ripples = ripples.filter(function (r) { return r.t < .5; });
      targets.forEach(function (g) { g.t += dt; });
    }
    function disc(x, y, r, fill) { ctx.beginPath(); ctx.arc(x, y, r, 0, 7); ctx.fillStyle = fill; ctx.fill(); }
    function draw() {
      var g = ctx.createLinearGradient(0, 0, 0, H);
      g.addColorStop(0, '#06163a'); g.addColorStop(.7, '#0a479f'); g.addColorStop(1, '#2f8fe8');
      ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
      ctx.strokeStyle = 'rgba(160,210,255,.13)'; ctx.lineWidth = 1; ctx.beginPath();
      var ox = -(me.x * .15) % 60, oy = -(me.y * .15) % 60;
      for (var x = ox; x < W; x += 60) { ctx.moveTo(x, 0); ctx.lineTo(x, H); }
      for (var y = oy; y < H; y += 60) { ctx.moveTo(0, y); ctx.lineTo(W, y); }
      ctx.stroke();
      targets.forEach(function (q) {
        var p = 1 + Math.sin(q.t * 4) * .08;
        ctx.save(); ctx.translate(q.x, q.y); ctx.rotate(q.t); ctx.fillStyle = '#ffd166';
        ctx.fillRect(-q.r * .75 * p, -q.r * .75 * p, q.r * 1.5 * p, q.r * 1.5 * p); ctx.restore();
      });
      shots.forEach(function (s) { disc(s.x, s.y, 5, '#fff'); });
      ripples.forEach(function (r) {
        ctx.beginPath(); ctx.arc(r.x, r.y, 10 + r.t * 90, 0, 7); ctx.lineWidth = 3;
        ctx.strokeStyle = 'rgba(' + r.c + ',' + (1 - r.t * 2) + ')'; ctx.stroke();
      });
      disc(me.x, me.y, 30, 'rgba(255,255,255,.16)');
      ctx.save(); ctx.translate(me.x, me.y); ctx.rotate(me.a);
      ctx.beginPath(); ctx.moveTo(22, 0); ctx.lineTo(-13, -15); ctx.lineTo(-6, 0); ctx.lineTo(-13, 15); ctx.closePath();
      ctx.fillStyle = '#fff'; ctx.fill(); ctx.restore();
      ctx.fillStyle = '#fff'; ctx.font = '700 22px system-ui, sans-serif'; ctx.textAlign = 'center';
      ctx.fillText(t('Skor ', 'Score ') + score, W / 2, H - 20);
      if (drag && drag.moved) {
        ctx.beginPath(); ctx.arc(drag.sx, drag.sy, 55, 0, 7); ctx.strokeStyle = 'rgba(255,255,255,.4)'; ctx.lineWidth = 2; ctx.stroke();
        disc(drag.x, drag.y, 17, 'rgba(255,255,255,.45)');
      }
    }
    function frame(now) {
      raf = 0;
      var dt = Math.min(.05, (now - (last || now)) / 1000); last = now;
      step(dt); draw();
      frames++;
      if (now - fpsAt >= 500) {
        fps = Math.round(frames * 1000 / (now - fpsAt)); frames = 0; fpsAt = now;
        if (!statsBox.hidden) statsBox.textContent = fps + ' fps\n' + W + '×' + H + '\n' + t('simulasi browser', 'browser simulation');
      }
      if (recAt) {
        var s = Math.floor((now - recAt) / 1000);
        recT.textContent = String(Math.floor(s / 60)).padStart(2, '0') + ':' + String(s % 60).padStart(2, '0');
      }
      run();
    }
    function run() {
      if (!raf && visible && !document.hidden && (!reduced.matches || used)) raf = requestAnimationFrame(frame);
    }
    function wake() { used = true; hint.hidden = true; last = 0; run(); }

    var map = { KeyW: 'w', KeyA: 'a', KeyS: 's', KeyD: 'd', ArrowUp: 'w', ArrowLeft: 'a', ArrowDown: 's', ArrowRight: 'd', Space: 'space' };
    function cap(k, on) { var n = $('.sim-keys [data-k="' + k + '"]'); if (n) n.classList.toggle('down', on); }
    canvas.addEventListener('keydown', function (e) {
      var k = map[e.code];
      if (e.key === 'Escape') { canvas.blur(); return; }
      if (!k || e.metaKey || e.ctrlKey || e.altKey) return;
      e.preventDefault(); keys[k] = true; cap(k, true); wake();
    });
    canvas.addEventListener('keyup', function (e) { var k = map[e.code]; if (k) { keys[k] = false; cap(k, false); } });
    canvas.addEventListener('blur', function () { keys = {}; $$('.sim-keys .down').forEach(function (n) { n.classList.remove('down'); }); });

    function point(e) {
      var r = canvas.getBoundingClientRect();
      return { x: (e.clientX - r.left) * W / r.width, y: (e.clientY - r.top) * H / r.height };
    }
    canvas.addEventListener('pointerdown', function (e) {
      var p = point(e);
      canvas.focus({ preventScroll: true });
      try { canvas.setPointerCapture(e.pointerId); } catch (x) {}
      drag = { sx: p.x, sy: p.y, x: p.x, y: p.y, moved: false };
      ripples.push({ x: p.x, y: p.y, t: 0, c: '255,255,255' });
      wake();
    });
    canvas.addEventListener('pointermove', function (e) {
      if (!drag) return;
      var p = point(e); drag.x = p.x; drag.y = p.y;
      if (Math.hypot(p.x - drag.sx, p.y - drag.sy) > 12) drag.moved = true;
    });
    function release() { if (drag && !drag.moved) fire(); drag = null; }
    canvas.addEventListener('pointerup', release);
    canvas.addEventListener('pointercancel', function () { drag = null; });

    $$('.sim-keys kbd').forEach(function (n) { n.setAttribute('aria-hidden', 'true'); });

    $('.sim-rail').addEventListener('click', function (e) {
      var b = e.target.closest('button'); if (!b) return;
      var act = b.getAttribute('data-act'), on = b.getAttribute('aria-pressed') !== 'true';
      if (b.hasAttribute('aria-pressed')) b.setAttribute('aria-pressed', String(on));
      if (act === 'rotate') { sim.classList.toggle('portrait', on); size(); draw(); }
      else if (act === 'shot') {
        var f = $('#simFlash'); f.classList.remove('go'); void f.offsetWidth; f.classList.add('go');
        say(t('Di aplikasi: tersimpan di ~/Pictures/Benz Mirror', 'In the app: saved to ~/Pictures/Benz Mirror'));
      } else if (act === 'rec') {
        recAt = on ? performance.now() : 0; recBox.hidden = !on; recT.textContent = '00:00';
        if (on) used = true;
        else say(t('Di aplikasi: tersimpan di ~/Movies/Benz Mirror', 'In the app: saved to ~/Movies/Benz Mirror'));
      } else if (act === 'keys') sim.classList.toggle('nokeys', !on);
      else if (act === 'stats') {
        statsBox.hidden = !on; used = true;
        statsBox.textContent = (fps || '…') + ' fps\n' + W + '×' + H + '\n' + t('simulasi browser', 'browser simulation');
      } else if (act === 'stream') {
        sim.classList.toggle('stream', on);
        if (on) say(t('Stream Mode: klik tombol yang sama untuk keluar', 'Stream Mode: press the same button to leave'));
      } else if (act === 'home') { me.x = W / 2; me.y = H / 2; me.vx = me.vy = 0; say('Home'); }
      else if (act === 'back') say('Back');
      else if (act === 'recents') say('Recents');
      run();
    });

    size(); draw();
    seen(canvas, function (on) { visible = on; last = 0; run(); });
    document.addEventListener('visibilitychange', function () { last = 0; run(); });
    langHooks.push(draw);
  })();

  /* ---------- logcat sample ---------- */
  (function () {
    var box = $('#log'), q = $('#logQ'), pause = $('#logPause'), level = 0, paused = false, visible = false, i = 0, lines = [];
    var sample = [
      [1, 'I/ActivityManager: Start proc com.example.app'], [0, 'D/OkHttp: --> GET /v1/profile'],
      [0, 'D/OkHttp: <-- 200 OK (84ms)'], [1, 'I/Choreographer: Skipped 3 frames'],
      [2, 'W/System: A resource failed to call close.'], [0, 'D/ViewRootImpl: relayout window'],
      [1, 'I/ExampleApp: Home screen ready'], [2, 'W/InputDispatcher: Window is slow to respond'],
      [3, 'E/AndroidRuntime: FATAL EXCEPTION: main'], [3, 'E/AndroidRuntime: java.lang.IllegalStateException'],
      [3, 'E/AndroidRuntime:   at com.example.app.Main.load'], [1, 'I/ActivityManager: Restarting activity'],
      [0, 'D/GC: concurrent copying freed 12MB']
    ];
    function push() {
      var s = sample[i++ % sample.length], d = new Date();
      lines.push([s[0], d.toTimeString().slice(0, 8) + ' ' + s[1]]);
      if (lines.length > 60) lines.shift();
    }
    function render() {
      var f = q.value.trim().toLowerCase();
      var shown = lines.filter(function (l) { return l[0] >= level && (!f || l[1].toLowerCase().indexOf(f) > -1); }).slice(-10);
      box.textContent = '';
      shown.forEach(function (l) {
        box.appendChild(el('div', l[0] === 2 ? 'w' : l[0] === 3 ? 'e' + (l[1].indexOf('AndroidRuntime') > -1 ? ' crash' : '') : '', l[1]));
      });
      if (!shown.length) box.appendChild(el('div', '', t('Tidak ada baris yang cocok.', 'No matching lines.')));
    }
    for (var n = 0; n < 24; n++) push();
    render();
    seen(box, function (on) { visible = on; });
    setInterval(function () { if (visible && !paused && !document.hidden && !reduced.matches) { push(); render(); } }, 900);
    $('#logLv').addEventListener('click', function (e) {
      var b = e.target.closest('button'); if (!b) return;
      level = Number(b.getAttribute('data-lv'));
      $$('#logLv button').forEach(function (x) { x.setAttribute('aria-pressed', String(x === b)); });
      render();
    });
    q.addEventListener('input', render);
    pause.addEventListener('click', function () {
      paused = !paused; pause.setAttribute('aria-pressed', String(paused)); pause.textContent = paused ? 'Resume' : 'Pause';
    });
    langHooks.push(render);
  })();

  /* ---------- network profiles ---------- */
  (function () {
    var dot = $('#netDot'), lat = $('#netLat'), down = $('#netDown'), anim;
    function set(b) {
      var l = Number(b.getAttribute('data-l')), d = Number(b.getAttribute('data-d'));
      $$('#net button').forEach(function (x) { x.setAttribute('aria-pressed', String(x === b)); });
      lat.textContent = l; down.textContent = d || '∞';
      if (anim) anim.cancel();
      if (!dot.animate || reduced.matches) return;
      var ms = d ? Math.max(700, Math.min(6000, 600 + l * 3 + 90000 / d * 3)) : 500;
      anim = dot.animate([{ left: '-2%' }, { left: '102%' }], { duration: ms, iterations: Infinity });
    }
    $('#net').addEventListener('click', function (e) { var b = e.target.closest('button'); if (b) set(b); });
    set($('#net [aria-pressed=true]'));
  })();

  /* ---------- colour picker ---------- */
  (function () {
    var c = $('#pick'), x = c.getContext('2d', { willReadFrequently: true }), loupe = $('#loupe'), value = '#0A55C8';
    var g = x.createLinearGradient(0, 0, c.width, c.height);
    [[0, '#020a1c'], [.35, '#0a55c8'], [.62, '#0a84ff'], [.82, '#5cc2ff'], [1, '#fcfdff']].forEach(function (s) { g.addColorStop(s[0], s[1]); });
    x.fillStyle = g; x.fillRect(0, 0, c.width, c.height);
    [['#35d467', 70, 160], ['#ffd166', 370, 70], ['#ff6961', 420, 165]].forEach(function (d) {
      x.beginPath(); x.arc(d[1], d[2], 30, 0, 7); x.fillStyle = d[0]; x.fill();
    });
    function move(e) {
      var r = c.getBoundingClientRect();
      var px = Math.max(0, Math.min(c.width - 1, Math.floor((e.clientX - r.left) * c.width / r.width)));
      var py = Math.max(0, Math.min(c.height - 1, Math.floor((e.clientY - r.top) * c.height / r.height)));
      var d = x.getImageData(px, py, 1, 1).data;
      value = '#' + [d[0], d[1], d[2]].map(function (v) { return v.toString(16).padStart(2, '0'); }).join('').toUpperCase();
      $('#hexV').textContent = value; $('#sw').style.background = value;
      loupe.hidden = false; loupe.style.background = value;
      loupe.style.left = (e.clientX - r.left) + 'px'; loupe.style.top = (e.clientY - r.top) + 'px';
    }
    c.addEventListener('pointermove', move);
    c.addEventListener('pointerdown', move);
    c.addEventListener('pointerleave', function () { loupe.hidden = true; });
    $('#hex').addEventListener('click', function () { copy(value, $('#hex span')); });
  })();

  /* ---------- spotlight on cards ---------- */
  $$('.card').forEach(function (c) {
    c.addEventListener('pointermove', function (e) {
      var r = c.getBoundingClientRect();
      c.style.setProperty('--mx', (e.clientX - r.left) + 'px'); c.style.setProperty('--my', (e.clientY - r.top) + 'px');
    });
    c.addEventListener('pointerleave', function () { c.style.removeProperty('--mx'); c.style.removeProperty('--my'); });
  });

  /* ---------- quality presets (values from the app) ---------- */
  (function () {
    var P = {
      balanced: { res: '1920 px', bit: 8, fps: 60, codec: 'H.264', note: ['Ringan untuk USB dan Wi-Fi. Key frame tiap 10 detik.', 'Light on USB and Wi-Fi. A key frame every 10 s.'] },
      high: { res: 'Native', bit: 20, fps: 60, codec: 'H.264', note: ['Resolusi asli. Key frame tiap 2 detik.', 'Native resolution. A key frame every 2 s.'] },
      gaming: { res: 'Native', bit: 40, fps: 60, codec: 'H.264', note: ['Bitrate konstan, key frame tiap 1 detik. Cocok untuk OBS.', 'Constant bitrate, a key frame every second. Good for OBS.'] },
      max: { res: 'Native', bit: 80, fps: 120, codec: 'H.265', note: ['Bitrate konstan. Disarankan lewat USB.', 'Constant bitrate. USB recommended.'] }
    };
    var cur = 'gaming', shown = { bit: 40, fps: 60 };
    function count(id, key, to) {
      var from = shown[key], start = null, node = $(id);
      shown[key] = to;
      if (reduced.matches || from === to) { node.textContent = to; return; }
      cancelAnimationFrame(node._r);
      node._r = requestAnimationFrame(function f(now) {
        start = start || now;
        var k = Math.min(1, (now - start) / 450);
        node.textContent = Math.round(from + (to - from) * (1 - Math.pow(1 - k, 3)));
        if (k < 1) node._r = requestAnimationFrame(f);
      });
    }
    function render() {
      var p = P[cur];
      $('#qRes').textContent = p.res; $('#qCodec').textContent = p.codec;
      count('#qBit', 'bit', p.bit); count('#qFps', 'fps', p.fps);
      $('#qGauge').style.width = (p.bit / 80 * 100) + '%';
      $('#qNote').textContent = t(p.note[0], p.note[1]);
    }
    $('#preset').addEventListener('click', function (e) {
      var b = e.target.closest('button'); if (!b) return;
      cur = b.getAttribute('data-p');
      $$('#preset button').forEach(function (x) { x.setAttribute('aria-pressed', String(x === b)); });
      render();
    });
    langHooks.push(render);
  })();

  /* ---------- shortcut search ---------- */
  $('#keyQ').addEventListener('input', function () {
    var f = this.value.trim().toLowerCase(), n = 0;
    $$('#keyList li').forEach(function (li) {
      var ok = li.firstElementChild.textContent.toLowerCase().indexOf(f) > -1;
      li.hidden = !ok; if (ok) n++;
    });
    $('#keyNone').hidden = n > 0;
  });

  /* ---------- install checklist ---------- */
  (function () {
    var done = read('bm.install'), items = $$('li[data-done]'), ids = [];
    items.forEach(function (li) {
      var id = li.getAttribute('data-done'), b = el('button', 'tick');
      b.type = 'button'; b.setAttribute('data-tick', id); li.insertBefore(b, li.firstChild);
      if (ids.indexOf(id) < 0) ids.push(id);
      b.addEventListener('click', function () { done[id] = !done[id]; write('bm.install', done); render(); });
    });
    function render() {
      var n = ids.filter(function (id) { return done[id]; }).length;
      $$('[data-tick]').forEach(function (b) {
        var on = !!done[b.getAttribute('data-tick')], title = $('h4', b.parentNode);
        var visible = title && $$('h4', b.parentNode).filter(function (h) { return !h.closest('[hidden]'); })[0] || title;
        var heading = visible ? (visible.querySelector('[lang=' + lang() + ']') || visible).textContent : '';
        b.setAttribute('aria-pressed', String(on));
        b.setAttribute('aria-label', t('Tandai selesai: ', 'Mark as done: ') + heading);
      });
      $('#doneBar').style.width = (n / ids.length * 100) + '%';
      $('#doneText').textContent = n === ids.length ? t('Semua langkah selesai', 'All steps done') : n + ' / ' + ids.length + ' ' + t('langkah', 'steps');
      $('#doneReset').hidden = !n;
    }
    $('#doneReset').addEventListener('click', function () { done = {}; write('bm.install', done); render(); });
    langHooks.push(render);

    var tapper = $('#tapper'), taps = 0;
    function tapRender() {
      $('#tapText').textContent = taps >= 7 ? t('Anda sekarang developer ✓', 'You are now a developer ✓')
        : taps ? t('Ketuk ' + (7 - taps) + ' kali lagi', (7 - taps) + ' more taps')
          : t('Latihan: Nomor build', 'Practice: Build number');
      $('i', tapper).style.backgroundSize = (Math.min(taps, 7) / 7 * 100) + '% 100%';
    }
    tapper.addEventListener('click', function () { taps = taps >= 7 ? 0 : taps + 1; tapRender(); });
    langHooks.push(tapRender);
  })();

  /* ---------- releases, download buttons and changelog ---------- */
  (function () {
    var R = window.BenzReleases, data = null;
    function date(s) {
      if (!s) return '';
      var d = new Date(s + 'T00:00:00Z');
      return isNaN(d) ? s : d.toLocaleDateString(t('id-ID', 'en-GB'), { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' });
    }
    function size(n) { return n ? (n / 1048576).toLocaleString(t('id-ID', 'en-GB'), { maximumFractionDigits: 1, minimumFractionDigits: 1 }) + ' MB' : ''; }
    function link(cls, href, text) { var a = el('a', cls, text); a.href = href; return a; }

    /* A small, safe subset of Markdown: headings, bullet lists and paragraphs, always as text. */
    function notes(text) {
      var box = el('div'), list = null, para = null;
      String(text || '').split(/\r?\n/).forEach(function (raw) {
        var line = raw.replace(/\*\*(.+?)\*\*/g, '$1').replace(/`([^`]*)`/g, '$1').replace(/\[([^\]]+)\]\([^)]*\)/g, '$1').trim();
        var m;
        if (!line) { list = para = null; return; }
        if ((m = /^#{1,6}\s+(.*)/.exec(line))) { list = para = null; box.appendChild(el('h4', '', m[1])); }
        else if ((m = /^(?:[-*+]|\d+\.)\s+(.*)/.exec(line))) {
          if (!list) { list = el('ul'); box.appendChild(list); para = null; }
          list.appendChild(el('li', '', m[1]));
        } else if (list && /^\s{2,}/.test(raw)) list.lastChild.textContent += ' ' + line;
        else if (para) para.textContent += ' ' + line;
        else { list = null; para = el('p', '', line); box.appendChild(para); }
      });
      return box;
    }

    function card() {
      var box = $('#dlState'), v = data && data.latest;
      box.textContent = '';
      if (!data) {
        box.appendChild(el('p', '', t('Memeriksa rilis terbaru…', 'Checking for the latest release…')));
        box.appendChild(link('btn big', R.web + '/releases', t('Buka halaman rilis', 'Open the releases page')));
      } else if (data.state === 'ready') {
        box.appendChild(el('div', 'dl-ver', 'Benz Mirror ' + v.version + (v.pre ? ' (beta)' : '')));
        var facts = el('ul', 'dl-facts');
        [date(v.date), size(v.size), v.source === 'release' ? 'GitHub Releases' : t('File di repositori', 'File in the repository')]
          .filter(Boolean).forEach(function (x) { facts.appendChild(el('li', '', x)); });
        box.appendChild(facts);
        if (v.pre) box.appendChild(el('p', 'note', t('Ini versi beta: sudah dicoba terutama di satu ponsel, jadi mungkin masih ada bagian yang kasar.', 'This is a beta. It has been tried mostly on one phone, so some parts may still be rough.')));
        var a = link('btn big', v.url, t('Unduh ', 'Download ') + v.file);
        a.id = 'dlMain';
        box.appendChild(a);
        if (v.sha256) {
          var s = el('div', 'sha'), c = el('code', '', 'SHA-256 ' + v.sha256), b = el('button', 'chip', t('Salin', 'Copy'));
          b.type = 'button'; b.setAttribute('data-copy', v.sha256);
          s.appendChild(c); s.appendChild(b); box.appendChild(s);
        }
        var p = el('p'); p.appendChild(link('', '#install', t('Setelah diunduh, ikuti cara install', 'After downloading, follow the install steps')));
        box.appendChild(p);
      } else if (data.state === 'empty') {
        box.appendChild(el('div', 'dl-ver', t('Belum ada unduhan', 'No download yet')));
        box.appendChild(el('p', '', t('Belum ada DMG yang diterbitkan. Pantau halaman rilis, atau bangun sendiri dari kode sumber dengan Xcode (panduannya ada di docs/developers).',
          'No DMG has been published yet. Watch the releases page, or build it yourself from the source with Xcode (the guide is in docs/developers).')));
        var row = el('div', 'cta');
        row.appendChild(link('btn big', R.web + '/releases', t('Halaman rilis', 'Releases page')));
        row.appendChild(link('btn big ghost', R.web + '/tree/release/development/docs/developers', t('Panduan membangun', 'Build guide')));
        box.appendChild(row);
      } else {
        box.appendChild(el('p', '', t('Info rilis tidak bisa dimuat sekarang (jaringan, atau batas permintaan GitHub). Unduh langsung dari GitHub.',
          'Release details cannot be loaded right now (network, or GitHub rate limit). Download straight from GitHub.')));
        box.appendChild(link('btn big', R.web + '/releases', t('Buka halaman rilis', 'Open the releases page')));
      }
    }

    function buttons() {
      var v = data && data.state === 'ready' ? data.latest : null;
      $$('[data-dl]').forEach(function (a) {
        a.href = v ? v.url : '#download';
        var label = $('[data-dl-label]', a);
        label.textContent = data && data.state === 'empty' ? t('Segera hadir', 'Coming soon') : t('Unduh untuk Mac', 'Download for Mac');
      });
      $('[data-dl-meta]').textContent = v ? t('Versi ', 'Version ') + v.version + (size(v.size) ? ' · ' + size(v.size) : '') : '';
      var file = v ? v.file : 'Benz-Mirror-<' + t('versi', 'version') + '>.dmg';
      $$('[data-file]').forEach(function (n) { n.textContent = file; });
      var cmd = 'shasum -a 256 ~/Downloads/' + file;
      $('[data-sum-cmd]').textContent = cmd;
    }

    function older() {
      var list = $('#olderList'), rest = data ? data.versions.filter(function (v) { return v !== data.latest && (!data.latest || v.version !== data.latest.version); }) : [];
      list.textContent = '';
      rest.forEach(function (v) {
        var li = el('li');
        li.appendChild(el('span', '', [v.version + (v.pre ? ' (beta)' : ''), date(v.date), size(v.size)].filter(Boolean).join(' · ')));
        li.appendChild(link('', v.url, t('Unduh', 'Download')));
        list.appendChild(li);
      });
      $('#older').hidden = !rest.length;
    }

    function timeline() {
      if (!data) return;
      var merged = {}, order = [];
      data.changelog.forEach(function (e) { merged[e.version] = { version: e.version, date: e.date, body: e.body, released: false }; order.push(e.version); });
      data.versions.forEach(function (v) {
        if (!merged[v.version]) { merged[v.version] = { version: v.version, body: '' }; order.push(v.version); }
        var m = merged[v.version];
        m.released = true; m.date = v.date || m.date; m.body = v.notes || m.body;
      });
      order.sort(function (a, b) {
        if (/unreleased/i.test(a)) return -1;
        if (/unreleased/i.test(b)) return 1;
        return R.compare(b, a);
      });
      if (!order.length) return;
      var box = $('#timeline'); box.textContent = '';
      order.slice(0, 12).forEach(function (key) {
        var e = merged[key], li = el('li');
        li.appendChild(el('h3', '', /unreleased/i.test(key) ? t('Berikutnya', 'Next') : key));
        var when = [date(e.date)];
        if (!e.released && data.state !== 'error') when.push(t('Belum dirilis', 'Not released yet'));
        li.appendChild(el('span', 'when', when.filter(Boolean).join(' · ')));
        li.appendChild(notes(e.body));
        box.appendChild(li);
      });
    }

    function render() { card(); buttons(); older(); timeline(); }
    langHooks.push(render);
    R.load().then(function (d) { data = d; render(); }, function () {
      data = { state: 'error', latest: null, versions: [], changelog: [] }; render();
    });
  })();

  setVariant(doc.getAttribute('data-variant') || 'a', false);
  applyLang();
  onScroll();
})();
