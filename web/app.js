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
  error: "",
  phase: "Lobby",
  selfRole: null,
  nightActionDone: false,
  nightMessage: "",
  seerResult: null,
  witchVictimId: null,
  revealedRoles: {},
  gameResult: null,
  hunterPending: false,
  hunterActionDone: false,
  hunterMessage: ""
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
  leaveButton: document.querySelector("#leave-button"),
  startButton: document.querySelector("#start-button"),
  nightSection: document.querySelector("#night-section"),
  nightPhase: document.querySelector("#night-phase"),
  nightRoleName: document.querySelector("#night-role-name"),
  nightRoleDescription: document.querySelector("#night-role-description"),
  nightStatus: document.querySelector("#night-status"),
  wolfPanel: document.querySelector("#wolf-action-panel"),
  wolfTarget: document.querySelector("#wolf-target"),
  wolfSubmit: document.querySelector("#wolf-submit"),
  seerPanel: document.querySelector("#seer-action-panel"),
  seerTarget: document.querySelector("#seer-target"),
  seerSubmit: document.querySelector("#seer-submit"),
  seerResultPanel: document.querySelector("#seer-result-panel"),
  seerResultText: document.querySelector("#seer-result-text"),
  guardPanel: document.querySelector("#guard-action-panel"),
  guardTarget: document.querySelector("#guard-target"),
  guardSubmit: document.querySelector("#guard-submit"),
  witchPanel: document.querySelector("#witch-action-panel"),
  witchVictimPanel: document.querySelector("#witch-victim-panel"),
  witchVictimText: document.querySelector("#witch-victim-text"),
  witchHeal: document.querySelector("#witch-heal"),
  witchTarget: document.querySelector("#witch-target"),
  witchPoison: document.querySelector("#witch-poison"),
  witchPass: document.querySelector("#witch-pass"),
  hunterPanel: document.querySelector("#hunter-action-panel"),
  hunterPendingPanel: document.querySelector("#hunter-pending-panel"),
  hunterTarget: document.querySelector("#hunter-target"),
  hunterShoot: document.querySelector("#hunter-shoot"),
  hunterPass: document.querySelector("#hunter-pass"),
  hunterStatus: document.querySelector("#hunter-status"),
  nightWaitingPanel: document.querySelector("#night-waiting-panel")
};

const roleNames = {
  Werewolf: "Sói",
  Seer: "Tiên Tri",
  Guard: "Bảo Vệ",
  Witch: "Phù Thủy",
  Villager: "Dân Làng",
  Hunter: "Thợ Săn"
};

const roleDescriptions = {
  Werewolf: "Chọn mục tiêu để tấn công trong đêm.",
  Seer: "Chọn người chơi để kiểm tra phe.",
  Guard: "Chọn người chơi để bảo vệ.",
  Witch: "Cứu nạn nhân, dùng thuốc độc hoặc bỏ lượt.",
  Villager: "Bạn không có hành động đặc biệt trong đêm.",
  Hunter: "Nếu bị loại, bạn có thể bắn một người hoặc bỏ lượt khi Server cấp quyền."
};

function normalizePlayerName(name) {
  return name.trim().replace(/\s+/gu, " ");
}

function getSelfPlayer() {
  return state.players.find(
    player => player.playerId === state.selfPlayerId
  );
}

function getPlayerName(playerId) {
  const player = state.players.find(
    item => item.playerId === playerId
  );

  return player?.displayName || playerId || "Không có";
}

function resetNightState() {
  state.phase = "Lobby";
  state.selfRole = null;
  state.nightActionDone = false;
  state.nightMessage = "";
  state.seerResult = null;
  state.witchVictimId = null;
  state.revealedRoles = {};
  state.gameResult = null;
  state.hunterPending = false;
  state.hunterActionDone = false;
  state.hunterMessage = "";
}

function resetRoomState() {
  state.roomId = null;
  state.selfPlayerId = null;
  state.hostPlayerId = null;
  state.players = [];
  state.pending = null;
  resetNightState();
}

function canStartGame() {
  const playerCount = state.players.length;

  return (
    state.connected &&
    state.selfPlayerId !== null &&
    state.selfPlayerId === state.hostPlayerId &&
    state.phase === "Lobby" &&
    state.pending === null &&
    (playerCount === 8 || playerCount === 9) &&
    state.players.every(player => player.ready)
  );
}

function renderLobby() {
  const inRoom = state.selfPlayerId !== null;
  const inLobby = state.phase === "Lobby";
  const busy = state.pending !== null;

  el.joinSection.hidden = inRoom;
  el.lobbySection.hidden = !inRoom || !inLobby;

  el.joinButton.disabled = !state.connected || busy;
  el.createButton.disabled = !state.connected || busy;
  el.readyButton.disabled = !state.connected || busy || !inLobby;
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

  const readyCount = state.players.filter(
    player => player.ready
  ).length;

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

  const me = getSelfPlayer();

  el.readyButton.textContent = me?.ready
    ? "Hủy sẵn sàng"
    : "Sẵn sàng";

  el.selfStatus.textContent = me
    ? me.ready
      ? "Bạn đã sẵn sàng. Hãy chờ những người chơi khác."
      : "Bạn chưa sẵn sàng. Nhấn nút khi đã chuẩn bị xong."
    : "";

  const isHost =
    inRoom &&
    state.selfPlayerId === state.hostPlayerId;

  el.startButton.hidden = !isHost || !inLobby;
  el.startButton.disabled = !canStartGame();

  el.startButton.textContent =
    state.pending?.type === "StartGame"
      ? "Đang bắt đầu ván..."
      : "Bắt đầu ván";
}

function setTargetOptions(select, players) {
  const selectedValue = select.value;

  select.replaceChildren();

  const placeholder = document.createElement("option");
  placeholder.value = "";
  placeholder.textContent = "-- Chọn người chơi --";
  select.appendChild(placeholder);

  for (const player of players) {
    const option = document.createElement("option");
    option.value = player.playerId;
    option.textContent = player.displayName || player.playerId;
    select.appendChild(option);
  }

  if (players.some(player => player.playerId === selectedValue)) {
    select.value = selectedValue;
  }
}

function renderNightTargets() {
  const otherPlayers = state.players.filter(
    player => player.playerId !== state.selfPlayerId
  );

  // PlayerView chua co alive va team.
  // UI chi loc muc tieu theo thong tin duoc phep biet.
  // Server van phai validate moi NightAction.
  setTargetOptions(el.wolfTarget, otherPlayers);
  setTargetOptions(el.seerTarget, otherPlayers);
  setTargetOptions(el.guardTarget, state.players);
  setTargetOptions(el.witchTarget, otherPlayers);

  // PlayerView chua co lifeStatus; Server phai validate Hunter target.
  // Loai cac Player da duoc cong bo chet.
  setTargetOptions(el.hunterTarget, otherPlayers.filter(
    player => !Object.prototype.hasOwnProperty.call(
      state.revealedRoles, player.playerId
    )
  ));
}

function renderNight() {
  const inRoom = state.selfPlayerId !== null;
  const isNight = state.phase === "Night";

  el.nightSection.hidden = !inRoom || !isNight;

  if (!inRoom || !isNight) {
    return;
  }

  const role = state.selfRole;

  el.nightPhase.textContent = state.phase;

  el.nightRoleName.textContent = role
    ? roleNames[role] || role
    : "Đang chờ Server xác nhận vai trò";

  el.nightRoleDescription.textContent = role
    ? roleDescriptions[role] || "Chờ hướng dẫn từ Server."
    : "Server chưa gửi thông tin vai trò riêng tư.";

  const canAct =
    state.connected &&
    state.pending === null &&
    role !== null &&
    !state.nightActionDone;

  el.wolfPanel.hidden = role !== "Werewolf";
  el.seerPanel.hidden = role !== "Seer";
  el.guardPanel.hidden = role !== "Guard";
  el.witchPanel.hidden = role !== "Witch";
  el.hunterPanel.hidden = role !== "Hunter";

  el.nightWaitingPanel.hidden =
    role === "Werewolf" ||
    role === "Seer" ||
    role === "Guard" ||
    role === "Witch" ||
    role === "Hunter";

  renderNightTargets();

  el.wolfTarget.disabled = !canAct;
  el.seerTarget.disabled = !canAct;
  el.guardTarget.disabled = !canAct;
  el.witchTarget.disabled = !canAct;

  el.wolfSubmit.disabled =
    !canAct || !el.wolfTarget.value;

  el.seerSubmit.disabled =
    !canAct || !el.seerTarget.value;

  el.guardSubmit.disabled =
    !canAct || !el.guardTarget.value;

  el.witchHeal.disabled =
    !canAct || state.witchVictimId === null;

  el.witchPoison.disabled =
    !canAct || !el.witchTarget.value;

  el.witchPass.disabled = !canAct;

  // Hunter khong duoc ban neu chua co HunterShotPending.
  const canHunterAct = state.connected &&
    state.pending === null &&
    role === "Hunter" &&
    state.hunterPending &&
    !state.hunterActionDone;

  el.hunterPendingPanel.hidden = !state.hunterPending;
  el.hunterTarget.disabled = !canHunterAct;
  el.hunterShoot.disabled =
    !canHunterAct || !el.hunterTarget.value;
  el.hunterPass.disabled = !canHunterAct;

  el.hunterStatus.textContent = state.hunterMessage ||
    (state.hunterPending
      ? "Bạn đã được quyền bắn hoặc bỏ lượt."
      : "Đang chờ thông báo từ Server.");

  if (state.nightMessage) {
    el.nightStatus.textContent = state.nightMessage;
  } else if (state.nightActionDone) {
    el.nightStatus.textContent =
      "Hành động đã được Server xác nhận.";
  } else if (!role) {
    el.nightStatus.textContent =
      "Đang chờ thông tin vai trò từ Server.";
  } else {
    el.nightStatus.textContent =
      "Hãy chọn hành động phù hợp với vai trò.";
  }

  el.seerResultPanel.hidden = state.seerResult === null;

  if (state.seerResult !== null) {
    const teamName =
      state.seerResult === "Wolves" ? "Sói" : "Dân Làng";

    el.seerResultText.textContent =
      `Kết quả soi: phe ${teamName}.`;
  }

  el.witchVictimPanel.hidden =
    state.witchVictimId === null;

  if (state.witchVictimId !== null) {
    el.witchVictimText.textContent =
      `Nạn nhân được Sói chọn: ${
        getPlayerName(state.witchVictimId)
      }.`;
  }
}

function render() {
  el.status.textContent = state.connected
    ? "Đã kết nối Server"
    : "Mất kết nối Server";

  el.status.dataset.mode =
    state.connected ? "online" : "offline";

  el.message.textContent = state.error;

  renderLobby();
  renderNight();
}

function sendCommand(type, fields = {}) {
  if (state.pending !== null) {
    return;
  }

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

  state.pending = { type, requestId };
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

function sendNightAction(choice) {
  if (
    state.phase !== "Night" ||
    state.selfRole === null ||
    state.selfPlayerId === null ||
    state.nightActionDone
  ) {
    state.error = "Bạn chưa được phép hành động trong đêm.";
    render();
    return;
  }

  sendCommand("NightAction", { choice });
}

function handleNightAccepted() {
  if (state.pending?.type === "NightAction") {
    state.pending = null;
  }

  state.nightActionDone = true;
  state.nightMessage = "Server đã chấp nhận hành động.";
}

function sendHunterAction(choice) {
  if (
    state.phase !== "Night" ||
    state.selfRole !== "Hunter" ||
    !state.hunterPending ||
    state.hunterActionDone ||
    state.selfPlayerId === null
  ) {
    state.error = "Hunter chưa được Server cấp quyền bắn.";
    render();
    return;
  }

  sendCommand("HunterAction", { choice });
}

function handlePhaseChanged(phase) {
  const previousPhase = state.phase;

  state.phase = phase;

  // PhaseChanged Night xac nhan StartGame da thanh cong.
  if (
    phase === "Night" &&
    state.pending?.type === "StartGame"
  ) {
    state.pending = null;
  }

  if (phase === "Night" && previousPhase !== "Night") {
    state.nightActionDone = false;
    state.nightMessage = "";
    state.seerResult = null;
    state.witchVictimId = null;
    state.hunterPending = false;
    state.hunterActionDone = false;
    state.hunterMessage = "";
  }

  if (phase !== "Night") {
    state.nightActionDone = false;
    state.nightMessage = "";
    state.seerResult = null;
    state.witchVictimId = null;
    state.hunterPending = false;
    state.hunterActionDone = false;
    state.hunterMessage = "";
  }
}function handleServerMessage(message) {
  switch (message.type) {
    case "LobbySnapshot":
      state.roomId = message.roomId;
      state.selfPlayerId = message.selfPlayerId;
      state.hostPlayerId = message.hostPlayerId;
      state.players = Array.isArray(message.players)
        ? message.players
        : [];
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
        resetRoomState();
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

    // Role bi mat chi duoc Server gui cho chu so huu.
    case "YourRole":
      if (message.roomId === state.roomId) {
        state.selfRole = message.role;
        state.nightMessage =
          "Bạn đã nhận vai trò từ Server.";
      }
      break;

    case "NightActionAccepted":
      if (message.roomId === state.roomId) {
        handleNightAccepted();
      }
      break;

    case "SeerResult":
      if (message.roomId === state.roomId) {
        state.seerResult = message.team;
        state.nightMessage = "Đã nhận kết quả soi riêng tư.";
      }
      break;

    case "WitchVictimNotice":
      if (message.roomId === state.roomId) {
        state.witchVictimId = message.victimId;
        state.nightMessage = message.victimId === null
          ? "Sói không có nạn nhân để cứu."
          : "Phù Thủy đã nhận thông báo nạn nhân.";
      }
      break;

    case "HunterShotPending":
      if (
        message.roomId === state.roomId &&
        state.selfRole === "Hunter"
      ) {
        state.hunterPending = true;
        state.hunterActionDone = false;
        state.hunterMessage =
          "Đến lượt Hunter: chọn mục tiêu hoặc bỏ lượt.";
        state.nightMessage =
          "Hunter được quyền bắn sau khi bị loại.";
      }
      break;

    case "HunterShotResolved":
      if (message.roomId === state.roomId) {
        if (
          state.selfRole === "Hunter" &&
          message.hunterId === state.selfPlayerId
        ) {
          state.hunterPending = false;
          state.hunterActionDone = true;
          state.hunterMessage =
            "Server đã xử lý lượt Hunter.";

          if (state.pending?.type === "HunterAction") {
            state.pending = null;
          }
        }
      }
      break;

    case "NightResolved":
      if (message.roomId === state.roomId) {
        state.nightMessage = "Đêm đã được xử lý.";
      }
      break;

    case "PlayerRoleRevealed":
      if (message.roomId === state.roomId) {
        state.revealedRoles[message.playerId] = {
          role: message.role,
          team: message.team
        };
      }
      break;

    case "PhaseChanged":
      if (message.roomId === state.roomId) {
        handlePhaseChanged(message.phase);
      }
      break;

    case "GameFinished":
      if (message.roomId === state.roomId) {
        state.phase = "GameOver";
        state.gameResult = message.result;
        state.pending = null;

        const results = {
          WinnerVillage: "Phe Dân Làng chiến thắng!",
          WinnerWolves: "Phe Sói chiến thắng!",
          Draw: "Ván chơi kết thúc hòa!"
        };

        state.error =
          results[message.result] || "Ván chơi đã kết thúc.";
      }
      break;

    case "CommandRejected":
      if (
        message.requestId === null ||
        message.requestId === state.pending?.requestId
      ) {
        if (state.pending?.type === "NightAction") {
          state.nightMessage =
            "Hành động không được chấp nhận.";
        }

        if (state.pending?.type === "HunterAction") {
          state.hunterMessage =
            "Server chưa xử lý hành động Hunter: " +
            (
              message.message ||
              message.code ||
              "Lệnh bị từ chối."
            );

          // Giu Hunter pending va mo lai nut khi Server tu choi.
          state.hunterActionDone = false;
        }

        state.pending = null;
        state.error =
          message.message ||
          message.code ||
          "Yêu cầu bị từ chối.";
      }
      break;

    default:
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
  const me = getSelfPlayer();

  if (me) {
    sendCommand("SetReady", { ready: !me.ready });
  }
});

el.leaveButton.addEventListener("click", () => {
  sendCommand("LeaveGame");
});

// Chi Host duoc phep gui StartGame tu giao dien.
// Pure Engine van kiem tra lai quyen va luat.
el.startButton.addEventListener("click", () => {
  if (!canStartGame()) {
    state.error =
      "Cần Host, đủ 8 hoặc 9 người và tất cả sẵn sàng.";
    render();
    return;
  }

  sendCommand("StartGame");
});

el.wolfTarget.addEventListener("change", render);
el.seerTarget.addEventListener("change", render);
el.guardTarget.addEventListener("change", render);
el.witchTarget.addEventListener("change", render);
el.hunterTarget.addEventListener("change", render);

el.wolfSubmit.addEventListener("click", () => {
  if (el.wolfTarget.value) {
    sendNightAction({
      action: "WolfTarget",
      targetId: el.wolfTarget.value
    });
  }
});

el.seerSubmit.addEventListener("click", () => {
  if (el.seerTarget.value) {
    sendNightAction({
      action: "SeerTarget",
      targetId: el.seerTarget.value
    });
  }
});

el.guardSubmit.addEventListener("click", () => {
  if (el.guardTarget.value) {
    sendNightAction({
      action: "GuardTarget",
      targetId: el.guardTarget.value
    });
  }
});

el.witchHeal.addEventListener("click", () => {
  if (state.witchVictimId !== null) {
    sendNightAction({
      action: "WitchHeal"
    });
  }
});

el.witchPoison.addEventListener("click", () => {
  if (el.witchTarget.value) {
    sendNightAction({
      action: "WitchPoison",
      targetId: el.witchTarget.value
    });
  }
});

el.witchPass.addEventListener("click", () => {
  sendNightAction({
    action: "WitchPass"
  });
});

// Hunter: chi gui khi Server da phat HunterShotPending.
el.hunterShoot.addEventListener("click", () => {
  if (el.hunterTarget.value) {
    sendHunterAction({
      action: "HunterShot",
      targetId: el.hunterTarget.value
    });
  }
});

el.hunterPass.addEventListener("click", () => {
  sendHunterAction({
    action: "HunterPass"
  });
});

socket = new WebSocket(WS_URL);

socket.addEventListener("open", () => {
  state.connected = true;
  state.error = "";
  render();
});

socket.addEventListener("message", event => {
  let message;

  try {
    message = JSON.parse(event.data);
  } catch {
    state.error =
      "Server gửi dữ liệu JSON không hợp lệ.";
    render();
    return;
  }

  try {
    handleServerMessage(message);
  } catch (error) {
    console.error(
      "Loi xu ly Server message:",
      error
    );
    state.error =
      "Không xử lý được phản hồi từ Server.";
    render();
  }
});

socket.addEventListener("close", () => {
  state.connected = false;
  state.pending = null;
  resetRoomState();
  render();
});

socket.addEventListener("error", () => {
  state.error = "Không kết nối được Server.";
  render();
});

render();