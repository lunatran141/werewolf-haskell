const {test} = require('node:test');
const assert = require('node:assert/strict');
const {existsSync, readFileSync} = require('node:fs');
const {join} = require('node:path');
const vm = require('node:vm');

function setupAudio() {
  // Giả lập trình duyệt để kiểm tra thứ tự phát, dừng và lưu âm lượng.
  class Element {
    constructor() {
      this.children = [];
      this.listeners = {};
      this.style = {setProperty() {}};
    }
    appendChild(child) { this.children.push(child); }
    append(...children) { this.children.push(...children); }
    addEventListener(type, callback) { this.listeners[type] = callback; }
    setAttribute() {}
    remove() { this.removed = true; }
    fire(type) { this.listeners[type](); }
  }
  const played = [];
  class Audio {
    constructor(src) {
      this.src = src;
      this.paused = true;
      played.push(this);
    }
    play() { this.paused = false; return Promise.resolve(); }
    pause() { this.paused = true; }
  }
  const storage = new Map();
  const timers = new Map();
  let nextTimerId = 1;
  const body = new Element();
  const state = {roomId: 'R', phase: 'Lobby', gameResult: null, reconnecting: false};
  const context = vm.createContext({Audio, document: {body, createElement: () => new Element()},
    state,
    setTimeout(callback, delay) {
      const id = nextTimerId++;
      timers.set(id, {callback, delay});
      return id;
    },
    clearTimeout(id) { timers.delete(id); },
    localStorage: {
      getItem(key) { return storage.get(key) ?? null; },
      setItem(key, value) { storage.set(key, value); }
    }});
  const source = readFileSync(join(__dirname, '../web/ui.js'), 'utf8');
  const marker = '// Am thanh chi la phan hien thi:';
  assert.ok(source.includes(marker));
  vm.runInContext(source.slice(source.indexOf(marker)), context);
  const render = () => vm.runInContext('renderAtmosphere()', context);
  render();
  return {body, played, render, state, storage, timers};
}

test('MP3 mở đầu đêm phát một lần, nhạc đêm lặp và dừng khi vào Day', () => {
  const {played, render, state} = setupAudio();
  state.phase = 'Night';
  render();
  assert.equal(played[0].src, 'audio/night-intro.mp3');
  assert.equal(played[0].loop, false);
  played[0].onended();
  assert.equal(played[1].src, 'audio/night-loop.mp3');
  assert.equal(played[1].loop, true);
  state.phase = 'Day';
  render();
  assert.equal(played[1].paused, true);
  assert.equal(played[2].src, 'audio/day-intro.mp3');
});

test('Tiếng vào Day dừng sau 5 giây và không phát lại trong cùng Day', () => {
  const {body, played, render, state, timers} = setupAudio();
  state.phase = 'Day';
  render();
  const dayAudio = played[0];
  const dayTimer = [...timers.values()].find(timer => timer.delay === 5000);
  assert.ok(dayTimer, 'Day phải có thời hạn âm thanh 5 giây');
  dayTimer.callback();
  assert.equal(dayAudio.paused, true);
  render();
  const button = body.children[0].children[0];
  button.fire('click');
  button.fire('click');
  assert.equal(played.length, 1, 'Bật lại âm thanh không phát lại tiếng gáy trong Day');
});

test('GameOver phát đúng nhạc thắng và không lặp lại khi render tiếp', () => {
  const {played, render, state} = setupAudio();
  state.phase = 'GameOver';
  state.gameResult = 'WinnerVillage';
  render();
  assert.equal(played[0].src, 'audio/village-win.mp3');
  render();
  assert.equal(played.length, 1);
});

test('Sói thắng dùng nhạc riêng; reconnect ở Night chỉ phát nhạc nền', () => {
  const {played, render, state} = setupAudio();
  state.phase = 'Night';
  state.reconnecting = true;
  render();
  assert.equal(played[0].src, 'audio/night-loop.mp3');
  state.reconnecting = false;
  state.phase = 'GameOver';
  state.gameResult = 'WinnerWolves';
  render();
  assert.equal(played[0].paused, true);
  assert.equal(played[1].src, 'audio/wolves-win.mp3');
});

test('Thanh âm lượng và nút bật/tắt áp dụng ngay, lưu lựa chọn', () => {
  const {body, played, render, state, storage} = setupAudio();
  state.phase = 'Night';
  render();
  const [button, label, value] = body.children[0].children;
  const slider = label.children[0];
  slider.value = '25';
  slider.fire('input');
  assert.equal(played[0].volume, 0.25);
  assert.equal(value.textContent, '25%');
  button.fire('click');
  assert.equal(played[0].paused, true);
  button.fire('click');
  assert.equal(played[0].paused, false);
  assert.deepEqual(JSON.parse(storage.get('werewolf-audio-settings')),
    {muted: false, volume: 0.25});
});

test('Năm tệp âm thanh của người dùng đã được đặt trong web/audio', () => {
  for (const name of ['night-intro', 'night-loop', 'day-intro', 'village-win', 'wolves-win']) {
    assert.ok(existsSync(join(__dirname, '../web/audio', `${name}.mp3`)));
  }
});
