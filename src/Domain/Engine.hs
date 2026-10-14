-- | Pure Engine xu ly GameState va Command, tra ve state cung DomainEvent.
module Domain.Engine where
import Domain.Types
import Domain.Night
  ( NightOutcome(..), nightActionPrivateEvents
  , wolfVotingComplete, wolfVictim, resolveNightEffects )
import Domain.Rules
  ( checkWin, lynchTarget, tallyVotes )
import Domain.Validation
  ( validateGameInvariant
  , validateJoin
  , validateLeave
  , validateSetReady
  , expectedRoles
  , validateRolePreset
  , validateStartGame
  , validateNightAction
  , validateChat
  , validateHunterShot
  , validatePlayerAlive
  , validatePlayerExists
  , validateVote
  )
-- Them nguoi choi vao Lobby.
-- PlayerId do Server cap; validateJoin tao Player voi ten da chuan hoa.
joinPlayer
  :: GameState
  -> PlayerId
  -> String
  -> Either GameError (GameState, [DomainEvent])
joinPlayer state pid name = do
  player <- validateJoin state pid name
  let isFirst = null (gamePlayers state)
      newState = state
        { gamePlayers = gamePlayers state ++ [player]
        , gameHost = if isFirst then pid else gameHost state
        }
  validateGameInvariant newState
  pure (newState, [PlayerJoined pid])
-- Xoa nguoi choi khoi Lobby.
-- Neu Host roi, nguoi con lai Join som nhat tro thanh Host.
leavePlayer
  :: GameState
  -> PlayerId
  -> Either GameError (GameState, [DomainEvent])
leavePlayer state pid = do
  _ <- validateLeave state pid
  let remaining = filter ((/= pid) . playerId) (gamePlayers state)
      hostLeft = gameHost state == pid
      newHost =
        if hostLeft
          then case remaining of
            []    -> ""
            p : _ -> playerId p
          else gameHost state
      newState = state
        { gamePlayers = remaining
        , gameHost = newHost
        }
      events =
        [PlayerLeft pid] ++
        [HostChanged newHost | hostLeft && not (null remaining)]
  validateGameInvariant newState
  pure (newState, events)
-- Doi trang thai Ready cua mot nguoi choi.
-- Neu gia tri khong doi thi khong phat ReadyChanged.
setPlayerReady
  :: GameState
  -> PlayerId
  -> Bool
  -> Either GameError (GameState, [DomainEvent])
setPlayerReady state pid ready = do
  currentPlayer <- validateSetReady state pid
  let changed = playerReady currentPlayer /= ready
      updatePlayer player
        | playerId player == pid = player { playerReady = ready }
        | otherwise = player
      newState = state
        { gamePlayers =
            if changed
              then map updatePlayer (gamePlayers state)
              else gamePlayers state
        }
      events =
        if changed
          then [ReadyChanged pid ready]
          else []
  validateGameInvariant newState
  pure (newState, events)
-- Xu ly rieng cac command thuoc Lobby.
applyLobbyCommand
  :: GameState
  -> Command
  -> Either GameError (GameState, [DomainEvent])
applyLobbyCommand state command =
  case command of
    Join pid name       -> joinPlayer state pid name
    Leave pid           -> leavePlayer state pid
    SetReady pid ready  -> setPlayerReady state pid ready
    _                   -> Left InvalidCommand
-- Bat dau van bang danh sach vai da duoc Server xao tron.
-- Ham nay khong tu random va khong gui WebSocket.
startGame
  :: GameState
  -> PlayerId
  -> [Role]
  -> Either GameError (GameState, [DomainEvent])
startGame state actor shuffledRoles = do
  let count = length (gamePlayers state)
      -- Preset la cau hinh dung theo so nguoi, chua phai thu tu chia vai.
      preset = maybe [] id (expectedRoles count)
      -- emptyLobby co gameConfiguredRoles = [].
      -- Chuan bi preset de validateStartGame kiem tra duoc.
      configuredState =
        state { gameConfiguredRoles = preset }
  -- Kiem tra Lobby, dung Host, du 8/9 nguoi, moi nguoi Ready.
  validateStartGame actor configuredState
  -- Kiem tra danh sach Server dua vao co dung bo vai hay khong.
  validateRolePreset count shuffledRoles
  let assignedPlayers =
        zipWith assignRole (gamePlayers configuredState) shuffledRoles
      assignRole player role =
        player
          { playerRole = Just role
          , playerLifeStatus = Alive
          }
      newState =
        configuredState
          { gamePlayers = assignedPlayers
          , gamePhase = Night
          , gameDay = 1
          , gameVotes = []
          , gameNightActions = []
          , gameWolfVotingClosed = False
          , gameWitchHealReady = True
          , gameWitchPoisonReady = True
          , gameLastProtected = Nothing
          , gamePendingReveals = []
          , gamePendingHunter = Nothing
          , gameHunterTriggered = False
          , gameNightResolved = False
          , gameVotingResolved = False
          , gameResult = Nothing
          }
      roleEvents =
        [ PlayerRoleAssigned (playerId player) role
        | (player, role) <- zip assignedPlayers shuffledRoles
        ]
      events =
        [GameStarted, PhaseChanged Night] ++ roleEvents
  validateGameInvariant newState
  pure (newState, events)
-- AdvancePhase chi dung de ket thuc thoi gian thao luan Day.
-- Night va Voting phai duoc resolve truoc khi chuyen pha.
advancePhase
  :: GameState
  -> Either GameError (GameState, [DomainEvent])
advancePhase state =
  case gamePhase state of
    GameOver ->
      Left GameAlreadyOver
    Day -> do
      validateGameInvariant state
      if gamePendingHunter state /= Nothing
        then Left InvalidGameState
        else do
          let newState =
                state
                  { gamePhase = Voting
                  , gameVotes = []
                  , gameNightResolved = False
                  , gameVotingResolved = False
                  }
          validateGameInvariant newState
          pure (newState, [PhaseChanged Voting])
    _ ->
      Left WrongPhase
-- Chi goi sau khi ResolveNight da xu ly xong.
finishResolvedNight
  :: GameState
  -> Maybe GameResult
  -> Either GameError (GameState, [DomainEvent])
finishResolvedNight =
  finishResolvedPhase Night Day
-- Chi goi sau khi ResolveVoting da xu ly xong.
finishResolvedVoting
  :: GameState
  -> Maybe GameResult
  -> Either GameError (GameState, [DomainEvent])
finishResolvedVoting =
  finishResolvedPhase Voting Night
-- Doi pha tu state da xu ly xong Night hoac Voting.
-- Nothing: van tiep tuc. Just result: van ket thuc.
finishResolvedPhase
  :: Phase
  -> Phase
  -> GameState
  -> Maybe GameResult
  -> Either GameError (GameState, [DomainEvent])
finishResolvedPhase expectedPhase continuePhase state result = do
  if gamePhase state == GameOver
    then Left GameAlreadyOver
    else Right ()
  if gamePhase state /= expectedPhase
    then Left WrongPhase
    else Right ()
  -- Danh sach action/vote rong chua du chung minh da resolve.
  -- Resolver tuong ung phai dat dau True sau khi xu ly xong.
  if (expectedPhase == Night && not (gameNightResolved state))
      || (expectedPhase == Voting && not (gameVotingResolved state))
    then Left InvalidGameState
    else Right ()
  validateGameInvariant state
  -- Khong chuyen pha khi con Hunter, role reveal hoac action chua xu ly.
  if gamePendingHunter state /= Nothing
      || not (null (gamePendingReveals state))
      || (expectedPhase == Night
          && not (null (gameNightActions state)))
      || (expectedPhase == Voting
          && not (null (gameVotes state)))
    then Left InvalidGameState
    else Right ()
  let nextPhase =
        case result of
          Nothing -> continuePhase
          Just _  -> GameOver
      nextDay =
        if expectedPhase == Voting && result == Nothing
          then gameDay state + 1
          else gameDay state
      newState =
        state
          { gamePhase = nextPhase
          , gameDay = nextDay
          , gameNightActions = []
          , gameWolfVotingClosed = False
          , gameVotes = []
          , gameNightResolved = False
          , gameVotingResolved = False
          , gameResult = result
          }
      events =
        [PhaseChanged nextPhase] ++
        case result of
          Nothing -> []
          Just finalResult -> [GameFinished finalResult]
  validateGameInvariant newState
  pure (newState, events)
applyPhaseCommand
  :: GameState
  -> Command
  -> Either GameError (GameState, [DomainEvent])
applyPhaseCommand state command =
  case command of
    StartGame actor shuffledRoles ->
      startGame state actor shuffledRoles
    AdvancePhase ->
      advancePhase state
    _ ->
      Left InvalidCommand
-- T05: Xac thuc va luu mot hanh dong ban dem.
-- Lenh khong hop le tra Left, khong cap nhat GameState.
submitNightAction :: GameState -> PlayerId -> NightChoice
                  -> Either GameError (GameState, [DomainEvent])
submitNightAction state actor choice = do
  validateNightAction state actor choice
  -- Tao cac su kien rieng tu, bao gom ket qua soi cua Tien Tri.
  events <- nightActionPrivateEvents state actor choice
  -- Luu hanh dong da duoc xac thuc, khong thay doi state ban dau.
  let newState = state
        { gameNightActions = gameNightActions state ++ [(actor, choice)] }
  validateGameInvariant newState
  pure (newState, events)
-- T05: Server khoa phieu Soi va gui thong bao rieng cho Phu Thuy.
-- timedOut chi do Server cung cap, khong tin gia tri tu client.
closeWolfVoting :: GameState -> Bool -> Either GameError (GameState, [DomainEvent])
closeWolfVoting state timedOut = do
  if gamePhase state /= Night then Left WrongPhase else Right ()
  if gameNightResolved state || gameWolfVotingClosed state
    then Left InvalidGameState else Right ()
  if gamePendingHunter state /= Nothing || not (null (gamePendingReveals state))
    then Left InvalidGameState else Right ()
  validateGameInvariant state
  if not timedOut && not (wolfVotingComplete state)
    then Left InvalidGameState else Right ()
  let newState = state {gameWolfVotingClosed = True}
      witchIds = [playerId p | p <- gamePlayers state
                 , playerLifeStatus p == Alive, playerRole p == Just Witch]
      events = [WitchVictimNotice pid (wolfVictim state) | pid <- witchIds]
  validateGameInvariant newState
  pure (newState, events)
-- T05: Nhan Command NightAction theo ADT da dinh nghia tai T02.
applyNightCommand :: GameState -> Command -> Either GameError (GameState, [DomainEvent])
applyNightCommand state command =
  case command of
    NightAction actor choice -> submitNightAction state actor choice
    ResolveNight -> resolveNightTurn state
    _ -> Left InvalidCommand
-- T05: Tinh ket qua dem, cap nhat nguoi chet va tai nguyen cua cac vai.
-- Chua chuyen sang Day vi Hunter va Role Reveal co the dang cho.
resolveNightTurn :: GameState -> Either GameError (GameState, [DomainEvent])
resolveNightTurn state = do
  if gamePhase state /= Night then Left WrongPhase else Right ()
  if gameNightResolved state then Left InvalidGameState else Right ()
  if gamePendingHunter state /= Nothing then Left InvalidGameState else Right ()
  if not (null (gamePendingReveals state)) then Left InvalidGameState else Right ()
  validateGameInvariant state
  -- Chi resolve khi da khoa phieu hoac tat ca Soi da bo phieu.
  if not (gameWolfVotingClosed state) && not (wolfVotingComplete state)
    then Left InvalidGameState else Right ()
  let outcome = resolveNightEffects state
      deaths = outcomeDeaths outcome
      -- Chi danh dau chet, khong thay doi vai da duoc chia.
      updatePlayer player
        | playerId player `elem` deaths = player {playerLifeStatus = Dead}
        | otherwise = player
      deadHunter =
        [ playerId player
        | player <- gamePlayers state
        , playerId player `elem` deaths
        , playerRole player == Just Hunter
        ]
      pendingHunter = case deadHunter of
        pid : _ -> Just pid
        [] -> Nothing
      newState = state
        { gamePlayers = map updatePlayer (gamePlayers state)
        , gameNightActions = []
        , gameWitchHealReady = outcomeHealReadyAfter outcome
        , gameWitchPoisonReady = outcomePoisonReadyAfter outcome
        , gameLastProtected = outcomeLastProtectedAfter outcome
        , gamePendingReveals = deaths
        , gamePendingHunter = pendingHunter
        , gameNightResolved = True
        }
      -- HunterShotPending la Private; chua tiet lo vai nguoi chet.
      events = [NightResolved deaths]
        ++ [HunterShotPending pid | pid <- deadHunter]
  validateGameInvariant newState
  pure (newState, events)

-- T05: Xet ket qua sau tat ca death effects, khong random.
-- Uu tien Draw, Village roi Wolves.
nightGameResult :: GameState -> Maybe GameResult
nightGameResult state
  | wolves == 0 && village == 0 = Just Draw
  | wolves == 0 = Just (Winner Village)
  | wolves >= village = Just (Winner Wolves)
  | otherwise = Nothing
  where
    alive = filter ((== Alive) . playerLifeStatus) (gamePlayers state)
    wolves = length [p | p <- alive, playerRole p == Just Werewolf]
    village = length [p | p <- alive, maybe False ((== Village) . teamOfRole) (playerRole p)]

-- T05: Reveal vai cua nguoi chet va ket thuc Night khi khong con Hunter pending.
-- Hunter Shot/Pass thuoc T06; khong bo qua buoc nay de chuyen pha.
completeNightTurn :: GameState -> Either GameError (GameState, [DomainEvent])
completeNightTurn state = do
  if gamePhase state /= Night then Left WrongPhase else Right ()
  if not (gameNightResolved state) then Left InvalidGameState else Right ()
  if gamePendingHunter state /= Nothing then Left HunterNotPending else Right ()
  validateGameInvariant state

  let lookupPlayer pid = case filter ((== pid) . playerId) (gamePlayers state) of
        p : _ -> Just p
        [] -> Nothing
      reveals =
        [ PlayerRoleRevealed pid role (teamOfRole role)
        | pid <- gamePendingReveals state
        , Just p <- [lookupPlayer pid]
        , playerLifeStatus p == Dead
        , Just role <- [playerRole p]
        ]
      readyState = state {gamePendingReveals = []}

  if length reveals /= length (gamePendingReveals state)
    then Left InvalidGameState
    else Right ()
  (nextState, phaseEvents) <- finishResolvedNight readyState (nightGameResult readyState)
  pure (nextState, reveals ++ phaseEvents)

-- T06: Dispatcher chung cho Domain Engine. Các lệnh Resolve vẫn là lệnh
-- nội bộ do Server gọi, còn Vote/Chat đi qua cùng một pure transition.
applyCommand
  :: GameState
  -> Command
  -> Either GameError (GameState, [DomainEvent])
applyCommand state command
  | gamePhase state == GameOver = Left GameAlreadyOver
  | otherwise =
      case command of
        Join _ _ -> applyLobbyCommand state command
        Leave _ -> applyLobbyCommand state command
        SetReady _ _ -> applyLobbyCommand state command
        StartGame _ _ -> applyPhaseCommand state command
        AdvancePhase -> applyPhaseCommand state command
        NightAction _ _ -> applyNightCommand state command
        Vote actor target -> castVote state actor target
        Chat actor message -> sendChat state actor message
        ResolveNight -> applyNightCommand state command
        ResolveVoting -> resolveVoting state
        ResolveHunter actor target -> resolveHunterShot state actor target

-- T06: Nhận một phiếu hợp lệ và chỉ thêm đúng một bản ghi vào round hiện tại.
-- Nếu validation lỗi thì state và event đều không thay đổi.
castVote
  :: GameState
  -> PlayerId
  -> PlayerId
  -> Either GameError (GameState, [DomainEvent])
castVote state actor target = do
  validateVote state actor target
  if null (gamePendingReveals state) then Right () else Left InvalidGameState
  let newState = state
        { gameVotes = gameVotes state ++ [(actor, target)] }
  validateGameInvariant newState
  pure (newState, [VoteUpdated actor target])

-- T06: Kiểm tra cửa sổ Voting trước khi tally. Vote đã chốt hoặc Hunter
-- đang chờ bắn thì không được nhận thêm phiếu.
validateVotingWindow :: GameState -> Either GameError ()
validateVotingWindow state = do
  if gamePhase state == Voting then Right () else Left WrongPhase
  if gameVotingResolved state
    then Left InvalidGameState
    else Right ()
  if gamePendingHunter state == Nothing
    then Right ()
    else Left HunterNotPending
  validateGameInvariant state
  validateStoredVotes state
  if null (gamePendingReveals state) then Right () else Left InvalidGameState

-- T06: Kiểm tra lại các phiếu đã lưu để bảo vệ Engine ngay cả khi caller
-- tạo GameState trực tiếp thay vì đi qua castVote.
validateStoredVotes :: GameState -> Either GameError ()
validateStoredVotes state = mapM_ validateEntry (gameVotes state)
  where
    validateEntry (actor, target) = do
      voter <- validatePlayerExists actor (gamePlayers state)
      _ <- validatePlayerAlive voter
      victim <- validatePlayerExists target (gamePlayers state)
      _ <- validatePlayerAlive victim
      if actor == target then Left InvalidTarget else Right ()

-- T06: Chốt toàn bộ phiếu. Tie và no-vote đều đi thẳng sang Night kế tiếp,
-- tuyệt đối không mở lại round Voting.
resolveVoting :: GameState -> Either GameError (GameState, [DomainEvent])
resolveVoting state = do
  validateVotingWindow state
  let target = lynchTarget (gameVotes state)
      tallyEvents = [VotingResolved (tallyVotes (gameVotes state)) target]
      baseState = state
        { gameVotes = []
        , gameVotingResolved = True
        }
  case target of
    Nothing ->
      finishVotingDeaths baseState tallyEvents

    Just targetId -> do
      targetPlayer <- validatePlayerExists targetId (gamePlayers state)
      _ <- validatePlayerAlive targetPlayer
      let killedState = baseState
            { gamePlayers = markDead targetId (gamePlayers state)
            , gamePendingReveals = appendUnique targetId (gamePendingReveals state)
            , gamePendingHunter =
                if playerRole targetPlayer == Just Hunter
                  then Just targetId
                  else Nothing
            }
      validateGameInvariant killedState
      case gamePendingHunter killedState of
        Just hunterId ->
          -- Chưa reveal role/chưa checkWin khi Hunter còn quyền bắn.
          pure (killedState, tallyEvents ++ [HunterShotPending hunterId])
        Nothing ->
          finishVotingDeaths killedState tallyEvents

-- T06: Xử lý lựa chọn bắn hoặc bỏ qua của Hunter đang pending.
resolveHunterShot
  :: GameState
  -> PlayerId
  -> Maybe PlayerId
  -> Either GameError (GameState, [DomainEvent])
resolveHunterShot state actor target = do
  -- Hunter có quyền bắn sau khi chết ở cả Night và Voting.
  if gamePhase state `elem` [Night, Voting] then Right () else Left WrongPhase
  validateGameInvariant state
  if (gamePhase state == Night && gameNightResolved state)
      || (gamePhase state == Voting && gameVotingResolved state)
    then Right () else Left InvalidGameState
  validateHunterShot state actor target
  let newState =
        state
          { gamePlayers = maybe (gamePlayers state)
              (\targetId -> markDead targetId (gamePlayers state))
              target
          , gamePendingReveals = maybe (gamePendingReveals state)
              (\targetId -> appendUnique targetId (gamePendingReveals state))
              target
          , gamePendingHunter = Nothing
          , gameHunterTriggered = True
          }
  validateGameInvariant newState
  case gamePhase state of
    Night -> do
      (finished, events) <- completeNightTurn newState
      pure (finished, HunterShotResolved actor target
        : map PlayerEliminated (gamePendingReveals newState) ++ events)
    _ -> finishVotingDeaths newState [HunterShotResolved actor target]

-- T06: Sau khi mọi death effect và Hunter chain đã xong, reveal đúng một
-- lần rồi mới kiểm tra thắng và chuyển phase.
finishVotingDeaths
  :: GameState
  -> [DomainEvent]
  -> Either GameError (GameState, [DomainEvent])
finishVotingDeaths state prefixEvents = do
  if gamePhase state /= Voting then Left WrongPhase else Right ()
  if gamePendingHunter state /= Nothing then Left HunterNotPending else Right ()
  if not (gameVotingResolved state) then Left InvalidGameState else Right ()
  validateGameInvariant state
  reveals <- pendingRevealEvents state
  let revealIds = gamePendingReveals state
      revealedState = state { gamePendingReveals = [] }
      publicDeaths = [PlayerEliminated pid | pid <- revealIds]
  -- Dùng lại transition T04 để tránh hai nơi định nghĩa cách tăng vòng.
  (nextState, phaseEvents) <- finishResolvedVoting revealedState (checkWin revealedState)
  pure (nextState, prefixEvents ++ publicDeaths ++ reveals ++ phaseEvents)

pendingRevealEvents :: GameState -> Either GameError [DomainEvent]
pendingRevealEvents state = mapM revealOne (gamePendingReveals state)
  where
    revealOne pid = do
      player <- validatePlayerExists pid (gamePlayers state)
      case (playerLifeStatus player, playerRole player) of
        (Dead, Just role) ->
          Right (PlayerRoleRevealed pid role (teamOfRole role))
        _ -> Left InvalidGameState

-- T06: Chat chỉ phát event public ở Day và không làm thay đổi gameplay state.
sendChat
  :: GameState
  -> PlayerId
  -> String
  -> Either GameError (GameState, [DomainEvent])
sendChat state actor message = do
  validateChat state actor message
  validateGameInvariant state
  pure (state, [ChatMessage actor message])

markDead :: PlayerId -> [Player] -> [Player]
markDead targetId = map mark
  where
    mark player
      | playerId player == targetId = player {playerLifeStatus = Dead}
      | otherwise = player

appendUnique :: Eq a => a -> [a] -> [a]
appendUnique value values
  | value `elem` values = values
  | otherwise = values ++ [value]
