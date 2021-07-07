{-# LANGUAGE IncoherentInstances #-}
module Spago.Prelude
  (
  -- * Basic exports
    module X
  , Proxy(..)
  , NonEmpty (..)
  , Seq (..)
  , Validation(..)
  , first
  , second
  , headMay
  , lastMay
  , empty
  , ifM

  -- * Logging, errors, printing, etc
  , Pretty
  , pretty
  , output
  , outputStr
  , jsonToText
  , jsonToTextPretty
  , die
  , hush
  , surroundQuote
  , withLineBuffering
  , logInfo
  , logWarn
  , logDebug
  , logError
  , HasLogFunc

  -- * Lens
  , (</>)
  , (^..)
  , transformMOf
  , the
  , HasType

  -- * Files and directories
  , FilePath
  , pathFromText
  , testfile
  , testdir
  , mktree
  , mv
  , cptree
  , assertDirectory
  , chmod
  , executable
  , readTextFile
  , writeTextFile
  , isAbsolute
  , pathSeparator
  , shouldRefreshFile
  , makeAbsolute
  , getModificationTime
  , Turtle.mktempdir

  -- * Running commands
  , ExitCode (..)
  , callCommand
  , shell
  , shellStrict
  , shellStrictWithErr
  , systemStrictWithErr
  , viewShell
  , findExecutableOrDie
  , findExecutable

  -- * Other
  , Dhall.Core.throws
  , repr
  , with
  , appendonly
  , githubTokenEnvVar
  ) where


import qualified Data.Text                             as Text
import qualified Data.Text.Prettyprint.Doc             as Pretty
import qualified Data.Text.Prettyprint.Doc.Render.Text as PrettyText
import qualified Data.Time                             as Time
import           Dhall                                 (Text)
import qualified Dhall.Core
import qualified RIO
import qualified System.FilePath                       as FilePath
import qualified System.Info
import qualified System.IO
import qualified Turtle
import qualified UnliftIO.Directory                    as Directory

import           Control.Applicative                   (empty)
import           Control.Monad                         as X
import           Control.Monad.Reader                  as X
import           Data.Aeson                            as X hiding (Result (..), json)
import           Data.Bifunctor                        (first, second)
import           Data.Bool                             as X
import           Data.Either                           as X
import           Data.Either.Validation                (Validation (..))
import           Data.Foldable                         as X
import           Data.Generics.Product                 (the, HasType(..))
import           Data.Maybe                            as X
import           Data.Sequence                         (Seq (..))
import           Data.Text.Prettyprint.Doc             (Pretty)
import           Dhall.Optics                          (transformMOf)
import           Lens.Family                           ((^..))
import           RIO                                   as X hiding (FilePath, first, force, second, HasLogFunc, logDebug, logError, logInfo, logWarn, (^..))
import           RIO.Orphans                           as X
import           Safe                                  (headMay, lastMay)
import           System.FilePath                       (isAbsolute, pathSeparator, (</>))
import           Turtle                                (FilePath, appendonly, chmod,
                                                        executable, mktree, repr, shell,
                                                        shellStrict, shellStrictWithErr,
                                                        systemStrictWithErr, testdir)
import           UnliftIO.Directory                    (getModificationTime, makeAbsolute)
import           UnliftIO.Process                      (callCommand)


import qualified Data.Aeson as Json
import qualified Data.Aeson.Encode.Pretty as Json
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BSL
import qualified Data.ByteString.Search as BSS
import qualified Data.ByteString.UTF8 as UTF8
import qualified Data.Text.Lazy as LT
import qualified Data.Text.Lazy.Encoding as LT
import qualified System.IO as IO


-- | Generic Error that we throw on program exit.
--   We have it so that errors are displayed nicely to the user
newtype SpagoError = SpagoError { _unError :: Text }
instance Exception SpagoError
instance Show SpagoError where
  show (SpagoError err) = Text.unpack err


output :: MonadIO m => Text -> m ()
output = Turtle.printf (Turtle.s Turtle.% "\n")

outputStr :: MonadIO m => String -> m ()
outputStr = output . Text.pack

die :: (MonadIO m, HasLogFunc env, MonadReader env m) => [Utf8Builder] -> m a
die reasons = do
  traverse_ logError reasons
  exitFailure

ifM :: Monad m => m Bool -> m a -> m a -> m a
ifM p x y = p >>= \b -> if b then x else y

-- | Suppress the 'Left' value of an 'Either'
hush :: Either a b -> Maybe b
hush = either (const Nothing) Just

pathFromText :: Text -> Turtle.FilePath
pathFromText = Turtle.fromText

testfile :: MonadIO m => Text -> m Bool
testfile = Turtle.testfile . pathFromText

-- | Unfortunately ByteString's readFile does not convert line endings on
-- Windows, so we have to do it ourselves
fixCRLF :: BS.ByteString -> BS.ByteString
fixCRLF = BSL.toStrict . BSS.replace "\r\n" ("\n" :: BS.ByteString)

readTextFile :: MonadIO m => Turtle.FilePath -> m Text
readTextFile inFile' = do
  content <- liftIO $ BS.readFile $ Turtle.encodeString inFile'
  pure (Text.pack $ UTF8.toString $ fixCRLF content)

writeTextFile :: MonadIO m => Text -> Text -> m ()
writeTextFile inFile text = liftIO $ BS.writeFile
  (Text.unpack inFile)
  (UTF8.fromString $ Text.unpack text)

withLineBuffering :: MonadIO m => m a -> m ()
withLineBuffering action = do
  previousBuffering <- liftIO $ IO.hGetBuffering IO.stderr
  liftIO $ IO.hSetBuffering IO.stderr IO.LineBuffering
  action
  liftIO $ IO.hSetBuffering IO.stderr previousBuffering

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


-- | Code from: https://github.com/dhall-lang/dhall-haskell/blob/d8f2787745bb9567a4542973f15e807323de4a1a/dhall/src/Dhall/Import.hs#L578
assertDirectory :: (MonadIO m, HasLogFunc env, MonadReader env m) => FilePath.FilePath -> m ()
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
        die [ "Directory " <> displayShow directory <> " is not accessible. " <> displayShow permissions ]
    else do
      logDebug $ "Directory " <> displayShow directory <> " does not exist, creating..."
      assertDirectory (FilePath.takeDirectory directory)

      Directory.createDirectory directory

      Directory.setPermissions directory private


githubTokenEnvVar :: IsString t => t
githubTokenEnvVar = "SPAGO_GITHUB_TOKEN"


-- | Check if the file is present and more recent than 1 day
shouldRefreshFile :: HasLogFunc env => FilePath.FilePath -> RIO env Bool
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

-- | Return the full path of the executable we're trying to call. On Windows we
--   first try the `.cmd` version.
findExecutable :: MonadIO m => String -> m (Maybe Text)
findExecutable x =
  fmap (fmap Text.pack) $ case System.Info.os of
    "mingw32" -> Directory.findExecutable (x <> ".cmd") >>= \case
      Nothing -> Directory.findExecutable x
      success -> pure success
    _ -> Directory.findExecutable x


-- | Return the full path of the executable we're trying to call,
--   or die trying
findExecutableOrDie :: HasLogFunc env => String -> RIO env Text
findExecutableOrDie cmd = do
  findExecutable cmd >>= \case
    Nothing -> die [ "Executable was not found in path: " <> displayShow cmd ]
    -- Note: we ignore the path and just return the input because the one we get
    -- here is absolute, and Windows doesn't seem to be able to deal with that.
    -- See: https://github.com/purescript/spago/issues/635
    Just _path -> pure $ Text.pack cmd


jsonToText :: ToJSON a => a -> Text
jsonToText = LT.toStrict . LT.decodeUtf8 . Json.encode

jsonToTextPretty :: ToJSON a => a -> Text
jsonToTextPretty = LT.toStrict . LT.decodeUtf8 . Json.encodePretty

type HasLogFunc env = HasType LogFunc env

liftLog
  :: (HasLogFunc env, MonadIO m, MonadReader env m)
  => (Utf8Builder -> RIO LogFunc ())
  -> Utf8Builder
  -> m ()
liftLog logImpl msg = do
  logFunc <- view (the @LogFunc)
  runRIO logFunc (logImpl msg)

logDebug, logInfo, logWarn, logError
  :: (HasLogFunc env, MonadIO m, MonadReader env m)
  => Utf8Builder
  -> m ()
logDebug = liftLog RIO.logDebug
logInfo = liftLog RIO.logInfo
logWarn = liftLog RIO.logWarn
logError = liftLog RIO.logError
