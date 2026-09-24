// Browser platform layer: asset loading, input, drawing and the frame loop.
// Ports to other systems replace this file; src/game/* only uses the object returned here.

const KEYMAP = {
  ArrowLeft: 'left', ArrowRight: 'right', ArrowUp: 'up', ArrowDown: 'down',
  KeyA: 'left', KeyD: 'right', KeyW: 'up', KeyS: 'down', Space: 'jump',
};

export async function createPlatform(canvas) {
  const ctx = canvas.getContext('2d');
  ctx.imageSmoothingEnabled = false;

  const held = new Set();
  const pressed = [];  // one-shot keys (chamber select etc.)
  addEventListener('keydown', (e) => {
    if (KEYMAP[e.code]) { held.add(KEYMAP[e.code]); e.preventDefault(); }
    if (!e.repeat) pressed.push(e.key);
  });
  addEventListener('keyup', (e) => { if (KEYMAP[e.code]) held.delete(KEYMAP[e.code]); });
  addEventListener('blur', () => held.clear());

  // On-screen controls: [data-hold] buttons act like held keys (multi-touch, so you can run
  // and jump at once); [data-press] buttons send one key press.
  for (const el of document.querySelectorAll('[data-hold]')) {
    const name = el.dataset.hold, pointers = new Set();
    const release = (e) => {
      pointers.delete(e.pointerId);
      if (!pointers.size) { held.delete(name); el.classList.remove('down'); }
    };
    el.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      pointers.add(e.pointerId);
      held.add(name);
      el.classList.add('down');
      try { el.setPointerCapture(e.pointerId); } catch { /* no live pointer (synthetic event) */ }
    });
    for (const type of ['pointerup', 'pointercancel', 'lostpointercapture']) el.addEventListener(type, release);
    el.addEventListener('contextmenu', (e) => e.preventDefault());
  }
  for (const el of document.querySelectorAll('[data-press]')) {
    el.addEventListener('pointerdown', (e) => { e.preventDefault(); pressed.push(el.dataset.press); });
  }

  function loadImage(url) {
    return new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = () => reject(new Error('failed to load ' + url));
      img.src = url;
    });
  }

  return {
    width: canvas.width,
    height: canvas.height,

    async loadJSON(url) {
      const r = await fetch(url);
      if (!r.ok) throw new Error('failed to load ' + url);
      return r.json();
    },

    // Returns { width, height, data: Uint8ClampedArray RGBA, handle } for pixel access.
    async loadBitmap(url) {
      const img = await loadImage(url);
      const c = document.createElement('canvas');
      c.width = img.width; c.height = img.height;
      const cx = c.getContext('2d');
      cx.drawImage(img, 0, 0);
      const { data } = cx.getImageData(0, 0, img.width, img.height);
      return { width: img.width, height: img.height, data, handle: img };
    },

    // Build a drawable surface from RGBA pixels.
    makeSurface(width, height, rgba) {
      const c = document.createElement('canvas');
      c.width = width; c.height = height;
      c.getContext('2d').putImageData(new ImageData(rgba, width, height), 0, 0);
      return { width, height, handle: c };
    },

    input: {
      isDown: (name) => held.has(name),
      takePressed: () => pressed.splice(0),
    },

    gfx: {
      clear(color) { ctx.fillStyle = color; ctx.fillRect(0, 0, canvas.width, canvas.height); },
      draw(surface, dx, dy) { ctx.drawImage(surface.handle, Math.round(dx), Math.round(dy)); },
      blit(surface, sx, sy, w, h, dx, dy, flipX = false) {
        dx = Math.round(dx); dy = Math.round(dy);
        if (!flipX) { ctx.drawImage(surface.handle, sx, sy, w, h, dx, dy, w, h); return; }
        ctx.save();
        ctx.translate(dx + w, dy);
        ctx.scale(-1, 1);
        ctx.drawImage(surface.handle, sx, sy, w, h, 0, 0, w, h);
        ctx.restore();
      },
      rect(x, y, w, h, color) { ctx.fillStyle = color; ctx.fillRect(x, y, w, h); },
    },

    // Fixed 60 Hz update, render on every animation frame.
    run(update, render) {
      const STEP = 1000 / 60;
      let last = performance.now(), acc = 0;
      function frame(now) {
        acc += Math.min(now - last, 250);
        last = now;
        while (acc >= STEP) { update(); acc -= STEP; }
        render();
        requestAnimationFrame(frame);
      }
      requestAnimationFrame(frame);
    },
  };
}
