// Chạy thử giao diện khi TV2 chưa có WebSocket.
const DEMO = true;

// Điền địa chỉ WebSocket do TV2 cung cấp khi tích hợp Server thật.
const WS_URL = "";

let socket = null;
let requestNumber = 0;
let demoNextId = 1;
let demoHostPlayerId = null;

const state = {
  connected: DEMO,
  roomId: null,
  selfPlayerId: null,
  hostPlayerId: null,
  players: [],
  pending: null,
  error: ""
};

// Dữ liệu Server giả lập, tách khỏi state của giao diện.
const demoPlayers = [];

const el = {
  status: document.querySelector("#connection-status"),
  message: document.querySelector("#message"),
  joinSection: document.querySelector("#join-section"),
  lobbySection: document.querySelector("#lobby-section"),
  joinForm: document.querySelector("#join-form"),
  roomId: document.querySelector("#room-id"),
  playerName: document.querySelector("#player-name"),
  joinButton: document.querySelector("#join-button"),
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

// Vẽ giao diện từ state hiện tại.
function render() {
  el.status.textContent = DEMO
    ? "Đang dùng Server giả lập"
    : state.connected
      ? "Đã kết nối Server"
      : "Mất kết nối Server";

  el.status.dataset.mode = DEMO
    ? "demo"
    : state.connected
      ? "online"
      : "offline";

  el.message.textContent = state.error;
  el.joinSection.hidden = state.selfPlayerId !== null;
  el.lobbySection.hidden = state.selfPlayerId === null;

  const busy = state.pending !== null;

  el.joinButton.disabled = !state.connected || busy;
  el.readyButton.disabled = !state.connected || busy;
  el.leaveButton.disabled = !state.connected || busy;

  el.joinButton.textContent =
    state.pending?.type === "JoinGame"
      ? "Đang tham gia..."
      : "Tham gia phòng";

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
    ready.className = `ready-badge${player.ready ? " is-ready" : ""}`;
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

// Tạo command. Giao diện chưa tự thay đổi danh sách người chơi ở bước này.
function sendCommand(type, fields = {}) {
  if (!state.connected || state.pending !== null) return;

  const requestId = `req-${Date.now()}-${++requestNumber}`;

  const command = {
    type,
    requestId,
    roomId: fields.roomId ?? state.roomId,
    ...fields
  };

  state.pending = {
    type,
    requestId,
    ready: fields.ready
  };

  state.error = "";
  render();

  if (DEMO) {
    setTimeout(() => mockServer(command), 300);
    return;
  }

  try {
    socket.send(JSON.stringify(command));
  } catch {
    state.pending = null;
    state.error = "Không gửi được yêu cầu. Hãy kiểm tra kết nối.";
    render();
  }
}

// Chỉ cập nhật giao diện sau khi có phản hồi từ Server hoặc Server giả lập.
function handleServerMessage(message) {
  switch (message.type) {
    case "LobbySnapshot":
      // Mẫu phản hồi giả lập; khi tích hợp cần đối chiếu JSON thật với TV2.
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
      if (message.requestId === state.pending?.requestId) {
        state.pending = null;
        state.error =
          message.message || message.code || "Yêu cầu bị từ chối.";
      }
      break;
  }

  render();
}

// Server giả lập chỉ dùng để thử giao diện trước khi có WebSocket thật.
function mockServer(command) {
  if (command.type === "JoinGame") {
    const name = normalizePlayerName(command.playerName);

    if (
      demoPlayers.some(
        player =>
          normalizePlayerName(player.displayName).toLowerCase() ===
          name.toLowerCase()
      )
    ) {
      handleServerMessage({
        type: "CommandRejected",
        requestId: command.requestId,
        message: "Tên này đã có trong phòng."
      });
      return;
    }

    if (demoPlayers.length >= 9) {
      handleServerMessage({
        type: "CommandRejected",
        requestId: command.requestId,
        message: "Phòng đã đủ 9 người."
      });
      return;
    }

    const player = {
      playerId: `player-${demoNextId++}`,
      displayName: name,
      ready: false
    };

    demoPlayers.push(player);

    if (demoHostPlayerId === null) {
      demoHostPlayerId = player.playerId;
    }

    handleServerMessage({
      type: "LobbySnapshot",
      roomId: command.roomId,
      selfPlayerId: player.playerId,
      hostPlayerId: demoHostPlayerId,
      players: [...demoPlayers]
    });
  }

  if (command.type === "LeaveGame") {
    const leavingId = state.selfPlayerId;
    const wasHost = demoHostPlayerId === leavingId;

    const index = demoPlayers.findIndex(
      player => player.playerId === leavingId
    );

    if (index !== -1) {
      demoPlayers.splice(index, 1);
    }

    if (wasHost) {
      demoHostPlayerId = demoPlayers[0]?.playerId ?? null;
    }

    handleServerMessage({
      type: "PlayerLeft",
      playerId: leavingId
    });

    if (wasHost && demoHostPlayerId !== null) {
      handleServerMessage({
        type: "HostChanged",
        hostPlayerId: demoHostPlayerId
      });
    }
  }

  if (command.type === "SetReady") {
    const player = demoPlayers.find(
      item => item.playerId === state.selfPlayerId
    );

    if (!player) return;

    player.ready = command.ready;

    handleServerMessage({
      type: "ReadyChanged",
      playerId: player.playerId,
      ready: player.ready
    });
  }
}

// Người chơi nhập mã phòng và tên, sau đó gửi ý định Join.
el.joinForm.addEventListener("submit", event => {
  event.preventDefault();

  const roomId = el.roomId.value.trim();
  const playerName = normalizePlayerName(el.playerName.value);

  if (!roomId || !playerName) {
    state.error = "Hãy nhập mã phòng và tên.";
    render();
    return;
  }

  sendCommand("JoinGame", { roomId, playerName });
});

// Gửi trạng thái Ready ngược với trạng thái hiện tại.
el.readyButton.addEventListener("click", () => {
  const me = state.players.find(
    player => player.playerId === state.selfPlayerId
  );

  if (me) {
    sendCommand("SetReady", { ready: !me.ready });
  }
});

// Yêu cầu rời phòng; chỉ xóa người khỏi UI khi có phản hồi.
el.leaveButton.addEventListener("click", () => {
  sendCommand("LeaveGame");
});

// Kết nối WebSocket thật khi TV2 đã cung cấp địa chỉ và hợp đồng JSON.
if (!DEMO) {
  if (!WS_URL) {
    state.error = "Chưa có địa chỉ WebSocket từ TV2.";
  } else {
    socket = new WebSocket(WS_URL);

    socket.addEventListener("open", () => {
      state.connected = true;
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
  }
}

render();