const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {join} = require('node:path');

const html = readFileSync(join(__dirname, '../web/index.html'), 'utf8');
const app = readFileSync(join(__dirname, '../web/app.js'), 'utf8');
const ui = readFileSync(join(__dirname, '../web/ui.js'), 'utf8');

test('T13: chat is rendered as text, never as player-controlled HTML', () => {
  assert.match(ui, /line\.textContent\s*=\s*chat\.message/);
  assert.match(ui, /document\.createTextNode\(chat\.message\)/);
  assert.doesNotMatch(ui, /innerHTML\s*=\s*chat\./);
  assert.doesNotMatch(ui, /insertAdjacentHTML\s*\(/);
  assert.doesNotMatch(ui, /document\.write\s*\(/);
});

test('T13: browser and server chat limits stay aligned at 300 characters', () => {
  assert.match(html, /id="chat-input"[^>]*maxlength="300"/s);
});

test('T13: FAQ and ability dialogs expose labels, close controls and focus targets', () => {
  for (const id of ['game-help-dialog', 'role-help-dialog']) {
    const dialog = html.match(new RegExp(`<dialog\\s+id="${id}"[\\s\\S]*?<\\/dialog>`));
    assert.ok(dialog, `missing dialog #${id}`);
    assert.match(dialog[0], /aria-labelledby="[^"]+"/);
    assert.match(dialog[0], /class="[^"]*dialog-close[^"]*"[^>]*autofocus/);
  }
  assert.match(app,
    /dialog\.querySelector\("\.dialog-close"\)\.addEventListener\("click", \(\) => dialog\.close\(\)\)/);
  assert.match(app, /helpDialog\.showModal\(\)/);
});
