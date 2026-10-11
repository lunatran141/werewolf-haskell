-- | Pure Engine nhận state và command, rồi trả state cùng domain event.
module Domain.Engine where

import Domain.Types
import Domain.Validation
  ( validateGameInvariant
  , validateJoin
  , validateLeave
  , validateSetReady
  , expectedRoles
  , validateRolePreset
  , validateStartGame
  )

-- Thêm người chơi vào Lobby.
-- PlayerId do Server cấp; validateJoin tạo Player với tên đã chuẩn hóa.
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

-- Xóa người chơi khỏi Lobby.
-- Nếu Host rời, người còn lại Join sớm nhất trở thành Host.
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

-- Đổi trạng thái Ready của một người chơi.
-- Nếu giá trị không đổi thì không phát ReadyChanged.
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

-- Xử lý riêng các command thuộc Lobby.
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

-- Bắt đầu ván bằng danh sách vai đã được Server xáo trộn.
-- Hàm này không tự random và không gửi WebSocket.
startGame
  :: GameState
  -> PlayerId
  -> [Role]
  -> Either GameError (GameState, [DomainEvent])
startGame state actor shuffledRoles = do
  let count = length (gamePlayers state)

      -- Preset là cấu hình đúng theo số người, chưa phải thứ tự chia vai.
      preset = maybe [] id (expectedRoles count)

      -- emptyLobby có gameConfiguredRoles = [].
      -- Chuẩn bị preset để validateStartGame kiểm tra được.
      configuredState =
        state { gameConfiguredRoles = preset }

  -- Kiểm tra Lobby, đúng Host, đủ 8/9 người, mọi người Ready.
  validateStartGame actor configuredState

  -- Kiểm tra danh sách Server đưa vào có đúng bộ vai hay không.
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

-- AdvancePhase chỉ dùng để kết thúc thời gian thảo luận Day.
-- Night và Voting phải được resolve trước khi chuyển pha.
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

-- Chỉ gọi sau khi ResolveNight đã xử lý xong.
finishResolvedNight
  :: GameState
  -> Maybe GameResult
  -> Either GameError (GameState, [DomainEvent])
finishResolvedNight =
  finishResolvedPhase Night Day

-- Chỉ gọi sau khi ResolveVoting đã xử lý xong.
finishResolvedVoting
  :: GameState
  -> Maybe GameResult
  -> Either GameError (GameState, [DomainEvent])
finishResolvedVoting =
  finishResolvedPhase Voting Night

-- Đổi pha từ state đã xử lý xong Night hoặc Voting.
-- Nothing: ván tiếp tục. Just result: ván kết thúc.
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

  -- Danh sách action/vote rỗng chưa đủ chứng minh đã resolve.
  -- Resolver tương ứng phải đặt dấu True sau khi xử lý xong.
  if (expectedPhase == Night && not (gameNightResolved state))
      || (expectedPhase == Voting && not (gameVotingResolved state))
    then Left InvalidGameState
    else Right ()

  validateGameInvariant state

  -- Không chuyển pha khi còn Hunter, role reveal hoặc action chưa xử lý.
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