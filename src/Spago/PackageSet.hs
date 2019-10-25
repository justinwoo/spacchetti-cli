module Spago.PackageSet
  ( upgradePackageSet
  , checkPursIsUpToDate
  , makePackageSetFile
  , freeze
  , ensureFrozen
  , packagesPath
  , findRootOutputPath
  ) where

import           Spago.Prelude

import           Data.Ord        (comparing)
import qualified Data.Text       as Text
import qualified Data.Versions   as Version
import qualified Dhall.Freeze
import qualified Dhall.Pretty
import qualified Safe

import qualified Spago.Dhall     as Dhall
import qualified Spago.GitHub    as GitHub
import           Spago.Messages  as Messages
import qualified Spago.Purs      as Purs
import qualified Spago.Templates as Templates
import qualified System.FilePath
import qualified System.IO

packagesPath :: IsString t => t
packagesPath = "packages.dhall"


-- | Tries to create the `packages.dhall` file if needed
makePackageSetFile :: Spago m => Bool -> Dhall.TemplateComments -> m ()
makePackageSetFile force comments = do
  hasPackagesDhall <- testfile packagesPath
  if force || not hasPackagesDhall
    then writeTextFile packagesPath $ Dhall.processComments comments Templates.packagesDhall
    else echo $ Messages.foundExistingProject packagesPath
  Dhall.format packagesPath


-- | Tries to upgrade the Package-Sets release of the local package set.
--   It will:
--   - try to read the latest tag from GitHub
--   - try to read the current package-set file
--   - try to replace the git tag to which the package-set imports point to
--     (if they point to the Package-Sets repo. This can be eventually made GitHub generic)
--   - if all of this succeeds, it will regenerate the hashes and write to file
upgradePackageSet :: Spago m => m ()
upgradePackageSet = do
  echoDebug "Running `spago upgrade-set`"

  GitHub.getLatestPackageSetsTag >>= \case
    Right tag -> updateTag tag
    Left (err :: SomeException) -> do
      echo "WARNING: was not possible to upgrade the package-sets release"
      echoDebug $ "Error: " <> tshow err

  where
    updateTag :: Spago m => Text -> m ()
    updateTag releaseTagName =  do
      let quotedTag = surroundQuote releaseTagName
      echoDebug $ "Found the most recent tag for \"purescript/package-sets\": " <> quotedTag
      rawPackageSet <- liftIO $ Dhall.readRawExpr packagesPath
      case rawPackageSet of
        Nothing -> die Messages.cannotFindPackages
        -- Skip the check if the tag is already the newest
        Just (_, expr)
          | (currentTag:_) <- foldMap getCurrentTag expr
          , currentTag == releaseTagName
            -> echo $ "Skipping package set version upgrade, already on latest version: " <> quotedTag
        Just (header, expr) -> do
          echo $ "Upgrading the package set version to " <> quotedTag
          let newExpr = fmap (upgradeImports releaseTagName) expr
          echo $ Messages.upgradingPackageSet releaseTagName
          liftIO $ Dhall.writeRawExpr packagesPath (header, newExpr)
          -- If everything is fine, refreeze the imports
          freeze packagesPath

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
    , hash
    , ..
    }
  , ..
  })             = [isJust hash]
isRemoteFrozen _ = []


localImportPath :: Dhall.Import -> Maybe System.IO.FilePath
localImportPath (Dhall.Import
  { importHashed = Dhall.ImportHashed
    { importType = localImport@(Dhall.Local _ _)
    }
  })              = Just $ Text.unpack $ pretty localImport
localImportPath _ = Nothing


rootPackagePath :: Dhall.Import -> Maybe System.IO.FilePath
rootPackagePath (Dhall.Import
  { importHashed = Dhall.ImportHashed
    { importType = localImport@(Dhall.Local _ Dhall.File { file = "packages.dhall" })
    }
  , Dhall.importMode = Dhall.Code
  })              = Just $ Text.unpack $ pretty localImport
rootPackagePath _ = Nothing


-- | In a Monorepo we don't wish to rebuild our shared packages over and over,
-- | so we build into an output folder where our root packages.dhall lives
findRootOutputPath :: Spago m => System.IO.FilePath -> m (Maybe System.IO.FilePath)
findRootOutputPath path = do
  echoDebug "Locating root path of packages.dhall"
  imports <- liftIO $ Dhall.readImports $ Text.pack path
  let localImports = mapMaybe rootPackagePath imports
  pure $ flip System.FilePath.replaceFileName "output" <$> findRootPath localImports

-- | Given a list of filepaths, find the one with the least folders
findRootPath :: [System.IO.FilePath] -> Maybe System.IO.FilePath
findRootPath = Safe.minimumByMay (comparing (length . System.FilePath.splitSearchPath))

-- | Freeze the package set remote imports so they will be cached
freeze :: Spago m => System.IO.FilePath -> m ()
freeze path = do
  echo Messages.freezePackageSet
  liftIO $
    Dhall.Freeze.freeze
      (Dhall.InputFile path)
      Dhall.Freeze.OnlyRemoteImports
      Dhall.Freeze.Secure
      Dhall.Pretty.ASCII
      Dhall.NoCensor


-- | Freeze the file if any of the remote imports are not frozen
ensureFrozen :: Spago m => System.IO.FilePath -> m ()
ensureFrozen path = do
  echoDebug "Ensuring that the package set is frozen"
  imports <- liftIO $ Dhall.readImports $ Text.pack path
  let areRemotesFrozen = foldMap isRemoteFrozen imports
  case areRemotesFrozen of
    []      -> echo Messages.failedToCheckPackageSetFrozen
    remotes -> unless (and remotes) $
      traverse_ (maybe (pure ()) freeze . localImportPath) imports
