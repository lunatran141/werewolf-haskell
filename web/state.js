const VOTE_DURATION_MS = 60_000;
const DAY_DURATION_MS = 180_000;
let voteClockInterval = null;
let dayClockInterval = null;
const chatBubbleTimers = new Map();

const state = {
  connected: false,
  entranceMode: "join",
  roomId: null,
  reconnecting: false,
  selfPlayerId: null,
  hostPlayerId: null,
  players: [],
  pending: null,
  retryCommand: null,
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
  validTargets: null,
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


function handleNightAccepted() {
  if (state.pending?.type === "NightAction") {
    state.pending = null;
  }

  state.nightActionDone = true;
  state.nightMessage = "Server đã chấp nhận hành động.";
}


function handlePhaseChanged(phase) {
  const previousPhase = state.phase;
  if (previousPhase !== phase) state.validTargets = null;

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
    state.chatDay = null;
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
      if (saveRoomVersion(message.roomId, message.version) === false) {
        socket.close();
      } else if (state.retryCommand && state.pending === null && socket.readyState === WebSocket.OPEN) {
        const command = state.retryCommand;
        state.pending = {type: command.type, requestId: command.requestId, command};
        socket.send(JSON.stringify(command));
      }
      break;

    case "VotingSnapshot":
      // Day và Voting cùng số vòng: phải xét cả chuyển phase để xóa tally cũ.
      if (message.phase === "Voting" && (voting.phase !== "Voting" || message.day !== voting.day)) {
        voting.summary = "";
        voting.tally = [];
      }
      if (state.phase !== message.phase) handlePhaseChanged(message.phase);
      // Khóa lựa chọn mỗi khi snapshot thay đổi, chờ danh sách riêng mới từ Server.
      state.validTargets = null;
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

    case "ValidTargetsSnapshot":
      if (message.roomId === state.roomId && message.phase === state.phase &&
          message.day === voting.day && Number.isSafeInteger(message.version) &&
          Array.isArray(message.targets) &&
          (state.validTargets === null || message.version >= state.validTargets.version)) {
        const actions = {};
        for (const entry of message.targets) {
          if (entry && typeof entry.action === "string" && Array.isArray(entry.playerIds)) {
            actions[entry.action] = entry.playerIds.filter(id => typeof id === "string");
          }
        }
        state.validTargets = {phase: message.phase, day: message.day,
          version: message.version, actions};
      }
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
        state.retryCommand = null;
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
        if (message.code === "DuplicateRequest") {
          if (state.pending?.type === "Chat") el.chatInput.value = "";
          state.pending = null;
          state.retryCommand = null;
          break;
        }
        const failedCommand = state.pending?.command;
        if (["NightAction", "Vote", "HunterAction"].includes(state.pending?.type)) {
          state.validTargets = null;
        }
        if (message.code === "ServerTimeout" && failedCommand) {
          state.retryCommand = failedCommand;
        } else if (failedCommand) {
          state.retryCommand = null;
        }
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
