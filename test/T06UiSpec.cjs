
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {join} = require('node:path');
const vm = require('node:vm');

function setup() {
  class Element {
    constructor() {
      this.children = []; this.value = ''; this.dataset = {}; this.listeners = {}; this.attributes = {};
      this.style = {setProperty() {}};
      const classes = new Set();
      this.classList = {
        add(name) { classes.add(name); },
        toggle(name, enabled) { if (enabled) classes.add(name); else classes.delete(name); },
        contains(name) { return classes.has(name); }
      };
    }
    replaceChildren(...children) { this.children = children; this.value = ''; }
    appendChild(child) { this.children.push(child); }
    append(...children) { this.children.push(...children); }
    addEventListener(type, handler) { this.listeners[type] = handler; }
    setAttribute(name, value) { this.attributes[name] = value; }
    focus() { this.focused = true; }
    fire(type, fields = {}) { this.listeners[type]({preventDefault() {}, ...fields}); }
    querySelector() { return new Element(); }
  }
  const elements = new Map();
  // Mỗi selector phải tồn tại trong HTML thật; bắt lỗi mất panel hoặc trùng ID khi merge.
  const html = readFileSync(join(__dirname, '../web/index.html'), 'utf8');
  const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map(match => match[1]);
  assert.equal(new Set(ids).size, ids.length, 'HTML không được trùng ID');
  const get = id => {
    assert.ok(ids.includes(id), `Không có phần tử #${id}`);
    if (!elements.has(id)) elements.set(id, new Element());
    return elements.get(id);
  };
  let connection;
  let now = 1_000_000;
  let nextIntervalId = 1;
  const intervals = new Map();
  class Socket {
    static OPEN = 1;
    constructor() { this.readyState = 1; this.listeners = {}; this.sent = []; connection = this; }
    addEventListener(type, callback) { this.listeners[type] = callback; }
    send(data) { this.sent.push(JSON.parse(data)); }
  }
  const context = vm.createContext({WebSocket: Socket, console,
    location: {protocol: 'http:', host: 'localhost'},
    Date: class extends Date { static now() { return now; } },
    setInterval(callback) { const id = nextIntervalId++; intervals.set(id, callback); return id; },
    clearInterval(id) { intervals.delete(id); },
    setTimeout() { return nextIntervalId++; }, clearTimeout() {},
    localStorage: {getItem() { return null; }, setItem() {}}, document: {
    body: new Element(),
    querySelector: selector => selector.startsWith('#') ? get(selector.slice(1)) : null, getElementById: get,
    createElement: () => new Element()
  }});
  vm.runInContext(readFileSync(join(__dirname, '../web/avatar.js'), 'utf8'), context);
  for (const file of ['protocol.js', 'state.js', 'ui.js']) {
    vm.runInContext(readFileSync(join(__dirname, '../web', file), 'utf8'), context);
  }
  vm.runInContext(readFileSync(join(__dirname, '../web/app.js'), 'utf8'), context);
  let currentRole = null;
  let currentPhase = 'Lobby';
  let currentDay = 0;
  let version = 0;
  const rawMessage = data => connection.listeners.message({data: JSON.stringify(data)});
  const sendTargets = (data = {}) => {
    const list = data.players ?? players;
    const alive = list.filter(player => player.alive);
    const otherIds = alive.filter(player => player.playerId !== 'p1').map(player => player.playerId);
    const action = data.canShoot ? 'HunterShot' : currentPhase === 'Voting'
      ? 'Vote' : currentPhase === 'Night' ? ({Werewolf: 'WolfTarget', Seer: 'SeerTarget',
        Guard: 'GuardTarget', Witch: 'WitchPoison'})[currentRole] : null;
    const ids = action === 'GuardTarget' ? alive.map(player => player.playerId) : otherIds;
    rawMessage({type: 'ValidTargetsSnapshot', roomId: 'R', phase: currentPhase,
      day: currentDay, version: ++version,
      targets: action ? [{action, playerIds: data.hasVoted ? [] : ids}] : []});
  };
  const message = data => {
    rawMessage(data);
    if (data.type === 'YourRole') currentRole = data.role;
    if (data.type === 'VotingSnapshot' && data.roomId === 'R') {
      currentPhase = data.phase; currentDay = data.day;
      if (currentPhase !== 'Lobby') sendTargets(data);
    }
    if (data.type === 'CommandRejected' && data.requestId === connection.sent.at(-1)?.requestId) {
      sendTargets();
    }
  };
  connection.listeners.open();
  const players = [
    {playerId: 'p1', displayName: 'Một', alive: true},
    {playerId: 'p2', displayName: 'Hai', alive: true},
    {playerId: 'p3', displayName: 'Ba', alive: false}
  ];
  message({type: 'LobbySnapshot', roomId: 'R', selfPlayerId: 'p1', hostPlayerId: 'p1', players});
  const snapshot = changes => message({type: 'VotingSnapshot', roomId: 'R', phase: 'Voting', day: 1,
    players, hasVoted: false, canShoot: false, resolved: false, result: null, ...changes});
  snapshot();
  const choose = () => { get('vote-target').value = 'p2'; get('vote-target').fire('change'); };
  const advance = ms => { now += ms; for (const callback of [...intervals.values()]) callback(); };
  return {get, connection, message, rawMessage, snapshot, choose, advance};
}

test('Sao chớp độc lập và đồng hồ Voting 60 giây không reset khi có snapshot mới', () => {
  const {get, snapshot, advance} = setup();
  assert.equal(get('twinkling-stars').children.length, 160);
  assert.equal(get('vote-clock-value').textContent, '01:00');
  advance(15_000);
  assert.equal(get('vote-clock-value').textContent, '00:45');
  snapshot({hasVoted: true});
  assert.equal(get('vote-clock-value').textContent, '00:45');
  advance(45_000);
  assert.equal(get('vote-clock-value').textContent, '00:00');
  assert.equal(get('vote-button').disabled, true);
});

test('Dashboard có 9 ô từ snapshot thật và chỉ ô của mình hiện vai riêng', () => {
  const {get, message} = setup();
  assert.match(get('appearance-preview').children[0].innerHTML, /avatar-chibi-svg/);
  const grid = get('player-list');
  assert.equal(grid.children.length, 9);
  assert.equal(grid.children[0].classList.contains('is-me'), true);
  assert.equal(grid.children[2].classList.contains('is-dead'), true);
  assert.equal(grid.children[8].classList.contains('is-empty'), true);
  message({type: 'YourRole', roomId: 'R', role: 'Seer'});
  assert.equal(grid.children[0].children.some(child => child.textContent === 'Tiên Tri'), true);
  assert.equal(grid.children[1].children.some(child => child.textContent === 'Tiên Tri'), false);
});

test('Bỏ phiếu trên ô bằng bàn phím giữ focus và giải thích ô bị khóa', () => {
  const {get} = setup();
  const grid = get('player-list');
  assert.match(grid.children[0].children.find(child => child.className === 'dashboard-card-footer').textContent, /Không chọn chính mình/);
  assert.match(grid.children[2].children.find(child => child.className === 'dashboard-card-footer').textContent, /Đã bị loại/);
  grid.children[1].fire('keydown', {key: 'Enter'});
  assert.equal(get('vote-target').value, 'p2');
  assert.equal(grid.children[1].focused, true);
  assert.equal(grid.children[1].attributes['aria-pressed'], 'true');
});

test('Nút tạo phòng chuyển đúng chế độ và avatar dùng SVG từ folder UI', () => {
  const {get} = setup();
  const svg = get('appearance-preview').children[0].innerHTML;
  assert.match(svg, /avatar-chibi-svg/);
  assert.match(svg, /ellipse cx="40" cy="44"/);
  get('host-mode-button').fire('click');
  assert.equal(get('join-button').hidden, true);
  assert.equal(get('create-button').hidden, false);
  get('join-mode-button').fire('click');
  assert.equal(get('join-button').hidden, false);
  assert.equal(get('create-button').hidden, true);
});

test('Chỉ chọn người sống khác mình; chặn gửi lặp và chờ đúng request', () => {
  const {get, connection, message, snapshot, choose} = setup();
  assert.deepEqual(get('vote-target').children.map(p => p.value), ['', 'p2']);
  choose();
  get('vote-form').fire('submit');
  get('vote-form').fire('submit');
  assert.equal(connection.sent.length, 1);
  const command = connection.sent[0];
  assert.equal(command.type, 'Vote');
  assert.equal(command.targetId, 'p2');
  assert.equal(command.actorId, undefined);
  message({type: 'ActionAccepted', roomId: 'R', requestId: 'khac'});
  assert.equal(get('vote-button').disabled, true);
  snapshot({hasVoted: true});
  message({type: 'ActionAccepted', roomId: 'R', requestId: command.requestId});
  assert.equal(get('vote-button').disabled, true);
  assert.match(get('voting-status').textContent, /đã nhận phiếu/);
});

test('Từ chối có thông báo và cho thử lại; sai phòng bị bỏ qua', () => {
  const {get, connection, message, choose, snapshot} = setup();
  choose(); get('vote-form').fire('submit');
  message({type: 'CommandRejected', requestId: connection.sent[0].requestId, message: 'Mục tiêu sai'});
  assert.equal(get('message').textContent, 'Mục tiêu sai');
  assert.equal(get('vote-target').disabled, false);
  choose();
  assert.equal(get('vote-button').disabled, false);
  snapshot({roomId: 'OTHER', hasVoted: true});
  assert.equal(get('vote-button').disabled, false);
});

test('Hòa/không phiếu và vòng mới hiển thị đúng, xóa tally dù Day cùng số vòng', () => {
  const {get, message, snapshot} = setup();
  message({type: 'VotingResolved', roomId: 'R', tally: [['p1', 1], ['p2', 1]], targetId: null});
  assert.match(get('vote-result').textContent, /Hòa phiếu/);
  assert.equal(get('vote-tally').children.length, 2);
  snapshot({phase: 'Night', day: 2});
  snapshot({phase: 'Day', day: 2});
  snapshot({day: 2});
  assert.equal(get('vote-tally').children.length, 0);
  assert.equal(get('vote-result').textContent, '');
  message({type: 'VotingResolved', roomId: 'R', tally: [], targetId: null});
  assert.match(get('vote-result').textContent, /Không có phiếu/);
});

test('Hunter được bỏ qua; vai người chết vẫn ẩn trước GameOver', () => {
  const {get, connection, message, snapshot} = setup();
  message({type: 'YourRole', roomId: 'R', role: 'Hunter'});
  snapshot({canShoot: true, resolved: true});
  assert.equal(get('hunter-action-panel').hidden, false);
  assert.equal(get('hunter-pass').disabled, false);
  get('hunter-pass').fire('click');
  assert.equal(connection.sent[0].type, 'HunterAction');
  assert.deepEqual(connection.sent[0].choice, {action: 'HunterPass'});
  assert.equal(get('vote-reveals').children.length, 0);
  message({type: 'PlayerRoleRevealed', roomId: 'R', playerId: 'p2', role: 'Hunter', team: 'Village'});
  assert.equal(get('vote-reveals').children.length, 0);
  assert.equal(get('revealed-role-list').children.length, 0);
});

test('Sai phase, người chết và mất kết nối đều khóa thao tác', () => {
  const {get, connection, snapshot, choose} = setup();
  choose(); snapshot({phase: 'Night'});
  assert.equal(get('vote-button').disabled, true);
  snapshot({players: [{playerId: 'p1', alive: false}, {playerId: 'p2', alive: true}]});
  assert.equal(get('vote-button').disabled, true);
  snapshot(); choose(); connection.readyState = 3; connection.listeners.close();
  assert.equal(get('vote-button').disabled, true);
  assert.match(get('connection-status').textContent, /Mất kết nối/);
  assert.equal(get('voting-section').hidden, true);
  assert.equal(get('join-section').hidden, true);
  assert.equal(get('lobby-section').hidden, false);
  assert.equal(get('player-list').children.length, 9);
});

test('Giữ StartGame và Night UI của T05 sau khi ghép Voting', () => {
  const {get, connection, message, snapshot} = setup();
  snapshot({phase: 'Lobby', players: Array.from({length: 8}, (_, i) =>
    ({playerId: `p${i + 1}`, displayName: `Người ${i + 1}`, alive: true, ready: true}))});
  assert.equal(get('start-button').disabled, false);
  get('start-button').fire('click');
  assert.equal(connection.sent[0].type, 'StartGame');
  message({type: 'YourRole', roomId: 'R', role: 'Seer'});
  message({type: 'PhaseChanged', roomId: 'R', phase: 'Night'});
  snapshot({phase: 'Night'});
  assert.equal(get('night-section').hidden, false);
  assert.equal(get('seer-action-panel').hidden, false);
  assert.equal(get('wolf-action-panel').hidden, true);
  get('seer-target').value = 'p2'; get('seer-target').fire('change');
  get('seer-submit').fire('click');
  assert.equal(connection.sent[1].type, 'NightAction');
  assert.deepEqual(connection.sent[1].choice, {action: 'SeerTarget', targetId: 'p2'});
  message({type: 'NightActionAccepted', roomId: 'R'});
  message({type: 'SeerResult', roomId: 'R', team: 'Wolves'});
  assert.match(get('seer-result-text').textContent, /Sói/);
  assert.equal(get('seer-submit').disabled, true);
  snapshot({phase: 'Day'});
  snapshot({phase: 'Voting'});
  assert.equal(get('night-section').hidden, true);
  assert.equal(get('voting-section').hidden, false);
});

test('Hunter dùng cùng nút bắn ở Night và Voting, phản hồi có hunterId', () => {
  for (const phase of ['Night', 'Voting']) {
    const {get, connection, message, snapshot} = setup();
    message({type: 'YourRole', roomId: 'R', role: 'Hunter'});
    snapshot({phase, canShoot: true, resolved: true});
    get('hunter-target').value = 'p2'; get('hunter-target').fire('change');
    get('hunter-shoot').fire('click');
    assert.deepEqual(connection.sent[0].choice, {action: 'HunterShot', targetId: 'p2'});
    assert.equal(get('hunter-shoot').disabled, true);
    message({type: 'HunterShotResolved', roomId: 'R', hunterId: 'p1', targetId: 'p2'});
    assert.equal(get('hunter-pass').disabled, true);
  }
});

test('Ô mục tiêu chờ danh sách riêng từ Server và bỏ snapshot cũ', () => {
  const {get, rawMessage, message, connection} = setup();
  rawMessage({type: 'VotingSnapshot', roomId: 'R', phase: 'Day', day: 2,
    players: [{playerId: 'p1', displayName: 'Một', alive: true},
      {playerId: 'p2', displayName: 'Hai', alive: true}],
    hasVoted: false, canShoot: false, resolved: false, result: null});
  rawMessage({type: 'VotingSnapshot', roomId: 'R', phase: 'Voting', day: 2,
    players: [{playerId: 'p1', displayName: 'Một', alive: true},
      {playerId: 'p2', displayName: 'Hai', alive: true}],
    hasVoted: false, canShoot: false, resolved: false, result: null});
  assert.equal(get('vote-target').disabled, true);
  assert.deepEqual(get('vote-target').children.map(option => option.value), ['']);
  rawMessage({type: 'ValidTargetsSnapshot', roomId: 'R', phase: 'Voting', day: 1,
    version: 99, targets: [{action: 'Vote', playerIds: ['p2']}]});
  assert.equal(get('vote-target').disabled, true, 'snapshot vòng cũ không mở quyền');
  message({type: 'ValidTargetsSnapshot', roomId: 'R', phase: 'Voting', day: 2,
    version: 100, targets: [{action: 'Vote', playerIds: ['p2']}]});
  assert.equal(get('vote-target').disabled, false);
  assert.deepEqual(get('vote-target').children.map(option => option.value), ['', 'p2']);
  get('vote-target').value = 'p2'; get('vote-target').fire('change');
  get('vote-form').fire('submit');
  assert.equal(connection.sent.at(-1).targetId, 'p2');
});
