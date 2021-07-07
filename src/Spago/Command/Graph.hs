module Spago.Command.Graph where

import Spago.Prelude
import Spago.Env

import qualified Data.Set as Set
import qualified Data.Map as Map
import qualified Data.Text as Text
import qualified System.FilePath.Glob as Glob
import qualified System.IO as Sys

import qualified Spago.Packages as Packages


graphNotSupportedError :: IsString p => p
graphNotSupportedError = "`spago graph` only works on PureScript v0.14.0 or higher. Please upgrade your compiler"

graphModules :: HasBuildEnv env => JsonFlag -> RIO env ()
graphModules json = do
  logDebug "Running `spago graph modules`"
  view (the @Graph) >>= \case
    Nothing -> logError graphNotSupportedError
    Just (ModuleGraph moduleGraph) -> output $ case json of
      JsonOutputNo -> modulesToDot moduleGraph
      JsonOutputYes -> jsonToTextPretty moduleGraph

graphPackages :: HasBuildEnv env => JsonFlag -> RIO env ()
graphPackages json = do
  logDebug "Running `spago graph packages`"
  maybeGraph <- view (the @Graph)
  case maybeGraph of
    Nothing -> logError graphNotSupportedError
    Just (ModuleGraph moduleGraph) -> do
      BuildOptions{ depsOnly } <- view (the @BuildOptions)
      Config{ name, configSourcePaths } <- view (the @Config)
      PackageSet { packagesDB } <- view (the @PackageSet)
      deps <- Packages.getProjectDeps
      let Packages.Globs{..} = Packages.getGlobs deps depsOnly configSourcePaths
      let
        matchesGlob :: Sys.FilePath -> SourcePath -> Bool
        matchesGlob path sourcePath =
          Glob.match (Glob.compile (Text.unpack (unSourcePath sourcePath))) path

        getPackageFromPath :: Text -> PackageName
        getPackageFromPath path =
          let maybeDependency = fmap fst
                $ find (\(_, sourcePath) -> matchesGlob (Text.unpack path) sourcePath)
                $ Map.toList depsGlobs
          in case maybeDependency of
            -- if we didn't match a dependency path, then it must come from our project
            Nothing -> PackageName name
            Just dep -> dep

        -- We first build a mapping from ModuleName to PackageName, so we can look it up easily
        moduleToPackageMap :: Map ModuleName PackageName
        moduleToPackageMap = Map.map (\ModuleGraphNode{ graphNodePath } -> getPackageFromPath graphNodePath) moduleGraph

        -- Then we take the module graph Map, and:
        -- * key becomes package
        -- * value.depends now contains packages
        moduleToMaybePackage :: (ModuleName, ModuleGraphNode) -> Maybe (Map PackageName PackageGraphNode)
        moduleToMaybePackage (moduleName, ModuleGraphNode{ graphNodeDepends }) = do
          pkgName <- Map.lookup moduleName moduleToPackageMap
          Package{ location } <- Map.lookup pkgName packagesDB
          pure $ Map.singleton pkgName $
            PackageGraphNode
              location
              $ Set.delete pkgName -- this is to remove self-loops
              $ Set.fromList
              $ mapMaybe (`Map.lookup` moduleToPackageMap)
              $ Set.toList graphNodeDepends

        -- ..while we fold all the singletons together merging their dependencies
        packageGraph
          = Map.delete (PackageName "psci-support")
          $ Map.unionsWith const
          $ mapMaybe moduleToMaybePackage
          $ Map.toList moduleGraph

      output $ case json of
        JsonOutputNo -> packagesToDot (PackageName name) packageGraph
        JsonOutputYes  -> jsonToTextPretty packageGraph

data PackageGraphNode = PackageGraphNode
  { pkgNodeLocation :: !PackageLocation
  , pkgNodeDepends :: !(Set PackageName)
  }
  deriving (Eq)

instance ToJSON PackageGraphNode where
  toJSON PackageGraphNode{..} = object
    [ "depends" .= pkgNodeDepends
    , "location" .= pkgNodeLocation
    ]

packagesToDot :: PackageName -> Map PackageName PackageGraphNode -> Text
packagesToDot (PackageName currentPackage) packageGraph
  = "strict digraph deps {\n"
  <> tshow currentPackage <> " [style=dashed];\n"
  <> Map.foldMapWithKey nodeToDot packageGraph
  <> "}\n"
  where
    nodeToDot :: PackageName -> PackageGraphNode -> Text
    nodeToDot (PackageName pkg) PackageGraphNode{..}
      = foldMap (\(PackageName dep) -> tshow pkg <> " -> " <> tshow dep <> ";\n") pkgNodeDepends

modulesToDot :: Map ModuleName ModuleGraphNode -> Text
modulesToDot moduleGraph
  = "strict digraph modules {\n"
  <> Map.foldMapWithKey nodeToDot moduleGraph
  <> "}\n"
  where
    nodeToDot :: ModuleName -> ModuleGraphNode -> Text
    nodeToDot (ModuleName m) ModuleGraphNode{ graphNodeDepends }
      = foldMap (\(ModuleName dep) -> tshow m <> " -> " <> tshow dep <> ";\n") graphNodeDepends