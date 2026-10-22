const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {join} = require('node:path');
const vm = require('node:vm');

function setup(role = 'Villager', savedSession = null) {
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
    fire(type, fields = {}) { this.listeners[type]({preventDefault() {}, stopPropagation() {}, ...fields}); }
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
  const connections = [];
  const timers = [];
  const storage = new Map();
  if (savedSession) storage.set('werewolf-session', JSON.stringify(savedSession));
  class Socket {
    static OPEN = 1;
    constructor() { this.readyState = 1; this.listeners = {}; this.sent = []; this.closed = false; connection = this; connections.push(this); }
    addEventListener(type, callback) { this.listeners[type] = callback; }
    send(data) { this.sent.push(JSON.parse(data)); }
    close() { this.closed = true; }
  }
  const context = vm.createContext({WebSocket: Socket, console,
    location: {protocol: 'http:', host: 'localhost'},
    setInterval() { return 1; }, clearInterval() {}, setTimeout(callback) { timers.push(callback); return timers.length; }, clearTimeout() {},
    localStorage: {
      getItem(key) { return storage.get(key) ?? null; },
      setItem(key, value) { storage.set(key, value); },
      removeItem(key) { storage.delete(key); }
    },
    document: {body: new Element(), querySelector: selector => selector.startsWith('#') ? get(selector.slice(1)) : null,
      getElementById: get, createElement: () => new Element(), createTextNode: value => value}
  });
  vm.runInContext(readFileSync(join(__dirname, '../web/avatar.js'), 'utf8'), context);
  for (const file of ['protocol.js', 'state.js', 'ui.js']) {
    vm.runInContext(readFileSync(join(__dirname, '../web', file), 'utf8'), context);
  }
  vm.runInContext(readFileSync(join(__dirname, '../web/app.js'), 'utf8'), context);
  let currentRole = role;
  let currentPhase = 'Lobby';
  let currentDay = 0;
  let version = 0;
  let wolfTeam = [];
  const rawMessage = data => connection.listeners.message({data: JSON.stringify(data)});
  const sendTargets = (data = {}) => {
    const list = data.players ?? players;
    const alive = list.filter(player => player.alive);
    let ids = alive.filter(player => player.playerId !== 'p1').map(player => player.playerId);
    const action = data.canShoot ? 'HunterShot' : currentPhase === 'Voting'
      ? 'Vote' : currentPhase === 'Night' ? ({Werewolf: 'WolfTarget', Seer: 'SeerTarget',
        Guard: 'GuardTarget', Witch: 'WitchPoison'})[currentRole] : null;
    if (action === 'WolfTarget') ids = ids.filter(id => !wolfTeam.includes(id));
    if (action === 'GuardTarget') ids = alive.map(player => player.playerId);
    rawMessage({type: 'ValidTargetsSnapshot', roomId: 'R', phase: currentPhase,
      day: currentDay, version: ++version,
      targets: action ? [{action, playerIds: data.hasVoted ? [] : ids}] : []});
  };
  const message = data => {
    rawMessage(data);
    if (data.type === 'YourRole') currentRole = data.role;
    if (data.type === 'WolfTeam') wolfTeam = data.playerIds;
    if (data.type === 'VotingSnapshot') {
      currentPhase = data.phase; currentDay = data.day;
      if (currentPhase !== 'Lobby') sendTargets(data);
    }
    if (data.type === 'CommandRejected' && data.requestId === connection.sent.at(-1)?.requestId) {
      sendTargets();
    }
  };
  connection.listeners.open();
  const players = [{playerId: 'p1', displayName: 'Một', alive: true},
    {playerId: 'p2', displayName: 'Hai', alive: true}];
  message({type: 'LobbySnapshot', roomId: 'R', selfPlayerId: 'p1', hostPlayerId: 'p1', players});
  message({type: 'YourRole', roomId: 'R', role});
  message({type: 'VotingSnapshot', roomId: 'R', phase: 'Day', day: 1,
    players, hasVoted: false, canShoot: false, resolved: false, result: null});
  return {get, message, rawMessage, get connection() { return connection; }, connections, timers, players, storage};
}

test('Trình duyệt dùng token đã lưu để reconnect đúng phòng', () => {
  const saved = {roomId: 'R', playerId: 'p1', sessionToken: 'secret-token', lastVersion: 42};
  const {connection, message, storage} = setup('Villager', saved);
  assert.equal(connection.sent[0].type, 'Reconnect');
  assert.equal(connection.sent[0].roomId, 'R');
  assert.equal(connection.sent[0].sessionToken, 'secret-token');
  assert.equal('lastVersion' in connection.sent[0], false,
    'full snapshot is the recovery contract; no server cursor is sent');

  message({type: 'SessionEstablished', roomId: 'R', playerId: 'p1', sessionToken: 'new-token'});
  assert.equal(JSON.parse(storage.get('werewolf-session')).sessionToken, 'new-token');
  message({type: 'RoomVersion', roomId: 'R', version: 47});
  assert.equal(JSON.parse(storage.get('werewolf-session')).lastVersion, 47);
  message({type: 'RoomVersion', roomId: 'R', version: 49});
  assert.equal(connection.closed, true, 'server reconnect se co snapshot khi cursor bi nhay');
  assert.equal(JSON.parse(storage.get('werewolf-session')).lastVersion, 47);
});

test('Lệnh đang chờ được gửi lại sau reconnect với cùng requestId', () => {
  const saved = {roomId: 'R', playerId: 'p1', sessionToken: 'secret-token'};
  const {get, message, connection, connections, timers} = setup('Villager', saved);
  message({type: 'SessionEstablished', roomId: 'R', playerId: 'p1', sessionToken: 'secret-token'});
  message({type: 'RoomVersion', roomId: 'R', version: 1});
  get('chat-input').value = 'xin chao';
  get('chat-form').fire('submit');
  const firstSocket = connection;
  const original = firstSocket.sent.at(-1);
  assert.equal(original.type, 'Chat');

  firstSocket.listeners.close();
  timers.at(-1)();
  const reconnectedSocket = connections.at(-1);
  reconnectedSocket.listeners.open();
  message({type: 'SessionEstablished', roomId: 'R', playerId: 'p1', sessionToken: 'secret-token'});
  message({type: 'LobbySnapshot', roomId: 'R', selfPlayerId: 'p1', hostPlayerId: 'p1', players: []});
  message({type: 'RoomVersion', roomId: 'R', version: 1});

  const retried = reconnectedSocket.sent.at(-1);
  assert.equal(retried.type, 'Chat');
  assert.equal(retried.requestId, original.requestId);
  assert.equal(retried.message, original.message);
});

test('Phiên reconnect cũ tự được xóa và không hiện cảnh báo khi mở lại trang', () => {
  const saved = {roomId: 'ROOM-OLD', playerId: 'p1', sessionToken: 'expired-token'};
  const {get, message, storage} = setup('Villager', saved);

  message({type: 'CommandRejected', requestId: null, code: 'INVALID_SESSION',
    message: 'Session is no longer valid.'});

  assert.equal(storage.has('werewolf-session'), false);
  assert.equal(get('join-section').hidden, false);
  assert.equal(get('lobby-section').hidden, true);
  assert.equal(get('message').textContent, '');
});

test('Mỗi người có thể tự rời phòng và quay về màn hình đầu sau GameOver', () => {
  const {get, message, connection, storage} = setup();
  storage.set('werewolf-session', JSON.stringify({roomId: 'R', playerId: 'p1'}));
  message({type: 'GameFinished', roomId: 'R', result: 'WinnerVillage'});
  assert.equal(get('result-section').hidden, false);
  assert.equal(get('return-home-button').hidden, false);

  get('return-home-button').fire('click');
  const command = connection.sent.at(-1);
  assert.equal(command.type, 'LeaveGame');
  assert.equal(command.roomId, 'R');

  message({type: 'PlayerLeft', roomId: 'R', playerId: 'p1'});
  assert.equal(get('result-section').hidden, true);
  assert.equal(get('join-section').hidden, false);
  assert.equal(storage.has('werewolf-session'), false);
});

test('Người không phải Host cũng có nút tự rời phòng sau GameOver', () => {
  const {get, message, connection} = setup();
  message({type: 'LobbySnapshot', roomId: 'R', selfPlayerId: 'p1', hostPlayerId: 'p2',
    players: [{playerId: 'p1', displayName: 'Một', alive: true},
      {playerId: 'p2', displayName: 'Hai', alive: true}]});
  message({type: 'GameFinished', roomId: 'R', result: 'WinnerWolves'});
  assert.equal(get('return-home-button').hidden, false);
  get('return-home-button').fire('click');
  assert.equal(connection.sent.at(-1).type, 'LeaveGame');
});

test('Lịch sử chat tách theo ngày, theo kênh và khử tin trùng sequence', () => {
  const {get, message, players} = setup('Werewolf');
  message({type: 'ChatMessage', roomId: 'R', playerId: 'p2', message: 'Ngày một',
    channel: 'PublicDay', day: 1, sequence: 1});
  message({type: 'ChatMessage', roomId: 'R', playerId: 'p2', message: 'Ngày một',
    channel: 'PublicDay', day: 1, sequence: 1});
  assert.equal(get('chat-messages').children.length, 2);
  assert.equal(get('chat-messages').children[0].textContent, 'Ngày 1 bắt đầu');
  message({type: 'VotingSnapshot', roomId: 'R', phase: 'Day', day: 2,
    players, hasVoted: false, canShoot: false, resolved: false, result: null});
  message({type: 'ChatMessage', roomId: 'R', playerId: 'p2', message: 'Ngày hai',
    channel: 'PublicDay', day: 2, sequence: 2});
  assert.equal(get('chat-messages').children.length, 2);
  assert.equal(get('chat-day-select').value, '2');
  get('chat-day-select').value = '1'; get('chat-day-select').fire('change');
  assert.equal(get('chat-heading').textContent, 'Chat chung · Ngày 1');
  assert.equal(get('chat-messages').children.length, 2);
  get('chat-wolves-tab').fire('click');
  message({type: 'ChatMessage', roomId: 'R', playerId: 'p1', message: 'Mục tiêu B',
    channel: 'WolvesNight', day: 1, sequence: 3});
  assert.equal(get('chat-heading').textContent, 'Chat Sói · Đêm 2');
  assert.equal(get('chat-input').disabled, true, 'Chat Sói không gửi trong pha Day');
  get('chat-day-select').value = '1'; get('chat-day-select').fire('change');
  assert.equal(get('chat-heading').textContent, 'Chat Sói · Đêm 1');
  assert.equal(get('chat-messages').children.length, 2);
  assert.equal(get('chat-messages').children[0].textContent, 'Đêm 1');
});

test('Sói còn sống gửi được chat riêng trong Night với channel WolvesNight', () => {
  const {get, message, connection, players} = setup('Werewolf');
  message({type: 'VotingSnapshot', roomId: 'R', phase: 'Night', day: 1,
    players, hasVoted: false, canShoot: false, resolved: false, result: null});
  get('chat-wolves-tab').fire('click');
  get('chat-input').value = 'Chọn người số 2';
  get('chat-input').fire('input');
  assert.equal(get('chat-input').disabled, false);
  get('chat-form').fire('submit');
  assert.equal(connection.sent.length, 1);
  assert.equal(connection.sent[0].type, 'Chat');
  assert.equal(connection.sent[0].channel, 'WolvesNight');
  assert.equal(connection.sent[0].message, 'Chọn người số 2');
});

test('Sói thấy tiến độ phối hợp và mục tiêu cuối sau khi khóa phiếu', () => {
  const {get, message, players} = setup('Werewolf');
  message({type: 'VotingSnapshot', roomId: 'R', phase: 'Night', day: 1,
    players, hasVoted: false, canShoot: false, resolved: false, result: null});
  message({type: 'WolfVoteUpdated', roomId: 'R', submitted: 1, total: 3});
  assert.match(get('wolf-vote-status').textContent, /1\/3 Sói/);
  message({type: 'WolfTargetLocked', roomId: 'R', targetId: 'p2'});
  assert.match(get('wolf-vote-status').textContent, /Hai/);
});

test('Danh sách mục tiêu Sói loại chính mình và các đồng đội do Server gửi', () => {
  const {get, message, players} = setup('Werewolf');
  message({type: 'WolfTeam', roomId: 'R', playerIds: ['p1', 'p2']});
  message({type: 'VotingSnapshot', roomId: 'R', phase: 'Night', day: 1,
    players, hasVoted: false, canShoot: false, resolved: false, result: null});
  const targetValues = get('wolf-target').children.map(option => option.value);
  assert.deepEqual(targetValues, ['']);
});

test('Dashboard dùng appearance của Server cho mọi người chơi', () => {
  const {get, message} = setup();
  const appearance = {hair: 'long', hairColor: '#ABCDEF', skin: '#C28865',
    outfit: '#064E3B', accessory: 'halo'};
  message({type: 'LobbySnapshot', roomId: 'R', selfPlayerId: 'p1', hostPlayerId: 'p1',
    players: [{playerId: 'p1', displayName: 'Một', alive: true, appearance},
      {playerId: 'p2', displayName: 'Hai', alive: true, appearance}]});
  const secondAvatar = get('player-list').children[1].children[1];
  assert.match(secondAvatar.innerHTML, /#ABCDEF/i);
  assert.match(secondAvatar.innerHTML, /#064E3B/i);
});

test('Create/Join gửi ngoại hình đã chọn tới Server', () => {
  const {get, connection} = setup();
  get('room-id').value = 'ROOM-AVATAR';
  get('player-name').value = 'Người chơi mới';
  get('appearance-hair').value = 'ponytail';
  get('appearance-hair-color').value = '#EC4899';
  get('appearance-skin').value = '#C28865';
  get('appearance-outfit').value = '#064E3B';
  get('appearance-accessory').value = 'flower_crown';

  get('join-form').fire('submit');

  const command = connection.sent.at(-1);
  assert.equal(command.type, 'JoinGame');
  assert.equal(command.roomId, 'ROOM-AVATAR');
  assert.deepEqual(command.appearance, {
    hair: 'ponytail', hairColor: '#EC4899', skin: '#C28865',
    outfit: '#064E3B', accessory: 'flower_crown'
  });
});

test('Có thể chọn mục tiêu Voting trực tiếp bằng ô người chơi', () => {
  const {get, message, players} = setup();
  message({type: 'VotingSnapshot', roomId: 'R', phase: 'Voting', day: 1,
    players, hasVoted: false, canShoot: false, resolved: false, result: null});
  const secondCard = get('player-list').children[1];
  assert.equal(secondCard.classList.contains('is-targetable'), true);
  secondCard.fire('click');
  assert.equal(get('vote-target').value, 'p2');
  assert.equal(get('player-list').children[1].classList.contains('is-selected-target'), true);
  assert.equal(get('vote-button').disabled, false);
});

test('Có thể chọn mục tiêu Night Action trực tiếp bằng ô người chơi', () => {
  const {get, message, players} = setup('Seer');
  message({type: 'VotingSnapshot', roomId: 'R', phase: 'Night', day: 1,
    players, hasVoted: false, canShoot: false, resolved: false, result: null});
  get('player-list').children[1].fire('click');
  assert.equal(get('seer-target').value, 'p2');
  assert.equal(get('seer-submit').disabled, false);
});

test('Snapshot lịch sử từ Server dùng senderId/text và không nhân đôi tin đã nhận', () => {
  const {get, message} = setup();
  const chat = {day: 1, channel: 'PublicDay', messageId: 'm1', sequence: 5,
    senderId: 'p2', text: 'Tin đã lưu'};
  message({type: 'ChatMessage', roomId: 'R', ...chat});
  message({type: 'ChatHistorySnapshot', roomId: 'R', messages: [chat, {...chat,
    messageId: 'm2', sequence: 6, text: 'Tin kế tiếp'}]});
  assert.equal(get('chat-messages').children.length, 3);
});

test('Server đồng bộ thời gian Day/Voting và đồng hồ Day ẩn khi sang Night', () => {
  const {get, message, players} = setup();
  assert.equal(get('day-clock').hidden, false);
  assert.match(get('day-clock-value').textContent, /^0[23]:[0-5][0-9]$/);
  message({type: 'PhaseTimeRemaining', roomId: 'R', phase: 'Day', day: 1,
    remainingMs: 120000});
  assert.match(get('day-clock-value').textContent, /^02:00$/);
  message({type: 'VotingSnapshot', roomId: 'R', phase: 'Night', day: 1,
    players, hasVoted: false, canShoot: false, resolved: false, result: null});
  assert.equal(get('day-clock').hidden, true);
  message({type: 'VotingSnapshot', roomId: 'R', phase: 'Voting', day: 1,
    players, hasVoted: false, canShoot: false, resolved: false, result: null});
  message({type: 'PhaseTimeRemaining', roomId: 'R', phase: 'Voting', day: 1,
    remainingMs: 30000});
  assert.equal(get('vote-clock-value').textContent, '00:30');
});

test('Chỉ hiển thị bảng Voting sau khi Server chuyển đúng sang Voting', () => {
  const {get, message, players} = setup('Seer');
  assert.equal(get('voting-section').hidden, true, 'Day chỉ hiện phần thảo luận');

  message({type: 'VotingSnapshot', roomId: 'R', phase: 'Night', day: 1,
    players, hasVoted: false, canShoot: false, resolved: false, result: null});
  assert.equal(get('voting-section').hidden, true, 'Night phải chờ các vai hành động');

  message({type: 'VotingSnapshot', roomId: 'R', phase: 'Voting', day: 1,
    players, hasVoted: false, canShoot: false, resolved: false, result: null});
  assert.equal(get('voting-section').hidden, false);
  assert.equal(get('voting-title').textContent, 'Bỏ phiếu · Vòng 1');
});

test('Kết quả soi vẫn hiện khi Tiên Tri là người cuối cùng và Server chuyển sang Day', () => {
  const {get, message, players} = setup('Seer');
  message({type: 'VotingSnapshot', roomId: 'R', phase: 'Night', day: 1,
    players, hasVoted: false, canShoot: false, resolved: false, result: null});

  message({type: 'SeerResult', roomId: 'R', team: 'Wolves'});
  message({type: 'PhaseChanged', roomId: 'R', phase: 'Day'});
  message({type: 'VotingSnapshot', roomId: 'R', phase: 'Day', day: 1,
    players, hasVoted: false, canShoot: false, resolved: false, result: null});

  assert.equal(get('seer-day-result-panel').hidden, false);
  assert.match(get('seer-day-result-text').textContent, /phe Sói/);

  message({type: 'PhaseChanged', roomId: 'R', phase: 'Night'});
  assert.equal(get('seer-day-result-panel').hidden, true,
    'Đêm mới phải xóa kết quả soi của đêm trước');
});

test('Nút bỏ qua thảo luận chờ đủ người sống rồi Server mới mở Voting', () => {
  const {get, message, connection, players} = setup();
  message({type: 'DiscussionSkipState', roomId: 'R', submitted: 0,
    total: 2, hasSkipped: false});
  assert.equal(get('discussion-skip-panel').hidden, false);
  assert.match(get('discussion-skip-status').textContent, /0\/2/);

  get('discussion-skip-button').fire('click');
  assert.equal(connection.sent.at(-1).type, 'SkipDiscussion');

  message({type: 'ActionAccepted', roomId: 'R',
    requestId: connection.sent.at(-1).requestId});
  message({type: 'DiscussionSkipState', roomId: 'R', submitted: 1,
    total: 2, hasSkipped: true});
  assert.equal(get('discussion-skip-button').disabled, true);
  assert.match(get('discussion-skip-button').textContent, /Chờ người còn lại/);

  message({type: 'VotingSnapshot', roomId: 'R', phase: 'Voting', day: 1,
    players, hasVoted: false, canShoot: false, resolved: false, result: null});
  assert.equal(get('discussion-skip-panel').hidden, true);
  assert.equal(get('voting-section').hidden, false);
});

test('Phù Thủy chờ Sói chốt phiếu rồi mới được cứu, dùng độc hoặc bỏ lượt', () => {
  const {get, message, connection, players} = setup('Witch');
  message({type: 'VotingSnapshot', roomId: 'R', phase: 'Night', day: 1,
    players, hasVoted: false, canShoot: false, resolved: false, result: null});
  assert.equal(get('witch-victim-panel').hidden, false);
  assert.match(get('witch-victim-text').textContent, /Đang chờ tất cả Sói/);
  assert.equal(get('witch-heal').disabled, true);
  assert.equal(get('witch-target').disabled, true);
  assert.equal(get('witch-pass').disabled, true);

  message({type: 'WitchVictimNotice', roomId: 'R', victimId: 'p2'});
  assert.match(get('witch-victim-text').textContent, /Hai/);
  assert.equal(get('witch-heal').disabled, false);
  assert.equal(get('witch-target').disabled, false);
  assert.equal(get('witch-pass').disabled, false);
  get('witch-heal').fire('click');
  assert.equal(connection.sent.length, 1);
  assert.equal(connection.sent[0].choice.action, 'WitchHeal');
});

test('Reconnect giữ trạng thái hành động và thuốc riêng của Phù Thủy', () => {
  const {get, message, players} = setup('Witch');
  message({type: 'VotingSnapshot', roomId: 'R', phase: 'Night', day: 2,
    players, hasVoted: false, canShoot: false, resolved: false, result: null});
  message({type: 'WitchVictimNotice', roomId: 'R', victimId: 'p2'});
  message({type: 'PrivateActionState', roomId: 'R', nightActionSubmitted: true,
    witchHealReady: false, witchPoisonReady: true, lastProtectedId: null});
  assert.equal(get('witch-heal').disabled, true);
  assert.equal(get('witch-poison').disabled, true, 'Đã gửi action trong đêm nên mọi nút phải khóa');
  assert.match(get('night-status').textContent, /xác nhận/);
});

test('Thợ Săn còn sống không thấy bộ chọn bắn; chỉ mở khi Server cấp quyền', () => {
  const {get, message, players} = setup('Hunter');
  message({type: 'VotingSnapshot', roomId: 'R', phase: 'Night', day: 1,
    players, hasVoted: false, canShoot: false, resolved: false, result: null});
  assert.equal(get('hunter-action-panel').hidden, true);
  assert.equal(get('hunter-choice-panel').hidden, true);
  assert.equal(get('night-waiting-panel').hidden, false);
  assert.match(get('night-status').textContent, /không có hành động ban đêm/);
  assert.match(get('hunter-status').textContent, /đang còn sống/);
  message({type: 'HunterShotPending', roomId: 'R'});
  assert.equal(get('hunter-action-panel').hidden, false);
  assert.equal(get('hunter-choice-panel').hidden, false);
  assert.equal(get('night-waiting-panel').hidden, true);
  assert.equal(get('hunter-pass').disabled, false);
});

test('Thông báo hệ thống về kết quả phiếu được giữ trong lịch sử đúng ngày', () => {
  const {get, message, players} = setup();
  message({type: 'ChatMessage', roomId: 'R', day: 1, channel: 'PublicDay',
    messageId: 'system-1', sequence: 1, senderId: '__system__',
    text: 'Kết quả bỏ phiếu vòng 1: Hai 2 phiếu. Hai đã chết.'});
  message({type: 'VotingSnapshot', roomId: 'R', phase: 'Night', day: 2,
    players, hasVoted: false, canShoot: false, resolved: false, result: null});
  assert.equal(get('chat-day-select').value, '1',
    'Sang Night mới vẫn giữ ngày vừa chốt để nhìn thấy kết quả ngay');
  const systemLine = get('chat-messages').children[1];
  assert.equal(systemLine.className, 'chat-system-message');
  assert.match(systemLine.textContent, /Kết quả bỏ phiếu vòng 1/);
});

test('Mã lỗi kỹ thuật từ Server được hiển thị bằng tiếng Việt có dấu', () => {
  const {get, message, connection, players} = setup('Werewolf');
  message({type: 'VotingSnapshot', roomId: 'R', phase: 'Night', day: 1,
    players, hasVoted: false, canShoot: false, resolved: false, result: null});
  get('wolf-target').value = 'p2'; get('wolf-target').fire('change');
  get('wolf-submit').fire('click');
  const requestId = connection.sent[0].requestId;
  message({type: 'CommandRejected', requestId, code: 'InvalidTarget',
    message: 'NightAction bi tu choi: InvalidTarget'});
  assert.equal(get('message').textContent,
    'Mục tiêu không hợp lệ. Hãy chọn một người còn sống đúng luật.');
  assert.equal(get('night-status').textContent,
    'Mục tiêu không hợp lệ. Hãy chọn một người còn sống đúng luật.');
});

test('Tin chat mới hiện bong bóng đúng ô người gửi, snapshot cũ không tạo bong bóng', () => {
  const {get, message} = setup();
  message({type: 'ChatHistorySnapshot', roomId: 'R', messages: [{day: 1,
    channel: 'PublicDay', messageId: 'm1', sequence: 1, senderId: 'p2', text: 'Tin cũ'}]});
  let secondCard = get('player-list').children[1];
  assert.equal(secondCard.children.some(child => child.className === 'dashboard-chat-bubble'), false);

  message({type: 'ChatMessage', roomId: 'R', day: 1, channel: 'PublicDay',
    messageId: 'm2', sequence: 2, playerId: 'p2', message: 'Tin vừa gửi'});
  secondCard = get('player-list').children[1];
  const bubble = secondCard.children.find(child => child.className === 'dashboard-chat-bubble');
  assert.equal(bubble.textContent, 'Tin vừa gửi');
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
  assert.match(get('role-help-text').textContent, /Giai đoạn: Ban đêm/);
  assert.match(get('role-help-text').textContent, /Chọn người khác/);
});

test('Chat trở về ngày hiện tại sau khi đổi kênh hoặc bước sang Day mới', () => {
  const {get, message, players} = setup('Werewolf');
  message({type: 'ChatMessage', roomId: 'R', day: 1, channel: 'PublicDay',
    messageId: 'system-day-1', sequence: 1, senderId: '__system__',
    text: 'Kết quả bỏ phiếu ngày 1'});
  message({type: 'VotingSnapshot', roomId: 'R', phase: 'Night', day: 2,
    players, hasVoted: false, canShoot: false, resolved: false, result: null});
  assert.equal(get('chat-day-select').value, '1', 'vẫn xem được kết quả ngày trước');

  get('chat-wolves-tab').fire('click');
  assert.equal(get('chat-day-select').value, '2');
  assert.equal(get('chat-input').disabled, false, 'Sói gửi được tin ở đêm hiện tại');
  get('chat-day-select').value = '1';
  get('chat-day-select').fire('change');
  assert.equal(get('chat-input').disabled, true, 'xem lịch sử thì không gửi tin');

  message({type: 'VotingSnapshot', roomId: 'R', phase: 'Day', day: 2,
    players, hasVoted: false, canShoot: false, resolved: false, result: null});
  assert.equal(get('chat-day-select').value, '2', 'Day mới tự chọn ngày hiện tại');
  get('chat-public-tab').fire('click');
  assert.equal(get('chat-input').disabled, false, 'chat chung gửi được ở Day mới');

  get('chat-day-select').value = '1';
  get('chat-day-select').fire('change');
  assert.match(get('chat-messages').children[1].textContent, /Kết quả bỏ phiếu ngày 1/);
  get('chat-public-tab').fire('click');
  assert.equal(get('chat-day-select').value, '2', 'bấm lại tab đưa về ngày hiện tại');
});

test('Bong bóng chat tự ẩn sau timer, lịch sử chat vẫn còn', () => {
  const {get, message, timers} = setup();

  message({
    type: 'ChatMessage', roomId: 'R', day: 1,
    channel: 'PublicDay', messageId: 'm-timer', sequence: 10,
    playerId: 'p2', message: 'Tin cần tự ẩn'
  });

  const hasBubble = () =>
    get('player-list').children[1].children.some(
      child => child.className === 'dashboard-chat-bubble'
    );

  assert.equal(hasBubble(), true);
  timers.at(-1)(); // Giả lập timer 5 giây trong setup()
  assert.equal(hasBubble(), false);
  assert.ok(
    get('chat-messages').children.some(
      line => line.children.includes('Tin cần tự ẩn')
    ),
    'Ẩn bong bóng không được xóa lịch sử chat'
  );
});