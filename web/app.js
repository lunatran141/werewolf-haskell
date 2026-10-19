const WS_URL = `${location.protocol === "https:" ? "wss:" : "ws:"}//${location.host}/ws`;let socket = null;
let requestNumber = 0;
const VOTE_DURATION_MS = 60_000;
const DAY_DURATION_MS = 180_000;
let voteClockInterval = null;
let dayClockInterval = null;
const chatBubbleTimers = new Map();
let reconnectTimer = null;
const SESSION_STORAGE_KEY = "werewolf-session";

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
  reconnecting: false,
  selfPlayerId: null,
  hostPlayerId: null,
  players: [],
  pending: null,
  error: "",
  phase: "Lobby",
  selfRole: null,
  selfAbility: null,
  nightActionDone: false,
  nightMessage: "",
  seerResult: null,
  wolfVotesSubmitted: 0,
  wolfVotesTotal: 0,
  wolfTargetLocked: false,
  wolfLockedTargetId: null,
  wolfTeammateIds: [],
  witchVictimId: null,
  witchVictimResolved: false,
  witchHealReady: true,
  witchPoisonReady: true,
  guardLastTargetId: null,
  revealedRoles: {},
  gameResult: null,
  hunterPending: false,
  hunterActionDone: false,
  hunterMessage: "",
  chatMessages: [],
  chatBubbles: {},
  chatDay: null,
  chatChannel: "PublicDay",
  discussionSkipsSubmitted: 0,
  discussionSkipsTotal: 0,
  hasSkippedDiscussion: false,
  appearance: null
};

// T06: Chỉ lưu dữ liệu server cho phép xem, không chứa vai của người còn sống.
const voting = {
  phase: "Lobby", day: 0, players: [], hasVoted: false,
  canShoot: false, resolved: false, result: null, tally: [],
  summary: "", reveals: [], clockDay: null, deadlineMs: null
};

// Đồng hồ phía trình duyệt chỉ giúp người chơi theo dõi. Server vẫn là nguồn
// quyết định duy nhất cho việc kết thúc Day và chuyển sang Voting.
const discussionClock = {day: null, deadlineMs: null};

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
  wolfVoteStatus: document.querySelector("#wolf-vote-status"),
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
  hunterChoicePanel: document.querySelector("#hunter-choice-panel"),
  hunterTarget: document.querySelector("#hunter-target"),
  hunterShoot: document.querySelector("#hunter-shoot"),
  hunterPass: document.querySelector("#hunter-pass"),
  hunterStatus: document.querySelector("#hunter-status"),
  nightWaitingPanel: document.querySelector("#night-waiting-panel"),
  daySection: document.querySelector("#day-section"),
  chatMessages: document.querySelector("#chat-messages"),
  chatDaySelect: document.querySelector("#chat-day-select"),
  chatPublicTab: document.querySelector("#chat-public-tab"),
  chatWolvesTab: document.querySelector("#chat-wolves-tab"),
  chatHeading: document.querySelector("#chat-heading"),
  seerDayResultPanel: document.querySelector("#seer-day-result-panel"),
  seerDayResultText: document.querySelector("#seer-day-result-text"),
  dayClock: document.querySelector("#day-clock"),
  dayClockLabel: document.querySelector("#day-clock-label"),
  dayClockValue: document.querySelector("#day-clock-value"),
  dayClockBar: document.querySelector("#day-clock-bar"),
  discussionSkipPanel: document.querySelector("#discussion-skip-panel"),
  discussionSkipStatus: document.querySelector("#discussion-skip-status"),
  discussionSkipButton: document.querySelector("#discussion-skip-button"),
  chatForm: document.querySelector("#chat-form"),
  chatInput: document.querySelector("#chat-input"),
  chatSubmit: document.querySelector("#chat-submit"),
  chatStatus: document.querySelector("#chat-status"),
  resultSection: document.querySelector("#result-section"),
  resultTitle: document.querySelector("#result-title"),
  resultMessage: document.querySelector("#result-message"),
  revealedRoleList: document.querySelector("#revealed-role-list"),
  returnHomeButton: document.querySelector("#return-home-button"),
  returnHomeStatus: document.querySelector("#return-home-status")
};

const roleNames = {
  Werewolf: "Sói",
  Seer: "Tiên Tri",
  Guard: "Bảo Vệ",
  Witch: "Phù Thủy",
  Villager: "Dân Làng",
  Hunter: "Thợ Săn"
};

const serverErrorMessages = {
  InvalidPlayerId: "Mã người chơi không hợp lệ.",
  INVALID_PLAYER_NAME: "Tên người chơi không hợp lệ.",
  InvalidPlayerName: "Tên người chơi không hợp lệ.",
  DUPLICATE_PLAYER_ID: "Mã người chơi đã tồn tại trong phòng.",
  DuplicatePlayerId: "Mã người chơi đã tồn tại trong phòng.",
  DUPLICATE_PLAYER_NAME: "Tên này đã có người sử dụng trong phòng.",
  DuplicatePlayerName: "Tên này đã có người sử dụng trong phòng.",
  InvalidPlayerCount: "Số người chơi chưa phù hợp để bắt đầu.",
  NotAllReady: "Vẫn còn người chơi chưa sẵn sàng.",
  NOT_AUTHORIZED: "Bạn không có quyền thực hiện hành động này.",
  NotAuthorized: "Bạn không có quyền thực hiện hành động này.",
  WRONG_PHASE: "Không thể thực hiện hành động ở giai đoạn hiện tại.",
  WrongPhase: "Không thể thực hiện hành động ở giai đoạn hiện tại.",
  DeadPlayer: "Người chơi đã chết không thể thực hiện hành động này.",
  PLAYER_NOT_FOUND: "Không tìm thấy người chơi trong phòng.",
  PlayerNotFound: "Không tìm thấy người chơi trong phòng.",
  InvalidTarget: "Mục tiêu không hợp lệ. Hãy chọn một người còn sống đúng luật.",
  AlreadyVoted: "Bạn đã bỏ phiếu trong vòng này.",
  GameAlreadyStarted: "Ván chơi đã bắt đầu.",
  GameAlreadyOver: "Ván chơi đã kết thúc.",
  ROOM_FULL: "Phòng đã đủ người.",
  RoomFull: "Phòng đã đủ người.",
  InvalidRole: "Vai trò của bạn không được phép thực hiện hành động này.",
  InvalidNightAction: "Hành động ban đêm không hợp lệ.",
  AbilityAlreadyUsed: "Khả năng này đã được sử dụng.",
  HunterNotPending: "Thợ Săn chưa được Server cấp quyền bắn.",
  DuplicateNightAction: "Bạn đã gửi hành động trong đêm này.",
  EmptyChat: "Tin nhắn không được để trống.",
  ChatTooLong: "Tin nhắn không được dài quá 300 ký tự.",
  NotReady: "Bạn chưa ở trạng thái sẵn sàng.",
  AlreadySkippedDiscussion: "Bạn đã đồng ý bỏ qua lượt thảo luận này.",
  DuplicateRequest: "Yêu cầu này đã được xử lý trước đó.",
  InvalidAppearance: "Ngoại hình đã chọn không hợp lệ.",
  ROOM_NOT_FOUND: "Không tìm thấy phòng.",
  NOT_JOINED: "Bạn chưa tham gia phòng.",
  WRONG_ROOM: "Yêu cầu không thuộc phòng hiện tại.",
  ALREADY_JOINED: "Bạn đã ở trong một phòng.",
  INVALID_HUNTER_ACTION: "Lựa chọn của Thợ Săn không hợp lệ."
};

function localizedServerError(message) {
  if (serverErrorMessages[message.code]) return serverErrorMessages[message.code];
  if (typeof message.message === "string" && /[^\x00-\x7F]/u.test(message.message)) {
    return message.message;
  }
  return message.code
    ? `Yêu cầu bị từ chối (${message.code}).`
    : "Yêu cầu bị từ chối.";
}

const phaseNames = {
  Lobby: "Phòng chờ",
  Night: "Ban đêm",
  Day: "Ban ngày",
  Voting: "Bỏ phiếu",
  GameOver: "Kết thúc ván"
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
  return state.appearance;
}

function targetSelectionContext() {
  const alive = state.players.filter(player => player.alive !== false);
  const otherAlive = alive.filter(player => player.playerId !== state.selfPlayerId);
  if (state.phase === "Voting" && canChooseTarget() && state.connected && state.pending === null) {
    return {select: voteEl["vote-target"], validIds: new Set(otherAlive.map(player => player.playerId))};
  }
  if (state.hunterPending && state.selfRole === "Hunter" && !state.hunterActionDone &&
      state.connected && state.pending === null) {
    return {select: el.hunterTarget, validIds: new Set(otherAlive.map(player => player.playerId))};
  }
  const canAct = state.phase === "Night" && state.connected && state.pending === null &&
    !state.nightActionDone && getSelfPlayer()?.alive !== false;
  if (!canAct) return null;
  switch (state.selfRole) {
    case "Werewolf":
      return {select: el.wolfTarget, validIds: new Set(otherAlive
        .filter(player => !state.wolfTeammateIds.includes(player.playerId))
        .map(player => player.playerId))};
    case "Seer":
      return {select: el.seerTarget, validIds: new Set(otherAlive.map(player => player.playerId))};
    case "Guard":
      return {select: el.guardTarget, validIds: new Set(alive
        .filter(player => player.playerId !== state.guardLastTargetId)
        .map(player => player.playerId))};
    case "Witch":
      return state.witchVictimResolved && state.witchPoisonReady
        ? {select: el.witchTarget, validIds: new Set(otherAlive.map(player => player.playerId))}
        : null;
    default:
      return null;
  }
}

function chooseTargetFromCard(playerId) {
  const context = targetSelectionContext();
  if (!context?.validIds.has(playerId)) return;
  context.select.value = playerId;
  render();
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
    // Snapshot Server là nguồn dữ liệu chung để mọi trình duyệt thấy cùng avatar.
    // Fallback theo slot chỉ dùng cho contract cũ chưa có appearance.
    const appearance = player.appearance || (isMe && state.appearance
      ? state.appearance
      : {...defaultAppearance, hair: hairstyles[slot % hairstyles.length],
        outfit: outfits[slot % outfits.length], accessory: accessories[slot % accessories.length]});
    const avatar = makeAvatar(appearance, player.playerId);
    const bubbleText = state.chatBubbles[player.playerId];
    if (bubbleText) {
      const bubble = document.createElement("div");
      bubble.className = "dashboard-chat-bubble";
      bubble.textContent = bubbleText;
      item.appendChild(bubble);
    }
    const footer = document.createElement("div");
    footer.className = "dashboard-card-footer";
    footer.textContent = isDead ? "✕ Đã bị loại"
      : state.phase === "Lobby" ? (player.ready ? "✓ Sẵn sàng" : "Chưa sẵn sàng")
      : "Đang chơi";
    item.append(name, avatar, footer);

    const targetContext = targetSelectionContext();
    const targetable = targetContext?.validIds.has(player.playerId) === true;
    const selected = targetContext?.select.value === player.playerId;
    item.classList.toggle("is-targetable", targetable);
    item.classList.toggle("is-selected-target", selected);
    if (targetable) {
      item.tabIndex = 0;
      item.setAttribute("role", "button");
      item.setAttribute("aria-label", `Chọn ${player.displayName || player.playerId} làm mục tiêu`);
      item.addEventListener("click", () => chooseTargetFromCard(player.playerId));
      item.addEventListener("keydown", event => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          chooseTargetFromCard(player.playerId);
        }
      });
    }

    if (isMe && state.phase !== "Lobby" && state.selfRole) {
      const role = document.createElement("div");
      role.className = "dashboard-own-role";
      role.textContent = roleNames[state.selfRole] || state.selfRole;
      const help = document.createElement("button");
      help.type = "button";
      help.className = "dashboard-ability-button";
      help.textContent = "Khả năng của tôi";
      help.addEventListener("click", event => {
        if (event?.stopPropagation) event.stopPropagation();
        document.getElementById("role-help-title").textContent = role.textContent;
        const ability = state.selfAbility;
        document.getElementById("role-help-text").textContent = ability
          ? [ability.description, ability.phase && `Giai đoạn: ${phaseNames[ability.phase] || ability.phase}`,
            ability.targetRules && `Mục tiêu: ${ability.targetRules}`].filter(Boolean).join("\n")
          : roleHelp[state.selfRole] || "Chưa có hướng dẫn.";
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

function startVoteClock(day, remainingMs = null) {
  if (Number.isFinite(remainingMs)) {
    voting.clockDay = day;
    voting.deadlineMs = Date.now() + Math.max(0, remainingMs);
  } else if (voting.clockDay !== day || voting.deadlineMs === null) {
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

function clearDayClock() {
  if (dayClockInterval !== null) clearInterval(dayClockInterval);
  dayClockInterval = null;
  discussionClock.day = null;
  discussionClock.deadlineMs = null;
}

function renderDayClock() {
  const visible = state.phase === "Day" && discussionClock.deadlineMs !== null;
  el.dayClock.hidden = !visible;
  if (!visible) return;
  const remaining = Math.max(0, discussionClock.deadlineMs - Date.now());
  const seconds = Math.ceil(remaining / 1000);
  el.dayClockValue.textContent = `${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`;
  el.dayClockBar.style.setProperty("width", `${remaining / DAY_DURATION_MS * 100}%`);
  el.dayClock.classList.toggle("is-urgent", seconds <= 15);
  el.dayClockLabel.textContent = seconds === 0
    ? "Đã hết giờ · chờ Server chuyển sang bỏ phiếu"
    : "Thời gian thảo luận";
}

function startDayClock(day, remainingMs = null) {
  if (Number.isFinite(remainingMs)) {
    discussionClock.day = day;
    discussionClock.deadlineMs = Date.now() + Math.max(0, remainingMs);
  } else if (discussionClock.day !== day || discussionClock.deadlineMs === null) {
    discussionClock.day = day;
    discussionClock.deadlineMs = Date.now() + DAY_DURATION_MS;
  }
  if (dayClockInterval === null) {
    dayClockInterval = setInterval(() => {
      renderDayClock();
      if (Date.now() >= discussionClock.deadlineMs) {
        clearInterval(dayClockInterval);
        dayClockInterval = null;
        renderDayClock();
      }
    }, 250);
  }
  renderDayClock();
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
  // Không dựng form bỏ phiếu trong Night/Day: chỉ Server được quyền mở Voting.
  const active = state.connected && state.selfPlayerId !== null &&
    state.phase === "Voting" && voting.phase === "Voting";
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
  // Không công khai vai khi bị loại; danh sách vai chỉ có ở GameOver.
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
  state.selfAbility = null;
  state.nightActionDone = false;
  state.nightMessage = "";
  state.seerResult = null;
  state.wolfVotesSubmitted = 0;
  state.wolfVotesTotal = 0;
  state.wolfTargetLocked = false;
  state.wolfLockedTargetId = null;
  state.wolfTeammateIds = [];
  state.witchVictimId = null;
  state.witchVictimResolved = false;
  state.witchHealReady = true;
  state.witchPoisonReady = true;
  state.guardLastTargetId = null;
  state.revealedRoles = {};
  state.gameResult = null;
  state.hunterPending = false;
  state.hunterActionDone = false;
  state.hunterMessage = "";
  state.chatMessages = [];
  state.chatBubbles = {};
  for (const timer of chatBubbleTimers.values()) {
    if (typeof clearTimeout === "function") clearTimeout(timer);
  }
  chatBubbleTimers.clear();
  state.chatDay = null;
  state.chatChannel = "PublicDay";
  state.discussionSkipsSubmitted = 0;
  state.discussionSkipsTotal = 0;
  state.hasSkippedDiscussion = false;
}

function resetRoomState() {
  clearVoteClock();
  clearDayClock();
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
  const inRoom = state.connected && state.selfPlayerId !== null;
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
  setTargetOptions(el.wolfTarget, otherPlayers.filter(player =>
    !state.wolfTeammateIds.includes(player.playerId)));
  setTargetOptions(el.seerTarget, otherPlayers);
  setTargetOptions(el.guardTarget, alivePlayers.filter(player =>
    player.playerId !== state.guardLastTargetId));
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
  const inRoom = state.connected && state.selfPlayerId !== null;
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
  const witchCanChoose = canAct && state.witchVictimResolved;

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
  el.witchTarget.disabled = !witchCanChoose;

  el.wolfSubmit.disabled =
    !canAct || !el.wolfTarget.value;

  if (state.wolfTargetLocked) {
    el.wolfVoteStatus.textContent = state.wolfLockedTargetId === null
      ? "Phiếu Sói đã khóa: hòa hoặc không có phiếu, đêm nay không có nạn nhân."
      : `Phiếu Sói đã khóa mục tiêu: ${getPlayerName(state.wolfLockedTargetId)}.`;
  } else if (state.wolfVotesTotal > 0) {
    el.wolfVoteStatus.textContent =
      `Đã chốt ${state.wolfVotesSubmitted}/${state.wolfVotesTotal} Sói. ` +
      "Mỗi Sói còn sống cần gửi một lựa chọn.";
  } else {
    el.wolfVoteStatus.textContent =
      "Hãy cùng các Sói còn sống chốt một mục tiêu.";
  }

  el.seerSubmit.disabled =
    !canAct || !el.seerTarget.value;

  el.guardSubmit.disabled =
    !canAct || !el.guardTarget.value;

  el.witchHeal.disabled =
    !witchCanChoose || !state.witchHealReady || state.witchVictimId === null;

  el.witchPoison.disabled =
    !witchCanChoose || !state.witchPoisonReady || !el.witchTarget.value;

  el.witchPass.disabled = !witchCanChoose;

  if (state.nightMessage) {
    el.nightStatus.textContent = state.nightMessage;
  } else if (state.nightActionDone) {
    el.nightStatus.textContent =
      "Hành động đã được Server xác nhận.";
  } else if (!role) {
    el.nightStatus.textContent =
      "Đang chờ thông tin vai trò từ Server.";
  } else if (role === "Witch" && !state.witchVictimResolved) {
    el.nightStatus.textContent =
      "Đang chờ tất cả Sói chốt mục tiêu trước khi Phù Thủy hành động.";
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

  el.witchVictimPanel.hidden = role !== "Witch";

  if (role === "Witch" && !state.witchVictimResolved) {
    el.witchVictimText.textContent =
      "Đang chờ tất cả Sói còn sống chốt mục tiêu. Bạn chưa cần chọn hành động.";
  } else if (role === "Witch" && state.witchVictimId === null) {
    el.witchVictimText.textContent =
      "Phiếu Sói hòa hoặc không có phiếu, nên đêm này không có nạn nhân để cứu. Bạn có thể dùng thuốc độc hoặc bỏ lượt.";
  } else if (state.witchVictimId !== null) {
    el.witchVictimText.textContent =
      `Nạn nhân được Sói chọn: ${
        getPlayerName(state.witchVictimId)
      }.`;
  }
}

// T06: Một bảng Hunter dùng chung cho Night và Voting, không phụ thuộc panel Night.
function renderHunter() {
  // Vai Thợ Săn đã có thẻ chung như các vai khác trong Night. Chỉ mở thẻ
  // hành động độc lập khi Server thực sự cấp quyền bắn sau lúc bị loại.
  const active = state.connected && state.selfPlayerId !== null && state.selfRole === "Hunter" &&
    state.hunterPending;
  el.hunterPanel.hidden = !active;
  const allowed = active && state.connected && state.pending === null &&
    state.hunterPending && !state.hunterActionDone && ["Night", "Voting"].includes(state.phase);
  setTargetOptions(el.hunterTarget, state.players.filter(p =>
    p.playerId !== state.selfPlayerId && p.alive !== false && !state.revealedRoles[p.playerId]));
  el.hunterPendingPanel.hidden = !state.hunterPending;
  el.hunterChoicePanel.hidden = !state.hunterPending;
  el.hunterTarget.disabled = !allowed;
  el.hunterShoot.disabled = !allowed || !el.hunterTarget.value;
  el.hunterPass.disabled = !allowed;
  el.hunterStatus.textContent = !state.connected ? "Mất kết nối. Không thể gửi lựa chọn."
    : state.hunterMessage || (state.hunterPending
      ? "Bạn có thể bắn hoặc bỏ lượt; hết hạn sẽ tự bỏ qua."
      : "Bạn đang còn sống; quyền bắn chỉ mở sau khi bạn bị loại và Server xác nhận.");
}

function render() {
  document.body.dataset.phase = state.phase;
  document.body.classList.toggle("phase-day", state.phase === "Day");
  document.body.classList.toggle("phase-night", state.phase === "Night");
  document.body.classList.toggle("phase-voting", state.phase === "Voting");
  document.body.classList.toggle("phase-game-over", state.phase === "GameOver");
  document.body.classList.toggle("hunter-pending", state.hunterPending === true);

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
  const inGame = state.connected && state.selfPlayerId !== null && state.phase !== "Lobby";
  el.daySection.hidden = !inGame;
  if (!inGame) return;

  const showSeerDayResult = state.phase === "Day" &&
    state.selfRole === "Seer" && state.seerResult !== null;
  el.seerDayResultPanel.hidden = !showSeerDayResult;
  if (showSeerDayResult) {
    const teamName = state.seerResult === "Wolves" ? "Sói" : "Dân Làng";
    el.seerDayResultText.textContent =
      `Kết quả lượt soi đêm vừa rồi: người bạn chọn thuộc phe ${teamName}.`;
  }

  const isWolf = state.selfRole === "Werewolf";
  if (!isWolf && state.chatChannel === "WolvesNight") state.chatChannel = "PublicDay";
  el.chatWolvesTab.hidden = !isWolf;
  el.chatPublicTab.setAttribute("aria-pressed", String(state.chatChannel === "PublicDay"));
  el.chatWolvesTab.setAttribute("aria-pressed", String(state.chatChannel === "WolvesNight"));
  el.chatPublicTab.classList.toggle("is-active", state.chatChannel === "PublicDay");
  el.chatWolvesTab.classList.toggle("is-active", state.chatChannel === "WolvesNight");

  const days = new Set(state.chatMessages.filter(chat => chat.channel === state.chatChannel)
    .map(chat => chat.day));
  if (Number.isInteger(voting.day) && voting.day > 0) days.add(voting.day);
  const currentDay = state.chatDay ?? (voting.day > 0 ? voting.day : 1);
  days.add(currentDay);
  el.chatDaySelect.replaceChildren();
  for (const day of [...days].sort((a, b) => a - b)) {
    const option = document.createElement("option");
    option.value = String(day);
    option.textContent = `Ngày ${day}`;
    el.chatDaySelect.appendChild(option);
  }
  el.chatDaySelect.value = String(currentDay);
  el.chatHeading.textContent = `${state.chatChannel === "WolvesNight" ? "Chat Sói · Đêm" : "Chat chung · Ngày"} ${currentDay}`;
  renderDayClock();

  const canSkipDiscussion = state.phase === "Day" && getSelfPlayer()?.alive === true;
  el.discussionSkipPanel.hidden = state.phase !== "Day";
  el.discussionSkipStatus.textContent =
    `${state.discussionSkipsSubmitted}/${state.discussionSkipsTotal} người còn sống đã đồng ý.`;
  el.discussionSkipButton.disabled = !state.connected || state.pending !== null ||
    !canSkipDiscussion || state.hasSkippedDiscussion;
  el.discussionSkipButton.textContent = state.hasSkippedDiscussion
    ? "Đã đồng ý · Chờ người còn lại"
    : "Đồng ý chuyển sang bỏ phiếu";

  el.chatMessages.replaceChildren();
  const marker = document.createElement("div");
  marker.className = "chat-day-marker";
  marker.textContent = state.chatChannel === "WolvesNight"
    ? `Đêm ${currentDay}`
    : `Ngày ${currentDay} bắt đầu`;
  el.chatMessages.appendChild(marker);
  const visible = state.chatMessages.filter(chat => chat.day === currentDay &&
    chat.channel === state.chatChannel).sort((a, b) => a.sequence - b.sequence);
  for (const chat of visible) {
    const line = document.createElement("p");
    if (chat.playerId === "__system__") {
      line.className = "chat-system-message";
      line.textContent = chat.message;
      el.chatMessages.appendChild(line);
      continue;
    }
    const author = document.createElement("strong");
    author.textContent = `${getPlayerName(chat.playerId)}: `;
    line.append(author, document.createTextNode(chat.message));
    el.chatMessages.appendChild(line);
  }
  if (visible.length === 0) {
    const empty = document.createElement("p");
    empty.className = "chat-empty";
    empty.textContent = "Chưa có tin nhắn cho mục này.";
    el.chatMessages.appendChild(empty);
  }

  const isCurrentDay = currentDay === voting.day;
  const canChatPublic = state.chatChannel === "PublicDay" && state.phase === "Day";
  const canChatWolves = state.chatChannel === "WolvesNight" &&
    state.phase === "Night" && isWolf;
  const canChat = getSelfPlayer()?.alive === true && isCurrentDay &&
    (canChatPublic || canChatWolves);
  const busy = state.pending !== null;
  el.chatInput.disabled = !state.connected || busy || !canChat;
  el.chatSubmit.disabled = !state.connected || busy || !canChat || !el.chatInput.value.trim();
  el.chatStatus.textContent = state.chatChannel === "WolvesNight"
    ? canChat ? "Chỉ các Sói còn sống trong phòng nhận được tin nhắn này."
      : "Chat Sói chỉ mở cho Sói còn sống vào ban đêm."
    : canChat ? "Bạn có thể thảo luận ban ngày."
    : "Đang xem lịch sử; chỉ người còn sống mới gửi được ở ban ngày hiện tại.";
}

function renderResult() {
  const isGameOver = state.connected && state.selfPlayerId !== null && state.phase === "GameOver";
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

  el.returnHomeButton.hidden = false;
  el.returnHomeButton.disabled = !state.connected || state.pending !== null;
  el.returnHomeButton.textContent = state.pending?.type === "LeaveGame"
    ? "Đang rời phòng..."
    : "Rời phòng và quay lại";
  el.returnHomeStatus.textContent =
    "Bạn có thể tạo phòng mới hoặc tham gia một phòng khác.";

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

function readSavedSession() {
  try {
    const saved = JSON.parse(localStorage.getItem(SESSION_STORAGE_KEY) || "null");
    return saved && typeof saved.roomId === "string" &&
      typeof saved.sessionToken === "string" ? saved : null;
  } catch {
    return null;
  }
}

function saveSession(roomId, playerId, sessionToken) {
  try {
    const previous = readSavedSession();
    localStorage.setItem(SESSION_STORAGE_KEY,
      JSON.stringify({roomId, playerId, sessionToken,
        lastVersion: previous?.roomId === roomId ? previous.lastVersion : 0}));
  } catch { /* Trình duyệt chặn localStorage: ván vẫn chơi được nhưng không tự nối lại. */ }
}

function saveRoomVersion(roomId, version) {
  const saved = readSavedSession();
  if (!saved || saved.roomId !== roomId || !Number.isSafeInteger(version) || version < 0) return;
  const previousVersion = Number.isSafeInteger(saved.lastVersion) ? saved.lastVersion : 0;
  if (!state.reconnecting && previousVersion > 0 && version > previousVersion + 1) return false;
  try {
    saved.lastVersion = Math.max(previousVersion, version);
    localStorage.setItem(SESSION_STORAGE_KEY, JSON.stringify(saved));
  } catch { /* Cursor không ảnh hưởng khả năng chơi nếu storage bị chặn. */ }
  state.reconnecting = false;
  return true;
}

function clearSavedSession() {
  try { localStorage.removeItem(SESSION_STORAGE_KEY); } catch { /* Không có quyền lưu trữ. */ }
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

  if (state.selfRole === "Witch" && !state.witchVictimResolved) {
    state.error = "Phù Thủy phải chờ Server khóa phiếu Sói trước khi hành động.";
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

let dayTransitionTimer = null;

function showDayTransition() {
  document.querySelector(".day-transition")?.remove();
  clearTimeout(dayTransitionTimer);

  const overlay = document.createElement("div");
  overlay.className = "day-transition";
  overlay.setAttribute("aria-hidden", "true");

  const sun = document.createElement("span");
  sun.className = "day-transition-sun";
  sun.textContent = "☀️";

  overlay.appendChild(sun);
  document.body.appendChild(overlay);

  dayTransitionTimer = setTimeout(() => {
    overlay.remove();
    dayTransitionTimer = null;
  }, 1600);
}

function handlePhaseChanged(phase) {
  const previousPhase = state.phase;

  if (previousPhase === "Voting" && phase !== "Voting") clearVoteClock();
  if (previousPhase === "Day" && phase !== "Day") clearDayClock();

  // Đồng bộ một phase cho cả T05 và T06; xóa kết quả cũ khi bắt đầu Voting mới.
  if (phase === "Voting" && voting.phase !== "Voting") {
    voting.summary = "";
    voting.tally = [];
  }
  state.phase = phase;
  voting.phase = phase;
  if (previousPhase === "Night" && phase === "Day") {
  showDayTransition();
}

  if (phase === "Day" && previousPhase !== "Day") {
    state.discussionSkipsSubmitted = 0;
    state.discussionSkipsTotal = state.players.filter(player => player.alive).length;
    state.hasSkippedDiscussion = false;
  }
  if (phase !== "Day") {
    state.discussionSkipsSubmitted = 0;
    state.discussionSkipsTotal = 0;
    state.hasSkippedDiscussion = false;
  }

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
    state.wolfVotesSubmitted = 0;
    state.wolfVotesTotal = 0;
    state.wolfTargetLocked = false;
    state.wolfLockedTargetId = null;
    state.witchVictimId = null;
    state.witchVictimResolved = false;
    state.hunterPending = false;
    state.hunterActionDone = false;
    state.hunterMessage = "";
  }

  if (phase !== "Night") {
    state.nightActionDone = false;
    state.nightMessage = "";
    // Giữ kết quả riêng của Tiên Tri khi Night chuyển sang Day để họ kịp xem.
    // Kết quả chỉ bị xóa ở nhánh bắt đầu Night mới phía trên.
    state.wolfVotesSubmitted = 0;
    state.wolfVotesTotal = 0;
    state.wolfTargetLocked = false;
    state.wolfLockedTargetId = null;
    state.witchVictimId = null;
    state.witchVictimResolved = false;
    state.hunterPending = false;
    state.hunterActionDone = false;
    state.hunterMessage = "";
  }
}

function receiveChat(chat, showBubble = true) {
  const day = Number(chat.day ?? voting.day);
  const channel = chat.channel || "PublicDay";
  const playerId = chat.senderId ?? chat.playerId;
  const message = chat.text ?? chat.message;
  if (!Number.isInteger(day) || day < 1 || !["PublicDay", "WolvesNight"].includes(channel)) return;
  if (channel === "WolvesNight" && state.selfRole !== "Werewolf") return;
  if (typeof message !== "string" || !playerId) return;
  if (state.chatMessages.some(item => item.day === day && item.channel === channel &&
    (chat.messageId != null && item.messageId === chat.messageId ||
      Number.isInteger(chat.sequence) && item.sequence === chat.sequence))) return;
  state.chatMessages.push({
    day, channel, messageId: chat.messageId ?? null,
    sequence: Number.isInteger(chat.sequence) ? chat.sequence : state.chatMessages.length,
    playerId, message
  });

  // Khi Server vừa chốt Voting, giữ khung chat ở ngày vừa kết thúc để người
  // chơi nhìn thấy ngay kết quả trong lúc chuyển sang Night kế tiếp.
  if (showBubble && playerId === "__system__" && channel === "PublicDay") {
    state.chatDay = day;
  }

  if (showBubble && playerId !== "__system__" &&
      state.players.some(player => player.playerId === playerId)) {
    state.chatBubbles[playerId] = message;
    if (typeof clearTimeout === "function" && chatBubbleTimers.has(playerId)) {
      clearTimeout(chatBubbleTimers.get(playerId));
    }
    if (typeof setTimeout === "function") {
      chatBubbleTimers.set(playerId, setTimeout(() => {
        delete state.chatBubbles[playerId];
        chatBubbleTimers.delete(playerId);
        render();
      }, 5000));
    }
  }
}

function handleServerMessage(message) {
  // Không áp dụng thông điệp của phòng khác vào UI đang mở.
  if (message.roomId && state.roomId && message.roomId !== state.roomId && message.type !== "LobbySnapshot") return;
  switch (message.type) {
    case "RoomVersion":
      if (saveRoomVersion(message.roomId, message.version) === false) socket.close();
      break;

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
      if (message.phase === "Day") startDayClock(message.day);
      state.hunterPending = message.canShoot;
      if (message.canShoot) state.hunterActionDone = false;
      state.players = message.players.map(player => ({
        ...state.players.find(p => p.playerId === player.playerId), ...player
      }));
      break;

    case "PhaseTimeRemaining":
      if (message.phase !== state.phase || message.day !== voting.day ||
          !Number.isFinite(message.remainingMs)) break;
      if (message.phase === "Day") startDayClock(message.day, message.remainingMs);
      if (message.phase === "Voting" && !voting.resolved) {
        startVoteClock(message.day, message.remainingMs);
      }
      break;

    case "DiscussionSkipState":
      state.discussionSkipsSubmitted = Number.isInteger(message.submitted)
        ? message.submitted : 0;
      state.discussionSkipsTotal = Number.isInteger(message.total)
        ? message.total : 0;
      state.hasSkippedDiscussion = message.hasSkipped === true;
      break;

    case "PrivateActionState":
      if (message.roomId === state.roomId) {
        if (state.phase === "Night") {
          state.nightActionDone = message.nightActionSubmitted === true;
          if (state.nightActionDone) {
            state.nightMessage = "Hành động đã được Server xác nhận.";
          }
        }
        if (typeof message.witchHealReady === "boolean") {
          state.witchHealReady = message.witchHealReady;
        }
        if (typeof message.witchPoisonReady === "boolean") {
          state.witchPoisonReady = message.witchPoisonReady;
        }
        state.guardLastTargetId = typeof message.lastProtectedId === "string"
          ? message.lastProtectedId : null;
      }
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

    case "SessionEstablished":
      if (message.roomId && message.playerId && message.sessionToken) {
        saveSession(message.roomId, message.playerId, message.sessionToken);
        state.roomId = message.roomId;
        state.selfPlayerId = message.playerId;
        if (state.pending?.type === "Reconnect") state.pending = null;
      }
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
        clearSavedSession();
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
        if (message.role !== "Werewolf") state.wolfTeammateIds = [];
        state.selfAbility = message.ability && typeof message.ability.description === "string"
          ? message.ability : null;
        state.nightMessage =
          "Bạn đã nhận vai trò từ Server.";
      }
      break;

    case "WolfTeam":
      if (message.roomId === state.roomId && state.selfRole === "Werewolf") {
        state.wolfTeammateIds = Array.isArray(message.playerIds)
          ? message.playerIds.filter(playerId => typeof playerId === "string")
          : [];
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

    case "WolfVoteUpdated":
      if (message.roomId === state.roomId) {
        state.wolfVotesSubmitted = Number.isInteger(message.submitted)
          ? message.submitted : 0;
        state.wolfVotesTotal = Number.isInteger(message.total)
          ? message.total : 0;
        state.nightMessage =
          `Sói đã chốt ${state.wolfVotesSubmitted}/${state.wolfVotesTotal} lựa chọn.`;
      }
      break;

    case "WolfTargetLocked":
      if (message.roomId === state.roomId) {
        state.wolfTargetLocked = true;
        state.wolfLockedTargetId = message.targetId ?? null;
        state.nightMessage = state.wolfLockedTargetId === null
          ? "Phiếu Sói đã khóa nhưng không có nạn nhân duy nhất."
          : `Mục tiêu của đàn Sói đã khóa: ${getPlayerName(state.wolfLockedTargetId)}.`;
      }
      break;

    case "WitchVictimNotice":
      if (message.roomId === state.roomId) {
        state.witchVictimResolved = true;
        state.witchVictimId = message.victimId;
        state.nightMessage = message.victimId === null
          ? "Phiếu Sói đã khóa nhưng không có nạn nhân duy nhất để cứu."
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

    case "PlayerDied":
    case "PlayerEliminated":
      if (message.roomId === state.roomId) {
        state.players = state.players.map(player => player.playerId === message.playerId
          ? {...player, alive: false} : player);
      }
      break;

    case "PlayerRoleRevealed":
      // Legacy event: không đưa vai người chết lên UI trước GameOver.
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

    case "GameRolesRevealed":
      if (message.roomId === state.roomId && state.phase === "GameOver" && Array.isArray(message.roles)) {
        state.revealedRoles = {};
        for (const entry of message.roles) {
          if (entry && entry.playerId && roleNames[entry.role]) {
            state.revealedRoles[entry.playerId] = {role: entry.role};
          }
        }
      }
      break;

    case "ChatMessage":
      if (message.roomId === state.roomId) {
        receiveChat(message);
      }
      break;

    case "ChatHistorySnapshot":
      // Chỉ hiện dữ liệu lịch sử Server cấp cho chính kết nối này; không tự suy vai hay kênh.
      if (message.roomId === state.roomId && Array.isArray(message.messages)) {
        for (const chat of message.messages) receiveChat(chat, false);
      }
      break;

    case "CommandRejected":
      if (message.code === "INVALID_SESSION") {
        // Token trong localStorage có thể thuộc một RoomRuntime đã được dọn khi
        // người cuối cùng rời phòng hoặc khi Server khởi động lại. Đây là trạng
        // thái bình thường lúc mở lại trang: quên phiên cũ và hiện form vào phòng.
        clearSavedSession();
        resetRoomState();
        state.error = "";
        break;
      }
      if (
        message.requestId === null ||
        message.requestId === state.pending?.requestId
      ) {
        const localizedError = localizedServerError(message);
        if (state.pending?.type === "NightAction") {
          state.nightMessage = localizedError;
        }

        if (state.pending?.type === "HunterAction") {
          state.hunterMessage = localizedError;

          // Giu Hunter pending va mo lai nut khi Server tu choi.
          state.hunterActionDone = false;
        }

        state.pending = null;
        state.error = localizedError;
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
    const appearance = saveAppearance();
    sendCommand(state.entranceMode === "host" ? "CreateRoom" : "JoinGame",
      {...fields, appearance});
  }
});

el.createButton.addEventListener("click", () => {
  const fields = readRoomForm();

  if (fields) {
    const appearance = saveAppearance();
    sendCommand("CreateRoom", {...fields, appearance});
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

el.returnHomeButton.addEventListener("click", () => {
  if (state.phase === "GameOver" && state.selfPlayerId !== null) {
    sendCommand("LeaveGame");
  }
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
el.chatDaySelect.addEventListener("change", () => {
  state.chatDay = Number(el.chatDaySelect.value);
  renderDay();
});
el.chatPublicTab.addEventListener("click", () => {
  state.chatChannel = "PublicDay";
  renderDay();
});
el.chatWolvesTab.addEventListener("click", () => {
  if (state.selfRole === "Werewolf") {
    state.chatChannel = "WolvesNight";
    renderDay();
  }
});
el.chatForm.addEventListener("submit", event => {
  event.preventDefault();
  const message = el.chatInput.value.trim();
  const correctPhase =
    state.chatChannel === "PublicDay" && state.phase === "Day" ||
    state.chatChannel === "WolvesNight" && state.phase === "Night" && state.selfRole === "Werewolf";
  if (correctPhase && (state.chatDay ?? voting.day) === voting.day &&
      getSelfPlayer()?.alive === true && message) {
    sendCommand("Chat", { channel: state.chatChannel, message });
  }
});

el.discussionSkipButton.addEventListener("click", () => {
  if (state.phase === "Day" && getSelfPlayer()?.alive === true &&
      !state.hasSkippedDiscussion) {
    sendCommand("SkipDiscussion");
  }
});

function connectSocket() {
  socket = new WebSocket(WS_URL);

  socket.addEventListener("open", () => {
    state.connected = true;
    state.error = "";
    const saved = readSavedSession();
    if (saved) {
      state.reconnecting = true;
      const requestId = `reconnect-${Date.now()}-${++requestNumber}`;
      state.pending = {type: "Reconnect", requestId};
      socket.send(JSON.stringify({
        type: "Reconnect", requestId,
        roomId: saved.roomId, sessionToken: saved.sessionToken,
        lastVersion: Number.isSafeInteger(saved.lastVersion) ? saved.lastVersion : 0
      }));
    }
    render();
  });

  socket.addEventListener("message", event => {
    let message;
    try {
      message = JSON.parse(event.data);
    } catch {
      state.error = "Server gửi dữ liệu JSON không hợp lệ.";
      render();
      return;
    }

    try {
      handleServerMessage(message);
    } catch (error) {
      console.error("Loi xu ly Server message:", error);
      state.error = "Không xử lý được phản hồi từ Server.";
      render();
    }
  });

  socket.addEventListener("close", () => {
    state.connected = false;
    state.pending = null;
    state.error = readSavedSession()
      ? "Mất kết nối Server. Đang thử nối lại..."
      : "Đã mất kết nối Server.";
    render();
    if (typeof setTimeout === "function" && reconnectTimer === null) {
      reconnectTimer = setTimeout(() => {
        reconnectTimer = null;
        connectSocket();
      }, 1500);
    }
  });

  socket.addEventListener("error", () => {
    state.error = "Không kết nối được Server.";
    render();
  });
}

connectSocket();

render();
