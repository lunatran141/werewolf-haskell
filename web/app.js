const WS_URL = "ws://localhost:8080/ws";
let socket = null;
let requestNumber = 0;
const VOTE_DURATION_MS = 60_000;
let voteClockInterval = null;

function createTwinklingStars() {
  const layer = document.getElementById("twinkling-stars");
  // Gần bằng mật độ hai lớp sao cũ trên màn hình desktop, nhưng mỗi sao chớp riêng.
  for (let i = 0; i < 160; i += 1) {
    const star = document.createElement("span");
    star.style.setProperty("--star-x", `${2 + (i * 73.17) % 96}%`);
    star.style.setProperty("--star-y", `${3 + (i * i * 19.7 + i * 11.3) % 92}%`);
    star.style.setProperty("--star-size", `${1 + i % 4 * 0.35}px`);
    star.style.setProperty("--star-duration", `${1.8 + i % 7 * 0.32}s`);
    star.style.setProperty("--star-delay", `${-i * 0.37}s`);
    layer.appendChild(star);
  }
}
createTwinklingStars();

const state = {
  connected: false,
  entranceMode: "join",
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
  hunterMessage: "",
  chatMessages: [],
  appearance: null
};

// T06: Chỉ lưu dữ liệu server cho phép xem; không chứa vai của người còn sống.
const voting = {
  phase: "Lobby", day: 0, players: [], hasVoted: false,
  canShoot: false, resolved: false, result: null, tally: [],
  summary: "", reveals: [], clockDay: null, deadlineMs: null
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
  joinModeButton: document.querySelector("#join-mode-button"),
  hostModeButton: document.querySelector("#host-mode-button"),
  roomTitle: document.querySelector("#room-title"),
  playerList: document.querySelector("#player-list"),
  lobbyActions: document.querySelector("#lobby-actions"),
  appearancePreview: document.querySelector("#appearance-preview"),
  helpButton: document.querySelector("#game-help-button"),
  helpDialog: document.querySelector("#game-help-dialog"),
  roleDialog: document.querySelector("#role-help-dialog"),
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
  nightWaitingPanel: document.querySelector("#night-waiting-panel"),
  daySection: document.querySelector("#day-section"),
  chatMessages: document.querySelector("#chat-messages"),
  chatForm: document.querySelector("#chat-form"),
  chatInput: document.querySelector("#chat-input"),
  chatSubmit: document.querySelector("#chat-submit"),
  chatStatus: document.querySelector("#chat-status"),
  resultSection: document.querySelector("#result-section"),
  resultTitle: document.querySelector("#result-title"),
  resultMessage: document.querySelector("#result-message"),
  revealedRoleList: document.querySelector("#revealed-role-list")
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

const roleHelp = {
  Werewolf: "Mỗi đêm chọn một người phe Dân còn sống. Mục tiêu có nhiều phiếu Sói nhất và không hòa sẽ bị cắn; ví dụ A–A–B thì chọn A. Hòa hoặc không có phiếu thì không ai bị cắn.",
  Seer: "Mỗi đêm soi một người còn sống khác mình. Bạn chỉ nhận kết quả riêng về phe Sói hoặc phe Dân, không biết vai cụ thể.",
  Guard: "Mỗi đêm bảo vệ một người còn sống, có thể là bản thân. Không chọn cùng người hai đêm liên tiếp. Chỉ chặn Sói cắn.",
  Witch: "Mỗi đêm chọn một việc: cứu nạn nhân Sói nếu có, đầu độc một người còn sống khác mình, hoặc bỏ qua. Mỗi loại thuốc dùng tối đa một lần trong cả ván.",
  Hunter: "Khi chết, bạn có thể bắn một người khác còn sống hoặc bỏ qua. Hết thời gian mà chưa chọn sẽ tự bỏ qua.",
  Villager: "Bạn không có kỹ năng ban đêm. Khi còn sống, hãy thảo luận ban ngày và bỏ phiếu cho người khác còn sống."
};

const appearanceIds = ["appearance-hair", "appearance-hair-color", "appearance-skin", "appearance-outfit", "appearance-accessory"];
const defaultAppearance = {hair: "messy", hairColor: "#1E293B", skin: "#FDE2D0", outfit: "#1E1B4B", accessory: "none"};

function readAppearance() {
  return {
    hair: document.getElementById("appearance-hair").value,
    hairColor: document.getElementById("appearance-hair-color").value,
    skin: document.getElementById("appearance-skin").value,
    outfit: document.getElementById("appearance-outfit").value,
    accessory: document.getElementById("appearance-accessory").value
  };
}

function makeAvatar(appearance, avatarId = "preview") {
  const avatar = document.createElement("div");
  avatar.className = "dashboard-avatar";
  avatar.innerHTML = generateAvatarSvg(avatarId, {
    hairStyle: appearance.hair,
    hairColor: appearance.hairColor,
    skinColor: appearance.skin,
    clothingColor: appearance.outfit,
    accessory: appearance.accessory
  });
  return avatar;
}

function renderAppearancePreview() {
  el.appearancePreview.replaceChildren(makeAvatar(readAppearance()));
}

function saveAppearance() {
  state.appearance = readAppearance();
  try {
    localStorage.setItem("werewolf-appearance", JSON.stringify(state.appearance));
  } catch { /* Trình duyệt có thể chặn lưu trữ ở file://; vẫn cho vào phòng. */ }
}

function renderDashboardPlayers() {
  el.playerList.replaceChildren();
  const outfits = ["#1E1B4B", "#1E3A8A", "#064E3B", "#701A75", "#881337", "#0F172A"];
  const hairstyles = ["messy", "spiky", "curly", "bob", "long", "ponytail"];
  const accessories = ["none", "cat_ears", "flower_crown", "straw_hat", "halo", "sunglasses"];
  for (let slot = 0; slot < 9; slot += 1) {
    const player = state.players[slot];
    const item = document.createElement("li");
    item.className = "dashboard-card";
    if (!player) {
      item.classList.add("is-empty");
      item.textContent = `Ô ${slot + 1} · Chờ người chơi`;
      el.playerList.appendChild(item);
      continue;
    }

    const isMe = player.playerId === state.selfPlayerId;
    const isHost = player.playerId === state.hostPlayerId;
    const isDead = player.alive === false;
    if (isMe) item.classList.add("is-me");
    if (isDead) item.classList.add("is-dead");
    if (state.phase === "Lobby" && player.ready) item.classList.add("is-ready");

    const name = document.createElement("div");
    name.className = "dashboard-card-name";
    name.textContent = `${slot + 1} · ${player.displayName || "Người chơi"}${isHost ? " 👑" : ""}${isMe ? " · Bạn" : ""}`;
    const appearance = isMe && state.appearance
      ? state.appearance
      : {...defaultAppearance, hair: hairstyles[slot % hairstyles.length],
        outfit: outfits[slot % outfits.length], accessory: accessories[slot % accessories.length]};
    const avatar = makeAvatar(appearance, player.playerId);
    const footer = document.createElement("div");
    footer.className = "dashboard-card-footer";
    footer.textContent = isDead ? "✕ Đã bị loại"
      : state.phase === "Lobby" ? (player.ready ? "✓ Sẵn sàng" : "Chưa sẵn sàng")
      : "Đang chơi";
    item.append(name, avatar, footer);

    if (isMe && state.phase !== "Lobby" && state.selfRole) {
      const role = document.createElement("div");
      role.className = "dashboard-own-role";
      role.textContent = roleNames[state.selfRole] || state.selfRole;
      const help = document.createElement("button");
      help.type = "button";
      help.className = "dashboard-ability-button";
      help.textContent = "Khả năng của tôi";
      help.addEventListener("click", () => {
        document.getElementById("role-help-title").textContent = role.textContent;
        document.getElementById("role-help-text").textContent = roleHelp[state.selfRole] || "Chưa có hướng dẫn.";
        el.roleDialog.showModal();
      });
      item.append(role, help);
    }
    el.playerList.appendChild(item);
  }
}

// Các phần tử mới độc lập với bố cục phòng chờ đã có của nhóm.
const voteEl = Object.fromEntries([
  "voting-section", "voting-title", "voting-status", "vote-form",
  "vote-target", "vote-button", "vote-result", "vote-tally", "vote-reveals",
  "vote-clock", "vote-clock-value", "vote-clock-bar"
].map(id => [id, document.getElementById(id)]));

function clearVoteClock() {
  if (voteClockInterval !== null) clearInterval(voteClockInterval);
  voteClockInterval = null;
  voting.clockDay = null;
  voting.deadlineMs = null;
}

function renderVoteClock() {
  const visible = state.phase === "Voting" && !voting.resolved && voting.deadlineMs !== null;
  voteEl["vote-clock"].hidden = !visible;
  if (!visible) return;
  const remaining = Math.max(0, voting.deadlineMs - Date.now());
  const seconds = Math.ceil(remaining / 1000);
  voteEl["vote-clock-value"].textContent = `${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`;
  voteEl["vote-clock-bar"].style.setProperty("width", `${remaining / VOTE_DURATION_MS * 100}%`);
  voteEl["vote-clock"].classList.toggle("is-urgent", seconds <= 10);
}

function startVoteClock(day) {
  if (voting.clockDay !== day || voting.deadlineMs === null) {
    voting.clockDay = day;
    voting.deadlineMs = Date.now() + VOTE_DURATION_MS;
  }
  if (voteClockInterval === null) {
    voteClockInterval = setInterval(() => {
      renderVoteClock();
      if (Date.now() >= voting.deadlineMs) {
        clearInterval(voteClockInterval);
        voteClockInterval = null;
        renderVoting();
      }
    }, 250);
  }
  renderVoteClock();
}

function playerLabel(pid) {
  return voting.players.find(p => p.playerId === pid)?.displayName || pid;
}

// UI chỉ mở thao tác theo snapshot; server vẫn xác thực lại mọi lệnh.
function canChooseTarget() {
  const me = voting.players.find(p => p.playerId === state.selfPlayerId);
  return state.phase === "Voting" && !voting.resolved &&
    !voting.hasVoted && me?.alive === true && !state.hunterPending &&
    (voting.deadlineMs === null || Date.now() < voting.deadlineMs);
}

function renderVoting() {
  const active = state.selfPlayerId !== null && voting.phase !== "Lobby";
  voteEl["voting-section"].hidden = !active;
  renderVoteClock();
  el.readyButton.hidden = active;
  el.leaveButton.disabled = active || !state.connected || state.pending !== null;
  if (!active) {
    voteEl["vote-target"].disabled = true;
    voteEl["vote-button"].disabled = true;
    return;
  }

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
  voteEl["vote-button"].textContent = "Gửi phiếu";

  const status = !state.connected ? "Mất kết nối. Không thể gửi lựa chọn."
    : state.pending ? "Đang chờ server xác nhận…"
    : voting.canShoot ? "Bạn là Thợ săn vừa bị loại. Chọn bắn hoặc bỏ qua; hết thời hạn sẽ tự bỏ qua."
    : voting.result ? ({Draw: "Ván chơi hòa.", WinnerVillage: "Phe Dân thắng!", WinnerWolves: "Phe Sói thắng!"}[voting.result])
    : voting.resolved ? "Đã khóa phiếu. Đang hoàn tất kết quả lượt chơi."
    : voting.phase !== "Voting" ? "Chưa đến thời gian bỏ phiếu."
    : !me?.alive ? "Bạn đã bị loại và chỉ có thể theo dõi."
    : voting.deadlineMs !== null && Date.now() >= voting.deadlineMs ? "Đã hết 60 giây. Chờ Server chốt phiếu."
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
  state.chatMessages = [];
}

function resetRoomState() {
  clearVoteClock();
  state.roomId = null;
  state.selfPlayerId = null;
  state.hostPlayerId = null;
  state.players = [];
  state.pending = null;
  resetNightState();
  Object.assign(voting, {phase: "Lobby", day: 0, players: [], hasVoted: false,
    canShoot: false, resolved: false, result: null, tally: [], summary: "", reveals: [],
    clockDay: null, deadlineMs: null});
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

  document.body.classList.toggle("in-room", inRoom);
  document.body.classList.toggle("in-lobby", inRoom && inLobby);
  el.joinSection.hidden = inRoom;
  el.lobbySection.hidden = !inRoom;
  el.lobbyActions.hidden = !inLobby;
  el.startButton.hidden = !inLobby;

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
      : "Tạo phòng và làm Host";

  el.roomTitle.textContent = `Phòng ${state.roomId ?? ""}`;
  el.playerCount.textContent = `${state.players.length}/9 người`;

  const readyCount = state.players.filter(
    player => player.ready
  ).length;

  el.readyCount.textContent =
    `${readyCount}/${state.players.length} sẵn sàng`;

  if (inRoom) renderDashboardPlayers();

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
  // Snapshot chỉ bổ sung trạng thái sống công khai, không bổ sung vai của người khác.
  const alivePlayers = state.players.filter(player => player.alive !== false);
  const otherPlayers = alivePlayers.filter(player => player.playerId !== state.selfPlayerId);

  // PlayerView chua co alive va team.
  // UI chi loc muc tieu theo thong tin duoc phep biet.
  // Server van phai validate moi NightAction.
  setTargetOptions(el.wolfTarget, otherPlayers);
  setTargetOptions(el.seerTarget, otherPlayers);
  setTargetOptions(el.guardTarget, alivePlayers);
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
    !state.nightActionDone && getSelfPlayer()?.alive !== false && !state.hunterPending;

  el.wolfPanel.hidden = role !== "Werewolf";
  el.seerPanel.hidden = role !== "Seer";
  el.guardPanel.hidden = role !== "Guard";
  el.witchPanel.hidden = role !== "Witch";

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

// T06: Một bảng Hunter dùng chung cho Night và Voting, không phụ thuộc panel Night.
function renderHunter() {
  const active = state.selfPlayerId !== null && state.selfRole === "Hunter" &&
    (state.phase === "Night" || state.hunterPending);
  el.hunterPanel.hidden = !active;
  const allowed = active && state.connected && state.pending === null &&
    state.hunterPending && !state.hunterActionDone && ["Night", "Voting"].includes(state.phase);
  setTargetOptions(el.hunterTarget, state.players.filter(p =>
    p.playerId !== state.selfPlayerId && p.alive !== false && !state.revealedRoles[p.playerId]));
  el.hunterPendingPanel.hidden = !state.hunterPending;
  el.hunterTarget.disabled = !allowed;
  el.hunterShoot.disabled = !allowed || !el.hunterTarget.value;
  el.hunterPass.disabled = !allowed;
  el.hunterStatus.textContent = !state.connected ? "Mất kết nối. Không thể gửi lựa chọn."
    : state.hunterMessage || (state.hunterPending
      ? "Bạn có thể bắn hoặc bỏ lượt; hết hạn sẽ tự bỏ qua."
      : "Đang chờ thông báo từ Server.");
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
  renderVoting();
  renderHunter();
  renderDay();
  renderResult();
}

function renderDay() {
  const isDay = state.selfPlayerId !== null && state.phase === "Day";
  el.daySection.hidden = !isDay;
  if (!isDay) return;

  el.chatMessages.replaceChildren();
  for (const chat of state.chatMessages) {
    const line = document.createElement("p");
    const author = document.createElement("strong");
    author.textContent = `${getPlayerName(chat.playerId)}: `;
    line.append(author, document.createTextNode(chat.message));
    el.chatMessages.appendChild(line);
  }

  const canChat = getSelfPlayer()?.alive === true;
  const busy = state.pending !== null;
  el.chatInput.disabled = !state.connected || busy || !canChat;
  el.chatSubmit.disabled = !state.connected || busy || !canChat || !el.chatInput.value.trim();
  el.chatStatus.textContent = canChat
    ? "Bạn có thể thảo luận ban ngày."
    : "Bạn đã bị loại và chỉ có thể xem thảo luận.";
}

function renderResult() {
  const isGameOver = state.selfPlayerId !== null && state.phase === "GameOver";
  el.resultSection.hidden = !isGameOver;
  if (!isGameOver) return;

  const results = {
    WinnerVillage: ["Dân Làng chiến thắng", "Phe Dân Làng đã loại hết Sói."],
    WinnerWolves: ["Phe Sói chiến thắng", "Số Sói còn sống đã áp đảo Dân Làng."],
    Draw: ["Ván chơi hòa", "Không còn người chơi nào sống sót."]
  };
  const [title, message] = results[state.gameResult] ||
    ["Ván chơi kết thúc", "Server đã kết thúc ván chơi."];
  el.resultTitle.textContent = title;
  el.resultMessage.textContent = message;

  el.revealedRoleList.replaceChildren();
  for (const [playerId, info] of Object.entries(state.revealedRoles)) {
    const item = document.createElement("p");
    item.textContent = `${getPlayerName(playerId)} — ${roleNames[info.role] || info.role}`;
    el.revealedRoleList.appendChild(item);
  }
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
    state.nightActionDone || getSelfPlayer()?.alive === false || state.hunterPending
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
    !["Night", "Voting"].includes(state.phase) ||
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

  if (previousPhase === "Voting" && phase !== "Voting") clearVoteClock();

  // Đồng bộ một phase cho cả T05 và T06; xóa kết quả cũ khi bắt đầu Voting mới.
  if (phase === "Voting" && voting.phase !== "Voting") {
    voting.summary = "";
    voting.tally = [];
  }
  state.phase = phase;
  voting.phase = phase;

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
      if (state.phase !== message.phase) handlePhaseChanged(message.phase);
      Object.assign(voting, {
        phase: message.phase, day: message.day, players: message.players,
        hasVoted: message.hasVoted, canShoot: message.canShoot,
        resolved: message.resolved, result: message.result
      });
      if (message.phase === "Voting" && !message.resolved) startVoteClock(message.day);
      state.hunterPending = message.canShoot;
      if (message.canShoot) state.hunterActionDone = false;
      state.players = message.players.map(player => ({
        ...state.players.find(p => p.playerId === player.playerId), ...player
      }));
      break;

    case "ActionAccepted":
      if (message.requestId === state.pending?.requestId) {
        if (state.pending.type === "Chat") el.chatInput.value = "";
        state.pending = null;
      }
      break;

    case "VotingResolved":
      voting.tally = message.tally;
      voting.resolved = true;
      if (voteClockInterval !== null) clearInterval(voteClockInterval);
      voteClockInterval = null;
      voting.summary = message.targetId
        ? `${playerLabel(message.targetId)} có số phiếu cao nhất duy nhất. Đang xử lý kết quả.`
        : message.tally.length ? "Hòa phiếu cao nhất: không loại ai, không bỏ phiếu lại."
        : "Không có phiếu: không loại ai.";
      break;

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
        voting.canShoot = false;
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
        if (!voting.reveals.some(p => p.playerId === message.playerId)) voting.reveals.push(message);
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
        clearVoteClock();
        state.phase = "GameOver";
        state.gameResult = message.result;
        state.pending = null;

        state.error = "";
      }
      break;

    case "ChatMessage":
      if (message.roomId === state.roomId) {
        state.chatMessages.push({
          playerId: message.playerId,
          message: message.message
        });
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

function switchEntranceMode(mode) {
  state.entranceMode = mode;
  const joining = mode === "join";
  el.joinModeButton.classList.toggle("is-active", joining);
  el.hostModeButton.classList.toggle("is-active", !joining);
  el.joinModeButton.setAttribute("aria-pressed", String(joining));
  el.hostModeButton.setAttribute("aria-pressed", String(!joining));
  el.joinButton.hidden = !joining;
  el.createButton.hidden = joining;
}

el.joinModeButton.addEventListener("click", () => switchEntranceMode("join"));
el.hostModeButton.addEventListener("click", () => switchEntranceMode("host"));
switchEntranceMode("join");

el.joinForm.addEventListener("submit", event => {
  event.preventDefault();

  const fields = readRoomForm();

  if (fields) {
    saveAppearance();
    sendCommand(state.entranceMode === "host" ? "CreateRoom" : "JoinGame", fields);
  }
});

el.createButton.addEventListener("click", () => {
  const fields = readRoomForm();

  if (fields) {
    saveAppearance();
    sendCommand("CreateRoom", fields);
  }
});

for (const id of appearanceIds) {
  document.getElementById(id).addEventListener("change", renderAppearancePreview);
}
document.getElementById("appearance-random").addEventListener("click", () => {
  for (const id of appearanceIds) {
    const select = document.getElementById(id);
    select.selectedIndex = Math.floor(Math.random() * select.options.length);
  }
  renderAppearancePreview();
});
try {
  const saved = JSON.parse(localStorage.getItem("werewolf-appearance") || "null");
  if (saved && typeof saved === "object") {
    const values = [saved.hair, saved.hairColor, saved.skin, saved.outfit, saved.accessory];
    appearanceIds.forEach((id, index) => {
      const select = document.getElementById(id);
      if ([...select.options].some(option => option.value === values[index])) {
        select.value = values[index];
      }
    });
  }
} catch { /* Dữ liệu cũ không hợp lệ: dùng lựa chọn mặc định. */ }
renderAppearancePreview();

el.helpButton.addEventListener("click", () => el.helpDialog.showModal());
for (const dialog of [el.helpDialog, el.roleDialog]) {
  dialog.querySelector(".dialog-close").addEventListener("click", () => dialog.close());
}

el.readyButton.addEventListener("click", () => {
  const me = getSelfPlayer();

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
  sendCommand("Vote", {targetId});
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

el.chatInput.addEventListener("input", render);
el.chatForm.addEventListener("submit", event => {
  event.preventDefault();
  const message = el.chatInput.value.trim();
  if (state.phase === "Day" && getSelfPlayer()?.alive === true && message) {
    sendCommand("Chat", { message });
  }
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
