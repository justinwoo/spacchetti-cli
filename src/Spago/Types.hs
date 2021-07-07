{-# LANGUAGE DuplicateRecordFields #-}
module Spago.Types where

import           Spago.Prelude

import qualified Data.Text      as Text
import qualified Data.Versions  as Version
import qualified Network.URI    as URI
import qualified GHC.IO

import qualified Spago.Dhall as Dhall
import qualified Spago.Messages as Messages

newtype PackageName = PackageName { packageName :: Text }
  deriving (Show, Read, Data)
  deriving newtype (Eq, Ord, ToJSON, FromJSON, ToJSONKey, FromJSONKey, Dhall.FromDhall)

-- | A package-set package.
--   Matches the packages definition in Package.dhall from package-sets
data Package = Package
  { dependencies :: ![PackageName]   -- ^ list of dependency package names
  , location     :: !PackageLocation -- ^ info about where the package is located
  }
  deriving (Eq, Show, Generic)


data PackageLocation
  = Remote
      { repo    :: !Repo          -- ^ the remote git repository
      , version :: !Text          -- ^ version string (also functions as a git ref)
      }
  | Local
      { localPath :: !Text        -- ^ local path of the package
      }
  deriving (Eq, Show, Generic)


-- | This instance is to make `spago ls packages --json` work
instance ToJSON PackageLocation where
  toJSON Remote{..} = object
    [ "tag" .= ("Remote" :: Text)
    , "contents" .= unRepo repo
    ]
  toJSON Local{..} = object
    [ "tag" .= ("Local" :: Text)
    , "contents" .= localPath
    ]

data PackageSet = PackageSet
  { packagesDB             :: Map PackageName Package
  , packagesMinPursVersion :: Maybe Version.SemVer
  }
  deriving (Show, Generic)


-- | We consider a "Repo" a "box of source to include in the build"
--   This can have different nature:
newtype Repo = Repo { unRepo :: Text }
  deriving (Eq, Show, Generic)

instance ToJSON Repo

instance Dhall.FromDhall Repo where
  autoWith _ = makeRepo <$> Dhall.strictText
    where
      -- We consider a "Remote" anything that `parseURI` thinks is a URI
      makeRepo repo = case URI.parseURI $ Text.unpack repo of
        Just _uri -> Repo repo
        Nothing   -> error $ Text.unpack $ Messages.failedToParseRepoString repo


-- | Whether to force an action
data Force = Force | NoForce
  deriving (Eq)

data IncludeTransitive = IncludeTransitive | NoIncludeTransitive

newtype ModuleName = ModuleName { unModuleName :: Text }
  deriving newtype (Show, Eq, Ord, FromJSON, FromJSONKey, ToJSON, ToJSONKey)
newtype TargetPath = TargetPath { unTargetPath :: Text }
newtype SourcePath = SourcePath { unSourcePath :: Text }
  deriving newtype (Show, Dhall.FromDhall)
newtype PursArg = PursArg { unPursArg :: Text }
  deriving newtype (Eq, Show)
newtype BackendArg = BackendArg { unBackendArg :: Text }
  deriving newtype (Eq)

data WithMain = WithMain | WithoutMain

data WithSrcMap = WithSrcMap | WithoutSrcMap

data CacheFlag = SkipCache | NewCache
  deriving (Eq)

data CheckModulesUnique = DoCheckModulesUnique | NoCheckModulesUnique

data JsonFlag = JsonOutputNo | JsonOutputYes

-- | A flag to skip patching the docs using @purescript-docs-search@.
data NoSearch = NoSearch | AddSearch
  deriving (Eq)

-- | Flag to open generated HTML documentation in browser
data OpenDocs = NoOpenDocs | DoOpenDocs
  deriving (Eq)

-- | Flag to disable the automatic use of `psa`
data UsePsa = UsePsa | NoPsa

-- | The output path that can be obtained via `ls`
data PathType
  = PathOutput
  | PathGlobalCache

-- | Only build deps and ignore project paths
data DepsOnly = DepsOnly | AllSources
  deriving (Eq)

data Watch = Watch | BuildOnce

-- | Flag to go through with the build step
--   or skip it, in the case of 'bundleApp' and 'bundleModule'.
data NoBuild = NoBuild | DoBuild

-- | Flag to skip the automatic installation of libraries on build
data NoInstall = NoInstall | DoInstall
  deriving Eq

-- Should we clear the screen on rebuild?
data ClearScreen = DoClear | NoClear
  deriving Eq

-- | Flag to allow files ignored via `.gitignore` to trigger a rebuild
data AllowIgnored = DoAllowIgnored | NoAllowIgnored

data ShowVersion = DoShowVersion | NoShowVersion


data BuildOptions = BuildOptions
  { shouldWatch    :: Watch
  , shouldClear    :: ClearScreen
  , allowIgnored   :: AllowIgnored
  , sourcePaths    :: [SourcePath]
  , withSourceMap  :: WithSrcMap
  , noInstall      :: NoInstall
  , pursArgs       :: [PursArg]
  , depsOnly       :: DepsOnly
  , beforeCommands :: [Text]
  , thenCommands   :: [Text]
  , elseCommands   :: [Text]
  }

defaultBuildOptions :: BuildOptions
defaultBuildOptions = BuildOptions
  { shouldClear = NoClear
  , shouldWatch = BuildOnce
  , allowIgnored = DoAllowIgnored
  , sourcePaths = []
  , withSourceMap = WithoutSrcMap
  , noInstall = DoInstall
  , depsOnly = AllSources
  , pursArgs = []
  , beforeCommands = []
  , thenCommands = []
  , elseCommands = []
  }

fromScriptOptions :: BuildOptions -> ScriptBuildOptions -> BuildOptions
fromScriptOptions opts ScriptBuildOptions{..} = opts
  { pursArgs = pursArgs
  , beforeCommands = beforeCommands
  , thenCommands = thenCommands
  , elseCommands = elseCommands
  }

-- TODO: Figure out how `Watch` would work for `spago script` and include it
data ScriptBuildOptions = ScriptBuildOptions
  { pursArgs       :: [PursArg]
  , beforeCommands :: [Text]
  , thenCommands   :: [Text]
  , elseCommands   :: [Text]
  } deriving (Eq, Generic, Show)


-- | Spago configuration file type
data Config = Config
  { name              :: Text
  , dependencies      :: [PackageName]
  , packageSet        :: PackageSet
  , alternateBackend  :: Maybe Text
  , configSourcePaths :: [SourcePath]
  , publishConfig     :: Either (Dhall.ReadError Void) PublishConfig
  } deriving (Show, Generic)


-- | The extra fields that are only needed for publishing libraries.
data PublishConfig = PublishConfig
  { publishLicense    :: Text
  , publishRepository :: Text
  } deriving (Show, Generic)

data PursCmd = PursCmd
  { purs :: Text
  , psa :: Maybe Text
  , compilerVersion :: Version.SemVer
  } deriving (Generic)

newtype Jobs = Jobs Int
newtype ConfigPath = ConfigPath Text
newtype GitCmd = GitCmd Text
newtype BowerCmd = BowerCmd Text

data GlobalCache = GlobalCache !GHC.IO.FilePath !(Maybe CacheFlag)

newtype ModuleGraph = ModuleGraph { unModuleGraph :: Map ModuleName ModuleGraphNode }
  deriving newtype (FromJSON, ToJSON)

data ModuleGraphNode = ModuleGraphNode
  { graphNodePath :: Text
  , graphNodeDepends :: Set ModuleName
  } deriving (Generic, Show)

instance FromJSON ModuleGraphNode where
  parseJSON = withObject "ModuleGraphNode" $ \o ->
    ModuleGraphNode
      <$> o .: "path"
      <*> o .: "depends"

instance ToJSON ModuleGraphNode where
  toJSON ModuleGraphNode{..} = object
    [ "path" .= graphNodePath
    , "depends" .= graphNodeDepends
    ]

instance Semigroup ModuleGraphNode where
  a <> b = ModuleGraphNode (graphNodePath a) ( graphNodeDepends a <> graphNodeDepends b)

type Graph = Maybe ModuleGraph
