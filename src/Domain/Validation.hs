-- | Các hàm kiểm tra Command và invariant sẽ được triển khai trong T02.
module Domain.Validation where

import Data.Char (isSpace, toLower)
import Data.List (sort)
import Domain.Types

-- Chuan hoa ten truoc khi LUU, khong chi truoc khi so sanh.
normalizePlayerName :: String -> String
normalizePlayerName = unwords . words

-- Dung cho so sanh khong phan biet khoang trang/hoa thuong.
-- Chua phai Unicode case-folding day du; can thu vien neu yeu cau ten da ngon ngu.
playerNameKey :: String -> String
playerNameKey = map toLower . normalizePlayerName

validatePlayerId :: PlayerId -> Either GameError PlayerId
validatePlayerId pid
  | all isSpace pid = Left InvalidPlayerId
  | otherwise       = Right pid

validatePlayerName :: String -> Either GameError String
validatePlayerName name
  | null clean = Left InvalidPlayerName
  | otherwise  = Right clean
  where clean = normalizePlayerName name

-- T02 chi tao Player ban dau; Join va su kien la T03.
mkPlayer :: PlayerId -> String -> Either GameError Player
mkPlayer pid name = do
  validId <- validatePlayerId pid
  validName <- validatePlayerName name
  pure (Player validId validName Nothing False Alive)

hasDuplicates :: Eq a => [a] -> Bool
hasDuplicates [] = False
hasDuplicates (x:xs) = x `elem` xs || hasDuplicates xs

validateUniquePlayerIds :: [Player] -> Either GameError ()
validateUniquePlayerIds ps
  | hasDuplicates (map playerId ps) = Left DuplicatePlayerId
  | otherwise = Right ()

validateUniquePlayerNames :: [Player] -> Either GameError ()
validateUniquePlayerNames ps
  | hasDuplicates (map (playerNameKey . playerName) ps) = Left DuplicatePlayerName
  | otherwise = Right ()

-- T01/leader chi cho bat dau khi CO DUNG 8 HOAC 9 nguoi.
validatePlayerCount :: [Player] -> Either GameError ()
validatePlayerCount ps
  | length ps `elem` [8, 9] = Right ()
  | otherwise = Left InvalidPlayerCount

validateAllReady :: [Player] -> Either GameError ()
validateAllReady ps
  | not (null ps) && all playerReady ps = Right ()
  | otherwise = Left NotAllReady

-- Preset 8/9 da duoc leader chot; so sanh multiset, khong so thu tu.
expectedRoles :: Int -> Maybe [Role]
expectedRoles 8 = Just [Werewolf, Werewolf, Seer, Guard, Witch, Hunter, Villager, Villager]
expectedRoles 9 = Just [Werewolf, Werewolf, Werewolf, Seer, Guard, Witch, Hunter, Villager, Villager]
expectedRoles _ = Nothing

validateRolePreset :: Int -> [Role] -> Either GameError ()
validateRolePreset count roles = case expectedRoles count of
  Nothing -> Left InvalidPlayerCount
  Just correct
    | sort roles == sort correct -> Right ()
    | otherwise -> Left InvalidRoleConfiguration

validatePlayerExists :: PlayerId -> [Player] -> Either GameError Player
validatePlayerExists pid ps = case filter ((== pid) . playerId) ps of
  []    -> Left PlayerNotFound
  p : _ -> Right p

validatePlayerAlive :: Player -> Either GameError Player
validatePlayerAlive p = case playerLifeStatus p of
  Alive -> Right p
  Dead  -> Left DeadPlayer

validateLivingTarget :: PlayerId -> [Player] -> Either GameError Player
validateLivingTarget pid ps = validatePlayerExists pid ps >>= validatePlayerAlive

validatePhase :: Phase -> GameState -> Either GameError ()
validatePhase expected game
  | gamePhase game == GameOver = Left GameAlreadyOver
  | gamePhase game == expected = Right ()
  | otherwise = Left WrongPhase

-- Cac validation Lobby dung chung, nhung state transition Join/Leave la T03.
validateJoin :: GameState -> PlayerId -> String -> Either GameError Player
validateJoin game pid name = do
  validatePhase Lobby game
  if length (gamePlayers game) >= 9 then Left RoomFull else Right ()
  p <- mkPlayer pid name
  validateUniquePlayerIds (gamePlayers game ++ [p])
  validateUniquePlayerNames (gamePlayers game ++ [p])
  pure p

validateLeave :: GameState -> PlayerId -> Either GameError Player
validateLeave game pid = do
  validatePhase Lobby game
  validatePlayerExists pid (gamePlayers game)

validateSetReady :: GameState -> PlayerId -> Either GameError Player
validateSetReady = validateLeave

-- Kiem tra start: dung Host, tat ca Ready, dung preset va invariant.
validateStartGame :: PlayerId -> GameState -> Either GameError ()
validateStartGame actor game = do
  validatePhase Lobby game
  if actor == gameHost game && not (null actor)
    then Right () else Left NotAuthorized
  validatePlayerCount (gamePlayers game)
  validateAllReady (gamePlayers game)
  validateRolePreset (length (gamePlayers game)) (gameConfiguredRoles game)
  validateGameInvariant game

-- Night Action: T02 chi xac thuc, T05 xac dinh thoi diem resolve.
validateNightAction :: GameState -> PlayerId -> NightChoice -> Either GameError ()
validateNightAction game actor action = do
  validatePhase Night game
  if gamePendingHunter game == Nothing then Right () else Left HunterNotPending
  p <- validatePlayerExists actor (gamePlayers game) >>= validatePlayerAlive
  if actor `elem` map fst (gameNightActions game)
    then Left DuplicateNightAction else Right ()
  case (playerRole p, action) of
    (Just Werewolf, WolfTarget target) -> do
      victim <- validateLivingTarget target (gamePlayers game)
      if fmap teamOfRole (playerRole victim) == Just Village
        then Right () else Left InvalidTarget
    (Just Seer, SeerTarget target) -> otherAlive target
    (Just Guard, GuardTarget target) -> do
      _ <- validateLivingTarget target (gamePlayers game)
      if Just target == gameLastProtected game
        then Left InvalidTarget else Right ()
    (Just Witch, WitchHeal) -> do
      if gameWitchHealReady game then Right () else Left AbilityAlreadyUsed
      -- Heal chi hop le neu co nan nhan Soi DUY NHAT.
      -- T05 can thu thap du phieu Soi truoc khi nhan Heal.
      if wolfVictimKnown game then Right () else Left InvalidNightAction
    (Just Witch, WitchPoison target) -> do
      if gameWitchPoisonReady game then Right () else Left AbilityAlreadyUsed
      otherAlive target
    (Just Witch, WitchPass) -> Right ()
    (Just Hunter, NoAction) -> Right ()
    (Just Villager, NoAction) -> Right ()
    _ -> Left InvalidNightAction
  where
    otherAlive target = do
      _ <- validateLivingTarget target (gamePlayers game)
      if actor == target then Left InvalidTarget else Right ()

-- Neu 2/3 Soi hoa phieu, khong co nan nhan de Witch Heal.
wolfVictimKnown :: GameState -> Bool
wolfVictimKnown game =
  let wolves = [playerId p | p <- gamePlayers game,
                playerLifeStatus p == Alive, playerRole p == Just Werewolf]
      votes = [t | (pid, WolfTarget t) <- gameNightActions game, pid `elem` wolves]
      unique [] = []
      unique (x:xs) = x : unique (filter (/= x) xs)
      winners = case votes of
        [] -> []
        _ -> let highest = maximum [length (filter (== t) votes) | t <- unique votes]
             in [t | t <- unique votes, length (filter (== t) votes) == highest]
  in not (null wolves) && length votes == length wolves && length winners == 1

validateVote :: GameState -> PlayerId -> PlayerId -> Either GameError ()
validateVote game actor target = do
  validatePhase Voting game
  if gamePendingHunter game == Nothing then Right () else Left HunterNotPending
  _ <- validatePlayerExists actor (gamePlayers game) >>= validatePlayerAlive
  _ <- validateLivingTarget target (gamePlayers game)
  if actor == target then Left InvalidTarget else Right ()
  if actor `elem` map fst (gameVotes game) then Left AlreadyVoted else Right ()

validateChat :: GameState -> PlayerId -> String -> Either GameError ()
validateChat game actor message = do
  validatePhase Day game
  _ <- validatePlayerExists actor (gamePlayers game) >>= validatePlayerAlive
  if all isSpace message then Left EmptyChat else Right ()

validateHunterShot :: GameState -> PlayerId -> Maybe PlayerId -> Either GameError ()
validateHunterShot game actor target = do
  if gamePendingHunter game == Just actor && not (gameHunterTriggered game)
    then Right () else Left HunterNotPending
  hunter <- validatePlayerExists actor (gamePlayers game)
  if playerRole hunter == Just Hunter && playerLifeStatus hunter == Dead
    then Right () else Left HunterNotPending
  case target of
    Nothing -> Right ()
    Just pid -> do
      _ <- validateLivingTarget pid (gamePlayers game)
      if pid == actor then Left InvalidTarget else Right ()

-- Invariant la contract sau MOI lan Engine cap nhat GameState.
validateGameInvariant :: GameState -> Either GameError ()
validateGameInvariant game = do
  let ps = gamePlayers game
      ids = map playerId ps
      active = gamePhase game /= Lobby
      uniqueActors = not (hasDuplicates (map fst (gameVotes game)))
                 && not (hasDuplicates (map fst (gameNightActions game)))
      refsOk = all (\(a,t) -> a `elem` ids && t `elem` ids) (gameVotes game)
            && all (\(a,_) -> a `elem` ids) (gameNightActions game)
      hostOk = if null ps then null (gameHost game) else gameHost game `elem` ids
  mapM_ (validatePlayerId . playerId) ps
  mapM_ (validatePlayerName . playerName) ps
  validateUniquePlayerIds ps
  validateUniquePlayerNames ps
  if length ps <= 9 then Right () else Left RoomFull
  if hostOk && uniqueActors && refsOk then Right () else Left InvalidGameState
  if gameWolfTiePolicy game == NoElimination && gameVoteTiePolicy game == NoElimination
    then Right () else Left InvalidTiePolicy
  if active then do
    validatePlayerCount ps
    validateRolePreset (length ps) (gameConfiguredRoles game)
    let assigned = [r | p <- ps, Just r <- [playerRole p]]
    if sort assigned == sort (gameConfiguredRoles game) && gameDay game >= 1
      then Right () else Left InvalidGameState
  else if all (\p -> playerRole p == Nothing && playerLifeStatus p == Alive) ps
       && gameDay game == 0 && null (gameVotes game)
       && null (gameNightActions game) && gameResult game == Nothing
       && null (gamePendingReveals game) && gamePendingHunter game == Nothing
       then Right () else Left InvalidGameState
  if (gamePhase game == GameOver) == (gameResult game /= Nothing)
    then Right () else Left InvalidGameState
  if (gamePhase game == Voting || null (gameVotes game))
     && (gamePhase game == Night || null (gameNightActions game))
    then Right () else Left InvalidGameState
  case gamePendingHunter game of
    Nothing -> Right ()
    Just pid -> do
      p <- validatePlayerExists pid ps
      if playerRole p == Just Hunter && playerLifeStatus p == Dead
         && not (gameHunterTriggered game) && gamePhase game /= GameOver
        then Right () else Left InvalidGameState
  if gameHunterTriggered game && gamePendingHunter game /= Nothing
    then Left InvalidGameState else Right ()


