-- | Pure Engine nhận state và command, rồi trả state cùng domain event.
module Domain.Engine where

import Data.Char (isSpace)
import Domain.Types
import Domain.Validation
import Domain.Rules

-- Hàm xử lý lệnh thuần của Domain.
applyCommand
  :: GameState
  -> Command
  -> Either GameError (GameState, [DomainEvent])
applyCommand state command
  | gamePhase state == GameOver = Left GameAlreadyOver
  | otherwise =
      case command of
        Join pid name       -> joinPlayer state pid name
        Leave pid           -> leavePlayer state pid
        SetReady pid ready  -> setPlayerReady state pid ready
        StartGame pid       -> startGame state pid
        AdvancePhase        -> advanceGamePhase state
        NightAction pid act -> submitNightAction state pid act
        Vote voter target   -> castVote state voter target
        Chat pid message    -> sendChat state pid message

-- Người chơi tham gia Lobby.
joinPlayer
  :: GameState -> PlayerId -> String
  -> Either GameError (GameState, [DomainEvent])
joinPlayer state pid name
  | gamePhase state /= Lobby = Left WrongPhase
  | length (gamePlayers state) >= maxPlayers = Left RoomFull
  | otherwise = do
      _ <- validatePlayerId pid
      _ <- validatePlayerName name
      let player = Player pid name Nothing False Alive
          players = gamePlayers state ++ [player]
      _ <- validateUniquePlayerIds players
      _ <- validateUniquePlayerNames players
      Right
        (state { gamePlayers = players }, [PlayerJoined pid])

-- Người chơi rời Lobby.
leavePlayer
  :: GameState -> PlayerId
  -> Either GameError (GameState, [DomainEvent])
leavePlayer state pid
  | gamePhase state /= Lobby = Left WrongPhase
  | otherwise = do
      _ <- validatePlayerExists pid (gamePlayers state)
      let remaining =
            filter ((/= pid) . playerId) (gamePlayers state)
          newHost =
            if gameHost state == pid
              then maybe (gameHost state) playerId (safeHead remaining)
              else gameHost state
      Right
        ( state
            { gamePlayers = remaining
            , gameHost = newHost
            }
        , [PlayerLeft pid]
        )

-- Thay đổi trạng thái sẵn sàng.
setPlayerReady
  :: GameState -> PlayerId -> Bool
  -> Either GameError (GameState, [DomainEvent])
setPlayerReady state pid ready
  | gamePhase state /= Lobby = Left WrongPhase
  | otherwise = do
      _ <- validatePlayerExists pid (gamePlayers state)
      let players = map update (gamePlayers state)
          update p
            | playerId p == pid = p { playerReady = ready }
            | otherwise = p
      Right
        (state { gamePlayers = players }, [ReadyChanged pid ready])

-- Bắt đầu game với cấu hình vai đã chốt.
startGame
  :: GameState -> PlayerId
  -> Either GameError (GameState, [DomainEvent])
startGame state pid
  | gamePhase state /= Lobby = Left GameAlreadyStarted
  | pid /= gameHost state = Left NotAuthorized
  | otherwise = do
      validatePlayerCount (gamePlayers state)
      validateAllReady (gamePlayers state)
      if not
          (validateRoleConfiguration
            (length (gamePlayers state))
            (gameConfiguredRoles state))
        then Left InvalidRoleConfiguration
        else
          let assigned =
                zipWith assignRole
                  (gamePlayers state)
                  (gameConfiguredRoles state)
              newState = state
                { gamePlayers = assigned
                , gamePhase = Night
                , gameDay = 1
                , gameVotes = []
                , gameNightActions = []
                , gameWitchHealReady = True
                , gameWitchPoisonReady = True
                , gameLastProtected = Nothing
                }
              roleEvents =
                map
                  (\p ->
                    case playerRole p of
                      Just role ->
                        PlayerRoleAssigned (playerId p) role
                      Nothing ->
                        PlayerRoleAssigned (playerId p) Villager)
                  assigned
          in Right
               (newState, GameStarted : PhaseChanged Night : roleEvents)
  where
    assignRole player role = player { playerRole = Just role }

-- Chuyển phase nội bộ.
advanceGamePhase
  :: GameState
  -> Either GameError (GameState, [DomainEvent])
advanceGamePhase state =
  case gamePhase state of
    Day ->
      Right
        ( state { gamePhase = Voting, gameVotes = [] }
        , [PhaseChanged Voting]
        )
    _ -> Left WrongPhase

-- Gửi hành động ban đêm.
submitNightAction
  :: GameState -> PlayerId -> NightChoice
  -> Either GameError (GameState, [DomainEvent])
submitNightAction state pid action
  | gamePhase state /= Night = Left WrongPhase
  | otherwise = do
      player <- validatePlayerExists pid (gamePlayers state)
      _ <- validatePlayerAlive player
      if any ((== pid) . fst) (gameNightActions state)
        then Left InvalidNightAction
        else do
          validateNightChoice state player action
          let actions = gameNightActions state ++ [(pid, action)]
              updated = state { gameNightActions = actions }
              accepted = [NightActionAccepted pid]
          if nightActionsComplete updated
            then resolveNight updated accepted
            else Right (updated, accepted)

-- Kiểm tra quyền dùng kỹ năng và mục tiêu ban đêm.
validateNightChoice
  :: GameState -> Player -> NightChoice
  -> Either GameError ()
validateNightChoice state player action =
  case (playerRole player, action) of
    (Just Werewolf, WolfTarget target) ->
      validateWolfTarget state player target

    (Just Seer, SeerTarget target) -> do
      _ <- validateLivingTarget target (gamePlayers state)
      if target == playerId player
        then Left InvalidTarget
        else Right ()

    (Just Guard, GuardTarget target) -> do
      _ <- validateLivingTarget target (gamePlayers state)
      if Just target == gameLastProtected state
        then Left InvalidTarget
        else Right ()

    (Just Witch, WitchHeal)
      | gameWitchHealReady state -> Right ()
      | otherwise -> Left InvalidNightAction

    (Just Witch, WitchPoison target)
      | gameWitchPoisonReady state -> do
          _ <- validateLivingTarget target (gamePlayers state)
          Right ()
      | otherwise -> Left InvalidNightAction

    (Just Witch, WitchPass) -> Right ()
    (Just Villager, NoAction) -> Right ()
    (Just Hunter, NoAction) -> Right ()
    _ -> Left InvalidNightAction
  where
    validateWolfTarget s p target = do
      targetPlayer <- validateLivingTarget target (gamePlayers s)
      if target == playerId p
          || playerRole targetPlayer == Just Werewolf
        then Left InvalidTarget
        else Right ()

-- Chờ các vai có hành động ban đêm gửi lựa chọn.
nightActionsComplete :: GameState -> Bool
nightActionsComplete state =
  all hasSubmitted requiredPlayers
  where
    requiredPlayers =
      filter
        (\p ->
          playerRole p `elem`
            [Just Werewolf, Just Seer, Just Guard, Just Witch])
        (livingPlayers (gamePlayers state))

    hasSubmitted player =
      any ((== playerId player) . fst) (gameNightActions state)

-- Giải quyết đêm bằng dữ liệu đã nhận.
resolveNight
  :: GameState -> [DomainEvent]
  -> Either GameError (GameState, [DomainEvent])
resolveNight state priorEvents =
  let actions = gameNightActions state
      wolves =
        [ (pid, target)
        | (pid, WolfTarget target) <- actions
        ]
      wolfWinners = voteWinners wolves
      wolfTarget = resolveTie (gameWolfTiePolicy state) wolfWinners
      guardTarget = firstGuardTarget actions
      seerEvents = mapMaybeSeer state actions
      healUsed = any ((== WitchHeal) . snd) actions
      poisonTarget = firstPoisonTarget actions
      victim =
        case wolfTarget of
          Just target
            | Just target == guardTarget -> Nothing
            | healUsed && gameWitchHealReady state -> Nothing
            | otherwise -> Just target
          Nothing -> Nothing
      killed =
        uniqueIds
          (maybe [] (: []) victim
            ++ maybe [] (: []) poisonTarget)
      players = map (killPlayers killed) (gamePlayers state)
      updated = state
        { gamePlayers = players
        , gamePhase = Day
        , gameNightActions = []
        , gameVotes = []
        , gameWitchHealReady =
            gameWitchHealReady state && not healUsed
        , gameWitchPoisonReady =
            gameWitchPoisonReady state && poisonTarget == Nothing
        , gameLastProtected = guardTarget
        }
      deathEvents = map PlayerEliminated killed
      win = checkWinner players
  in case win of
       Just team ->
         Right
           ( updated { gamePhase = GameOver }
           , priorEvents ++ seerEvents ++ deathEvents
               ++ [NightResolved killed, PhaseChanged GameOver, GameEnded team]
           )
       Nothing ->
         Right
           ( updated
           , priorEvents ++ seerEvents ++ deathEvents
               ++ [NightResolved killed, PhaseChanged Day]
           )
  where
    killPlayers killed player
      | playerId player `elem` killed =
          player { playerLifeStatus = Dead }
      | otherwise = player

-- Lấy mục tiêu được Bảo Vệ trong danh sách hành động.
firstGuardTarget
  :: [(PlayerId, NightChoice)] -> Maybe PlayerId
firstGuardTarget [] = Nothing
firstGuardTarget ((_, choice) : rest) =
  case choice of
    GuardTarget target -> Just target
    _ -> firstGuardTarget rest

-- Lấy mục tiêu bị đầu độc trong danh sách hành động.
firstPoisonTarget
  :: [(PlayerId, NightChoice)] -> Maybe PlayerId
firstPoisonTarget [] = Nothing
firstPoisonTarget ((_, choice) : rest) =
  case choice of
    WitchPoison target -> Just target
    _ -> firstPoisonTarget rest

-- Tạo sự kiện kết quả Tiên Tri.
mapMaybeSeer
  :: GameState -> [(PlayerId, NightChoice)] -> [DomainEvent]
mapMaybeSeer state actions =
  [ SeerResult pid team
  | (pid, SeerTarget target) <- actions
  , Just player <- [findPlayer target (gamePlayers state)]
  , Just role <- [playerRole player]
  , let team = teamOfRole role
  ]

-- Bỏ phiếu ban ngày.
castVote
  :: GameState -> PlayerId -> PlayerId
  -> Either GameError (GameState, [DomainEvent])
castVote state voter target
  | gamePhase state /= Voting = Left WrongPhase
  | otherwise = do
      voterPlayer <- validatePlayerExists voter (gamePlayers state)
      _ <- validatePlayerAlive voterPlayer
      _ <- validateLivingTarget target (gamePlayers state)
      if voter == target
        then Left InvalidTarget
        else if any ((== voter) . fst) (gameVotes state)
          then Left AlreadyVoted
          else do
            let votes = gameVotes state ++ [(voter, target)]
                updated = state { gameVotes = votes }
                voteEvent = VoteUpdated voter target
                alive = livingPlayers (gamePlayers state)
            if length votes < length alive
              then Right (updated, [voteEvent])
              else resolveVoting updated [voteEvent]

-- Tổng hợp phiếu, xử lý hòa và kiểm tra phe thắng.
resolveVoting
  :: GameState -> [DomainEvent]
  -> Either GameError (GameState, [DomainEvent])
resolveVoting state priorEvents =
  let winners = voteWinners (gameVotes state)
      eliminated = resolveTie (gameVoteTiePolicy state) winners
      players = map eliminate (gamePlayers state)
      newState = state
        { gamePlayers = players
        , gameVotes = []
        }
      deathEvents =
        maybe [] (\pid -> [PlayerEliminated pid]) eliminated
      winner = checkWinner players
  in case winner of
       Just team ->
         Right
           ( newState { gamePhase = GameOver }
           , priorEvents ++ deathEvents
               ++ [PhaseChanged GameOver, GameEnded team]
           )
       Nothing ->
         Right
           ( newState
               { gamePhase = Night
               , gameDay = gameDay state + 1
               , gameNightActions = []
               }
           , priorEvents ++ deathEvents ++ [PhaseChanged Night]
           )
  where
    eliminate player
      | Just (playerId player) ==
          resolveTie
            (gameVoteTiePolicy state)
            (voteWinners (gameVotes state)) =
          player { playerLifeStatus = Dead }
      | otherwise = player

-- Chat công khai trong ban ngày.
sendChat
  :: GameState -> PlayerId -> String
  -> Either GameError (GameState, [DomainEvent])
sendChat state pid message
  | gamePhase state /= Day = Left WrongPhase
  | otherwise = do
      player <- validatePlayerExists pid (gamePlayers state)
      _ <- validatePlayerAlive player
      if all isSpace message
        then Left InvalidCommand
        else Right (state, [ChatMessage pid message])

-- Lấy phần tử đầu tiên an toàn.
safeHead :: [a] -> Maybe a
safeHead [] = Nothing
safeHead (x : _) = Just x

-- Loại bỏ ID trùng nhau.
uniqueIds :: [PlayerId] -> [PlayerId]
uniqueIds = foldr add []
  where
    add x xs
      | x `elem` xs = xs
      | otherwise = x : xs
