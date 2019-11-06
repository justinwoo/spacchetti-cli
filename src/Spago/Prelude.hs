module Spago.Prelude
  ( die
  , Dhall.Core.throws
  , hush
  , pathFromText
  , assertDirectory
  , App (..)
  , UsePsa(..)
  , Spago
  , module X
  , Proxy(..)
  , NonEmpty (..)
  , Seq (..)
  , Pretty
  , FilePath
  , ExitCode (..)
  , Validation(..)
  , (</>)
  , (^..)
  , surroundQuote
  , transformMOf
  , testfile
  , testdir
  , mktree
  , mv
  , cptree
  , bimap
  , first
  , second
  , chmod
  , executable
  , readTextFile
  , writeTextFile
  , isAbsolute
  , pathSeparator
  , headMay
  , lastMay
  , shouldRefreshFile
  , makeAbsolute
  , hPutStrLn
  , empty
  , callCommand
  , shell
  , shellStrict
  , shellStrictWithErr
  , systemStrictWithErr
  , viewShell
  , repr
  , with
  , appendonly
  , async'
  , mapTasks'
  , withTaskGroup'
  , Turtle.mktempdir
  , getModificationTime
  , docsSearchVersion
  , githubTokenEnvVar
  , pretty
  , output
  , outputStr
  , askApp
  ) where


import qualified Control.Concurrent.Async.Pool         as Async
import qualified Control.Monad.Catch                   as Catch
import qualified Data.Text                             as Text
import qualified Data.Text.Prettyprint.Doc             as Pretty
import qualified Data.Text.Prettyprint.Doc.Render.Text as PrettyText
import qualified Data.Time                             as Time
import           Dhall                                 (Text)
import qualified Dhall.Core
import qualified System.FilePath                       as FilePath
import qualified System.IO
import qualified Turtle
import qualified UnliftIO.Directory                    as Directory

import           Control.Applicative                   (empty)
import           Control.Monad                         as X
import           Control.Monad.Reader                  as X
import           Data.Aeson                            as X hiding (Result (..))
import           Data.Bifunctor                        (bimap, first, second)
import           Data.Bool                             as X
import           Data.Either                           as X
import           Data.Either.Validation                (Validation (..))
import           Data.Foldable                         as X
import           Data.List.NonEmpty                    (NonEmpty (..))
import           Data.Maybe                            as X
import           Data.Sequence                         (Seq (..))
import           Data.Text.Prettyprint.Doc             (Pretty)
import           Dhall.Optics                          (transformMOf)
import           Lens.Family                           ((^..))
import           RIO                                   as X hiding (FilePath, first, second, force)
import           Safe                                  (headMay, lastMay)
import           System.FilePath                       (isAbsolute, pathSeparator, (</>))
import           System.IO                             (hPutStrLn)
import           Turtle                                (ExitCode (..), FilePath, appendonly, chmod,
                                                        executable, mktree, repr, shell,
                                                        shellStrict, shellStrictWithErr,
                                                        systemStrictWithErr, testdir)
import           UnliftIO.Directory                    (getModificationTime, makeAbsolute)
import           UnliftIO.Process                      (callCommand)


-- | Generic Error that we throw on program exit.
--   We have it so that errors are displayed nicely to the user
newtype SpagoError = SpagoError { _unError :: Text }
instance Exception SpagoError
instance Show SpagoError where
  show (SpagoError err) = Text.unpack err


-- | Flag to disable the automatic use of `psa`
data UsePsa = UsePsa | NoPsa

-- | App configuration containing parameters and other common
--   things it's useful to compute only once at startup.
data App = App
  { appUsePsa      :: UsePsa
  , appJobs        :: Int
  , appConfigPath  :: Text
  , appOutputPath  :: Text
  , appGlobalCache :: Text
  , appLocalCache  :: Text
  , appLogFunc :: !LogFunc
  }

instance HasLogFunc App where
  logFuncL = lens appLogFunc (\x y -> x { appLogFunc = y })


type Spago = RIO App


-- | Facility to easily get global parameters from the environment
askApp :: (App -> a) -> Spago a
askApp = view . to


output :: MonadIO m => Text -> m ()
output = Turtle.printf (Turtle.s Turtle.% "\n")

outputStr :: MonadIO m => String -> m ()
outputStr = output . Text.pack

die :: MonadThrow m => Text -> m a
die reason = throwM $ SpagoError reason

-- | Suppress the 'Left' value of an 'Either'
hush :: Either a b -> Maybe b
hush = either (const Nothing) Just

pathFromText :: Text -> Turtle.FilePath
pathFromText = Turtle.fromText

testfile :: MonadIO m => Text -> m Bool
testfile = Turtle.testfile . pathFromText

readTextFile :: MonadIO m => Turtle.FilePath -> m Text
readTextFile = liftIO . Turtle.readTextFile


writeTextFile :: MonadIO m => Text -> Text -> m ()
writeTextFile path text = liftIO $ Turtle.writeTextFile (Turtle.fromText path) text


with :: MonadIO m => Turtle.Managed a -> (a -> IO r) -> m r
with r f = liftIO $ Turtle.with r f


viewShell :: (MonadIO m, Show a) => Turtle.Shell a -> m ()
viewShell = Turtle.view


surroundQuote :: IsString t => Semigroup t => t -> t
surroundQuote y = "\"" <> y <> "\""


mv :: MonadIO m => System.IO.FilePath -> System.IO.FilePath -> m ()
mv from to' = Turtle.mv (Turtle.decodeString from) (Turtle.decodeString to')


cptree :: MonadIO m => System.IO.FilePath -> System.IO.FilePath -> m ()
cptree from to' = Turtle.cptree (Turtle.decodeString from) (Turtle.decodeString to')


withTaskGroup' :: Int -> (Async.TaskGroup -> Spago b) -> Spago b
withTaskGroup' n action = withRunInIO $ \run -> Async.withTaskGroup n (\taskGroup -> run $ action taskGroup)

async' :: Async.TaskGroup -> Spago a -> Spago (Async.Async a)
async' taskGroup action = withRunInIO $ \run -> Async.async taskGroup (run action)

mapTasks' :: Traversable t => Async.TaskGroup -> t (Spago a) -> Spago (t a)
mapTasks' taskGroup actions = withRunInIO $ \run -> Async.mapTasks taskGroup (run <$> actions)

-- | Code from: https://github.com/dhall-lang/dhall-haskell/blob/d8f2787745bb9567a4542973f15e807323de4a1a/dhall/src/Dhall/Import.hs#L578
assertDirectory :: (MonadIO m, MonadThrow m) => FilePath.FilePath -> m ()
assertDirectory directory = do
  let private = transform Directory.emptyPermissions
        where
          transform =
            Directory.setOwnerReadable   True
            .   Directory.setOwnerWritable   True
            .   Directory.setOwnerSearchable True

  let accessible path =
        Directory.readable   path
        && Directory.writable   path
        && Directory.searchable path

  directoryExists <- Directory.doesDirectoryExist directory

  if directoryExists
    then do
      permissions <- Directory.getPermissions directory
      unless (accessible permissions) $ do
        die $ "Directory " <> tshow directory <> " is not accessible. " <> tshow permissions
    else do
      assertDirectory (FilePath.takeDirectory directory)

      Directory.createDirectory directory

      Directory.setPermissions directory private


-- | Release tag for the `purescript-docs-search` app.
docsSearchVersion :: Text
docsSearchVersion = "v0.0.5"


githubTokenEnvVar :: IsString t => t
githubTokenEnvVar = "SPAGO_GITHUB_TOKEN"


-- | Check if the file is present and more recent than 1 day
shouldRefreshFile :: FilePath.FilePath -> Spago Bool
shouldRefreshFile path = (tryIO $ liftIO $ do
  fileExists <- testfile $ Text.pack path
  lastModified <- getModificationTime path
  now <- Time.getCurrentTime
  let fileIsRecentEnough = Time.addUTCTime Time.nominalDay lastModified >= now
  pure $ not (fileExists && fileIsRecentEnough)) >>= \case
    Right v -> pure v
    Left err -> do
      logDebug $ "Unable to read file " <> displayShow path <> ". Error was: " <> display err
      pure True


-- | Prettyprint a `Pretty` expression
pretty :: Pretty.Pretty a => a -> Dhall.Text
pretty = PrettyText.renderStrict
  . Pretty.layoutPretty Pretty.defaultLayoutOptions
  . Pretty.pretty
