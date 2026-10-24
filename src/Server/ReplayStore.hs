{-# LANGUAGE ScopedTypeVariables #-}

-- | Kho replay cong khai dung chung giua Game Server va Analytics Worker.
-- Module nay chi luu 'MatchSummary' da duoc lam sach; tuyet doi khong ghi
-- 'GameState', vai tro, chat hay muc tieu hanh dong len NFS.
module Server.ReplayStore
  ( ReplayStore
  , ReplayWriteResult(..)
  , StorageError(..)
  , newReplayStore
  , writeReplay
  , readReplay
  , replayFilePath
  , renderStorageError
  , storageErrorFromIOException
  ) where

import Control.Exception
  ( IOException
  , bracketOnError
  , catch
  , try
  )
import qualified Data.ByteString as BS
import Data.Char (isAlphaNum)
import System.Directory
  ( createDirectoryIfMissing
  , doesFileExist
  , removeFile
  , renameFile
  )
import System.FilePath ((</>), takeFileName)
import System.IO
  ( Handle
  , hClose
  , hFlush
  , openBinaryTempFile
  )
import System.IO.Error
  ( ioeGetErrorString
  , isDoesNotExistError
  , isPermissionError
  )

import Protocol.Analytics
  ( MatchSummary(..)
  , decodeMatchSummaryLine
  , encodeMatchSummaryLine
  )

newtype ReplayStore = ReplayStore
  { replayRoot :: FilePath
  }

data ReplayWriteResult
  = ReplayCreated FilePath
  | ReplayAlreadyPresent FilePath
  deriving (Eq, Show)

data StorageError
  = StorageUnavailable FilePath String
  | StoragePermissionDenied FilePath
  | StorageCorrupt FilePath String
  | StorageConflict FilePath
  | StorageInvalidMatchId String
  deriving (Eq, Show)

newReplayStore :: FilePath -> ReplayStore
newReplayStore = ReplayStore

-- | Chuyen matchId thanh ten file an toan, khong cho phep path traversal.
replayFilePath :: ReplayStore -> String -> Either StorageError FilePath
replayFilePath store identifier
  | null identifier = Left (StorageInvalidMatchId identifier)
  | length identifier > 160 = Left (StorageInvalidMatchId identifier)
  | all validCharacter identifier =
      Right (replayRoot store </> identifier <> ".json")
  | otherwise = Left (StorageInvalidMatchId identifier)
  where
    validCharacter character =
      isAlphaNum character || character == '-' || character == '_'

-- | Ghi replay bang file tam + rename. Ghi lai cung matchId/cung noi dung la
-- idempotent; cung matchId nhung noi dung khac bi tu choi.
writeReplay
  :: ReplayStore
  -> MatchSummary
  -> IO (Either StorageError ReplayWriteResult)
writeReplay store summary =
  case replayFilePath store (matchId summary) of
    Left err -> pure (Left err)
    Right target -> do
      existence <- try (doesFileExist target)
      case existence of
        Left (err :: IOException) ->
          pure (Left (storageErrorFromIOException target err))
        Right True -> compareExisting target
        Right False -> writeNew target
  where
    compareExisting target = do
      existing <- readReplay store (matchId summary)
      pure $ case existing of
        Right stored
          | stored == summary -> Right (ReplayAlreadyPresent target)
          | otherwise -> Left (StorageConflict target)
        Left err -> Left err

    writeNew target = do
      outcome <- try $ do
        createDirectoryIfMissing True (replayRoot store)
        writeAtomicFile (replayRoot store) target
          (encodeMatchSummaryLine summary)
      pure $ case outcome of
        Left (err :: IOException) ->
          Left (storageErrorFromIOException target err)
        Right () -> Right (ReplayCreated target)

-- | Doc mot replay da lam sach. File qua 64 KiB bi xem la hong de tranh nap
-- du lieu vo han khi mount hoac file bi loi.
readReplay
  :: ReplayStore
  -> String
  -> IO (Either StorageError MatchSummary)
readReplay store identifier =
  case replayFilePath store identifier of
    Left err -> pure (Left err)
    Right path -> do
      outcome <- try (BS.readFile path)
      pure $ case outcome of
        Left (err :: IOException) ->
          Left (storageErrorFromIOException path err)
        Right bytes
          | BS.length bytes > maxReplayBytes ->
              Left (StorageCorrupt path "replay exceeds 64 KiB")
          | otherwise ->
              case decodeMatchSummaryLine bytes of
                Left err -> Left (StorageCorrupt path err)
                Right replay -> Right replay

maxReplayBytes :: Int
maxReplayBytes = 64 * 1024

writeAtomicFile :: FilePath -> FilePath -> BS.ByteString -> IO ()
writeAtomicFile directory target bytes =
  bracketOnError
    (openBinaryTempFile directory (takeFileName target <> ".tmp"))
    cleanupTemp
    (\(temporary, handle) -> do
      BS.hPut handle bytes
      hFlush handle
      hClose handle
      renameFile temporary target)

cleanupTemp :: (FilePath, Handle) -> IO ()
cleanupTemp (path, handle) = do
  hClose handle `catch` ignoreIOException
  removeFile path `catch` ignoreIOException

ignoreIOException :: IOException -> IO ()
ignoreIOException _ = pure ()

storageErrorFromIOException :: FilePath -> IOException -> StorageError
storageErrorFromIOException path err
  | isPermissionError err = StoragePermissionDenied path
  | isDoesNotExistError err =
      StorageUnavailable path (ioeGetErrorString err)
  | otherwise = StorageUnavailable path (ioeGetErrorString err)

-- | Thong bao log chi chua loai loi va duong dan, khong chen payload replay.
renderStorageError :: StorageError -> String
renderStorageError storageError =
  case storageError of
    StorageUnavailable path reason ->
      "StorageUnavailable at " <> path <> ": " <> reason
    StoragePermissionDenied path ->
      "StoragePermissionDenied at " <> path
    StorageCorrupt path reason ->
      "StorageCorrupt at " <> path <> ": " <> reason
    StorageConflict path ->
      "StorageConflict at " <> path
    StorageInvalidMatchId _ ->
      "StorageInvalidMatchId"
