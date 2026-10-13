
-- | Mot duong xu ly Command chung tu queue toi Pure Engine.
module Server.GameLoop
  ( processNextLobbyCommand
  , runLobbyLoop
  , CreateRoomError(..)
  , createRoomWithHost
  ) where

import Control.Concurrent.MVar (modifyMVar)

import Control.Concurrent.STM
  ( atomically
  , newEmptyTMVarIO
  , putTMVar
  , readTBQueue
  , readTVar
  , readTVarIO
  , takeTMVar
  , writeTBQueue
  , writeTChan
  , writeTVar
  )

import Data.Char (isSpace)

import Domain.Engine
  ( applyLobbyCommand
  , applyNightCommand
  , applyPhaseCommand
  , closeWolfVoting
  , completeNightTurn
  , resolveNightTurn
  )

import Domain.Night (wolfVotingComplete)

import Domain.Types
  ( Command(..)
  , DomainEvent
  , GameError(..)
  , GameState(..)
  , LifeStatus(..)
  , NightChoice(..)
  , Phase(..)
  , Player(..)
  , PlayerId
  , Role(..)
  )

import Protocol.Types (RequestId, RoomId)

import Server.Room
  ( QueuedCommand(..)
  , RoomRegistry(..)
  , RoomRuntime(..)
  , RoomUpdate(..)
  , newRoomRuntime
  )

-- Xac thuc PlayerId cua command voi phien ket noi.
-- Lenh noi bo khong duoc gui truc tiep tu Browser.
actorMatches :: QueuedCommand -> Bool
actorMatches request =
  case queuedCommand request of
    Join pid _ ->
      pid == queuedActorId request

    Leave pid ->
      pid == queuedActorId request

    SetReady pid _ ->
      pid == queuedActorId request

    StartGame pid _ ->
      pid == queuedActorId request

    NightAction pid _ ->
      pid == queuedActorId request

    _ ->
      False

-- Kiem tra mot nguoi choi da gui NightAction dung vai.
hasSubmittedNightAction :: GameState -> Player -> Bool
hasSubmittedNightAction state player =
  any actionMatches (gameNightActions state)
  where
    actorId = playerId player

    actionMatches (pid, choice)
      | pid /= actorId =
          False

      | otherwise =
          case (playerRole player, choice) of
            (Just Werewolf, WolfTarget _) ->
              True

            (Just Seer, SeerTarget _) ->
              True

            (Just Guard, GuardTarget _) ->
              True

            (Just Witch, WitchHeal) ->
              True

            (Just Witch, WitchPoison _) ->
              True

            (Just Witch, WitchPass) ->
              True

            _ ->
              False

-- Chi cac vai co hanh dong Night moi phai cho.
-- Villager va Hunter con song khong can gui NightAction.
needsNightAction :: Player -> Bool
needsNightAction player =
  playerLifeStatus player == Alive
    && playerRole player `elem`
      [ Just Werewolf
      , Just Seer
      , Just Guard
      , Just Witch
      ]

-- Kiem tra toan bo cac vai can hanh dong da hoan thanh.
-- Witch phai duoc quyen chon sau khi khoa phieu Soi.
allNightActionsSubmitted :: GameState -> Bool
allNightActionsSubmitted state =
  all (hasSubmittedNightAction state) activePlayers
  where
    activePlayers =
      filter needsNightAction (gamePlayers state)

-- Sau khi Soi cuoi cung bo phieu, tu dong khoa phieu.
-- Khong ResolveNight tai day vi Witch co the chua chon.
closeCompletedWolfVote
  :: GameState
  -> [DomainEvent]
  -> Either GameError (GameState, [DomainEvent])
closeCompletedWolfVote state actionEvents
  | gameWolfVotingClosed state =
      Right (state, actionEvents)

  | not (wolfVotingComplete state) =
      Right (state, actionEvents)

  | otherwise = do
      (closedState, closeEvents) <-
        closeWolfVoting state False

      pure
        ( closedState
        , actionEvents ++ closeEvents
        )

-- ResolveNight khi da du cac hanh dong.
-- Neu Hunter bi loai, dung lai cho T06 xu ly HunterShot.
-- Neu khong co Hunter pending, cong bo vai va chuyen Day.
finishCompletedNight
  :: GameState
  -> [DomainEvent]
  -> Either GameError (GameState, [DomainEvent])
finishCompletedNight state priorEvents
  | gamePhase state /= Night =
      Right (state, priorEvents)

  | gameNightResolved state =
      Right (state, priorEvents)

  | not (gameWolfVotingClosed state) =
      Right (state, priorEvents)

  | not (allNightActionsSubmitted state) =
      Right (state, priorEvents)

  | otherwise = do
      (resolvedState, resolveEvents) <-
        resolveNightTurn state

      let eventsAfterResolve =
            priorEvents ++ resolveEvents

      case gamePendingHunter resolvedState of
        Just _ ->
          -- Hunter phai duoc xu ly truoc khi cong bo ket qua.
          pure (resolvedState, eventsAfterResolve)

        Nothing -> do
          (completedState, completeEvents) <-
            completeNightTurn resolvedState

          pure
            ( completedState
            , eventsAfterResolve ++ completeEvents
            )

-- Chon Pure Engine theo loai command.
-- Cac buoc Night duoc ket hop thanh mot ket qua thuan tuy.
dispatchPlayerCommand
  :: GameState
  -> Command
  -> Either GameError (GameState, [DomainEvent])
dispatchPlayerCommand state command =
  case command of

    -- T04: Bat dau van.
    StartGame _ _ ->
      applyPhaseCommand state command

    -- T05: Soi bo phieu, sau do kiem tra dong phieu.
    NightAction _ (WolfTarget _) -> do
      (nextState, actionEvents) <-
        applyNightCommand state command

      (closedState, closedEvents) <-
        closeCompletedWolfVote nextState actionEvents

      finishCompletedNight closedState closedEvents

    -- T05: Seer, Guard, Witch.
    -- Sau moi hanh dong, kiem tra co the ket thuc Night chua.
    NightAction _ _ -> do
      (nextState, actionEvents) <-
        applyNightCommand state command

      finishCompletedNight nextState actionEvents

    -- Lobby.
    Join _ _ ->
      applyLobbyCommand state command

    Leave _ ->
      applyLobbyCommand state command

    SetReady _ _ ->
      applyLobbyCommand state command

    -- Browser khong duoc goi command noi bo.
    _ ->
      Left NotAuthorized

-- Xu ly mot command tu queue.
-- State, version va events duoc commit trong cung STM.
processNextLobbyCommand :: RoomRuntime -> IO ()
processNextLobbyCommand room = atomically $ do
  request <- readTBQueue (roomCommands room)
  currentState <- readTVar (roomState room)

  let result =
        if actorMatches request
          then dispatchPlayerCommand
                 currentState
                 (queuedCommand request)
          else Left NotAuthorized

  case result of
    Left err -> do
      -- Command loi khong doi state hay version.
      putTMVar (queuedReply request) (Left err)

    Right (nextState, events) -> do
      currentVersion <- readTVar (roomVersion room)

      let nextVersion = currentVersion + 1

      writeTVar (roomState room) nextState
      writeTVar (roomVersion room) nextVersion

      -- Gui DomainEvent de Broadcast loc theo tung client.
      writeTChan (roomUpdates room)
        RoomUpdate
          { updateVersion = nextVersion
          , updateState = nextState
          , updateEvents = events
          }

      putTMVar (queuedReply request) (Right nextState)

-- Worker xu ly Command Queue.
-- Dung khi nguoi cuoi cung roi phong.
runLobbyLoop :: RoomRuntime -> IO ()
runLobbyLoop room = do
  processNextLobbyCommand room

  state <- readTVarIO (roomState room)

  if null (gamePlayers state)
    then pure ()
    else runLobbyLoop room

-- Loi khi tao phong.
data CreateRoomError
  = InvalidRoomId
  | RoomAlreadyExists
  | HostJoinRejected GameError
  deriving (Eq, Show)

-- Tao phong va Host.
-- Chi cong bo phong sau khi Host Join thanh cong.
createRoomWithHost
  :: RoomRegistry
  -> RoomId
  -> RequestId
  -> PlayerId
  -> String
  -> (RoomRuntime -> IO ())
  -> IO (Either CreateRoomError (RoomRuntime, GameState))
createRoomWithHost registry rid requestId actor name startWorker
  | null rid || length rid > 32 || any isSpace rid =
      pure (Left InvalidRoomId)

  | otherwise =
      modifyMVar (registryRooms registry) $ \rooms ->
        case lookup rid rooms of
          Just _ ->
            pure (rooms, Left RoomAlreadyExists)

          Nothing -> do
            room <- newRoomRuntime rid
            reply <- newEmptyTMVarIO

            atomically $
              writeTBQueue (roomCommands room)
                QueuedCommand
                  { queuedRequestId = requestId
                  , queuedActorId = actor
                  , queuedCommand = Join actor name
                  , queuedReply = reply
                  }

            -- Phong chua duoc cong bo.
            processNextLobbyCommand room

            result <- atomically (takeTMVar reply)

            case result of
              Left err ->
                pure (rooms, Left (HostJoinRejected err))

              Right state -> do
                startWorker room

                pure
                  ( (rid, room) : rooms
                  , Right (room, state)
                  )
