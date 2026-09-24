import { createPlatform } from './platform/web.js';
import { Game } from './game/game.js';

const platform = await createPlatform(document.getElementById('screen'));
const game = new Game(platform);
await game.load('.');
platform.run(() => game.update(), () => game.render());
window.game = game;  // handy for poking at state from the console
