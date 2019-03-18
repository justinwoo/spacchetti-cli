module Spago.Build
  ( build
  , test
  , run
  , repl
  , bundle
  , makeModule
  , docs
  , Watch (..)
  , NoBuild (..)
  , Purs.ExtraArg (..)
  , Purs.ModuleName (..)
  , Purs.SourcePath (..)
  , Purs.TargetPath (..)
  , Purs.WithMain (..)
  ) where

import           Control.Exception    (SomeException, try)
import           Data.Maybe           (Maybe(..), fromMaybe)
import qualified Data.Set             as Set
import qualified Data.Text            as Text
import           System.Directory     (makeAbsolute)
import qualified System.FilePath.Glob as Glob
import           System.IO            (hPutStrLn)
import qualified Turtle               as T hiding (die, echo)

import qualified Spago.Config         as Config
import qualified Spago.Packages       as Packages
import qualified Spago.Purs           as Purs
import           Spago.Turtle
import           Spago.Watch          (watch)


data Watch = Watch | BuildOnce

-- | Flag to go through with the build step
--   or skip it, in the case of 'bundle' and 'makeModule'.
data NoBuild = NoBuild | DoBuild

defaultSourcePaths :: [Purs.SourcePath]
defaultSourcePaths =
  [ Purs.SourcePath "src/**/*.purs"
  , Purs.SourcePath "test/**/*.purs"
  ]

prepareBundleDefaults
  :: Maybe Purs.ModuleName
  -> Maybe Purs.TargetPath
  -> (Purs.ModuleName, Purs.TargetPath)
prepareBundleDefaults maybeModuleName maybeTargetPath = (moduleName, targetPath)
  where
    moduleName = fromMaybe (Purs.ModuleName "Main") maybeModuleName
    targetPath = fromMaybe (Purs.TargetPath "index.js") maybeTargetPath


-- | Build the project with purs, passing through
--   the additional args in the list
build :: Maybe Int -> Watch -> [Purs.SourcePath] -> [Purs.ExtraArg] -> IO ()
build maybeLimit shouldWatch sourcePaths passthroughArgs = do
  config <- Config.ensureConfig
  deps <- Packages.getProjectDeps config
  Packages.fetchPackages maybeLimit deps
  let projectGlobs = defaultSourcePaths <> sourcePaths
      allGlobs = Packages.getGlobs deps <> projectGlobs
      buildAction = Purs.compile allGlobs passthroughArgs
  absoluteProjectGlobs <- traverse makeAbsolute $ Text.unpack . Purs.unSourcePath <$> projectGlobs
  case shouldWatch of
    BuildOnce -> buildAction
    Watch     -> watch (Set.fromAscList $ fmap Glob.compile absoluteProjectGlobs) buildAction

-- | Start a repl
repl :: [Purs.SourcePath] -> [Purs.ExtraArg] -> IO ()
repl sourcePaths passthroughArgs = do
  config <- Config.ensureConfig
  deps <- Packages.getProjectDeps config
  let globs = Packages.getGlobs deps <> defaultSourcePaths <> sourcePaths
  Purs.repl globs passthroughArgs

-- | Test the project: compile and run "Test.Main"
--   (or the provided module name) with node
test :: Maybe Purs.ModuleName -> Maybe Int -> Watch -> [Purs.SourcePath] -> [Purs.ExtraArg] -> IO ()
test = runWithNode (Purs.ModuleName "Test.Main") (Just "Tests succeeded.") "Tests failed: "

-- | Run the project: compile and run "Main"
--   (or the provided module name) with node
run :: Maybe Purs.ModuleName -> Maybe Int -> Watch -> [Purs.SourcePath] -> [Purs.ExtraArg] -> IO ()
run = runWithNode (Purs.ModuleName "Main") Nothing "Running failed, exit code: "

-- | Run the project with node: compile and run with the provided ModuleName
--   (or the default one if that's missing)
runWithNode :: Purs.ModuleName
            -> Maybe T.Text
            -> T.Text
            -> Maybe Purs.ModuleName
            -> Maybe Int
            -> Watch
            -> [Purs.SourcePath]
            -> [Purs.ExtraArg]
            -> IO ()
runWithNode defaultModuleName maybeSuccessMessage failureMessage maybeModuleName
            maybeLimit shouldWatch paths passthroughArgs = do
  build maybeLimit shouldWatch paths passthroughArgs
  T.shell cmd T.empty >>= \case
    T.ExitSuccess   -> fromMaybe (pure ()) (echo <$> maybeSuccessMessage)
    T.ExitFailure n -> die $ failureMessage <> T.repr n
  where
    moduleName = fromMaybe defaultModuleName maybeModuleName
    cmd = "node -e \"require('./output/" <> Purs.unModuleName moduleName <> "').main()\""

  -- | Bundle the project to a js file
bundle :: Purs.WithMain -> Maybe Purs.ModuleName -> Maybe Purs.TargetPath -> NoBuild -> [Purs.SourcePath] -> [Purs.ExtraArg] -> IO ()
bundle withMain maybeModuleName maybeTargetPath noBuild paths passthroughArgs =
  let (moduleName, targetPath) = prepareBundleDefaults maybeModuleName maybeTargetPath
  in do
    case noBuild of
      DoBuild -> build Nothing BuildOnce paths passthroughArgs
      NoBuild -> pure ()
    Purs.bundle withMain moduleName targetPath

-- | Bundle into a CommonJS module
makeModule :: Maybe Purs.ModuleName -> Maybe Purs.TargetPath -> NoBuild -> [Purs.SourcePath] -> [Purs.ExtraArg] -> IO ()
makeModule maybeModuleName maybeTargetPath noBuild paths passthroughArgs = do
  let (moduleName, targetPath) = prepareBundleDefaults maybeModuleName maybeTargetPath
      jsExport = Text.unpack $ "\nmodule.exports = PS[\""<> Purs.unModuleName moduleName <> "\"];"
  echo "Bundling first..."
  bundle Purs.WithoutMain (Just moduleName) (Just targetPath) noBuild paths passthroughArgs
  -- Here we append the CommonJS export line at the end of the bundle
  try (T.with
        (T.appendonly $ T.fromText $ Purs.unTargetPath targetPath)
        ((flip hPutStrLn) jsExport))
    >>= \case
      Right _ -> echo $ "Make module succeeded and output file to " <> Purs.unTargetPath targetPath
      Left (n :: SomeException) -> die $ "Make module failed: " <> T.repr n

-- | Generate docs for the `sourcePaths`
docs :: [Purs.SourcePath] -> IO ()
docs sourcePaths = do
  config <- Config.ensureConfig
  deps <- Packages.getProjectDeps config
  echo "Generating documentation for the project. This might take a while.."
  Purs.docs $ defaultSourcePaths <> Packages.getGlobs deps <> sourcePaths
