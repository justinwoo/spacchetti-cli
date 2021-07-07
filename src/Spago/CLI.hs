module Spago.CLI
  ( module Spago.CLI
  , CLI.options
  ) where

import Spago.Prelude
import Spago.Env

import qualified Data.Text           as Text
import qualified Options.Applicative as Opts
import qualified Turtle              as CLI

import qualified Spago.Purs          as Purs
import qualified Spago.Version

import Spago.Dhall (TemplateComments (..))
import Spago.DryRun (DryRun (..))
import Spago.Purs (DocsFormat(..))
import Spago.Version (VersionBump (..))


-- | Commands that this program handles
data Command

  -- | Default catch-all command
  = Default ShowVersion

  -- | Initialize a new project
  | Init Force TemplateComments (Maybe Text)

  -- | Install (download) dependencies defined in spago.dhall
  | Install [PackageName]

  -- | Get source globs of dependencies in spago.dhall
  | Sources

  -- | List available packages
  | ListPackages JsonFlag

  -- | List dependencies of the project
  | ListDeps JsonFlag IncludeTransitive

  -- | Bump and tag a new version in preparation for release.
  | BumpVersion DryRun VersionBump

  -- | Upgrade the package-set to the latest release
  | PackageSetUpgrade (Maybe Text)

  -- | Freeze the package-set so it will be cached
  | Freeze

  -- | Runs `purescript-docs-search search`.
  | Search

  -- | Returns info about paths used by Spago
  | Path (Maybe PathType) BuildOptions

  -- | Show version
  | Version

  -- ### Build commands - i.e. they all call Purs at some point

  -- | Produce a graph representation of all the Modules in the build
  | GraphModules JsonFlag

  -- | Produce a graph representation of all the Packages in the build
  | GraphPackages JsonFlag

    -- | Build the project
  | Build BuildOptions

  -- | Start a REPL
  | Repl [PackageName] [SourcePath] [PursArg] DepsOnly

  -- | Generate documentation for the project and its dependencies
  | Docs (Maybe DocsFormat) [SourcePath] DepsOnly NoSearch OpenDocs

  -- | Run the project with some module, default Main
  | Run (Maybe ModuleName) BuildOptions [BackendArg]

  -- | Run the selected module as a script, specifying a .purs file,
  -- | optional package set tag, dependencies
  | Script Text (Maybe Text) [PackageName] ScriptBuildOptions

  -- | Test the project with some module, default Test.Main
  | Test (Maybe ModuleName) BuildOptions [BackendArg]

  -- | Bundle the project into an executable
  | BundleApp (Maybe ModuleName) (Maybe TargetPath) NoBuild BuildOptions

  -- | Bundle a module into a CommonJS module
  | BundleModule (Maybe ModuleName) (Maybe TargetPath) NoBuild BuildOptions

  -- | Verify that a single package is consistent with the Package Set
  | Verify PackageName

  -- | Verify that the Package Set is correct
  | VerifySet CheckModulesUnique

  -- ### Legacy commands

  -- | Bundle the project into an executable (replaced by BundleApp)
  | Bundle

  -- | Bundle a module into a CommonJS module (replaced by BundleModule)
  | MakeModule

  -- | List available packages (deprecated, old version of ListPackages)
  | ListPackagesOld


parser :: CLI.Parser (Command, GlobalOptions)
parser = do
  opts <- globalOptions
  command
    <-  projectCommands
    <|> packagesCommands
    <|> packageSetCommands
    <|> publishCommands
    <|> otherCommands
    <|> oldCommands
    <|> ( Default <$> versionOpt )
  pure (command, opts)
  where
    cacheFlag =
      let wrap = \case
            "skip" -> Just SkipCache
            "update" -> Just NewCache
            _ -> Nothing
      in CLI.optional $ CLI.opt wrap "global-cache" 'c' "Configure the global caching behaviour: skip it with `skip` or force update with `update`"

    beforeCommands = many $ Opts.strOption (Opts.long "before" <> Opts.help "Commands to run before a build.")
    thenCommands = many $ Opts.strOption (Opts.long "then" <> Opts.help "Commands to run following a successful build.")
    elseCommands = many $ Opts.strOption (Opts.long "else" <> Opts.help "Commands to run following an unsuccessful build.")

    versionBump = CLI.arg Spago.Version.parseVersionBump "bump" "How to bump the version. Acceptable values: 'major', 'minor', 'patch', or a version (e.g. 'v1.2.3')."

    quiet       = CLI.switch "quiet" 'q' "Suppress all spago logging"
    verbose     = CLI.switch "verbose" 'v' "Enable additional debug logging, e.g. printing `purs` commands"
    veryVerbose = CLI.switch "very-verbose" 'V' "Enable more verbosity: timestamps and source locations"
    noColor     = Opts.switch (Opts.long "no-color" <> Opts.help "Log without ANSI color escape sequences")

    -- Note: the first constructor is the default when the flag is not provided
    force        = bool NoForce Force <$> CLI.switch "force" 'f' "Overwrite any project found in the current directory"
    watch        = bool BuildOnce Watch <$> CLI.switch "watch" 'w' "Watch for changes in local files and automatically rebuild"
    noInstall    = bool DoInstall NoInstall <$> CLI.switch "no-install" 'n' "Don't run the automatic installation of packages"
    depsOnly     = bool AllSources DepsOnly <$> Opts.switch (Opts.long "deps-only" <> Opts.help "Only use sources from dependencies, skipping the project sources.")
    noSearch     = bool AddSearch NoSearch <$> CLI.switch "no-search" 'S' "Do not make the documentation searchable"
    clearScreen  = bool NoClear DoClear <$> CLI.switch "clear-screen" 'l' "Clear the screen on rebuild (watch mode only)"
    allowIgnored = bool NoAllowIgnored DoAllowIgnored <$> CLI.switch "allow-ignored" 'I' "Allow files ignored via .gitignore to trigger rebuilds (watch mode only)"
    noBuild      = bool DoBuild NoBuild <$> CLI.switch "no-build" 's' "Skip build step"
    srcMapFlag   = bool WithoutSrcMap WithSrcMap <$> CLI.switch "source-maps" 'x' "Whether to generate source maps for the bundle"
    jsonFlag     = bool JsonOutputNo JsonOutputYes <$> CLI.switch "json" 'j' "Produce JSON output"
    dryRun       = bool DryRun NoDryRun <$> CLI.switch "no-dry-run" 'f' "Actually perform side-effects (the default is to describe what would be done)"
    usePsa       = bool UsePsa NoPsa <$> CLI.switch "no-psa" 'P' "Don't build with `psa`, but use `purs`"
    openDocs     = bool NoOpenDocs DoOpenDocs <$> CLI.switch "open" 'o' "Open generated documentation in browser (for HTML format only)"
    noComments   = bool WithComments NoComments <$> CLI.switch "no-comments" 'C' "Generate package.dhall and spago.dhall files without tutorial comments"
    tag          = CLI.optional $ Opts.strOption (Opts.long "tag" <> Opts.help "Optional package set tag to be used instead of the latest one.")
    configPath   = CLI.optional $ CLI.optText "config" 'x' "Optional config path to be used instead of the default spago.dhall"
    chkModsUniq  = bool DoCheckModulesUnique NoCheckModulesUnique <$> CLI.switch "no-check-modules-unique" 'M' "Skip checking whether modules names are unique across all packages."
    transitive   = bool NoIncludeTransitive IncludeTransitive <$> CLI.switch "transitive" 't' "Include transitive dependencies"

    mainModule  = CLI.optional $ CLI.opt (Just . ModuleName) "main" 'm' "Module to be used as the application's entry point"
    toTarget    = CLI.optional $ CLI.opt (Just . TargetPath) "to" 't' "The target file path"
    docsFormat  = CLI.optional $ CLI.opt Purs.parseDocsFormat "format" 'f' "Docs output format (markdown | html | etags | ctags)"
    jobsLimit   = CLI.optional (CLI.optInt "jobs" 'j' "Limit the amount of jobs that can run concurrently")
    nodeArgs         = many $ CLI.opt (Just . BackendArg) "node-args" 'a' "Argument to pass to node (run/test only)"
    backendArgs      = many $ CLI.opt (Just . BackendArg) "exec-args" 'b' "Argument to pass to the backend (run/test only)"
    dependencyPackageNames = many $ CLI.opt (Just . PackageName) "dependency" 'd' "Package name to add as a dependency"
    scriptSource = CLI.arg Just "source" "Source file to run as script"
    sourcePaths      = many $ CLI.opt (Just . SourcePath) "path" 'p' "Source path to include (in addition to paths in spago.dhall)"

    packageName     = CLI.arg (Just . PackageName) "package" "Specify a package name. You can list them with `ls packages`"
    packageNames    = many $ CLI.arg (Just . PackageName) "package" "Package name to add as dependency"
    pursArgs        = many $ CLI.opt (Just . PursArg) "purs-args" 'u' "Arguments to pass to purs compile. Wrap in quotes."
    buildOptions  = BuildOptions <$> watch <*> clearScreen <*> allowIgnored <*> sourcePaths <*> srcMapFlag <*> noInstall
                    <*> pursArgs <*> depsOnly <*> beforeCommands <*> thenCommands <*> elseCommands
    scriptBuildOptions = ScriptBuildOptions <$> pursArgs <*> beforeCommands <*> thenCommands <*> elseCommands

    -- Opts.flag' creates a parser with no default value. This is intended.
    -- We want this parser to fail if it does not get a --version flag, rather
    -- than defaulting to NoShowVersion.  We rely on the parser failure to show
    -- the help message.
    versionOpt  = Opts.flag' DoShowVersion (Opts.long "version" <> Opts.help "Show spago version")

    -- Note: by default we limit concurrency to 20
    globalOptions = GlobalOptions <$> quiet <*> verbose <*> veryVerbose <*> (not <$> noColor) <*> usePsa
                    <*> jobsLimit <*> configPath <*> cacheFlag

    initProject =
      ( "init"
      , "Initialize a new sample project, or migrate a psc-package one"
      , Init <$> force <*> noComments <*> tag
      )

    script =
      ( "script"
      , "Run the selected file as a script with the specified dependencies and package set tag"
      , Script <$> scriptSource <*> tag <*> dependencyPackageNames <*> scriptBuildOptions
      )

    build =
      ( "build"
      , "Install the dependencies and compile the current package"
      , Build <$> buildOptions
      )

    repl =
      ( "repl"
      , "Start a REPL"
      , Repl <$> dependencyPackageNames <*> sourcePaths <*> pursArgs <*> depsOnly
      )

    execArgs = (++) <$> backendArgs <*> nodeArgs

    test =
      ( "test"
      , "Test the project with some module, default Test.Main"
      , Test <$> mainModule <*> buildOptions <*> execArgs
      )

    run =
      ( "run"
      , "Runs the project with some module, default Main"
      , Run <$> mainModule <*> buildOptions <*> execArgs
      )

    bundleApp =
      ( "bundle-app"
      , "Bundle the project into an executable"
      , BundleApp <$> mainModule <*> toTarget <*> noBuild <*> buildOptions
      )

    bundleModule =
      ( "bundle-module"
      , "Bundle the project into a CommonJS module"
      , BundleModule <$> mainModule <*> toTarget <*> noBuild <*> buildOptions
      )

    docs =
      ( "docs"
      , "Generate docs for the project and its dependencies"
      , Docs <$> docsFormat <*> sourcePaths <*> depsOnly <*> noSearch <*> openDocs
      )

    search =
      ( "search"
      , "Start a search REPL to find definitions matching names and types"
      , pure Search
      )

    pathSubcommand
      =   CLI.subcommand "output" "Output path for compiled code" (Path (Just PathOutput) <$> buildOptions)
      <|> CLI.subcommand "global-cache" "Location of the global cache" (Path (Just PathGlobalCache) <$> buildOptions)
      <|> (Path Nothing <$> buildOptions)

    path =
      ( "path"
      , "Display paths used by the project"
      , pathSubcommand
      )

    listPackages
      = CLI.subcommand "packages" "List packages available in the local package set"
        (ListPackages <$> jsonFlag)

    listDeps
      = CLI.subcommand "deps" "List dependencies of the project"
        (ListDeps <$> jsonFlag <*> transitive)

    list =
      ( "ls"
      , "List command. Supports: `packages`, `deps`"
      , listPackages <|> listDeps
      )

    graphPackages
      = CLI.subcommand "packages" "Graph all the packages in the build to their dependencies"
        (GraphPackages <$> jsonFlag)

    graphModules
      = CLI.subcommand "modules" "Graph all the modules in the build to their dependencies"
        (GraphModules <$> jsonFlag)

    graph =
      ( "graph"
      , "Graph command. Supports `packages`, `modules`"
      , graphPackages <|> graphModules
      )

    install =
      ( "install"
      , "Install (download) all dependencies listed in spago.dhall"
      , Install <$> packageNames
      )

    sources =
      ( "sources"
      , "List all the source paths (globs) for the dependencies of the project"
      , pure Sources
      )

    verify =
      ( "verify"
      , "Verify that a single package is consistent with the Package Set"
      , Verify <$> packageName
      )

    verifySet =
      ( "verify-set"
      , "Verify that the whole Package Set builds correctly"
      , VerifySet <$> chkModsUniq
      )

    upgradeSet =
      ( "upgrade-set"
      , "Upgrade the upstream in packages.dhall to the latest package-sets release"
      , PackageSetUpgrade <$> tag
      )

    freeze =
      ( "freeze"
      , "Recompute the hashes for the package-set"
      , pure Freeze
      )

    bumpVersion =
      ( "bump-version"
      , "Bump and tag a new version, and generate bower.json, in preparation for release."
      , BumpVersion <$> dryRun <*> versionBump
      )

    otherCommands = CLI.subcommandGroup "Other commands:"
      [ script
      , version
      ]

    version =
      ( "version"
      , "Show spago version"
      , pure Version
      )

    packagesFilter = CLI.optional $ CLI.opt (const Nothing) "filter" 'f' "Filter packages: direct deps with `direct`, transitive ones with `transitive`"
    listPackagesOld =
      Opts.command "list-packages" $ Opts.info (ListPackagesOld <$ packagesFilter <* jsonFlag) mempty

    bundle =
      Opts.command "bundle" $ Opts.info (Bundle <$ mainModule <* toTarget <* noBuild <* buildOptions) mempty

    makeModule =
      Opts.command "make-module" $ Opts.info (MakeModule <$ mainModule <* toTarget <* noBuild <* buildOptions) mempty


    projectCommands = CLI.subcommandGroup "Project commands:"
      [ initProject
      , build
      , repl
      , test
      , run
      , bundleApp
      , bundleModule
      , docs
      , search
      , path
      , sources
      , graph
      ]
    packagesCommands = CLI.subcommandGroup "Packages commands:"
      [ install
      , list
      ]
    packageSetCommands = CLI.subcommandGroup "Package set commands:"
      [ verify
      , verifySet
      , upgradeSet
      , freeze
      ]
    publishCommands = CLI.subcommandGroup "Publish commands:"
      [ bumpVersion
      ]
    oldCommands = Opts.subparser $ Opts.internal <> bundle <> makeModule <> listPackagesOld


echo :: MonadIO m => String -> m ()
echo = CLI.echo . CLI.unsafeTextToLine . Text.pack
