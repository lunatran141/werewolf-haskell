const WS_URL = "ws://localhost:8080/ws";

let socket = null;
let requestNumber = 0;

const state = {
  connected: false,
  roomId: null,
  selfPlayerId: null,
  hostPlayerId: null,
  players: [],
  pending: null,
  error: ""
};

// T06: Chỉ lưu dữ liệu server cho phép xem; không chứa vai của người còn sống.
const voting = {
  phase: "Lobby", day: 0, players: [], hasVoted: false,
  canShoot: false, resolved: false, result: null, tally: [],
  summary: "", reveals: []
};

const el = {
  status: document.querySelector("#connection-status"),
  message: document.querySelector("#message"),
  joinSection: document.querySelector("#join-section"),
  lobbySection: document.querySelector("#lobby-section"),
  joinForm: document.querySelector("#join-form"),
  roomId: document.querySelector("#room-id"),
  playerName: document.querySelector("#player-name"),
  joinButton: document.querySelector("#join-button"),
  createButton: document.querySelector("#create-button"),
  roomTitle: document.querySelector("#room-title"),
  playerList: document.querySelector("#player-list"),
  playerCount: document.querySelector("#player-count"),
  readyCount: document.querySelector("#ready-count"),
  selfStatus: document.querySelector("#self-status"),
  readyButton: document.querySelector("#ready-button"),
  leaveButton: document.querySelector("#leave-button")
};

// Các phần tử mới độc lập với bố cục phòng chờ đã có của nhóm.
const voteEl = Object.fromEntries([
  "voting-section", "voting-title", "voting-status", "vote-form",
  "vote-target", "vote-button", "hunter-pass", "vote-result", "vote-tally", "vote-reveals"
].map(id => [id, document.getElementById(id)]));

function playerLabel(pid) {
  return voting.players.find(p => p.playerId === pid)?.displayName || pid;
}

// UI chỉ mở thao tác theo snapshot; server vẫn xác thực lại mọi lệnh.
function canChooseTarget() {
  const me = voting.players.find(p => p.playerId === state.selfPlayerId);
  return voting.canShoot || (voting.phase === "Voting" && !voting.resolved &&
    !voting.hasVoted && me?.alive === true);
}

function renderVoting() {
  const active = state.selfPlayerId !== null && voting.phase !== "Lobby";
  voteEl["voting-section"].hidden = !active;
  el.readyButton.hidden = active;
  el.leaveButton.disabled = active || !state.connected || state.pending !== null;
  if (!active) return;

  const phaseNames = {Night: "Ban đêm", Day: "Thảo luận", Voting: "Bỏ phiếu", GameOver: "Kết thúc"};
  voteEl["voting-title"].textContent = `${phaseNames[voting.phase] || voting.phase} · Vòng ${voting.day}`;
  const me = voting.players.find(p => p.playerId === state.selfPlayerId);
  const allowed = canChooseTarget() && state.connected && state.pending === null;
  el.selfStatus.textContent = me?.alive ? "Bạn đang tham gia ván chơi." : "Bạn đang theo dõi ván chơi.";
  el.readyCount.textContent = `${voting.players.filter(p => p.alive).length}/${voting.players.length} còn sống`;
  const target = voteEl["vote-target"];
  const previous = target.value;
  target.replaceChildren();
  const placeholder = document.createElement("option");
  placeholder.value = "";
  placeholder.textContent = "— Chọn mục tiêu —";
  target.appendChild(placeholder);
  for (const player of voting.players.filter(p => p.alive && p.playerId !== state.selfPlayerId)) {
    const option = document.createElement("option");
    option.value = player.playerId;
    option.textContent = player.displayName;
    target.appendChild(option);
  }
  if (voting.players.some(p => p.alive && p.playerId !== state.selfPlayerId && p.playerId === previous)) {
    target.value = previous;
  }
  target.disabled = !allowed;
  voteEl["vote-button"].disabled = !allowed || !target.value;
  voteEl["vote-button"].textContent = voting.canShoot ? "Bắn mục tiêu" : "Gửi phiếu";
  voteEl["hunter-pass"].hidden = !voting.canShoot;
  voteEl["hunter-pass"].disabled = !allowed;

  const status = !state.connected ? "Mất kết nối. Không thể gửi lựa chọn."
    : state.pending ? "Đang chờ server xác nhận…"
    : voting.canShoot ? "Bạn là Thợ săn vừa bị loại. Chọn bắn hoặc bỏ qua; hết thời hạn sẽ tự bỏ qua."
    : voting.result ? ({Draw: "Ván chơi hòa.", WinnerVillage: "Phe Dân thắng!", WinnerWolves: "Phe Sói thắng!"}[voting.result])
    : voting.resolved ? "Đã khóa phiếu. Đang hoàn tất kết quả lượt chơi."
    : voting.phase !== "Voting" ? "Chưa đến thời gian bỏ phiếu."
    : !me?.alive ? "Bạn đã bị loại và chỉ có thể theo dõi."
    : voting.hasVoted ? "Server đã nhận phiếu của bạn. Không thể đổi lựa chọn trong vòng này."
    : "Hãy chọn người bị nghi ngờ. Hòa cao nhất hoặc không có phiếu sẽ không loại ai.";
  voteEl["voting-status"].textContent = status;
  voteEl["vote-result"].textContent = voting.summary;
  voteEl["vote-tally"].replaceChildren();
  for (const [pid, count] of voting.tally) {
    const item = document.createElement("li");
    item.textContent = `${playerLabel(pid)}: ${count} phiếu`;
    voteEl["vote-tally"].appendChild(item);
  }
  voteEl["vote-reveals"].replaceChildren();
  for (const reveal of voting.reveals) {
    const item = document.createElement("li");
    item.textContent = `${playerLabel(reveal.playerId)} đã bị loại — ${reveal.role} (${reveal.team})`;
    voteEl["vote-reveals"].appendChild(item);
  }
}

function normalizePlayerName(name) {
  return name.trim().replace(/\s+/gu, " ");
}

function render() {
  el.status.textContent = state.connected
    ? "Đã kết nối Server"
    : "Mất kết nối Server";

  el.status.dataset.mode = state.connected ? "online" : "offline";
  el.message.textContent = state.error;

  el.joinSection.hidden = state.selfPlayerId !== null;
  el.lobbySection.hidden = state.selfPlayerId === null;

  const busy = state.pending !== null;

  el.joinButton.disabled = !state.connected || busy;
  el.createButton.disabled = !state.connected || busy;
  el.readyButton.disabled = !state.connected || busy;
  el.leaveButton.disabled = !state.connected || busy;

  el.joinButton.textContent =
    state.pending?.type === "JoinGame"
      ? "Đang tham gia..."
      : "Tham gia phòng";

  el.createButton.textContent =
    state.pending?.type === "CreateRoom"
      ? "Đang tạo phòng..."
      : "Tạo phòng";

  el.roomTitle.textContent = `Phòng ${state.roomId ?? ""}`;
  el.playerCount.textContent = `${state.players.length}/9 người`;

  const readyCount = state.players.filter(player => player.ready).length;
  el.readyCount.textContent =
    `${readyCount}/${state.players.length} sẵn sàng`;

  el.playerList.replaceChildren();

  for (const player of state.players) {
    const isMe = player.playerId === state.selfPlayerId;
    const isHost = player.playerId === state.hostPlayerId;
    const displayName = player.displayName || "Người chơi";

    const item = document.createElement("li");
    item.className = `player-card${isMe ? " is-me" : ""}`;

    const avatar = document.createElement("span");
    avatar.className = "player-avatar";
    avatar.textContent =
      displayName.trim().charAt(0).toLocaleUpperCase() || "?";

    const info = document.createElement("span");
    info.className = "player-info";

    const name = document.createElement("span");
    name.className = "player-name";
    name.textContent = displayName;

    const role = document.createElement("span");
    role.className = "player-role";

    if (isHost && isMe) {
      role.textContent = "Host · Bạn";
    } else if (isHost) {
      role.textContent = "Host";
    } else if (isMe) {
      role.textContent = "Bạn";
    } else {
      role.textContent = "Thành viên";
    }

    const ready = document.createElement("span");
    ready.className =
      `ready-badge${player.ready ? " is-ready" : ""}`;
    ready.textContent = player.ready
      ? "Sẵn sàng"
      : "Chưa sẵn sàng";

    info.append(name, role);
    item.append(avatar, info, ready);
    el.playerList.appendChild(item);
  }

  const me = state.players.find(
    player => player.playerId === state.selfPlayerId
  );

  el.readyButton.textContent = me?.ready
    ? "Hủy sẵn sàng"
    : "Sẵn sàng";

  el.selfStatus.textContent = me
    ? me.ready
      ? "Bạn đã sẵn sàng. Hãy chờ những người chơi khác."
      : "Bạn chưa sẵn sàng. Nhấn nút khi đã chuẩn bị xong."
    : "";
  renderVoting();
}

function sendCommand(type, fields = {}) {
  if (state.pending !== null) return;

  if (!socket || socket.readyState !== WebSocket.OPEN) {
    state.error = "Chưa kết nối được Server.";
    render();
    return;
  }

  const requestId = `req-${Date.now()}-${++requestNumber}`;

  const command = {
    type,
    requestId,
    roomId: fields.roomId ?? state.roomId,
    ...fields
  };

  state.pending = {
    type,
    requestId
  };
  state.error = "";
  render();

  try {
    socket.send(JSON.stringify(command));
  } catch {
    state.pending = null;
    state.error = "Không gửi được yêu cầu. Hãy kiểm tra kết nối.";
    render();
  }
}

function handleServerMessage(message) {
  // Không áp dụng thông điệp của phòng khác vào UI đang mở.
  if (message.roomId && state.roomId && message.roomId !== state.roomId && message.type !== "LobbySnapshot") return;
  switch (message.type) {
    case "VotingSnapshot":
      // Day và Voting cùng số vòng: phải xét cả chuyển phase để xóa tally cũ.
      if (message.phase === "Voting" && (voting.phase !== "Voting" || message.day !== voting.day)) {
        voting.summary = "";
        voting.tally = [];
      }
      Object.assign(voting, {
        phase: message.phase, day: message.day, players: message.players,
        hasVoted: message.hasVoted, canShoot: message.canShoot,
        resolved: message.resolved, result: message.result
      });
      break;

    case "ActionAccepted":
      if (message.requestId === state.pending?.requestId) state.pending = null;
      break;

    case "VotingResolved":
      voting.tally = message.tally;
      voting.resolved = true;
      voting.summary = message.targetId
        ? `${playerLabel(message.targetId)} có số phiếu cao nhất duy nhất. Đang xử lý kết quả.`
        : message.tally.length ? "Hòa phiếu cao nhất: không loại ai, không bỏ phiếu lại."
        : "Không có phiếu: không loại ai.";
      break;

    case "PlayerRoleRevealed":
      if (!voting.reveals.some(p => p.playerId === message.playerId)) voting.reveals.push(message);
      break;

    case "HunterShotResolved":
      voting.canShoot = false;
      break;
    case "LobbySnapshot":
      state.roomId = message.roomId;
      state.selfPlayerId = message.selfPlayerId;
      state.hostPlayerId = message.hostPlayerId;
      state.players = message.players;
      state.pending = null;
      break;

    case "PlayerJoined":
      if (
        message.player &&
        !state.players.some(
          player => player.playerId === message.player.playerId
        )
      ) {
        state.players.push(message.player);
      }
      break;

    case "PlayerLeft":
      state.players = state.players.filter(
        player => player.playerId !== message.playerId
      );

      if (message.playerId === state.hostPlayerId) {
        state.hostPlayerId = null;
      }

      if (message.playerId === state.selfPlayerId) {
        state.selfPlayerId = null;
        state.hostPlayerId = null;
        state.roomId = null;
        state.players = [];
        state.pending = null;
        Object.assign(voting, {phase: "Lobby", players: [], hasVoted: false,
          canShoot: false, resolved: false, result: null, tally: [], summary: "", reveals: [], day: 0});
      }
      break;

    case "HostChanged":
      if (state.selfPlayerId !== null) {
        state.hostPlayerId = message.hostPlayerId;
      }
      break;

    case "ReadyChanged":
      state.players = state.players.map(player =>
        player.playerId === message.playerId
          ? { ...player, ready: message.ready }
          : player
      );

      if (
        message.playerId === state.selfPlayerId &&
        state.pending?.type === "SetReady"
      ) {
        state.pending = null;
      }
      break;

    case "CommandRejected":
      if (
        message.requestId === null ||
        message.requestId === state.pending?.requestId
      ) {
        state.pending = null;
        state.error =
          message.message || message.code || "Yêu cầu bị từ chối.";
      }
      break;
  }

  render();
}

function readRoomForm() {
  const roomId = el.roomId.value.trim();
  const playerName = normalizePlayerName(el.playerName.value);

  if (!roomId || !playerName) {
    state.error = "Hãy nhập mã phòng và tên.";
    render();
    return null;
  }

  return { roomId, playerName };
}

el.joinForm.addEventListener("submit", event => {
  event.preventDefault();

  const fields = readRoomForm();
  if (fields) {
    sendCommand("JoinGame", fields);
  }
});

el.createButton.addEventListener("click", () => {
  const fields = readRoomForm();
  if (fields) {
    sendCommand("CreateRoom", fields);
  }
});

el.readyButton.addEventListener("click", () => {
  const me = state.players.find(
    player => player.playerId === state.selfPlayerId
  );

  if (me) {
    sendCommand("SetReady", { ready: !me.ready });
  }
});

el.leaveButton.addEventListener("click", () => {
  sendCommand("LeaveGame");
});

// T06: Chặn bấm lặp ngay ở UI; payload không chứa ID người gửi hay vai.
voteEl["vote-target"].addEventListener("change", renderVoting);
voteEl["vote-form"].addEventListener("submit", event => {
  event.preventDefault();
  const targetId = voteEl["vote-target"].value;
  if (!canChooseTarget() || !targetId) return;
  sendCommand(voting.canShoot ? "HunterChoice" : "Vote", {targetId});
});
voteEl["hunter-pass"].addEventListener("click", () => {
  if (voting.canShoot) sendCommand("HunterChoice", {targetId: null});
});

socket = new WebSocket(WS_URL);

socket.addEventListener("open", () => {
  state.connected = true;
  state.error = "";
  render();
});

socket.addEventListener("message", event => {
  try {
    handleServerMessage(JSON.parse(event.data));
  } catch {
    state.error = "Server gửi dữ liệu không đọc được.";
    render();
  }
});

socket.addEventListener("close", () => {
  state.connected = false;
  state.pending = null;
  render();
});

socket.addEventListener("error", () => {
  state.error = "Không kết nối được Server.";
  render();
});

render();
