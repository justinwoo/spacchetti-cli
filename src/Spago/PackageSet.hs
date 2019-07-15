module Spago.PackageSet
  ( upgradePackageSet
  , checkPursIsUpToDate
  , makePackageSetFile
  , freeze
  , ensureFrozen
  , path
  , pathText
  , PackageSet(..)
  , Package (..)
  , PackageName (..)
  , Repo (..)
  ) where

import           Spago.Prelude

import qualified Data.Text       as Text
import qualified Data.Versions   as Version
import qualified Dhall
import           Dhall.Binary    (defaultStandardVersion)
import qualified Dhall.Freeze
import qualified Dhall.Pretty
import qualified GitHub
import           Network.URI     (parseURI)

import qualified Spago.Dhall     as Dhall
import           Spago.Messages  as Messages
import qualified Spago.Purs      as Purs
import qualified Spago.Templates as Templates


newtype PackageName = PackageName { packageName :: Text }
  deriving (Show)
  deriving newtype (Eq, Ord, ToJSON, FromJSON, ToJSONKey, FromJSONKey, Dhall.Interpret)

-- | A package-set package.
--   Matches the packages definition in Package.dhall from package-sets
data Package = Package
  { dependencies :: ![PackageName] -- ^ list of dependency package names
  , repo         :: !Repo          -- ^ the remote git repository or the local path
  , version      :: !Text          -- ^ version string (also functions as a git ref)
  }
  deriving (Eq, Show, Generic)

instance ToJSON Package
instance FromJSON Package

data PackageSet = PackageSet
  { packagesDB             :: Map PackageName Package
  , packagesMinPursVersion :: Maybe Version.SemVer
  }
  deriving (Show, Generic)

-- | We consider a "Repo" a "box of source to include in the build"
--   This can have different nature:
data Repo
  = Local !Text    -- ^ A local path
  | Remote !Text   -- ^ The address of a remote git repository
  deriving (Eq, Show, Generic)

instance ToJSON Repo
instance FromJSON Repo

instance Dhall.Interpret Repo where
  autoWith _ = makeRepo <$> Dhall.strictText
    where
      -- We consider a "Remote" anything that `parseURI` thinks is a URI
      makeRepo repo = case parseURI $ Text.unpack repo of
        Just _uri -> Remote repo
        Nothing   -> Local repo


pathText :: Text
pathText = "packages.dhall"

path :: FilePath
path = pathFromText pathText


-- | Tries to create the `packages.dhall` file. Fails when the file already exists,
--   unless `--force` has been used.
makePackageSetFile :: Bool -> IO ()
makePackageSetFile force = do
  unless force $ do
    hasPackagesDhall <- testfile path
    when hasPackagesDhall $ echo $ Messages.foundExistingProject pathText
  writeTextFile path Templates.packagesDhall
  Dhall.format DoFormat pathText


-- | Tries to upgrade the Package-Sets release of the local package set.
--   It will:
--   - try to read the latest tag from GitHub
--   - try to read the current package-set file
--   - try to replace the git tag to which the package-set imports point to
--     (if they point to the Package-Sets repo. This can be eventually made GitHub generic)
--   - if all of this succeeds, it will regenerate the hashes and write to file
upgradePackageSet :: Spago m => m ()
upgradePackageSet = do
  echoDebug "Running `spago package-set-upgrade`"
  result <- liftIO $ GitHub.executeRequest' $ GitHub.latestReleaseR "purescript" "package-sets"
  case result of
    Left err -> echoDebug $ Messages.failedToReachGitHub err
    Right GitHub.Release{..} -> do
      let quotedTag = surroundQuote releaseTagName
      echoDebug $ "Found the most recent tag for \"purescript/package-sets\": " <> quotedTag
      rawPackageSet <- liftIO $ Dhall.readRawExpr pathText
      case rawPackageSet of
        Nothing -> die Messages.cannotFindPackages
        -- Skip the check if the tag is already the newest
        Just (_, expr)
          | (currentTag:_) <- (foldMap getCurrentTag expr)
          , currentTag == releaseTagName
            -> echo $ "Skipping package set version upgrade, already on latest version: " <> quotedTag
        Just (header, expr) -> do
          echo $ "Upgrading the package set version to " <> quotedTag
          let newExpr = fmap (upgradeImports releaseTagName) expr
          echo $ Messages.upgradingPackageSet releaseTagName
          liftIO $ Dhall.writeRawExpr DoFormat pathText (header, newExpr)
          -- If everything is fine, refreeze the imports
          freeze
  where
    getCurrentTag :: Dhall.Import -> [Text]
    getCurrentTag Dhall.Import
      { importHashed = Dhall.ImportHashed
        { importType = Dhall.Remote Dhall.URL
          -- Check if we're dealing with the right repo
          { authority = "github.com"
          , path = Dhall.File
            { file = "packages.dhall"
            , directory = Dhall.Directory
              { components = [ currentTag, "download", "releases", "package-sets", "purescript" ]}
            }
          , ..
          }
        , ..
        }
      , ..
      } = [currentTag]
    -- TODO: remove this branch in 1.0
    getCurrentTag Dhall.Import
      { importHashed = Dhall.ImportHashed
        { importType = Dhall.Remote Dhall.URL
          -- Check if we're dealing with the right repo
          { authority = "raw.githubusercontent.com"
          , path = Dhall.File
            { directory = Dhall.Directory
              { components = [ "src", currentTag, "package-sets", "purescript" ]}
            , ..
            }
          , ..
          }
        , ..
        }
      , ..
      } = [currentTag]
    getCurrentTag _ = []

    -- | Given an import and a new purescript/package-sets tag,
    --   upgrades the import to the tag and resets the hash
    upgradeImports :: Text -> Dhall.Import -> Dhall.Import
    upgradeImports newTag (Dhall.Import
      { importHashed = Dhall.ImportHashed
        { importType = Dhall.Remote Dhall.URL
          { authority = "github.com"
          , path = Dhall.File
            { file = "packages.dhall"
            , directory = Dhall.Directory
              { components = [ _currentTag, "download", "releases", "package-sets", "purescript" ]}
            , ..
            }
          , ..
          }
        , ..
        }
      , ..
      }) =
      let components = [ newTag, "download", "releases", "package-sets", "purescript" ]
          directory = Dhall.Directory{..}
          newPath = Dhall.File{ file = "packages.dhall", .. }
          authority = "github.com"
          importType = Dhall.Remote Dhall.URL { path = newPath, ..}
          newHash = Nothing -- Reset the hash here, as we'll refreeze
          importHashed = Dhall.ImportHashed { hash = newHash, ..}
      in Dhall.Import{..}
    -- TODO: remove this branch in 1.0
    upgradeImports newTag imp@(Dhall.Import
      { importHashed = Dhall.ImportHashed
        { importType = Dhall.Remote Dhall.URL
          -- Check if we're dealing with the right repo
          { authority = "raw.githubusercontent.com"
          , path = Dhall.File
            { file = "packages.dhall"
            , directory = Dhall.Directory
              { components = [ "src", _currentTag, ghRepo, ghOrg ]}
            , ..
            }
          , ..
          }
        , ..
        }
      , ..
      }) =
      let components = [ newTag, "download", "releases", "package-sets", "purescript" ]
          directory = Dhall.Directory{..}
          newPath = Dhall.File{ file = "packages.dhall", ..}
          authority = "github.com"
          importType = Dhall.Remote Dhall.URL { path = newPath, ..}
          newHash = Nothing -- Reset the hash here, as we'll refreeze
          importHashed = Dhall.ImportHashed { hash = newHash, ..}
          newImport = Dhall.Import{..}
      in case (ghOrg, ghRepo) of
        ("spacchetti", "spacchetti")   -> newImport
        ("purescript", "package-sets") -> newImport
        _                              -> imp
    upgradeImports _ imp = imp


checkPursIsUpToDate :: Spago m => Maybe Version.SemVer -> m ()
checkPursIsUpToDate packagesMinPursVersion = do
  echoDebug "Checking if `purs` is up to date"
  maybeCompilerVersion <- Purs.version
  case (maybeCompilerVersion, packagesMinPursVersion) of
    (Just compilerVersion, Just pursVersionFromPackageSet) -> performCheck compilerVersion pursVersionFromPackageSet
    other -> do
      echo "WARNING: unable to parse compiler and package set versions, not checking if `purs` is compatible with it.."
      echoDebug $ "Versions we got: " <> tshow other
  where
    -- | The check is successful only when the installed compiler is "slightly"
    --   greater (or equal of course) to the minimum version. E.g. fine cases are:
    --   - current is 0.12.2 and package-set is on 0.12.1
    --   - current is 1.4.3 and package-set is on 1.3.4
    --   Not fine cases are e.g.:
    --   - current is 0.1.2 and package-set is 0.2.3
    --   - current is 1.2.3 and package-set is 1.3.4
    --   - current is 1.2.3 and package-set is 0.2.3
    performCheck :: Spago m => Version.SemVer -> Version.SemVer -> m ()
    performCheck actualPursVersion minPursVersion = do
      let versionList semver = semver ^.. (Version.major <> Version.minor <> Version.patch)
      case (versionList actualPursVersion, versionList minPursVersion) of
        ([0, b, c], [0, y, z]) | b == y && c >= z -> pure ()
        ([a, b, _c], [x, y, _z]) | a /= 0 && a == x && b >= y -> pure ()
        _ -> die $ Messages.pursVersionMismatch
            (Version.prettySemVer actualPursVersion)
            (Version.prettySemVer minPursVersion)


isRemoteFrozen :: Dhall.Import -> [Bool]
isRemoteFrozen (Dhall.Import
  { importHashed = Dhall.ImportHashed
    { importType = Dhall.Remote _
    , ..
    }
  , ..
  })             = [isJust hash]
isRemoteFrozen _ = []


-- | Freeze the package set remote imports so they will be cached
freeze :: Spago m => m ()
freeze = do
  echo Messages.freezePackageSet
  liftIO $ do
    Dhall.Freeze.freeze (Just $ Text.unpack pathText) False Dhall.Pretty.ASCII defaultStandardVersion


-- | Freeze the file if any of the remote imports are not frozen
ensureFrozen :: Spago m => m ()
ensureFrozen = do
  echoDebug "Ensuring that the package set is frozen"
  rawPackageSet <- liftIO $ Dhall.readRawExpr pathText
  case rawPackageSet of
    Nothing -> echo "WARNING: wasn't able to check if your package set file is frozen"
    Just (_header, expr) -> do
      let areRemotesFrozen = foldMap isRemoteFrozen expr
      unless (and areRemotesFrozen) $ do
        freeze
