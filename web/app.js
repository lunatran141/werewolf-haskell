let socket = null;
let requestNumber = 0;
let reconnectTimer = null;

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
  state.chatDay = null;
  renderDay();
});
el.chatWolvesTab.addEventListener("click", () => {
  if (state.selfRole === "Werewolf") {
    state.chatChannel = "WolvesNight";
    state.chatDay = null;
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
      state.validTargets = null;
      const requestId = `reconnect-${Date.now()}-${++requestNumber}`;
      state.pending = {type: "Reconnect", requestId};
      socket.send(JSON.stringify({
        type: "Reconnect", requestId,
        roomId: saved.roomId, sessionToken: saved.sessionToken
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
    state.validTargets = null;
    if (state.pending?.command && readSavedSession()) {
      state.retryCommand = state.pending.command;
    }
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
