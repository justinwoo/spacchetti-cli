{-# LANGUAGE CPP, TupleSections #-}
module Spago.Watch (watch, globToParent, ClearScreen (..)) where

-- This code was adapted from
-- https://github.com/commercialhaskell/stack/blob/0740444175f41e6ea5ed236cd2c53681e4730003/src/Stack/FileWatch.hs

import           Spago.Prelude            hiding (FilePath)

import qualified Control.Concurrent       as Concurrent
import           Control.Monad.Trans.Cont (ContT (..))
import qualified Data.Set                 as Set
import           Data.Text                (pack, toLower, unpack)
import           Data.Time.Clock          (NominalDiffTime, diffUTCTime, getCurrentTime)
import           GHC.IO                   (FilePath)
import           GHC.IO.Exception
import           System.Console.ANSI      (hClearScreen, hSetCursorPosition)
import qualified System.Environment       as Env
import           System.FilePath          (splitDirectories)
import qualified System.FilePath.Glob     as Glob
import qualified System.FSNotify          as Watch
#ifdef mingw32_HOST_OS
import           System.IO                (getLine, stderr)
#else
import           System.IO                (getLine, openFile, stderr)
import           System.Posix.Terminal    (getControllingTerminalName)
#endif
import qualified UnliftIO                 (bracket)

import           Spago.Messages           as Messages


-- Should we clear the screen on rebuild?
data ClearScreen = DoClear | NoClear
  deriving Eq

watch :: Set.Set Glob.Pattern -> ClearScreen -> Spago () -> Spago ()
watch globs shouldClear action = flip runContT return $ do
  let conf = Watch.defaultConfig { Watch.confDebounce = Watch.NoDebounce }
  manager <- ContT $ withManagerConf conf
  terminalHandle <- ContT $ withTerminalHandle
  maybeTerm <- liftIO $ Env.lookupEnv "TERM"
  let useColor = maybeTerm /= Just "dumb" && maybeTerm /= Just "win"
  let writer = getWriter terminalHandle useColor
  lift $ fileWatchConf manager terminalHandle writer shouldClear globs action


getWriter :: Handle -> Bool -> LogLevel -> Utf8Builder -> Spago ()
getWriter handle' useColor level msg =
    liftIO . hPutStrLn handle' . unpack . textDisplay $ msg'
  where
  msg' = setColor <> reset <> msg

  ifUseColor color = if useColor then color else ""

  reset     = ifUseColor "\ESC[0m"
  setBlue   = ifUseColor "\ESC[34m"
  setYellow = ifUseColor "\ESC[33m"

  setColor = case level of
    LevelInfo -> setBlue <> "[info] "
    LevelWarn -> setYellow <> "[warn] "
    _         -> ""


withManagerConf :: Watch.WatchConfig -> (Watch.WatchManager -> Spago a) -> Spago a
withManagerConf conf = UnliftIO.bracket
  (liftIO $ Watch.startManagerConf conf)
  (liftIO . Watch.stopManager)


backupHandle :: Handle
backupHandle = stderr


#ifdef mingw32_HOST_OS
withTerminalHandle :: (Handle -> Spago a) -> Spago a
withTerminalHandle = UnliftIO.bracket (return backupHandle) (const $ return ())
#else
withTerminalHandle :: (Handle -> Spago a) -> Spago a
withTerminalHandle = UnliftIO.bracket terminalHandle release
  where
    terminalHandle :: Spago Handle
    terminalHandle =
      (tryIO $ liftIO getControllingTerminalName) >>= \case
        Right terminalFilePath -> liftIO $ do
          terminalHandle' <- openFile terminalFilePath WriteMode
          hSetBuffering terminalHandle' NoBuffering
          return terminalHandle'
        Left e@IOError{..} -> case (ioe_type, ioe_location) of
          (UnsupportedOperation, "getControllingTerminalName") -> do
            logWarn $ display $ Messages.noControllingTerminal $ pack $ show e
            return backupHandle
          _ ->
            throwIO e
    release :: Handle -> Spago ()
    release handle' = do
      when (handle' /= backupHandle) $ liftIO $ do
        hClose handle'
#endif


debounceTime :: NominalDiffTime
debounceTime = 0.1


-- | Run an action, watching for file changes
--
-- When any files corresponding to the given @globs@ are changed,
-- we rerun the given @action@ again.
fileWatchConf
  :: Watch.WatchManager
  -> Handle
  -> (LogLevel -> Utf8Builder -> Spago ())
  -> ClearScreen
  -> Set.Set Glob.Pattern
  -> Spago ()
  -> Spago ()
fileWatchConf manager terminalHandle writer shouldClear globs action = do
  -- `lastEvent` is used for event debouncing.
  -- We don't use built-in debouncing because it does not work well with some
  -- text editors (#346).
  lastEvent <- liftIO $ do
    timeNow <- getCurrentTime
    newTVarIO timeNow
  (spagoTQueue :: TQueue (Spago ())) <- liftIO newTQueueIO
  env <- ask

  let clearScreen :: IO ()
      clearScreen = do
        hClearScreen terminalHandle
        hSetCursorPosition terminalHandle 0 0
        hFlush terminalHandle

  let matches :: Watch.Event -> Glob.Pattern -> Bool
      matches event glob = Glob.match glob $ Watch.eventPath event

  let serialize :: Spago () -> Spago ()
      serialize = liftIO . atomically . writeTQueue spagoTQueue

  let writeInfo :: Utf8Builder -> Spago ()
      writeInfo = writer LevelInfo

  let writeWarn :: Utf8Builder -> Spago ()
      writeWarn = writer LevelWarn

  let redisplay :: Maybe Utf8Builder -> Spago ()
      redisplay maybeMsg = serialize $ do
        when (shouldClear == DoClear) $
          liftIO clearScreen
        mapM_ writeInfo maybeMsg

  let spawnRunActionThread :: Spago ()
      spawnRunActionThread =
        void . liftIO . Concurrent.forkIO
          $ (forever $ atomically (readTQueue spagoTQueue) >>= runRIO env)
              `catch` \(err :: SomeException) ->
                runRIO env $ do
                  logError $ "Thread responsible for writing to the terminal broke. Restarting..."
                  logError $ "Error was: " <> display err
                  spawnRunActionThread

  let tryAction :: Spago ()
      tryAction = serialize $ do
        eres :: Either SomeException () <- try action
        case eres of
          Left e -> writeWarn $ display e
          _      -> writeInfo "Success! Waiting for next file change."
        writeInfo "Type help for available commands. Press enter to force a rebuild."

  let redisplayAndTryAction :: Maybe Utf8Builder -> Spago ()
      redisplayAndTryAction maybeMsg = redisplay maybeMsg *> tryAction

  let onChange :: Watch.Event -> Spago ()
      onChange event = do
        timeNow <- liftIO getCurrentTime
        rebuilding <- liftIO $ atomically $ do
          lastTime <- readTVar lastEvent
          let sufficientDelay = diffUTCTime timeNow lastTime > debounceTime
          let shouldRebuild = any (matches event) globs && sufficientDelay
          when shouldRebuild $ do
            writeTVar lastEvent timeNow
          return shouldRebuild
        when rebuilding $ do
          redisplayAndTryAction $ Just $ "File changed, triggered a build: " <> displayShow (Watch.eventPath event)

  let watchGlobs :: Spago ()
      watchGlobs = do
        forM_ (Set.toList globs) $ \glob -> liftIO $
          Watch.watchTree manager (globToParent glob) (const True) (runRIO env . onChange)

  let watchInput :: Spago ()
      watchInput = do
        line <- liftIO $ unpack . toLower . pack <$> getLine
        if line == "quit" then writeInfo "Leaving watch mode."
        else do
          case line of
            "help" -> traverse_ writeInfo
                        [ ""
                        , "help: display this help"
                        , "quit: exit"
                        , "build: force a rebuild"
                        , "watched: display watched files"
                        ]
            "build" -> redisplayAndTryAction Nothing
            "watched" -> mapM_ (writeInfo . displayShow) (Glob.decompile <$> Set.toList globs)
            "" -> redisplayAndTryAction Nothing
            _ -> writeWarn $ displayShow $ concat
                    [ "Unknown command: "
                    , show line
                    , ". Try 'help'"
                    ]
          watchInput

  spawnRunActionThread
  tryAction
  watchGlobs
  watchInput

globToParent :: Glob.Pattern -> FilePath
globToParent glob = go pathHead pathRest
  where
    pathHead : pathRest = splitDirectories $ Glob.decompile glob

    go acc []           = acc
    go acc ("*":_rest)  = acc
    go acc ("**":_rest) = acc
    go acc [_file]      = acc
    go acc (h:rest)     = go (acc </> h) rest
