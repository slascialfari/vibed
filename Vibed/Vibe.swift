// Vibed/Vibe.swift

import Foundation

struct Vibe: Identifiable {
    let id: UUID
    let title: String
    let description: String
    let htmlContent: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        description: String,
        htmlContent: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.htmlContent = htmlContent
        self.createdAt = createdAt
    }
}

extension Vibe {
    static let samples: [Vibe] = [glowBall, drumPad, shooterGame]

    static let glowBall = Vibe(
        title: "Glow Ball",
        description: "A glowing orb that rolls with your device's motion",
        htmlContent: glowBallHTML
    )

    static let drumPad = Vibe(
        title: "Drum Pad",
        description: "Touch-activated synthesized drum machine",
        htmlContent: drumPadHTML
    )

    static let shooterGame = Vibe(
        title: "Space Shooter",
        description: "Slide to dodge, tap to blast asteroids",
        htmlContent: shooterGameHTML
    )
}

// MARK: - HTML Content

private let glowBallHTML = #"""
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no, viewport-fit=cover">
<style>
* { margin: 0; padding: 0; }
html, body { width: 100%; height: 100%; overflow: hidden; background: #030510; }
canvas { position: fixed; top: 0; left: 0; touch-action: none; display: block; }
</style>
</head>
<body>
<canvas id="c"></canvas>
<script>
const c = document.getElementById('c');
const ctx = c.getContext('2d');
let W = c.width = window.innerWidth;
let H = c.height = window.innerHeight;
window.addEventListener('resize', () => { W = c.width = window.innerWidth; H = c.height = window.innerHeight; initStars(); });

let stars = [];
function initStars() {
  stars = Array.from({ length: 180 }, () => ({
    x: Math.random() * W, y: Math.random() * H,
    r: Math.random() * 1.4 + 0.2,
    a: Math.random() * 0.7 + 0.3
  }));
}
initStars();

let bx = W / 2, by = H / 2;
let vx = 0, vy = 0;
const R = 32, FRICTION = 0.97;
const trail = [];
const TRAIL_MAX = 18;
let gravX = 0, gravY = 0;
let motionEnabled = false;

function handleMotion(e) {
  const g = e.accelerationIncludingGravity;
  if (!g) return;
  gravX = (g.x || 0) * 0.55;
  gravY = -(g.y || 0) * 0.55;
}

function enableMotion() {
  if (motionEnabled) return;
  if (typeof DeviceMotionEvent !== 'undefined' && typeof DeviceMotionEvent.requestPermission === 'function') {
    DeviceMotionEvent.requestPermission()
      .then(p => { if (p === 'granted') { window.addEventListener('devicemotion', handleMotion); motionEnabled = true; } })
      .catch(() => {});
  } else if (typeof DeviceMotionEvent !== 'undefined') {
    window.addEventListener('devicemotion', handleMotion);
    motionEnabled = true;
  }
}

let touchStart = null;
c.addEventListener('touchstart', e => {
  e.preventDefault();
  enableMotion();
  const t = e.touches[0];
  touchStart = { x: t.clientX, y: t.clientY, t: Date.now(), bx, by };
}, { passive: false });

c.addEventListener('touchmove', e => {
  e.preventDefault();
  const t = e.touches[0];
  if (touchStart) {
    bx = Math.max(R, Math.min(W - R, touchStart.bx + (t.clientX - touchStart.x)));
    by = Math.max(R, Math.min(H - R, touchStart.by + (t.clientY - touchStart.y)));
    vx = 0; vy = 0;
  }
}, { passive: false });

c.addEventListener('touchend', e => {
  e.preventDefault();
  if (touchStart) {
    const t = e.changedTouches[0];
    const dt = (Date.now() - touchStart.t) / 1000;
    if (dt > 0 && dt < 0.25) {
      vx = (t.clientX - touchStart.x) / dt * 0.25;
      vy = (t.clientY - touchStart.y) / dt * 0.25;
    }
  }
  touchStart = null;
}, { passive: false });

function loop() {
  requestAnimationFrame(loop);

  vx += gravX; vy += gravY;
  vx *= FRICTION; vy *= FRICTION;
  bx += vx; by += vy;

  if (bx < R) { bx = R; vx = Math.abs(vx) * 0.65; }
  else if (bx > W - R) { bx = W - R; vx = -Math.abs(vx) * 0.65; }
  if (by < R) { by = R; vy = Math.abs(vy) * 0.65; }
  else if (by > H - R) { by = H - R; vy = -Math.abs(vy) * 0.65; }

  trail.push({ x: bx, y: by });
  if (trail.length > TRAIL_MAX) trail.shift();

  ctx.fillStyle = '#030510';
  ctx.fillRect(0, 0, W, H);

  stars.forEach(s => {
    ctx.beginPath();
    ctx.arc(s.x, s.y, s.r, 0, Math.PI * 2);
    ctx.fillStyle = `rgba(200,220,255,${s.a})`;
    ctx.fill();
  });

  trail.forEach((p, i) => {
    const t = i / TRAIL_MAX;
    const tr = R * t * 0.9;
    const g = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, tr * 2.5);
    g.addColorStop(0, `rgba(60,140,255,${t * 0.25})`);
    g.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.beginPath();
    ctx.arc(p.x, p.y, tr * 2.5, 0, Math.PI * 2);
    ctx.fillStyle = g;
    ctx.fill();
  });

  const og = ctx.createRadialGradient(bx, by, R, bx, by, R * 4);
  og.addColorStop(0, 'rgba(50,130,255,0.35)');
  og.addColorStop(0.5, 'rgba(20,60,180,0.12)');
  og.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.beginPath();
  ctx.arc(bx, by, R * 4, 0, Math.PI * 2);
  ctx.fillStyle = og;
  ctx.fill();

  const bg = ctx.createRadialGradient(bx - R * 0.3, by - R * 0.35, R * 0.08, bx, by, R);
  bg.addColorStop(0, '#ffffff');
  bg.addColorStop(0.25, '#b0d8ff');
  bg.addColorStop(0.65, '#3370ff');
  bg.addColorStop(1, '#001888');
  ctx.beginPath();
  ctx.arc(bx, by, R, 0, Math.PI * 2);
  ctx.fillStyle = bg;
  ctx.shadowColor = '#4488ff';
  ctx.shadowBlur = 28;
  ctx.fill();
  ctx.shadowBlur = 0;

  if (!motionEnabled) {
    ctx.font = '15px -apple-system, sans-serif';
    ctx.fillStyle = 'rgba(140,180,255,0.55)';
    ctx.textAlign = 'center';
    ctx.fillText('tap & tilt to roll', W / 2, H - 32);
  }
}

loop();
</script>
</body>
</html>
"""#

private let drumPadHTML = #"""
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no, viewport-fit=cover">
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
html, body { width: 100%; height: 100%; overflow: hidden; background: #0d0d12; font-family: -apple-system, sans-serif; }
#grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  grid-template-rows: repeat(3, 1fr);
  gap: 10px;
  padding: 14px;
  width: 100%; height: 100%;
}
.pad {
  border-radius: 16px;
  display: flex; flex-direction: column;
  align-items: center; justify-content: center;
  cursor: pointer;
  user-select: none; -webkit-user-select: none;
  transition: transform 0.07s, filter 0.07s;
}
.pad.hit { transform: scale(0.92); filter: brightness(2.4); }
.pad-icon { font-size: 28px; margin-bottom: 7px; }
.pad-label { font-size: 12px; font-weight: 700; letter-spacing: 1.5px; color: rgba(255,255,255,0.82); text-transform: uppercase; }
</style>
</head>
<body>
<div id="grid"></div>
<script>
// AudioContext is created lazily on the first tap.
// iOS requires the context to be both CREATED and resume()-d inside a
// user-gesture handler; creating it at page-load time leaves it suspended
// and some iOS versions refuse to unlock it later via resume() alone.
let AC = null;
function getAC() {
  if (!AC) AC = new (window.AudioContext || window.webkitAudioContext)();
  return AC;
}
const t0 = () => getAC().currentTime;

function noise(dur) {
  const ac = getAC();
  const buf = ac.createBuffer(1, ac.sampleRate * dur, ac.sampleRate);
  const d = buf.getChannelData(0);
  for (let i = 0; i < d.length; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / d.length, 1.1);
  return buf;
}

const pads = [
  { label: 'Kick', icon: '🥁', color: '#e74c3c',
    play() {
      const o = AC.createOscillator(), g = AC.createGain();
      o.connect(g); g.connect(AC.destination);
      o.frequency.setValueAtTime(160, t0()); o.frequency.exponentialRampToValueAtTime(0.001, t0() + 0.55);
      g.gain.setValueAtTime(1.2, t0()); g.gain.exponentialRampToValueAtTime(0.001, t0() + 0.55);
      o.start(t0()); o.stop(t0() + 0.56);
    }
  },
  { label: 'Snare', icon: '🔊', color: '#e67e22',
    play() {
      const s = AC.createBufferSource(), g = AC.createGain();
      s.buffer = noise(0.18); s.connect(g); g.connect(AC.destination);
      g.gain.setValueAtTime(0.9, t0()); g.gain.exponentialRampToValueAtTime(0.001, t0() + 0.18);
      s.start(t0());
    }
  },
  { label: 'Clap', icon: '👏', color: '#f39c12',
    play() {
      [0, 14, 28].forEach(ms => setTimeout(() => {
        const s = AC.createBufferSource(), g = AC.createGain();
        s.buffer = noise(0.04); s.connect(g); g.connect(AC.destination);
        g.gain.setValueAtTime(0.7, AC.currentTime);
        s.start(AC.currentTime);
      }, ms));
    }
  },
  { label: 'Hi-Hat', icon: '🎵', color: '#27ae60',
    play() {
      const s = AC.createBufferSource(), f = AC.createBiquadFilter(), g = AC.createGain();
      f.type = 'highpass'; f.frequency.value = 8000;
      s.buffer = noise(0.07); s.connect(f); f.connect(g); g.connect(AC.destination);
      g.gain.setValueAtTime(0.5, t0()); g.gain.exponentialRampToValueAtTime(0.001, t0() + 0.07);
      s.start(t0());
    }
  },
  { label: 'Open HH', icon: '✨', color: '#16a085',
    play() {
      const s = AC.createBufferSource(), f = AC.createBiquadFilter(), g = AC.createGain();
      f.type = 'bandpass'; f.frequency.value = 9000; f.Q.value = 0.8;
      const buf = AC.createBuffer(1, AC.sampleRate * 0.45, AC.sampleRate);
      const d = buf.getChannelData(0);
      for (let i = 0; i < d.length; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / d.length, 0.5);
      s.buffer = buf; s.connect(f); f.connect(g); g.connect(AC.destination);
      g.gain.setValueAtTime(0.45, t0()); g.gain.exponentialRampToValueAtTime(0.001, t0() + 0.45);
      s.start(t0());
    }
  },
  { label: 'Cymbal', icon: '🔔', color: '#2980b9',
    play() {
      const s = AC.createBufferSource(), f = AC.createBiquadFilter(), g = AC.createGain();
      f.type = 'bandpass'; f.frequency.value = 7500; f.Q.value = 0.4;
      const buf = AC.createBuffer(1, AC.sampleRate * 1.1, AC.sampleRate);
      const d = buf.getChannelData(0);
      for (let i = 0; i < d.length; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / d.length, 0.35);
      s.buffer = buf; s.connect(f); f.connect(g); g.connect(AC.destination);
      g.gain.setValueAtTime(0.5, t0()); g.gain.exponentialRampToValueAtTime(0.001, t0() + 1.1);
      s.start(t0());
    }
  },
  { label: 'Tom Hi', icon: '🟡', color: '#8e44ad',
    play() {
      const o = AC.createOscillator(), g = AC.createGain();
      o.connect(g); g.connect(AC.destination);
      o.frequency.setValueAtTime(220, t0()); o.frequency.exponentialRampToValueAtTime(80, t0() + 0.3);
      g.gain.setValueAtTime(0.9, t0()); g.gain.exponentialRampToValueAtTime(0.001, t0() + 0.3);
      o.start(t0()); o.stop(t0() + 0.31);
    }
  },
  { label: 'Tom Lo', icon: '🟠', color: '#6c3483',
    play() {
      const o = AC.createOscillator(), g = AC.createGain();
      o.connect(g); g.connect(AC.destination);
      o.frequency.setValueAtTime(110, t0()); o.frequency.exponentialRampToValueAtTime(35, t0() + 0.42);
      g.gain.setValueAtTime(0.9, t0()); g.gain.exponentialRampToValueAtTime(0.001, t0() + 0.42);
      o.start(t0()); o.stop(t0() + 0.43);
    }
  },
  { label: 'Rim', icon: '💥', color: '#c0392b',
    play() {
      const o = AC.createOscillator(), ns = AC.createBufferSource();
      const gn = AC.createGain(), go = AC.createGain(), mix = AC.createGain();
      o.frequency.value = 1700; o.type = 'square';
      ns.buffer = noise(0.04);
      ns.connect(gn); o.connect(go); gn.connect(mix); go.connect(mix); mix.connect(AC.destination);
      gn.gain.setValueAtTime(0.4, t0()); gn.gain.exponentialRampToValueAtTime(0.001, t0() + 0.04);
      go.gain.setValueAtTime(0.3, t0()); go.gain.exponentialRampToValueAtTime(0.001, t0() + 0.04);
      o.start(t0()); ns.start(t0()); o.stop(t0() + 0.05);
    }
  },
];

const grid = document.getElementById('grid');
pads.forEach(pad => {
  const el = document.createElement('div');
  el.className = 'pad';
  el.style.background = pad.color + '20';
  el.style.border = `2px solid ${pad.color}`;
  el.style.boxShadow = `0 0 20px ${pad.color}44, inset 0 0 10px ${pad.color}18`;
  el.innerHTML = `<div class="pad-icon">${pad.icon}</div><div class="pad-label">${pad.label}</div>`;

  const trigger = () => {
    const ac = getAC();
    ac.resume().then(() => pad.play());
    el.classList.add('hit');
    setTimeout(() => el.classList.remove('hit'), 120);
  };
  el.addEventListener('touchstart', e => { e.preventDefault(); trigger(); }, { passive: false });
  el.addEventListener('mousedown', trigger);
  grid.appendChild(el);
});
</script>
</body>
</html>
"""#

private let shooterGameHTML = #"""
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no, viewport-fit=cover">
<style>
* { margin: 0; padding: 0; }
html, body { width: 100%; height: 100%; overflow: hidden; background: #000; }
canvas { position: fixed; top: 0; left: 0; touch-action: none; display: block; }
</style>
</head>
<body>
<canvas id="c"></canvas>
<script>
const c = document.getElementById('c');
const ctx = c.getContext('2d');
let W = c.width = window.innerWidth;
let H = c.height = window.innerHeight;

const stars = Array.from({ length: 130 }, () => ({
  x: Math.random() * W, y: Math.random() * H,
  vy: 0.2 + Math.random() * 0.5,
  r: Math.random() * 1.2 + 0.2,
  a: 0.3 + Math.random() * 0.5
}));

const SW = 24, SH = 38;
const ship = { x: W / 2, y: H - 90, inv: 0 };
let bullets = [], enemies = [], particles = [];
let score = 0, lives = 3, dead = false, frame = 0;
let lastSpawn = 0, spawnDelay = 1600, lastAutoShot = 0;
let touchStartX = null, touchShipX = null;

c.addEventListener('touchstart', e => {
  e.preventDefault();
  if (dead) { resetGame(); return; }
  touchStartX = e.touches[0].clientX;
  touchShipX = ship.x;
  fireBullet();
}, { passive: false });

c.addEventListener('touchmove', e => {
  e.preventDefault();
  if (dead || touchStartX === null) return;
  ship.x = Math.max(SW, Math.min(W - SW, touchShipX + (e.touches[0].clientX - touchStartX)));
}, { passive: false });

c.addEventListener('touchend', e => { e.preventDefault(); touchStartX = null; }, { passive: false });

function fireBullet() {
  bullets.push({ x: ship.x, y: ship.y - SH / 2 });
}

function spawnEnemy() {
  const r = 16 + Math.random() * 12;
  enemies.push({
    x: r + Math.random() * (W - r * 2), y: -r, r,
    vy: 1.0 + score * 0.003 + Math.random() * 1.3,
    hue: 5 + Math.random() * 45
  });
}

function burst(x, y, hue, n) {
  for (let i = 0; i < n; i++) {
    const a = Math.random() * Math.PI * 2, sp = 1.5 + Math.random() * 4.5;
    particles.push({ x, y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp - 1, life: 1, hue, r: 2 + Math.random() * 3 });
  }
}

function resetGame() {
  bullets = []; enemies = []; particles = [];
  score = 0; lives = 3; dead = false; ship.x = W / 2; ship.inv = 0;
  lastSpawn = performance.now(); lastAutoShot = performance.now(); spawnDelay = 1600;
}

function drawShip(alpha) {
  ctx.save(); ctx.globalAlpha = alpha; ctx.translate(ship.x, ship.y);
  ctx.beginPath();
  ctx.moveTo(0, -SH / 2);
  ctx.lineTo(SW / 2, SH / 2);
  ctx.lineTo(SW / 4, SH / 3);
  ctx.lineTo(-SW / 4, SH / 3);
  ctx.lineTo(-SW / 2, SH / 2);
  ctx.closePath();
  ctx.fillStyle = '#00d4ff';
  ctx.shadowColor = '#00d4ff'; ctx.shadowBlur = 14;
  ctx.fill();
  const fl = 0.6 + Math.sin(frame * 0.4) * 0.35;
  ctx.beginPath();
  ctx.moveTo(-SW / 4, SH / 3);
  ctx.lineTo(0, SH / 2 + 16 * fl);
  ctx.lineTo(SW / 4, SH / 3);
  ctx.closePath();
  ctx.fillStyle = `rgba(255,110,0,${fl})`;
  ctx.shadowColor = 'orange'; ctx.shadowBlur = 12;
  ctx.fill();
  ctx.restore(); ctx.shadowBlur = 0;
}

function loop(ts) {
  requestAnimationFrame(loop);
  frame++;

  if (!dead) {
    stars.forEach(s => { s.y += s.vy; if (s.y > H) { s.y = 0; s.x = Math.random() * W; } });

    if (ts - lastAutoShot > 550) { fireBullet(); lastAutoShot = ts; }

    if (ts - lastSpawn > spawnDelay) {
      spawnEnemy(); lastSpawn = ts;
      spawnDelay = Math.max(480, spawnDelay - 18);
    }

    bullets.forEach(b => b.y -= 15);
    bullets = bullets.filter(b => b.y > -20);
    enemies.forEach(e => e.y += e.vy);

    for (let i = bullets.length - 1; i >= 0; i--) {
      for (let j = enemies.length - 1; j >= 0; j--) {
        const dx = bullets[i].x - enemies[j].x, dy = bullets[i].y - enemies[j].y;
        if (dx * dx + dy * dy < (enemies[j].r + 4) * (enemies[j].r + 4)) {
          burst(enemies[j].x, enemies[j].y, enemies[j].hue, 9);
          enemies.splice(j, 1); bullets.splice(i, 1); score += 10; break;
        }
      }
    }

    if (ship.inv <= 0) {
      for (let j = enemies.length - 1; j >= 0; j--) {
        const dx = enemies[j].x - ship.x, dy = enemies[j].y - ship.y;
        const dist = (enemies[j].r + SW * 0.65);
        if (dx * dx + dy * dy < dist * dist) {
          burst(ship.x, ship.y, 200, 14);
          enemies.splice(j, 1); lives--; ship.inv = 100;
          if (lives <= 0) dead = true;
          break;
        }
      }
    } else ship.inv--;

    enemies = enemies.filter(e => e.y < H + e.r);

    particles.forEach(p => { p.x += p.vx; p.y += p.vy; p.vy += 0.08; p.life -= 0.028; p.r *= 0.98; });
    particles = particles.filter(p => p.life > 0);
  }

  ctx.fillStyle = '#04040f';
  ctx.fillRect(0, 0, W, H);

  stars.forEach(s => {
    ctx.beginPath(); ctx.arc(s.x, s.y, s.r, 0, Math.PI * 2);
    ctx.fillStyle = `rgba(210,225,255,${s.a})`; ctx.fill();
  });

  bullets.forEach(b => {
    ctx.fillStyle = '#00ffbb'; ctx.shadowColor = '#00ffbb'; ctx.shadowBlur = 10;
    ctx.fillRect(b.x - 2, b.y - 6, 4, 12);
  });
  ctx.shadowBlur = 0;

  enemies.forEach(e => {
    const g = ctx.createRadialGradient(e.x - e.r * 0.3, e.y - e.r * 0.3, e.r * 0.1, e.x, e.y, e.r);
    g.addColorStop(0, `hsl(${e.hue},100%,80%)`); g.addColorStop(1, `hsl(${e.hue},90%,30%)`);
    ctx.beginPath(); ctx.arc(e.x, e.y, e.r, 0, Math.PI * 2);
    ctx.fillStyle = g; ctx.shadowColor = `hsl(${e.hue},100%,55%)`; ctx.shadowBlur = 18;
    ctx.fill();
  });
  ctx.shadowBlur = 0;

  particles.forEach(p => {
    ctx.beginPath(); ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
    ctx.fillStyle = `hsla(${p.hue},100%,60%,${p.life})`; ctx.fill();
  });

  if (!dead) {
    const alpha = ship.inv > 0 ? (Math.floor(ship.inv / 6) % 2 === 0 ? 0.22 : 1) : 1;
    drawShip(alpha);
  }

  ctx.shadowBlur = 0;
  ctx.textAlign = 'left';
  ctx.font = 'bold 22px -apple-system, monospace';
  ctx.fillStyle = '#ff4477';
  ctx.fillText('\u2665'.repeat(Math.max(0, lives)) + '\u2661'.repeat(Math.max(0, 3 - lives)), 16, 46);
  ctx.textAlign = 'right';
  ctx.fillStyle = '#ffffff';
  ctx.fillText(String(score).padStart(5, '0'), W - 16, 46);

  if (dead) {
    ctx.fillStyle = 'rgba(0,0,0,0.72)';
    ctx.fillRect(0, 0, W, H);
    ctx.textAlign = 'center';
    ctx.font = 'bold 46px -apple-system, monospace';
    ctx.fillStyle = '#ff3355';
    ctx.shadowColor = '#ff3355'; ctx.shadowBlur = 24;
    ctx.fillText('GAME OVER', W / 2, H / 2 - 44);
    ctx.shadowBlur = 0;
    ctx.font = '26px -apple-system, monospace';
    ctx.fillStyle = '#ffffff';
    ctx.fillText('Score: ' + score, W / 2, H / 2 + 10);
    ctx.font = '18px -apple-system, monospace';
    ctx.fillStyle = '#aaaaaa';
    ctx.fillText('tap to play again', W / 2, H / 2 + 54);
  }
}

resetGame();
requestAnimationFrame(loop);
</script>
</body>
</html>
"""#
