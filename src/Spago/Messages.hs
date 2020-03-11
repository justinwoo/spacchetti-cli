module Spago.Messages where

import           Spago.Prelude

import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Text          as Text

failedToParseLocalRepo :: Text -> Text
failedToParseLocalRepo spagoConfigPath = makeMessage
  [ "ERROR: when importing local packages you should point to their `spago.dhall` file."
  , "However, the following local package points to: " <> surroundQuote spagoConfigPath
  ]

cannotFindConfigLocalPackage :: Text -> Text
cannotFindConfigLocalPackage spagoConfigPath
  = "ERROR: it was not possible to find a `spago.dhall` file at the following location: "
  <> surroundQuote spagoConfigPath

failedToParsePackage :: Text -> Text
failedToParsePackage expr = makeMessage
  [ "ERROR: could not read a Package configuration."
  , "For remote packages, this is the expected type of the Package configuration:"
  , ""
  , "{ repo : Text, version : Text, dependencies : List Text }"
  , ""
  , "For local packages, this is how you should import them:"
  , ""
  , "./path/to/some/local/package/spago.dhall as Location"
  , ""
  , "..but your package declaration didn't match any of them, and was the following expression instead:"
  , ""
  , expr
  ]

failedToParseRepoString :: Text -> Text
failedToParseRepoString repo = makeMessage
  [ "ERROR: was not able to parse the address to the remote repo: " <> surroundQuote repo
  , ""
  , "This might be for one of the following reasons:"
  , ""
  , "- you're including a local path as a 'repo address', but that's not supported anymore, and you should switch to the new syntax for importing local packages, e.g.:"
  , ""
  , "  let overrides = { some-package = ./some/local/path/spago.dhall as Location }"
  , ""
  , "- you're trying to use a URL which doesn't conform to RFC 3986, e.g. in the form of `git@foo.com:bar/baz.git`."
  , "  The above example can be rewritten in a valid form as \"ssh://git@foo.com/bar/baz.git\""
  , ""
  ]

cannotFindConfig :: Text
cannotFindConfig = makeMessage
  [ "There's no " <> surroundQuote "spago.dhall" <> " in your current location."
  , ""
  , "If you already have a spago project you might be in the wrong subdirectory,"
  , "otherwise you might want to run `spago init` to initialize a new project."
  ]

cannotFindPackages :: Text
cannotFindPackages = makeMessage
  [ "There's no " <> surroundQuote "packages.dhall" <> " in your current location."
  , ""
  , "If you already have a spago project you might be in the wrong subdirectory,"
  , "otherwise you might want to run `spago init` to initialize a new package set file."
  ]

foundExistingProject :: Text -> Text
foundExistingProject pathText = makeMessage
  [ "Found a " <> surroundQuote pathText <> " file, skipping copy. Run `spago init --force` if you wish to overwrite it."
  ]

foundExistingDirectory :: Text -> Text
foundExistingDirectory dir
  = "Found existing directory " <> surroundQuote dir <> ", skipping copy of sample sources"

foundExistingFile :: Text -> Text
foundExistingFile file
  = "Found existing file " <> surroundQuote file <> ", not overwriting it"

foundLocalPackage :: Text -> Text -> Text
foundLocalPackage package path
  = "Skipping package " <> surroundQuote package <> ", using local path: " <> surroundQuote path

failedToInstallDep :: Text -> Text -> Text
failedToInstallDep dep err = makeMessage
  [ ""
  , "Failed to install dependency " <> dep
  , "Git output:"
  , ""
  , err
  , ""
  , "Aborting installation.."
  ]

failedToReadFile :: Text -> Text
failedToReadFile file = makeMessage
  [ "Failed to read " <> surroundQuote file ]

failedToReadPscFile :: Show a => a -> Text
failedToReadPscFile err = makeMessage
  [ "WARNING: found a \"psc-package.json\" file, but was not"
  , "able to read it, skipping the automatic import.."
  , "This is the error we got:"
  , ""
  , tshow err
  , ""
  ]

failedToParseFile :: Show a => Text -> a -> Text
failedToParseFile file err = makeMessage
  [ "Error while trying to parse " <> surroundQuote file
  , "Details:"
  , ""
  , tshow err
  ]

failedToParseCommandOutput :: Text -> Text -> Text
failedToParseCommandOutput command outputText = makeMessage
  [ "Failed to parse '" <> command <> "' output: "
  , surroundQuote outputText
  ]

failedToReachGitHub :: Show a => a -> Text
failedToReachGitHub err = makeMessage
  [ "Could not reach GitHub. Error:"
  , ""
  , tshow err
  ]

failedToAddDeps :: NonEmpty Text -> Text
failedToAddDeps pkgs = makeMessage $
  [ "Some of the dependencies you tried to add were not found in the package-set."
  , "Not adding any new dependencies to your new spago config."
  , "We didn't find:"
  ]
  <> map ("- " <>) (NonEmpty.toList pkgs)
  <> [""]

upgradingPackageSet :: Text -> Text
upgradingPackageSet newTag = makeMessage
  [ "Package-set upgraded to latest tag " <> surroundQuote newTag
  , "Fetching the new one and generating hashes.. (this might take some time)"
  ]

freezePackageSet :: Text
freezePackageSet = makeMessage
  [ "Generating new hashes for the package set file so it will be cached.. (this might take some time)"
  ]

failedToCheckPackageSetFrozen :: Text
failedToCheckPackageSetFrozen = makeMessage
  [ "WARNING: wasn't able to check if your package set import is frozen"
  ]

failedToCopyToGlobalCache :: Show a => a -> Text
failedToCopyToGlobalCache err = makeMessage
  [ "WARNING: was not able to copy the download to the global cache."
  , "Most likely this comes from permissions not being right, so you could try setting the `XDG_CACHE_HOME` env variable (which determines where the global cache is) to a location which is writable by your user."
  , "Error was:"
  , tshow err
  ]

pursVersionMismatch :: Text -> Text -> Text
pursVersionMismatch currentVersion minVersion = makeMessage
  [ "Oh noes! It looks like the PureScript version installed on your system is not compatible with the package-set you're using."
  , ""
  , "installed `purs` version:    " <> currentVersion
  , "minimum package-set version: " <> minVersion
  , ""
  , "There are a few ways to solve this:"
  , "- install a compatible `purs` version (i.e. in the same 'semver range' as the one in the package set)"
  , "- if the `purs` version is 'too new', you can try using `spago upgrade-set` to upgrade to the latest package set"
  , "- if you know what you're doing and you want to avoid this check, you can override the `version` of the `metadata` package in the packages.dhall:"
  , ""
  , "  let overrides = { metadata = upstream.metadata // { version = \"v" <> currentVersion <> "\" } }"
  , ""
  ]

getNewGitHubToken :: Text
getNewGitHubToken = makeMessage
  [ "Please obtain a GitHub personal access token at:"
  , "  https://github.com/settings/tokens/new"
  , "No scopes are required, so don't check any of the boxes."
  , ""
  , "After you've done that, assign it to the " <> githubTokenEnvVar <> " environment variable,"
  , "and then call `spago login` again so Spago can pick it up and save it to cache"
  ]

couldNotVerifySet :: Text
couldNotVerifySet = "Could not find a valid \"spago.dhall\" or \"packages.dhall\""

verifying :: Show a => a -> Text
verifying len = "Verifying " <> tshow len <> " packages, this might take a while.."

bundleCommandRenamed :: Text
bundleCommandRenamed =
  "The `bundle` command has been replaced with `bundle-app`, so use that instead."

makeModuleCommandRenamed :: Text
makeModuleCommandRenamed =
  "The `make-module` command has been replaced with `bundle-module`, so use that instead."

listPackagesCommandRenamed :: Text
listPackagesCommandRenamed =
  "The `list-packages` command has been replaced with `ls packages`, so use that instead."

globsDoNotMatchWhenWatching :: NonEmpty Text -> Text
globsDoNotMatchWhenWatching patterns = makeMessage $
  "WARNING: No matches found when trying to watch the following directories: " : NonEmpty.toList patterns

noControllingTerminal :: Show a => a -> Text
noControllingTerminal err = makeMessage
  [ "WARNING: The file path for the controlling terminal could not be determined."
  , "Details:"
  , ""
  , tshow err
  , ""
  ]

makeMessage :: [Text] -> Text
makeMessage = Text.intercalate "\n"
