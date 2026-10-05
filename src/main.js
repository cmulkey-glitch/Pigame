import { createPlatform } from './platform/web.js';
import { Game } from './game/game.js';

const platform = await createPlatform(document.getElementById('screen'));
const game = new Game(platform);
// ?pack=editor plays the levels saved by the chamber editor (editor.html) instead of the ROM's.
let pack = null;
if (new URLSearchParams(location.search).get('pack') === 'editor') {
  try { pack = JSON.parse(platform.storage.get('downland.editor.pack')); } catch { pack = null; }
}
await game.load('.', pack);
platform.run(() => game.update(), () => game.render());
window.game = game;  // handy for poking at state from the console
