// Chạy app.js thật trong DOM giả tối thiểu, không cần cài thư viện Node.
// Kiểm tra hành vi UI; không thay thế kiểm tra bố cục trên trình duyệt thật.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {join} = require('node:path');
const vm = require('node:vm');

function setup() {
  class Element {
    constructor() { this.children = []; this.value = ''; this.dataset = {}; this.listeners = {}; }
    replaceChildren() { this.children = []; this.value = ''; }
    appendChild(child) { this.children.push(child); }
    append(...children) { this.children.push(...children); }
    addEventListener(type, handler) { this.listeners[type] = handler; }
    fire(type) { this.listeners[type]({preventDefault() {}}); }
  }
  const elements = new Map();
  const get = id => {
    if (!elements.has(id)) elements.set(id, new Element());
    return elements.get(id);
  };
  let connection;
  class Socket {
    static OPEN = 1;
    constructor() { this.readyState = 1; this.listeners = {}; this.sent = []; connection = this; }
    addEventListener(type, callback) { this.listeners[type] = callback; }
    send(data) { this.sent.push(JSON.parse(data)); }
  }
  const context = vm.createContext({WebSocket: Socket, document: {
    querySelector: selector => get(selector.slice(1)), getElementById: get,
    createElement: () => new Element()
  }});
  vm.runInContext(readFileSync(join(__dirname, '../web/app.js'), 'utf8'), context);
  const message = data => connection.listeners.message({data: JSON.stringify(data)});
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
  return {get, connection, message, snapshot, choose};
}

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

test('Hunter được bỏ qua; role chỉ hiện khi nhận reveal công khai', () => {
  const {get, connection, message, snapshot} = setup();
  snapshot({canShoot: true, resolved: true});
  assert.equal(get('hunter-pass').hidden, false);
  get('hunter-pass').fire('click');
  assert.equal(connection.sent[0].type, 'HunterChoice');
  assert.equal(connection.sent[0].targetId, null);
  assert.equal(get('vote-reveals').children.length, 0);
  message({type: 'PlayerRoleRevealed', roomId: 'R', playerId: 'p2', role: 'Hunter', team: 'Village'});
  assert.match(get('vote-reveals').children[0].textContent, /Hai.*Hunter/);
});

test('Sai phase, người chết và mất kết nối đều khóa thao tác', () => {
  const {get, connection, snapshot, choose} = setup();
  choose(); snapshot({phase: 'Night'});
  assert.equal(get('vote-button').disabled, true);
  snapshot({players: [{playerId: 'p1', alive: false}, {playerId: 'p2', alive: true}]});
  assert.equal(get('vote-button').disabled, true);
  snapshot(); choose(); connection.readyState = 3; connection.listeners.close();
  assert.equal(get('vote-button').disabled, true);
  assert.match(get('voting-status').textContent, /Mất kết nối/);
});
