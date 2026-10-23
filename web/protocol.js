const isSeparateLocalWebServer =
  ["localhost", "127.0.0.1"].includes(location.hostname) &&
  location.port !== "8080";
const wsProtocol =
  location.protocol === "https:" && !isSeparateLocalWebServer ? "wss:" : "ws:";
const wsHost = isSeparateLocalWebServer
  ? `${location.hostname}:8080`
  : location.host;
const WS_URL = `${wsProtocol}//${wsHost}/ws`;
const SESSION_STORAGE_KEY = "werewolf-session";

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
  ServerBusy: "Máy chủ đang bận. Hãy thử lại.",
  ServerTimeout: "Máy chủ xử lý quá lâu. Hãy thử lại yêu cầu này.",
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


function sendCommand(type, fields = {}) {
  if (state.pending !== null) {
    return;
  }
  if (state.reconnecting) return;

  if (!socket || socket.readyState !== WebSocket.OPEN) {
    state.error = "Chưa kết nối được Server.";
    render();
    return;
  }

  const roomId = fields.roomId ?? state.roomId;
  const retry = state.retryCommand;
  const canReuseRequest = retry && retry.type === type && retry.roomId === roomId &&
    JSON.stringify(Object.fromEntries(Object.entries(retry).filter(([key]) =>
      !["type", "requestId", "roomId"].includes(key)))) === JSON.stringify(fields);
  if (retry && !canReuseRequest) {
    state.error = "Hãy thử lại yêu cầu đang chờ trước khi gửi yêu cầu khác.";
    render();
    return;
  }
  const command = canReuseRequest ? retry : {
    type,
    requestId: `req-${Date.now()}-${++requestNumber}`,
    roomId,
    ...fields
  };

  state.pending = {type, requestId: command.requestId, command};
  state.error = "";
  render();

  try {
    socket.send(JSON.stringify(command));
  } catch {
    state.retryCommand = command;
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
