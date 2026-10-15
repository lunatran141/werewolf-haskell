const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {join} = require('node:path');
const vm = require('node:vm');

function setup(role = 'Villager') {
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
    fire(type) { this.listeners[type]({preventDefault() {}}); }
    querySelector() { return new Element(); }
    showModal() { this.open = true; }
  }
  const elements = new Map();
  const html = readFileSync(join(__dirname, '../web/index.html'), 'utf8');
  const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map(match => match[1]);
  assert.equal(new Set(ids).size, ids.length);
  const get = id => {
    assert.ok(ids.includes(id), `Thiếu #${id}`);
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
  const context = vm.createContext({WebSocket: Socket, console,
    setInterval() { return 1; }, clearInterval() {},
    localStorage: {getItem() { return null; }, setItem() {}},
    document: {body: new Element(), querySelector: selector => get(selector.slice(1)),
      getElementById: get, createElement: () => new Element(), createTextNode: value => value}
  });
  vm.runInContext(readFileSync(join(__dirname, '../web/avatar.js'), 'utf8'), context);
  vm.runInContext(readFileSync(join(__dirname, '../web/app.js'), 'utf8'), context);
  const message = data => connection.listeners.message({data: JSON.stringify(data)});
  connection.listeners.open();
  const players = [{playerId: 'p1', displayName: 'Một', alive: true},
    {playerId: 'p2', displayName: 'Hai', alive: true}];
  message({type: 'LobbySnapshot', roomId: 'R', selfPlayerId: 'p1', hostPlayerId: 'p1', players});
  message({type: 'YourRole', roomId: 'R', role});
  message({type: 'VotingSnapshot', roomId: 'R', phase: 'Day', day: 1,
    players, hasVoted: false, canShoot: false, resolved: false, result: null});
  return {get, message, connection, players};
}

test('Lịch sử chat tách theo ngày, theo kênh và khử tin trùng sequence', () => {
  const {get, message, players} = setup('Werewolf');
  message({type: 'ChatMessage', roomId: 'R', playerId: 'p2', message: 'Ngày một',
    channel: 'PublicDay', day: 1, sequence: 1});
  message({type: 'ChatMessage', roomId: 'R', playerId: 'p2', message: 'Ngày một',
    channel: 'PublicDay', day: 1, sequence: 1});
  assert.equal(get('chat-messages').children.length, 1);
  message({type: 'VotingSnapshot', roomId: 'R', phase: 'Day', day: 2,
    players, hasVoted: false, canShoot: false, resolved: false, result: null});
  message({type: 'ChatMessage', roomId: 'R', playerId: 'p2', message: 'Ngày hai',
    channel: 'PublicDay', day: 2, sequence: 2});
  assert.equal(get('chat-messages').children.length, 1);
  assert.equal(get('chat-day-select').value, '2');
  get('chat-day-select').value = '1'; get('chat-day-select').fire('change');
  assert.equal(get('chat-heading').textContent, 'Chat chung · Ngày 1');
  assert.equal(get('chat-messages').children.length, 1);
  get('chat-wolves-tab').fire('click');
  message({type: 'ChatMessage', roomId: 'R', playerId: 'p1', message: 'Mục tiêu B',
    channel: 'WolvesNight', day: 1, sequence: 3});
  assert.equal(get('chat-heading').textContent, 'Chat Sói · Đêm 1');
  assert.equal(get('chat-messages').children.length, 1);
  assert.equal(get('chat-input').disabled, true, 'Chưa gửi chat Sói bằng contract Chat cũ');
});

test('Snapshot lịch sử từ Server dùng senderId/text và không nhân đôi tin đã nhận', () => {
  const {get, message} = setup();
  const chat = {day: 1, channel: 'PublicDay', messageId: 'm1', sequence: 5,
    senderId: 'p2', text: 'Tin đã lưu'};
  message({type: 'ChatMessage', roomId: 'R', ...chat});
  message({type: 'ChatHistorySnapshot', roomId: 'R', messages: [chat, {...chat,
    messageId: 'm2', sequence: 6, text: 'Tin kế tiếp'}]});
  assert.equal(get('chat-messages').children.length, 2);
});

test('Người không phải Sói không thấy chat riêng; người chết không được gửi', () => {
  const {get, message, connection} = setup();
  assert.equal(get('chat-wolves-tab').hidden, true);
  message({type: 'ChatMessage', roomId: 'R', playerId: 'p2', message: 'Bí mật',
    channel: 'WolvesNight', day: 1, sequence: 1});
  get('chat-wolves-tab').fire('click');
  assert.equal(get('chat-heading').textContent, 'Chat chung · Ngày 1');
  message({type: 'PlayerDied', roomId: 'R', playerId: 'p1'});
  get('chat-input').value = 'Không được gửi'; get('chat-input').fire('input');
  get('chat-form').fire('submit');
  assert.equal(connection.sent.length, 0);
  assert.equal(get('chat-input').disabled, true);
});

test('Không tiết lộ vai khi chết; chỉ GameRolesRevealed ở GameOver mới hiện', () => {
  const {get, message} = setup();
  message({type: 'PlayerRoleRevealed', roomId: 'R', playerId: 'p2', role: 'Werewolf'});
  message({type: 'PlayerDied', roomId: 'R', playerId: 'p2'});
  message({type: 'GameRolesRevealed', roomId: 'R', roles: [{playerId: 'p2', role: 'Werewolf'}]});
  assert.equal(get('revealed-role-list').children.length, 0);
  assert.equal(get('player-list').children[1].classList.contains('is-dead'), true);
  message({type: 'GameFinished', roomId: 'R', result: 'WinnerVillage'});
  assert.equal(get('result-section').hidden, false);
  assert.equal(get('revealed-role-list').children.length, 0);
  message({type: 'GameRolesRevealed', roomId: 'R', roles: [
    {playerId: 'p1', role: 'Villager'}, {playerId: 'p2', role: 'Werewolf'}]});
  assert.equal(get('revealed-role-list').children.length, 2);
});

test('Khả năng của tôi ưu tiên nội dung riêng từ YourRole của Server', () => {
  const {get, message} = setup();
  message({type: 'YourRole', roomId: 'R', role: 'Seer', ability: {
    description: 'Mô tả từ server', phase: 'Night', targetRules: 'Chọn người khác'
  }});
  const ownCard = get('player-list').children[0];
  const button = ownCard.children.find(child => child.className === 'dashboard-ability-button');
  button.fire('click');
  assert.match(get('role-help-text').textContent, /Mô tả từ server/);
  assert.match(get('role-help-text').textContent, /Chọn người khác/);
});
