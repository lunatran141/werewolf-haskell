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

function serverTargetIds(action) {
  const snapshot = state.validTargets;
  if (!snapshot || state.reconnecting || snapshot.phase !== state.phase ||
      snapshot.day !== voting.day || !Array.isArray(snapshot.actions[action])) return null;
  return new Set(snapshot.actions[action]);
}

function targetSelectionContext() {
  if (state.phase === "Voting" && canChooseTarget() && state.connected && state.pending === null) {
    const validIds = serverTargetIds("Vote");
    return validIds ? {select: voteEl["vote-target"], validIds} : null;
  }
  if (state.hunterPending && state.selfRole === "Hunter" && !state.hunterActionDone &&
      state.connected && state.pending === null) {
    const validIds = serverTargetIds("HunterShot");
    return validIds ? {select: el.hunterTarget, validIds} : null;
  }
  const canAct = state.phase === "Night" && state.connected && state.pending === null &&
    !state.nightActionDone && getSelfPlayer()?.alive !== false;
  if (!canAct) return null;
  const choices = {
    Werewolf: ["WolfTarget", el.wolfTarget],
    Seer: ["SeerTarget", el.seerTarget],
    Guard: ["GuardTarget", el.guardTarget],
    Witch: ["WitchPoison", el.witchTarget]
  };
  const choice = choices[state.selfRole];
  if (!choice || (state.selfRole === "Witch" &&
      (!state.witchVictimResolved || !state.witchPoisonReady))) return null;
  const validIds = serverTargetIds(choice[0]);
  return validIds ? {select: choice[1], validIds} : null;
}

function chooseTargetFromCard(playerId) {
  const context = targetSelectionContext();
  if (!context?.validIds.has(playerId)) return;
  context.select.value = playerId;
  render();
  const selectedCard = [...el.playerList.children]
    .find(card => card.dataset.playerId === playerId);
  selectedCard?.focus?.();
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
    item.dataset.playerId = player.playerId;
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
    const targetContext = targetSelectionContext();
    const targetable = targetContext?.validIds.has(player.playerId) === true;
    const selected = targetContext?.select.value === player.playerId;
    const footer = document.createElement("div");
    footer.className = "dashboard-card-footer";
    const unavailableReason = targetContext && !targetable
      ? isDead ? "Đã bị loại"
        : isMe && targetContext.select !== el.guardTarget ? "Không chọn chính mình"
        : state.selfRole === "Werewolf" && state.wolfTeammateIds.includes(player.playerId)
          ? "Không chọn đồng đội Sói"
          : state.selfRole === "Guard" && state.guardLastTargetId === player.playerId
            ? "Không bảo vệ cùng người hai đêm"
            : "Mục tiêu không hợp lệ"
      : null;
    footer.textContent = isDead ? "✕ Đã bị loại"
      : unavailableReason || (targetContext ? "Có thể chọn"
        : state.phase === "Lobby" ? (player.ready ? "✓ Sẵn sàng" : "Chưa sẵn sàng")
        : "Đang chơi");
    item.append(name, avatar, footer);

    item.classList.toggle("is-targetable", targetable);
    item.classList.toggle("is-selected-target", selected);
    item.classList.toggle("is-unavailable-target", Boolean(unavailableReason));
    if (unavailableReason) item.setAttribute("aria-label", `${player.displayName}: ${unavailableReason}`);
    if (targetable) {
      item.tabIndex = 0;
      item.setAttribute("role", "button");
      item.setAttribute("aria-pressed", String(selected));
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
  const validVotes = serverTargetIds("Vote");
  for (const player of voting.players.filter(p => validVotes?.has(p.playerId))) {
    const option = document.createElement("option");
    option.value = player.playerId;
    option.textContent = player.displayName;
    target.appendChild(option);
  }
  if (validVotes?.has(previous)) {
    target.value = previous;
  }
  target.disabled = !allowed || validVotes === null;
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
  state.validTargets = null;
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
  state.reconnecting = false;
  state.retryCommand = null;
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
  for (const [action, select] of [
    ["WolfTarget", el.wolfTarget], ["SeerTarget", el.seerTarget],
    ["GuardTarget", el.guardTarget], ["WitchPoison", el.witchTarget],
    ["HunterShot", el.hunterTarget]
  ]) {
    const validIds = serverTargetIds(action);
    setTargetOptions(select, state.players.filter(player => validIds?.has(player.playerId)));
  }
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
    ["Werewolf", "Seer", "Guard", "Witch"].includes(role) ||
    state.hunterPending;

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
  } else if (role === "Hunter") {
    el.nightStatus.textContent =
      "Bạn không có hành động ban đêm. Quyền bắn chỉ mở sau khi bạn bị loại và Server xác nhận.";
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
  const hunterTargets = serverTargetIds("HunterShot");
  setTargetOptions(el.hunterTarget, state.players.filter(p => hunterTargets?.has(p.playerId)));
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
  const inGame = state.selfPlayerId !== null && state.phase !== "Lobby";
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

  const isCurrentDay = Number(currentDay) === Number(voting.day);
  const me = getSelfPlayer();
  const isWolfChat = state.chatChannel === "WolvesNight";
  const correctPhase = isWolfChat
    ? state.phase === "Night" && state.selfRole === "Werewolf"
    : state.phase === "Day";
  const canType = state.connected && me?.alive === true &&
    isCurrentDay && correctPhase;
  const busy = state.pending !== null;

  // Có thể soạn tin trong lúc chờ Server, nhưng chỉ gửi khi yêu cầu trước hoàn tất.
  el.chatInput.disabled = !canType;
  el.chatSubmit.disabled = !canType || busy || !el.chatInput.value.trim();
  el.chatStatus.textContent = !state.connected
    ? "Mất kết nối Server. Chưa thể gửi tin."
    : me?.alive !== true
      ? "Bạn đã bị loại nên không thể gửi tin."
      : !isCurrentDay
        ? "Bạn đang xem lịch sử. Chọn ngày hiện tại để gửi tin."
        : !correctPhase
          ? isWolfChat
            ? "Chat Sói chỉ gửi được vào ban đêm bởi Sói còn sống."
            : "Chat chung chỉ gửi được ban ngày."
          : busy
            ? "Đang chờ Server xử lý yêu cầu trước đó."
            : isWolfChat
              ? "Chỉ Sói còn sống nhận được tin nhắn này."
              : "Bạn có thể thảo luận ban ngày.";
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
