-- | Các hàm kiểm tra Command và invariant của GameState.

module Domain.Validation where

import Data.Char (isSpace, toLower)

import Data.List (sort)

import Domain.Types

-- Chuẩn hóa tên trước khi lưu.

normalizePlayerName :: String -> String

normalizePlayerName = unwords . words

-- So sánh tên không phân biệt khoảng trắng và chữ hoa/thường.

-- Đây chưa phải Unicode case-folding đầy đủ.

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

  where

    clean = normalizePlayerName name

-- Kiem tra ngoai hinh theo cac tuy chon da thong nhat voi T07.
-- Tu choi gia tri ngoai danh sach truoc khi luu hoac dong bo.
validateAppearance :: Appearance -> Either GameError Appearance
validateAppearance appearance
  | appearanceHair appearance `notElem` validHairStyles = Left InvalidAppearance
  | appearanceHairColor appearance `notElem` validHairColors = Left InvalidAppearance
  | appearanceSkin appearance `notElem` validSkinColors = Left InvalidAppearance
  | appearanceOutfit appearance `notElem` validOutfits = Left InvalidAppearance
  | appearanceAccessory appearance `notElem` validAccessories = Left InvalidAppearance
  | otherwise = Right appearance
  where
    validHairStyles =
      [ "messy", "spiky", "curly", "bob", "long", "ponytail" ]

    validHairColors =
      [ "#1E293B", "#78350F", "#F59E0B"
      , "#EF4444", "#EC4899", "#8B5CF6"
      , "#3B82F6", "#10B981", "#F8FAFC"
      ]

    validSkinColors =
      [ "#FDE2D0", "#FED7AA", "#FDBA74"
      , "#C28865", "#FEF3C7"
      ]

    validOutfits =
      [ "#1E1B4B", "#1E3A8A", "#064E3B"
      , "#701A75", "#881337", "#0F172A"
      ]

    validAccessories =
      [ "none", "straw_hat", "cat_ears", "witch_hat"
      , "sunglasses", "horns", "halo", "flower_crown"
      ]

mkPlayer :: PlayerId -> String -> Either GameError Player

mkPlayer pid name = do

  validId <- validatePlayerId pid

  validName <- validatePlayerName name

  pure (Player validId validName Nothing False Alive defaultAppearance)

hasDuplicates :: Eq a => [a] -> Bool

hasDuplicates [] = False

hasDuplicates (x:xs) = x `elem` xs || hasDuplicates xs

validateUniquePlayerIds :: [Player] -> Either GameError ()

validateUniquePlayerIds ps

  | hasDuplicates (map playerId ps) = Left DuplicatePlayerId

  | otherwise = Right ()

validateUniquePlayerNames :: [Player] -> Either GameError ()

validateUniquePlayerNames ps

  | hasDuplicates (map (playerNameKey . playerName) ps) =

      Left DuplicatePlayerName

  | otherwise =

      Right ()

-- Chỉ bắt đầu ván khi có đúng 8 hoặc 9 người.

validatePlayerCount :: [Player] -> Either GameError ()

validatePlayerCount ps

  | length ps `elem` [8, 9] = Right ()

  | otherwise = Left InvalidPlayerCount

validateAllReady :: [Player] -> Either GameError ()

validateAllReady ps

  | not (null ps) && all playerReady ps = Right ()

  | otherwise = Left NotAllReady

-- So sánh bộ vai, không yêu cầu đúng thứ tự.

expectedRoles :: Int -> Maybe [Role]

expectedRoles 8 =

  Just [Werewolf, Werewolf, Seer, Guard, Witch, Hunter, Villager, Villager]

expectedRoles 9 =

  Just [Werewolf, Werewolf, Werewolf, Seer, Guard, Witch, Hunter, Villager, Villager]

expectedRoles _ =

  Nothing

validateRolePreset :: Int -> [Role] -> Either GameError ()

validateRolePreset count roles =

  case expectedRoles count of

    Nothing ->

      Left InvalidPlayerCount

    Just correct

      | sort roles == sort correct -> Right ()

      | otherwise -> Left InvalidRoleConfiguration

validatePlayerExists :: PlayerId -> [Player] -> Either GameError Player

validatePlayerExists pid ps =

  case filter ((== pid) . playerId) ps of

    []    -> Left PlayerNotFound

    p : _ -> Right p

validatePlayerAlive :: Player -> Either GameError Player

validatePlayerAlive p =

  case playerLifeStatus p of

    Alive -> Right p

    Dead  -> Left DeadPlayer

validateLivingTarget :: PlayerId -> [Player] -> Either GameError Player

validateLivingTarget pid ps =

  validatePlayerExists pid ps >>= validatePlayerAlive

validatePhase :: Phase -> GameState -> Either GameError ()

validatePhase expected game

  | gamePhase game == GameOver = Left GameAlreadyOver

  | gamePhase game == expected = Right ()

  | otherwise = Left WrongPhase

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

validateStartGame :: PlayerId -> GameState -> Either GameError ()

validateStartGame actor game = do

  validatePhase Lobby game

  if actor == gameHost game && not (null actor)

    then Right ()

    else Left NotAuthorized

  validatePlayerCount (gamePlayers game)

  validateAllReady (gamePlayers game)

  validateRolePreset (length (gamePlayers game)) (gameConfiguredRoles game)

  validateGameInvariant game

validateNightAction

  :: GameState

  -> PlayerId

  -> NightChoice

  -> Either GameError ()

validateNightAction game actor action = do

  validatePhase Night game

  if gameNightResolved game

    then Left InvalidGameState

    else Right ()

  if gamePendingHunter game == Nothing

    then Right ()

    else Left HunterNotPending

  p <- validatePlayerExists actor (gamePlayers game) >>= validatePlayerAlive

  if actor `elem` map fst (gameNightActions game)

    then Left DuplicateNightAction

    else Right ()

  case (playerRole p, action) of

    (Just Werewolf, WolfTarget target) -> do

      -- Khong cho Soi bo phieu sau khi da khoa luot.

      if gameWolfVotingClosed game

        then Left InvalidNightAction

        else Right ()

      -- Muc tieu phai con song va thuoc phe Village.

      victim <- validateLivingTarget target (gamePlayers game)

      if fmap teamOfRole (playerRole victim) == Just Village

        then Right ()

        else Left InvalidTarget

    (Just Seer, SeerTarget target) ->

      otherAlive target

    (Just Guard, GuardTarget target) -> do

      _ <- validateLivingTarget target (gamePlayers game)

      if Just target == gameLastProtected game

        then Left InvalidTarget

        else Right ()

    (Just Witch, WitchHeal) -> do

      -- Kiem tra Phu Thuy con binh Heal hay khong.

      if gameWitchHealReady game

        then Right ()

        else Left AbilityAlreadyUsed

      -- Chi duoc Heal sau khi Server da khoa phieu Soi.

      if gameWolfVotingClosed game

        then Right ()

        else Left InvalidNightAction

      -- Phai co mot nan nhan Soi duy nhat.

      if wolfVictimKnown game

        then Right ()

        else Left InvalidNightAction

    (Just Witch, WitchPoison target) -> do

      if gameWitchPoisonReady game

        then Right ()

        else Left AbilityAlreadyUsed

      otherAlive target

    (Just Witch, WitchPass) ->

      Right ()

    (Just Hunter, NoAction) ->

      Right ()

    (Just Villager, NoAction) ->

      Right ()

    _ ->

      Left InvalidNightAction

  where

    otherAlive target = do

      _ <- validateLivingTarget target (gamePlayers game)

      if actor == target

        then Left InvalidTarget

        else Right ()

-- T05: Lay danh sach muc tieu Night hop le cho mot actor va loai action.
-- Tai Server, actor phai duoc lay tu session da xac thuc.
-- Khong tin PlayerId do client tu khai.
validNightTargets
  :: GameState
  -> PlayerId
  -> (PlayerId -> NightChoice)
  -> [PlayerId]
validNightTargets game actor mkChoice =
  [ playerId target
  | target <- gamePlayers game
  , validateNightAction game actor (mkChoice (playerId target)) == Right ()
  ]

-- Nếu phiếu Sói hòa thì chưa có nạn nhân duy nhất cho Witch Heal.

wolfVictimKnown :: GameState -> Bool

wolfVictimKnown game =

  let wolves =

        [ playerId p

        | p <- gamePlayers game

        , playerLifeStatus p == Alive

        , playerRole p == Just Werewolf

        ]

      votes =

        [ target

        | (pid, WolfTarget target) <- gameNightActions game

        , pid `elem` wolves

        ]

      unique [] = []

      unique (x:xs) = x : unique (filter (/= x) xs)

      winners =

        case votes of

          [] -> []

          _ ->

            let highest =

                  maximum

                    [ length (filter (== target) votes)

                    | target <- unique votes

                    ]

            in [ target

               | target <- unique votes

               , length (filter (== target) votes) == highest

               ]

  in not (null wolves)

     && gameWolfVotingClosed game

     && length winners == 1

validateVote :: GameState -> PlayerId -> PlayerId -> Either GameError ()

validateVote game actor target = do

  validatePhase Voting game

  if gameVotingResolved game

    then Left InvalidGameState

    else Right ()

  if gamePendingHunter game == Nothing

    then Right ()

    else Left HunterNotPending

  _ <- validatePlayerExists actor (gamePlayers game) >>= validatePlayerAlive

  _ <- validateLivingTarget target (gamePlayers game)

  if actor == target

    then Left InvalidTarget

    else Right ()

  if actor `elem` map fst (gameVotes game)

    then Left AlreadyVoted

    else Right ()

validateChat :: GameState -> PlayerId -> String -> Either GameError ()

validateChat game actor message =
  validateChatInChannel game actor PublicDay message

-- T02: Kiem tra chat theo kenh va quyen cua actor.
-- Chi Server duoc xac dinh actor va room tu session.
validateChatInChannel
  :: GameState
  -> PlayerId
  -> ChatChannel
  -> String
  -> Either GameError ()
validateChatInChannel game actor channel message = do
  case channel of
    PublicDay ->
      validatePhase Day game

    WolvesNight ->
      validatePhase Night game

  player <- validatePlayerExists actor (gamePlayers game)
  _ <- validatePlayerAlive player

  case channel of
    PublicDay ->
      Right ()

    WolvesNight ->
      if playerRole player == Just Werewolf
        then Right ()
        else Left InvalidRole

  if all isSpace message
    then Left EmptyChat
    else Right ()
  if length message > 300
    then Left ChatTooLong
    else Right ()

validateHunterShot

  :: GameState

  -> PlayerId

  -> Maybe PlayerId

  -> Either GameError ()

validateHunterShot game actor target = do

  if gamePendingHunter game == Just actor

      && not (gameHunterTriggered game)

    then Right ()

    else Left HunterNotPending

  hunter <- validatePlayerExists actor (gamePlayers game)

  if playerRole hunter == Just Hunter

      && playerLifeStatus hunter == Dead

    then Right ()

    else Left HunterNotPending

  case target of

    Nothing ->

      Right ()

    Just pid -> do

      if pid == actor

        then Left InvalidTarget

        else do

          _ <- validateLivingTarget pid (gamePlayers game)

          Right ()

-- Invariant phải đúng sau mỗi lần Engine cập nhật GameState.

validateGameInvariant :: GameState -> Either GameError ()

validateGameInvariant game = do

  let ps = gamePlayers game

      ids = map playerId ps

      active = gamePhase game /= Lobby

      uniqueActors =

        not (hasDuplicates (map fst (gameVotes game)))

          && not (hasDuplicates (map fst (gameNightActions game)))

      refsOk =

        all (\(actor, target) -> actor `elem` ids && target `elem` ids)

            (gameVotes game)

          && all (\(actor, _) -> actor `elem` ids)

                 (gameNightActions game)

          && all (`elem` ids) (gamePendingReveals game)

      pendingRevealsOk =

        not (hasDuplicates (gamePendingReveals game))

          && all pendingRevealIsDead (gamePendingReveals game)

      voteEntriesOk =

        all validVoteEntry (gameVotes game)

      validVoteEntry (actor, target) =

        actor /= target

          && maybe False ((== Alive) . playerLifeStatus)

               (validateById actor ps)

          && maybe False ((== Alive) . playerLifeStatus)

               (validateById target ps)

      pendingRevealIsDead pid =

        case validateById pid ps of

          Just player -> playerLifeStatus player == Dead

          Nothing -> False

      hostOk =

        if null ps

          then null (gameHost game)

          else gameHost game `elem` ids

  mapM_ (validatePlayerId . playerId) ps

  mapM_ (validatePlayerName . playerName) ps

  validateUniquePlayerIds ps

  validateUniquePlayerNames ps

  if length ps <= 9

    then Right ()

    else Left RoomFull

  if hostOk && uniqueActors && refsOk && pendingRevealsOk && voteEntriesOk

    then Right ()

    else Left InvalidGameState

  if gameWolfTiePolicy game == NoElimination

      && gameVoteTiePolicy game == NoElimination

    then Right ()

    else Left InvalidTiePolicy

  if active

    then do

      validatePlayerCount ps

      validateRolePreset (length ps) (gameConfiguredRoles game)

      let assigned =

            [ role

            | p <- ps

            , Just role <- [playerRole p]

            ]

      if sort assigned == sort (gameConfiguredRoles game)

          && gameDay game >= 1

        then Right ()

        else Left InvalidGameState

    else

      if all (\p -> playerRole p == Nothing

                    && playerLifeStatus p == Alive) ps

          && gameDay game == 0

          && null (gameVotes game)

          && null (gameNightActions game)

          && gameResult game == Nothing

          && null (gamePendingReveals game)

          && gamePendingHunter game == Nothing

        then Right ()

        else Left InvalidGameState

  if (gamePhase game == GameOver) == (gameResult game /= Nothing)

    then Right ()

    else Left InvalidGameState

  if (gamePhase game == Voting || null (gameVotes game))

      && (gamePhase game == Night || null (gameNightActions game))

    then Right ()

    else Left InvalidGameState

  case gamePendingHunter game of

    Nothing ->

      Right ()

    Just pid -> do

      p <- validatePlayerExists pid ps

      if playerRole p == Just Hunter

          && playerLifeStatus p == Dead

          && not (gameHunterTriggered game)

          && gamePhase game /= GameOver

        then Right ()

        else Left InvalidGameState

  if gameHunterTriggered game && gamePendingHunter game /= Nothing

    then Left InvalidGameState

    else Right ()

  -- Dấu resolve chỉ được bật trong đúng Phase, sau khi action/vote đã xử lý.

  if gameNightResolved game

      && (gamePhase game /= Night

          || not (null (gameNightActions game)))

    then Left InvalidGameState

    else Right ()

  -- Kiem tra Voting da duoc resolve dung Phase.

  if gameVotingResolved game

      && (gamePhase game /= Voting

          || not (null (gameVotes game)))

    then Left InvalidGameState

    else Right ()

  -- Chi cho phep khoa phieu Soi trong Phase Night.

  if gameWolfVotingClosed game && gamePhase game /= Night

    then Left InvalidGameState

    else Right ()

-- Tìm Player trong invariant bằng Maybe để không tạo lỗi phụ khi dữ liệu

-- đang hỏng; refsOk đã kiểm tra ID tồn tại trước đó.

validateById :: PlayerId -> [Player] -> Maybe Player

validateById pid = go

  where

    go [] = Nothing

    go (player : rest)

      | playerId player == pid = Just player

      | otherwise = go rest
