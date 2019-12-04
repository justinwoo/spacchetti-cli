{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE OverloadedLists #-}
module Spago.Config
  ( defaultPath
  , makeConfig
  , ensureConfig
  , addDependencies
  , parsePackage
  , Config(..)
  , PublishConfig(..)
  ) where

import           Spago.Prelude

import qualified Data.List             as List
import qualified Data.List.NonEmpty    as NonEmpty
import qualified Data.Map              as Map
import qualified Data.SemVer           as SemVer
import qualified Data.Sequence         as Seq
import qualified Data.Set              as Set
import qualified Data.Text             as Text
import qualified Data.Text.Encoding    as Text
import qualified Data.Versions         as Version
import qualified Dhall.Core
import qualified Dhall.Map
import qualified Dhall.TypeCheck
import qualified Web.Bower.PackageMeta as Bower

import qualified Spago.Dhall           as Dhall
import qualified Spago.Messages        as Messages
import qualified Spago.PackageSet      as PackageSet
import qualified Spago.PscPackage      as PscPackage
import qualified Spago.Purs            as Purs
import qualified Spago.Templates       as Templates

import           Spago.Types           as PackageSet

-- | Default path for the Spago Config
defaultPath :: IsString t => t
defaultPath = "spago.dhall"

-- | Spago configuration file type
data Config = Config
  { name              :: Text
  , dependencies      :: [PackageName]
  , packageSet        :: PackageSet
  , alternateBackend  :: Maybe Text
  , configSourcePaths :: [Purs.SourcePath]
  , publishConfig     :: Either (Dhall.ReadError Void) PublishConfig
  } deriving (Show, Generic)

-- | The extra fields that are only needed for publishing libraries.
data PublishConfig = PublishConfig
  { publishLicense    :: Text
  , publishRepository :: Text
  } deriving (Show, Generic)

type Expr = Dhall.DhallExpr Dhall.Import
type ResolvedExpr = Dhall.DhallExpr Void


isLocationType :: (Eq s, Eq a) => Dhall.Expr s a -> Bool
isLocationType (Dhall.Union kvs) | locationUnionMap == Dhall.Map.toMap kvs = True
  where
    locationUnionMap = Map.fromList
      [ ("Environment", Just Dhall.Text)
      , ("Remote", Just Dhall.Text)
      , ("Local", Just Dhall.Text)
      , ("Missing", Nothing)
      ]
isLocationType _ = False


dependenciesType :: Dhall.Type [PackageName]
dependenciesType = Dhall.list (Dhall.auto :: Dhall.Type PackageName)


parsePackage :: (MonadIO m, MonadThrow m, MonadReader env m, HasLogFunc env) => ResolvedExpr -> m Package
parsePackage (Dhall.RecordLit ks) = do
  repo         <- Dhall.requireTypedKey ks "repo" (Dhall.auto :: Dhall.Type PackageSet.Repo)
  version      <- Dhall.requireTypedKey ks "version" Dhall.strictText
  dependencies <- Dhall.requireTypedKey ks "dependencies" dependenciesType
  let location = PackageSet.Remote{..}
  pure PackageSet.Package{..}
parsePackage (Dhall.App (Dhall.Field union "Local") (Dhall.TextLit (Dhall.Chunks [] spagoConfigPath)))
  | isLocationType union = do
      localPath <- case Text.isSuffixOf "/spago.dhall" spagoConfigPath of
        True  -> pure $ Text.dropEnd 12 spagoConfigPath
        False -> die [ display $ Messages.failedToParseLocalRepo spagoConfigPath ]
      rawConfig <- liftIO $ Dhall.readRawExpr spagoConfigPath
      dependencies <- case rawConfig of
        Nothing -> die [ display $ Messages.cannotFindConfigLocalPackage spagoConfigPath ]
        Just (_header, expr) -> do
          newExpr <- transformMExpr (pure . filterDependencies . addSourcePaths) expr
          -- Note: we have to use inputWithSettings here because we're about to resolve
          -- the raw config from the local project. So if that has any imports they
          -- should be relative to the directory of that package
          liftIO $
            Dhall.inputWithSettings
              (set Dhall.rootDirectory (Text.unpack localPath) Dhall.defaultInputSettings)
              dependenciesType
              (pretty newExpr)
      let location = PackageSet.Local{..}
      pure PackageSet.Package{..}
parsePackage expr = die [ display $ Messages.failedToParsePackage $ pretty expr ]


-- | Tries to read in a Spago Config
parseConfig :: Spago Config
parseConfig = do
  -- Here we try to migrate any config that is not in the latest format
  withConfigAST $ pure . addSourcePaths

  path <- askEnv envConfigPath
  expr <- liftIO $ Dhall.inputExpr $
            if isAbsolute (Text.unpack path) then path else ("./" <> path)

  case expr of
    Dhall.RecordLit ks -> do
      packages :: Map PackageName Package <- Dhall.requireKey ks "packages" (\case
        Dhall.RecordLit pkgs ->
          fmap (Map.mapKeys PackageSet.PackageName . Dhall.Map.toMap)
          $ traverse parsePackage pkgs
        something -> throwM $ Dhall.PackagesIsNotRecord something)

      let sourcesType  = Dhall.list (Dhall.auto :: Dhall.Type Purs.SourcePath)
      name              <- Dhall.requireTypedKey ks "name" Dhall.strictText
      dependencies      <- Dhall.requireTypedKey ks "dependencies" dependenciesType
      configSourcePaths <- Dhall.requireTypedKey ks "sources" sourcesType
      alternateBackend  <- Dhall.maybeTypedKey ks "backend" Dhall.strictText

      let ensurePublishConfig = do
            publishLicense    <- Dhall.requireTypedKey ks "license" Dhall.strictText
            publishRepository <- Dhall.requireTypedKey ks "repository" Dhall.strictText
            pure PublishConfig{..}
      publishConfig <- try ensurePublishConfig

      let metadataPackageName = PackageSet.PackageName "metadata"
      let (metadataMap, packagesDB) = Map.partitionWithKey (\k _v -> k == metadataPackageName) packages
      let packagesMinPursVersion = join
            $ fmap (hush . Version.semver . Text.replace "v" "" . PackageSet.version . PackageSet.location)
            $ Map.lookup metadataPackageName metadataMap
      let packageSet = PackageSet.PackageSet{..}

      pure Config{..}
    _ -> case Dhall.TypeCheck.typeOf expr of
      Right e  -> throwM $ Dhall.ConfigIsNotRecord e
      Left err -> throwM err


-- | Checks that the Spago config is there and readable
ensureConfig :: Spago Config
ensureConfig = do
  path <- askEnv envConfigPath
  exists <- testfile path
  unless exists $ do
    die [ display $ Messages.cannotFindConfig path ]
  try parseConfig >>= \case
    Right config -> do
      PackageSet.ensureFrozen $ Text.unpack path
      pure config
    Left (err :: Dhall.ReadError Void) -> throwM err


-- | Copies over `spago.dhall` to set up a Spago project.
--   Eventually ports an existing `psc-package.json` to the new config.
makeConfig :: Bool -> Dhall.TemplateComments -> Spago ()
makeConfig force comments = do
  path <- askEnv envConfigPath
  unless force $ do
    hasSpagoDhall <- testfile path
    when hasSpagoDhall $ die [ display $ Messages.foundExistingProject path ]
  writeTextFile path $ Dhall.processComments comments Templates.spagoDhall
  Dhall.format path

  -- We try to find an existing psc-package or Bower config, and if
  -- we find any we migrate the existing content
  -- Otherwise we just keep the default template
  bowerFileExists <- testfile "bower.json"
  pscfileExists <- testfile PscPackage.configPath

  case (pscfileExists, bowerFileExists) of
    (True, _) -> do
      -- first, read the psc-package file content
      content <- readTextFile PscPackage.configPath
      case eitherDecodeStrict $ Text.encodeUtf8 content of
        Left err -> logWarn $ display $ Messages.failedToReadPscFile err
        Right pscConfig -> do
          logInfo "Found a \"psc-package.json\" file, migrating to a new Spago config.."
          -- try to update the dependencies (will fail if not found in package set)
          let pscPackages = map PackageSet.PackageName $ PscPackage.depends pscConfig
          config <- ensureConfig
          void $ withConfigAST (\e -> addRawDeps config pscPackages
                                      $ updateName (PscPackage.name pscConfig) e)
    (_, True) -> do
      -- read the bowerfile
      content <- readTextFile "bower.json"
      case eitherDecodeStrict $ Text.encodeUtf8 content of
        Left err -> die [ display $ Messages.failedToParseFile path err ]
        Right packageMeta -> do
          logInfo "Found a \"bower.json\" file, migrating to a new Spago config.."
          -- then try to update the dependencies. We'll migrates the ones that we can,
          -- and print a message to the user to fix the missing ones
          config@Config{..} <- ensureConfig

          let (bowerName, packageResults) = migrateBower packageMeta packageSet
              (bowerErrors, bowerPackages) = partitionEithers packageResults

          if null bowerErrors
            then do
              logInfo "All Bower dependencies are in the set! 🎉"
              logInfo $ "You can now safely delete your " <> surroundQuote "bower.json"
            else do
              logWarn $ display $ showBowerErrors bowerErrors

          void $ withConfigAST (\e -> addRawDeps config bowerPackages
                                      $ updateName bowerName e)

    _ -> pure ()


migrateBower :: Bower.PackageMeta -> PackageSet -> (Text, [Either BowerDependencyError PackageName])
migrateBower Bower.PackageMeta{..} PackageSet{..} = (packageName, dependencies)
  where
    dependencies = map migratePackage (bowerDependencies <> bowerDevDependencies)

    -- | For each Bower dependency, we:
    --   * try to parse the range into a SemVer.Range
    --   * then check if it's a purescript package
    --   * then try to search in the Package Set for that package
    --   * then try to match the version there into the Bower range
    migratePackage :: (Bower.PackageName, Bower.VersionRange) -> Either BowerDependencyError PackageName
    migratePackage (Bower.runPackageName -> name, Bower.VersionRange unparsedRange) =
      case SemVer.parseSemVerRange unparsedRange of
        Left _err -> Left $ UnparsableRange (PackageName name) unparsedRange
        Right range -> case Text.stripPrefix "purescript-" name of
          Nothing -> Left $ NonPureScript name
          Just packageSetName | package <- PackageName packageSetName -> case Map.lookup package packagesDB of
            Nothing -> Left $ MissingFromTheSet package
            Just Package{ location = Local {..} } -> Right package
            Just Package{ location = Remote {..} } -> case SemVer.parseSemVer version of
              Right v | SemVer.matches range v -> Right package
              _                                -> Left $ WrongVersion package range version

    packageName =
      let name = Bower.runPackageName bowerName
      in case Text.isPrefixOf "purescript-" name of
        True  -> Text.drop 11 name
        False -> name

data BowerDependencyError
  = UnparsableRange PackageName Text
  | NonPureScript Text
  | MissingFromTheSet PackageName
  | WrongVersion PackageName SemVer.SemVerRange Text
  deriving (Eq, Ord)


showBowerErrors :: [BowerDependencyError] -> Text
showBowerErrors (List.sort -> errors)
  = "\n\nSpago encountered some errors while trying to migrate your Bower config.\n"
  <> "A Spago config has been generated but it's recommended that you apply the suggestions here\n\n"
  <> (Text.unlines $ map (\errorGroup ->
      (case List.head errorGroup of
         UnparsableRange _ _ -> "It was not possible to parse the version range for these packages:"
         NonPureScript _ -> "These packages are not PureScript packages, so you should install them with `npm` instead:"
         MissingFromTheSet _ -> "These packages are missing from the package set. You should add them in your local package set:\n(See here for how: https://github.com/spacchetti/spago#add-a-package-to-the-package-set)"
         WrongVersion _ _ _ -> "These packages are in the set, but did not match the Bower range. You can try to install them with `spago install some-package-name`")
      <> "\n"
      <> Text.unlines (map (("* " <>) . showE) errorGroup)) (List.groupBy groupFn errors))
  where
    groupFn (UnparsableRange _ _) (UnparsableRange _ _) = True
    groupFn (NonPureScript _) (NonPureScript _)         = True
    groupFn (MissingFromTheSet _) (MissingFromTheSet _) = True
    groupFn (WrongVersion _ _ _) (WrongVersion _ _ _)   = True
    groupFn _ _                                         = False

    showE (UnparsableRange (PackageName name) range) = surroundQuote name <> " had range " <> surroundQuote range
    showE (NonPureScript name) = surroundQuote name
    showE (MissingFromTheSet (PackageName name)) = surroundQuote name
    showE (WrongVersion (PackageName name) range version) = surroundQuote name <> " has version " <> version <> ", but range is " <> tshow range


updateName :: Text -> Expr -> Expr
updateName newName (Dhall.RecordLit kvs)
  | Just _name <- Dhall.Map.lookup "name" kvs = Dhall.RecordLit
    $ Dhall.Map.insert "name" (Dhall.toTextLit newName) kvs
updateName _ other = other

addRawDeps :: Config -> [PackageName] -> Expr -> Spago Expr
addRawDeps config newPackages r@(Dhall.RecordLit kvs) = case Dhall.Map.lookup "dependencies" kvs of
  Just (Dhall.ListLit _ dependencies) -> do
      case NonEmpty.nonEmpty notInPackageSet of
        -- If none of the newPackages are outside of the set, add them to existing dependencies
        Nothing -> do
          oldPackages <- traverse (throws . Dhall.fromTextLit) dependencies
          let newDepsExpr
                = Dhall.ListLit Nothing $ fmap (Dhall.toTextLit . PackageSet.packageName)
                $ Seq.sort $ nubSeq (Seq.fromList newPackages <> fmap PackageSet.PackageName oldPackages)
          pure $ Dhall.RecordLit $ Dhall.Map.insert "dependencies" newDepsExpr kvs
        Just pkgs -> do
          logWarn $ display $ Messages.failedToAddDeps $ NonEmpty.map PackageSet.packageName pkgs
          pure r
    where
      packagesDB = PackageSet.packagesDB $ packageSet config
      notInPackageSet = filter (\p -> Map.notMember p packagesDB) newPackages

      -- | Code from https://stackoverflow.com/questions/45757839
      nubSeq :: Ord a => Seq a -> Seq a
      nubSeq xs = (fmap fst . Seq.filter (uncurry notElem)) (Seq.zip xs seens)
        where
          seens = Seq.scanl (flip Set.insert) Set.empty xs
  Just _ -> do
    logWarn "Failed to add dependencies. The `dependencies` field wasn't a List of Strings."
    pure r
  Nothing -> do
    logWarn "Failed to add dependencies. You should have a record with the `dependencies` key for this to work."
    pure r
addRawDeps _ _ other = pure other

addSourcePaths :: Expr -> Expr
addSourcePaths (Dhall.RecordLit kvs)
  | isConfigV1 kvs = Dhall.RecordLit
    $ Dhall.Map.insert "sources" (Dhall.ListLit Nothing $ fmap Dhall.toTextLit $ Seq.fromList ["src/**/*.purs", "test/**/*.purs"]) kvs
addSourcePaths expr = expr

isConfigV1, isConfigV2 :: Dhall.Map.Map Text v -> Bool
isConfigV1 (Set.fromList . Dhall.Map.keys -> configKeySet) =
  let configV1Keys = ["name", "dependencies", "packages"]
  in configKeySet == configV1Keys


isConfigV2 (Set.fromList . Dhall.Map.keys -> configKeySet) =
  let configV2Keys = ["name", "dependencies", "packages", "sources"]
      optionalKeys = ["backend", "license", "repository"]
  in Set.difference configKeySet optionalKeys == configV2Keys


filterDependencies :: Expr -> Expr
filterDependencies (Dhall.RecordLit kvs)
  | isConfigV2 kvs, Just deps <- Dhall.Map.lookup "dependencies" kvs = deps
filterDependencies expr = expr


-- | Takes a function that manipulates the Dhall AST of the Config, and tries to run it
--   on the current config. If it succeeds, it writes back to file the result returned.
--   Note: it will pass in the parsed AST, not the resolved one (so e.g. imports will
--   still be in the tree). If you need the resolved one, use `ensureConfig`.
withConfigAST :: (Expr -> Spago Expr) -> Spago Bool
withConfigAST transform = do
  path <- askEnv envConfigPath
  rawConfig <- liftIO $ Dhall.readRawExpr path
  case rawConfig of
    Nothing -> die [ display $ Messages.cannotFindConfig path ]
    Just (header, expr) -> do
      newExpr <- transformMExpr transform expr
      -- Write the new expression only if it has actually changed
      let exprHasChanged = Dhall.Core.denote expr /= newExpr
      if exprHasChanged
        then liftIO $ Dhall.writeRawExpr path (header, newExpr)
        else logDebug "Transformed config is the same as the read one, not overwriting it"
      pure exprHasChanged


transformMExpr
  :: MonadIO m
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
addDependencies :: Config -> [PackageName] -> Spago ()
addDependencies config newPackages = do
  configHasChanged <- withConfigAST $ addRawDeps config newPackages
  unless configHasChanged $
    logWarn "Configuration file was not updated."
