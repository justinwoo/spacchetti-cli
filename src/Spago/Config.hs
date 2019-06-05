module Spago.Config
  ( makeConfig
  , ensureConfig
  , addDependencies
  , Config(..)
  ) where

import           Spago.Prelude

import qualified Data.Map           as Map
import qualified Data.Sequence      as Seq
import qualified Data.Set           as Set
import qualified Data.Text          as Text
import qualified Data.Text.Encoding as Text
import qualified Data.Versions      as Version
import qualified Dhall.Core
import qualified Dhall.Map
import qualified Dhall.TypeCheck

import qualified Spago.Dhall        as Dhall
import qualified Spago.Messages     as Messages
import qualified Spago.PackageSet   as PackageSet
import qualified Spago.PscPackage   as PscPackage
import qualified Spago.Templates    as Templates

import           Spago.PackageSet   (Package, PackageName, PackageSet)


pathText :: Text
pathText = "spago.dhall"

-- | Path for the Spago Config
path :: FilePath
path = pathFromText pathText


-- | Spago configuration file type
data Config = Config
  { name         :: Text
  , dependencies :: [PackageName]
  , packageSet   :: PackageSet
  } deriving (Show, Generic)

type Expr = Dhall.DhallExpr Dhall.Import

-- | Tries to read in a Spago Config
parseConfig :: Spago m => m Config
parseConfig = do
  expr <- liftIO $ Dhall.inputExpr $ "./" <> pathText
  case expr of
    Dhall.RecordLit ks -> do
      maybeConfig <- pure $ do
        let packageTyp      = Dhall.genericAuto :: Dhall.Type Package
            packageNamesTyp = Dhall.list (Dhall.auto :: Dhall.Type PackageName)
        name         <- Dhall.requireTypedKey ks "name" Dhall.strictText
        dependencies <- Dhall.requireTypedKey ks "dependencies" packageNamesTyp
        packages     <- Dhall.requireKey ks "packages" $ \case
          Dhall.RecordLit pkgs -> (Map.mapKeys PackageSet.PackageName . Dhall.Map.toMap)
            <$> traverse (Dhall.coerceToType packageTyp) pkgs
          something -> Left $ Dhall.PackagesIsNotRecord something

        let metadataPackageName = PackageSet.PackageName "metadata"
            (metadataMap, packagesDB) = Map.partitionWithKey (\k _v -> k == metadataPackageName) packages
            packagesMinPursVersion = join
              $ fmap (hush . Version.semver . (Text.replace "v" "") . PackageSet.version)
              $ Map.lookup metadataPackageName metadataMap
            packageSet = PackageSet.PackageSet{..}

        Right $ Config{..}

      case maybeConfig of
        Right config -> pure config
        Left err     -> throwM err
    _ -> case Dhall.TypeCheck.typeOf expr of
      Right e  -> throwM $ Dhall.ConfigIsNotRecord e
      Left err -> throwM $ err


-- | Checks that the Spago config is there and readable
ensureConfig :: Spago m => m Config
ensureConfig = do
  exists <- testfile path
  unless exists $ do
    die $ Messages.cannotFindConfig
  try parseConfig >>= \case
    Right config -> do
      PackageSet.ensureFrozen
      pure config
    Left (err :: Dhall.ReadError Dhall.TypeCheck.X) -> throwM err


-- | Copies over `spago.dhall` to set up a Spago project.
--   Eventually ports an existing `psc-package.json` to the new config.
makeConfig :: Spago m => Bool -> m ()
makeConfig force = do
  unless force $ do
    hasSpagoDhall <- testfile path
    when hasSpagoDhall $ die $ Messages.foundExistingProject pathText
  writeTextFile path Templates.spagoDhall
  Dhall.format pathText

  -- We try to find an existing psc-package config, and we migrate the existing
  -- content if we found one, otherwise we copy the default template
  pscfileExists <- testfile PscPackage.configPath
  when pscfileExists $ do
    -- first, read the psc-package file content
    content <- readTextFile PscPackage.configPath
    case eitherDecodeStrict $ Text.encodeUtf8 content of
      Left err -> echo $ Messages.failedToReadPscFile err
      Right pscConfig -> do
        echo "Found a \"psc-package.json\" file, migrating to a new Spago config.."
        -- try to update the dependencies (will fail if not found in package set)
        let pscPackages = map PackageSet.PackageName $ PscPackage.depends pscConfig
        config <- ensureConfig
        withConfigAST (\e -> addRawDeps config pscPackages
                            $ updateName (PscPackage.name pscConfig) e)


updateName :: Text -> Expr -> Expr
updateName newName (Dhall.RecordLit kvs)
  | Just _name <- Dhall.Map.lookup "name" kvs = Dhall.RecordLit
    $ Dhall.Map.insert "name" (Dhall.toTextLit newName) kvs
updateName _ other = other

addRawDeps :: Spago m => Config -> [PackageName] -> Expr -> m Expr
addRawDeps config newPackages r@(Dhall.RecordLit kvs)
  | Just (Dhall.ListLit Nothing dependencies) <- Dhall.Map.lookup "dependencies" kvs = do
      case notInPackageSet of
        -- If none of the newPackages are outside of the set, add them to existing dependencies
        [] -> do
          oldPackages <- traverse (throws . Dhall.fromTextLit) dependencies
          let newDepsExpr
                = Dhall.ListLit Nothing $ fmap (Dhall.toTextLit . PackageSet.packageName)
                $ Seq.sort $ nubSeq (Seq.fromList newPackages <> fmap PackageSet.PackageName oldPackages)
          pure $ Dhall.RecordLit $ Dhall.Map.insert "dependencies" newDepsExpr kvs
        pkgs -> do
          echo $ Messages.failedToAddDeps $ map PackageSet.packageName pkgs
          pure r
  where
    notInPackageSet = mapMaybe
      (\p -> case Map.lookup p (PackageSet.packagesDB $ packageSet config) of
               Just _  -> Nothing
               Nothing -> Just p)
      newPackages

    -- | Code from https://stackoverflow.com/questions/45757839
    nubSeq :: Ord a => Seq a -> Seq a
    nubSeq xs = (fmap fst . Seq.filter (uncurry notElem)) (Seq.zip xs seens)
      where
        seens = Seq.scanl (flip Set.insert) Set.empty xs
addRawDeps _ _ other = pure other


-- | Takes a function that manipulates the Dhall AST of the Config, and tries to run it
--   on the current config. If it succeeds, it writes back to file the result returned.
--   Note: it will pass in the parsed AST, not the resolved one (so e.g. imports will
--   still be in the tree). If you need the resolved one, use `ensureConfig`.
withConfigAST :: Spago m => (Expr -> m Expr) -> m ()
withConfigAST transform = do
  rawConfig <- liftIO $ Dhall.readRawExpr pathText
  case rawConfig of
    Nothing -> die Messages.cannotFindConfig
    Just (header, expr) -> do
      newExpr <- transformMExpr transform expr
      liftIO $ Dhall.writeRawExpr pathText (header, newExpr)
  where
    transformMExpr
      :: Spago m
      => (Dhall.Expr s Dhall.Import -> m (Dhall.Expr s Dhall.Import))
      -> Dhall.Expr s Dhall.Import
      -> m (Dhall.Expr s Dhall.Import)
    transformMExpr rules =
      transformMOf
        Dhall.subExpressions
        rules
      . Dhall.Core.denote


-- | Try to add the `newPackages` to the "dependencies" list in the Config.
--   It will not add any dependency if any of them is not in the package set.
--   If everything is fine instead, it will add the new deps, sort all the
--   dependencies, and write the Config back to file.
addDependencies :: Spago m => Config -> [PackageName] -> m ()
addDependencies config newPackages = do
  withConfigAST $ addRawDeps config newPackages
