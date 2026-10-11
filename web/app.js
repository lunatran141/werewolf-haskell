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
  switch (message.type) {
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