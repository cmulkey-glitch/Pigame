// Runs the brs interpreter with Roku-device `for each` semantics. On a real Roku an array or
// associative array has ONE iteration position: a `for each` nested over the same object
// (directly or through a call) restarts it, runs it to the end, and the outer loop then stops
// early. brs gives every loop its own iterator, which hid exactly that bug in Room_setDoor.
// Nested iteration of the same object is also reported on stderr.
// Usage: node tools/brs-device.cjs <path to brs cli.js> --root <dir> file.brs...
const path = require('path');
const [cli, ...args] = process.argv.slice(2);
const lib = path.join(path.dirname(require('fs').realpathSync(cli)), '..', 'lib');
const brs = require(lib);
const { Interpreter } = require(path.join(lib, 'interpreter'));
const { isIterable, BrsInvalid, ValueKind } = require(path.join(lib, 'brsTypes'));
const { Scope } = require(path.join(lib, 'interpreter', 'Environment'));
const { Stmt } = require(path.join(lib, 'parser'));
const { BrsError } = require(path.join(lib, 'Error'));

const position = new WeakMap();   // the object's single iteration position
const active = new WeakSet();

Interpreter.prototype.visitForEach = function (statement) {
  const target = this.evaluate(statement.target);
  if (!isIterable(target)) {
    return this.addError(new BrsError('Attempting to iterate across values of non-iterable type ' +
      ValueKind.toString(target.kind), statement.item.location));
  }
  if (active.has(target)) {
    const loc = statement.item.location;
    console.error(`device for-each: nested iteration of the same object at ${loc.file}(${loc.start.line}) ` +
      'ends the outer loop on a Roku');
  }
  const elements = target.getElements();
  position.set(target, 0);
  const wasActive = active.has(target);
  active.add(target);
  try {
    while (position.get(target) < elements.length) {
      const i = position.get(target);
      position.set(target, i + 1);
      this.environment.define(Scope.Function, statement.item.text, elements[i]);
      try {
        this.execute(statement.body);
      } catch (reason) {
        if (reason instanceof Stmt.ExitForReason) break;
        throw reason;
      }
    }
  } finally {
    if (!wasActive) active.delete(target);
  }
  return BrsInvalid.Instance;
};

const root = args[args.indexOf('--root') + 1];
const files = args.filter((a, i) => a !== '--root' && args[i - 1] !== '--root');
brs.execute(files, { root, componentDirs: [] }).catch((err) => {
  (err.messages && err.messages.length ? err.messages : [err.message]).forEach((m) => console.error(m));
  process.exitCode = 1;
});
