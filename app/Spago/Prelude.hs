module Spago.Prelude
  ( echo
  , echoStr
  , echoDebug
  , die
  , throws
  , hush
  , withDirectory
  , pathFromText
  , GlobalOptions (..)
  , Spago
  , module X
  , Typeable
  , Text
  , NonEmpty (..)
  , Map
  , Generic
  , Pretty
  , FilePath
  , ExitCode (..)
  , (<|>)
  , (</>)
  , (^..)
  , testfile
  , testdir
  , mktree
  , readTextFile
  , writeTextFile
  , atomically
  , newTVarIO
  , readTVar
  , readTVarIO
  , writeTVar
  , isAbsolute
  , pathSeparator
  , headMay
  , for
  , makeAbsolute
  , hPutStrLn
  , many
  , empty
  , callProcess
  , shell
  , shellStrict
  , systemStrictWithErr
  , viewShell
  , repr
  , with
  , appendonly
  ) where

import           Control.Applicative       (empty, many, (<|>))
import           Control.Monad             as X
import           Control.Monad.Catch       as X
import           Control.Monad.Reader      as X
import           Data.Aeson                as X
import           Data.Either               as X
import           Data.Foldable             as X
import           Data.List.NonEmpty        (NonEmpty (..))
import           Data.Map                  (Map)
import           Data.Maybe                as X
import           Data.Text                 (Text)
import qualified Data.Text                 as Text
import           Data.Text.Prettyprint.Doc (Pretty)
import           Data.Traversable          (for)
import           Data.Typeable             (Typeable)
import           GHC.Conc                  (atomically, newTVarIO, readTVar, readTVarIO, writeTVar)
import           GHC.Generics              (Generic)
import           Lens.Micro                ((^..))
import           Prelude                   as X hiding (FilePath)
import           Safe                      (headMay)
import           System.FilePath           (isAbsolute, pathSeparator, (</>))
import           System.IO                 (hPutStrLn)
import           Turtle                    (ExitCode (..), FilePath, appendonly, mktree, repr,
                                            shell, shellStrict, systemStrictWithErr, testdir,
                                            testfile)
import qualified Turtle                    as Turtle
import           UnliftIO                  (MonadUnliftIO)
import           UnliftIO.Directory        (makeAbsolute)
import           UnliftIO.Process          (callProcess)

-- | Generic Error that we throw on program exit.
--   We have it so that errors are displayed nicely to the user
--   (the default Turtle.die is not nice)
newtype SpagoError = SpagoError { _unError :: Text }
instance Exception SpagoError
instance Show SpagoError where
  show (SpagoError err) = Text.unpack err


data GlobalOptions = GlobalOptions
  { debug :: Bool
  }

type Spago m =
  ( MonadReader GlobalOptions m
  , MonadIO m
  , MonadUnliftIO m
  , MonadCatch m
  )

echo :: MonadIO m => Text -> m ()
echo = Turtle.printf (Turtle.s Turtle.% "\n")

echoStr :: MonadIO m => String -> m ()
echoStr = echo . Text.pack

echoDebug :: Spago m => Text -> m ()
echoDebug str = do
  hasDebug <- asks debug
  Turtle.when hasDebug $ do
    echo str

die :: MonadThrow m => Text -> m a
die reason = throwM $ SpagoError reason

-- | Throw Lefts
throws :: MonadThrow m => Exception e => Either e a -> m a
throws (Left  e) = throwM e
throws (Right a) = pure a

-- | Suppress the 'Left' value of an 'Either'
hush :: Either a b -> Maybe b
hush = either (const Nothing) Just

-- | Manage a directory tree as a resource, deleting it if we except during the @action@
--   NOTE: you should make sure the directory doesn't exist before calling this.
withDirectory :: Turtle.FilePath -> IO a -> IO a
withDirectory dir action = (Turtle.mktree dir >> action) `onException` (Turtle.rmtree dir)


pathFromText :: Text -> Turtle.FilePath
pathFromText = Turtle.fromText


readTextFile :: MonadIO m => Turtle.FilePath -> m Text
readTextFile = liftIO . Turtle.readTextFile


writeTextFile :: MonadIO m => Turtle.FilePath -> Text -> m ()
writeTextFile path text = liftIO $ Turtle.writeTextFile path text


with :: MonadIO m => Turtle.Managed a -> (a -> IO r) -> m r
with r f = liftIO $ Turtle.with r f


viewShell :: (MonadIO m, Show a) => Turtle.Shell a -> m ()
viewShell = Turtle.view
