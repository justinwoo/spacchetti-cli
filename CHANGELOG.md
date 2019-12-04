# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Bugfixes:
- Make `--config` work correctly with both relative and absolute paths (#505, #472)


## [0.12.1] - 2019-11-17

Bugfixes:
- Fix macOS release artifact (#503, #504)
- Complete parser implementation for module declarations, for `spago test` (#499)

Other improvements:
- Docs: fix typo in README (#498)
- Errors: use `logWarn` for all warnings (#501)

## [0.12.0] - 2019-11-15

Breaking changes (😱!!!):
- **Revert back to dynamically linked binary on Linux (#502, #500, #497)**

  The static binary was still dynamically linking to `glibc`, causing it to be broken on
  some distros. So for now we're back on a dynamically-linked executable.

## [0.11.1] - 2019-11-12

This is identical to `0.11.0`, but published under a new version number due to mishaps in the publishing CI process.

## [0.11.0] - 2019-11-12

Breaking changes (😱!!!):
- **Remove `psc-package`-related commands (#423, #425)**

  Since we are approaching a stable release and `spago` feature set is a superset of `psc-package` ones,
  from this release we do not support the commands to interop with `psc-package`:
  `psc-package-local-setup`, `psc-package-insdhall` and `psc-package-clean` commands.
- **Build static binaries for Linux (#437, 427)**

  This should fix the dynamic-library-compatibility problems on some distributions.
  It should work as well as the old dynamic binary, but it's theoretically a breaking change since
  some behaviours might be different.
- **Move all logging to `stderr` (#256, #475, #476, #486)**

  All "business output" (e.g. `spago sources`) will stay on `stdout`, so in practice everything
  should be fine, but this is theoretically a breaking change since someone might be depending
  on the output we had so far.


New features:
- add support for `spago build` and `spago run` with alternate backends (#355, #426, #452, #435)

  E.g: add the key `backend = "psgo"` in `spago.dhall` to compile/run with `psgo`
- add support for sharing the `output` folder in monorepos, to reduce build duplication.

  Pass `--no-share-output` flag to disable this behavior (#377, #422)
- add new command `spago path` that returns the paths used in the project.

  E.g. `spago path output` returns the output path so that it can be shared with tools such as `purs-loader`. (#463)
- `spago docs` now displays a link to the generated docs' `index.html`, and opens them in the browser when passed the `--open` flag (#379, #421)
- `spago init` has new `--no-comments` flag which skips adding tutorial comments to the generated `spago.dhall` and `packages.dhall` files (#417, #428)
- `spago verify-set` now compiles everything, to detect duplicate module names. This can be disabled with `--no-check-modules-unique` (#438)
- `spago install purescript-XYZ` will now strip `purescript-` prefix and install XYZ (if it exists in package set) instead of just failing with a warning (#367, #443)
- `spago run` now allows to pipe `stdin` to your running project (#488, #490)

Bugfixes:
- Fix Ctrl-C handling in REPL when using NPM installation on Windows (#493, #483)
- Fix confusing warning when trying to `spago install` a package already present in project dependencies list (#436, #439)
- Warn (but don't error) when trying to `--watch` missing directories (#406, #420, #447, #448)
- Do not watch files in `.spago` folder when running with `--watch` (#430, #446)
- The `--clear-screen` flag (usable e.g. with `spago build --watch`) now also resets cursor position, so the rebuild message always appears at top left of the screen (#465, #466)
- Allow additional fields in the config for local packages (#470)
- Fix `--config` option: get the correct paths when config file is in another directory (#478, #484)

Other improvements:
- Tests: speed up test suite by replacing some end-to-end tests with unit/property tests (#445, #440)
- Tests: update instructions to run tests (#449)
- Tests: always run test suites with UTF8 encoding (#482)
- Docs: various improvements to README (#432, #457, #464, #487)
- Docs: add "getting started" guides for Parcel, Webpack and Nodemon (#456, #461, #473)
- Errors: improve cache skipping error (#453, #480, #481)
- Errors: add a nice error message when trying to run `spago test` with no test modules (#489, #383, #492)
- Refactor: fix `hlint` warnings (#450)
- Refactor: rewrite Curator for moar maintainability (#458, #419)
- Deps: update to Dhall 1.27 and Purs 0.13.4 (#469)
- Deps: revert to GHC 8.4.4 and LTS-12 (#479)
- CI: fix release code (#494, #495)


## [0.10.0] - 2019-09-21

Breaking changes (😱!!!):
- **Flags and arguments that you want to give to `purs` are now passed with `--purs-args` (#353, #366)**

  The previous behaviour in which all arguments that could not parse as `spago` arguments
  were passed along to `purs` was sometimes confusing (e.g. when using `--path` and multiple
  arguments).

New features:
- Support watching js files (#407, #205)
- New `--no-search` flag for `spago docs` to skip patching the documentation using `purescript-docs-search` (#400)
- New `-x` flag for specifying the config path location (#357, #329)
- New `spago login` command, to save a GitHub token to the cache so it can be used for various operations hitting GitHub (#391, #403)

Bugfixes:
- "Quit" command in watch mode now actually quits (#390, #389)
- Do not compile files twice when using `--watch` and Vim (#346, #371)
- Use `git clone` instead of `git fetch` when fetching a package, so all tags can be installed (#373, #374)
- Fix Windows global cache location; now uses `LocalAppData` as default (#384, #380)
- Fix naming clash in short flag for repl dependencies (#352, #350)
- Fix failure to copy to global cache on a different filesystem (#385, #386)
- Fix watch function on Windows (issue with paths) (#387, #380, #401)
- Look up remote imports dynamically when doing frozen check, to always find the right `packages.dhall` (#349, #402)

Other Improvements:
- Performance: make no-op `spago install` faster (#409, #412)
- CI: remove reviews limitation on mergify (#354)
- CI: various fixes (#362, #368, #382, #388, #418)
- Docs: fix syntax errors in template comment (#369, #413, #408)
- Docs: fix link for package-set from commit (#405)
- Docs: keep README up to date with new features (#398, #347)
- Deps: upgrade to lts-14 and GHC-8.6 (#395)
- Deps: upgrade to dhall-1.26.0, v10 of the standard (#411, #358)

## [0.9.0] - 2019-07-30

Breaking changes (!!!):
- **Rename `package-set-upgrade` to `upgrade-set` (#336)**

  You now have to call `spago upgrade-set` if you wish to upgrade your package-sets version

- **Move the `--jobs` flag to be global (#338)**

  If you were invoking spago in this way: `spago install -j 10`, you now have to use `spago -j 10 install` instead

- **Import local packages `as Location` (#301, #244)**

  Before you'd import a local package in this way:

  ```dhall
  let additions =
    { foobar =
        mkPackage
          (../foobar/spago.dhall).dependencies
          "../foobar"
          "local-fix-whatever"
    }
  ```

  ..but now you'll have to import it using `as Location` instead:

  ```dhall
  let additions =
    { foobar = ../foobar/spago.dhall as Location }
  ```


New features:
- Add searchbar to docs generated with `spago docs` (#340, #333, #89)
- Add automatic migration of Bower projects when doing `spago init` (#159, #272, #342)
- Add `bump-version` command, for generating `bower.json` files and making version tags in Git (#203, #289, #324)
- Use `psa` for compiling if installed; you can avoid this with the new `--no-psa` flag (#305, #283, #252, #327)
- Add support for starting a repl within a folder which has not been setup as a spago project (#168, #280)
- Add `--format` flag to `spago docs` (#294, #299)
- Add project sources to `spago sources` output (#276, #287, #308)
- Watch all sources, including dependencies, when building with filewatch (#172, #309)
- Add `--deps-only` flag to build dependencies alone (#330, #331)

Bugfixes:
- Fix `spago install` failing when version branch names differ only by case on case-insensitive filesystems (#285)
- Change `--node-args` shortcut to `-a` to avoid clash (#292, #293)
- Stop reformatting config files if not necessary (#300, #302, #339)
- Make `spago run` write a file and execute it so that args are passed correctly (#297, #295)
- Add fallback for global cache directory (#314, #312)
- Do not overwrite `spago.dhall` when doing `spago init` twice (#318, #321)
- Catch exceptions when trying to fetch metadata (#325)
- Generate hashes when doing `psc-package-insdhall` (#337, #240)

Other Improvements:
- Curator: log exceptions to file to monitor eventual issues (#284)
- Docs: update README with newest features (#286)
- Docs: add docs about switching from Bower (#317)
- Errors: improve error message for overriding compiler version (#345, #343)
- Tests: improve failure messages (#298)
- Tests: fix `packages.dhall` fixtures manipulation (#307)
- Tests: add tests for the `list-packages` command (#304)
- Tests: add tests for local dependencies (#310)
- Config: remove `mkPackage` function in Dhall configs, and switch to package-sets releases for upstream (#322, #320, #319)
- Config: update test template to use `Effect.Class.Console` (#328, #334)
- CI: fix missing "commit since last release" message (#326)
- CI: add configuration for Mergify (#332)


## [0.8.5] - 2019-06-18

ZuriHac edition 🎉

New features:
- Add `sources` key to config to customize the sources used in the build (#273, #173)
- Add `--json` flag to the `list-packages` command to optionally output JSON (#263)
- Add `--clear-screen` flag to to clear the screen when watching (#271, #209)
- Add `--no-install` flag for build to prevent automatic installation (#274, #269)
- Add `--node-args` flag to pass arguments to Node in `run/test` commands (#267, #275)

Bugfixes:
- Fix `spago install` failing when version branch name contains `/`'s (#257, #258)
- Report all missing packages together when it's not possible to build an install plan (#264, #223)
- Pull the latest package-sets version when doing `init` (#254, #279)
- Fix `spago install` not adding new dependencies when list is empty (#282, #281)

Other Improvements:
- Docs: add visual overview of what Spago does "under the hood" in typical project workflow (#211)
- Docs: fix outdated references in README (#266)
- Tests: untangle testcases environments (#265, #214)
- Tests: improve packages test by checking for missing and circular dependencies (#270)

## [0.8.4] - 2019-06-12

New features:
- Add option to clear the screen to spago build/run (#209)
- Add option to pass args to node when doing spago test/run (#267)

Bugfixes:
- Produce an error message when asserting directory permissions (#250)
- Read purs version from inside the set instead of its GitHub tag (#253, #225)
- Skip copy to global cache when encountering a permissions problem (#220, #260)

Other improvements:
- Errors: add many debug logs (#251)
- CI: rewrite Curator in Haskell (#239)
- CI: build only `master` and tags on Travis (#247)
- Dev: add Nix section to stack.yaml (#248)
- Dev: tidy up the various executables, sources and dependencies (#251)

## [0.8.3] - 2019-06-03

Bugfixes:
- Fix `spago psc-package-clean` on Windows (#224)
- Fix `spago repl` starting on Windows where PureScript was installed with NPM (#235, #227)
- Fix missing filenames when encountering parse errors in Dhall files (#241, #222)
- Download packages in local repo instead of global tempdir (#243, #220)

Other improvements:
- Tests: test suite now works fully on Windows (#224)
- CI: parametrize LTS version (#236)
- CI: get PureScript binary for Travis from GitHub releases (#234)
- Error messages: fix whitespace (#221)

## [0.8.1] - 2019-05-29

New features:
- Add global cache to avoid redownloading dependencies (#188, #133)
- Add ability to pin a version to a commit hash in addition to branches and tags (#188, #200)

Bugfixes:
- Another attempt to fix NPM and Yarn installations on Windows (#215, #187)

Other improvements:
- The test suite is now written in Haskell rather than Python (#212, #177)
- Add `spago-curator` tool to generate metadata from the package set (#202)
- Improve docs (#208, #207, #218, #217)

## [0.8.0] - 2019-05-16

Breaking changes:
- Rename "bundle" to "bundle-app" and "make-module" to "bundle-module" for consistency (#175, #147)

Bugfixes:
- Don't fail `init` if a `packages.dhall` is already there, as it's the case of psc-package projects with local spacchetti (#180)

Other improvements:
- Remove CI check for package-sets version, add cron script to update it instead (#185)
- Fill in CHANGELOG from release notes (#186)
- Fix LICENSE file so GitHub recognizes it (#197)
- Add a CONTRIBUTING file (#198, #189)
- Improve README (#199, #194, #196, #201, #193, #192, #187, #178, #191, #150, #142)

## [0.7.7] - 2019-04-28

New features:
- Install "psci-support" on project init (#174)

## [0.7.5] - 2019-03-30

Bugfixes:
- Fix NPM and Yarn installations on Linux and Windows (#157, #167, #166)

## [0.7.4] - 2019-03-27

Bugfixes:
- correctly parse package-set release tag to avoid generating unnecessary warnings (#160, #161)
- skip 0.7.3.0 as I forgot to update the version field (#164)

## [0.7.2] - 2019-03-21

New features:
- introduce a `--verbose` flag to print debug information - e.g. `purs` commands being called by Spago (#154, #155)

## [0.7.1] - 2019-03-19

New features:
- Add `--watch` flag to `build`, `test`, `run`, `bundle` and `make-module` commands (#65, #126, #153)
- Add `spago docs` command, to generate documentation from the project and all dependencies (#127)
- Add `spago run` command, to run your project (#131, #137)

Other fixes and improvements:
- Automatically build in commands that require the project to be built (#146, #149)
- Don't automatically create a configuration if not found (#139, #144)
- Always ensure that the package-set has a hash on it, for speed and security reasons (#128)
- Improvements to documentation and FAQ (#132, #125, #119, #123, #104, #135)
- Improvements to errors, messages and logging (#143, #145, #133, #151, #148, #129, #130, #136)
- Improvements to tests (#95, #91, #138, #141, #140)
- Format Dhall files with ASCII instead of Unicode (#124)

## [0.7.0] - 2019-03-03

Breaking changes:
- The NPM package `purescript-spago` is now deprecated. New releases will be published only to the package `spago` (#115, #44)
- [Spacchetti has been merged in the official package-set](https://github.com/purescript/package-sets/pull/271): this means that `spago` will now use that as the reference package-set. (#120)

  As a result of this, the command `spago spacchetti-upgrade` has been renamed to `spago package-set-upgrade`.

New features:
- Support Windows in NPM install (#121, #109)
- Add `spago freeze` command to recompute hashes of the package-set (#113)
- Add `spago verify` and `spago verify-set` commands (#108, #14)
- Add the `--filter` flag to `spago list-packages`, to filter by direct and transitive deps (#106, #108)
- Check that the version of the installed compiler is at least what the package-set requires (#101, #107, #117, #116)

Other improvements:
- Improve the installation: do less work and print less useless stuff (#110, #112, #114)
- Skip the copy of template files if the source directories exist (#102, #105)

## [0.6.4] - 2019-02-07

New features:
- [`spago init` will search for a `psc-package.json`, and try to port it to your new `spago.dhall` config](https://github.com/spacchetti/spago/tree/6947bf1e9721b4e8a5e87ba8a546a7e9c83153e9#switching-from-psc-package) (#76)
- [Add the `spacchetti-upgrade` command, to automatically upgrade to the latest Package Set](https://github.com/spacchetti/spago/tree/6947bf1e9721b4e8a5e87ba8a546a7e9c83153e9#upgrading-the-package-set) (#93, #73)
- [You can now add local packages to the Package Set 🎉](https://github.com/spacchetti/spago/tree/6947bf1e9721b4e8a5e87ba8a546a7e9c83153e9#adding-and-overriding-dependencies-in-the-package-set) (#96, #88)
- [Now it's possible to run `spago install foo bar` to add new dependencies to your project](https://github.com/spacchetti/spago/tree/6947bf1e9721b4e8a5e87ba8a546a7e9c83153e9#adding-a-dependency) (#74)
- Now every time you try to build, Spago will also check that dependencies are installed (#75, #82)

Bugfixes:
- Spago would crash if `$HOME` was not set, now it doesn't anymore (#85, #90)
- `spago test` now actually works on Windows (#79)

Other improvements:
- Maany docs improvements (#83, #76, #93, #96, #99, #100)
- From this release we are publishing an experimental Windows build (#81)
- Add a PR checklista, so we don't forgetti (#86)

## [0.6.3] - 2019-01-18

New features:
- `spago repl` will now spawn a PureScript repl in your project (#46, #62)
- `spago list-packages` will list all the packages available in your package-set (#71)

## [0.6.2] - 2019-01-07

New features:
- `spago build` and `spago test` now have the `--path` option to specify custom source paths to include (#68, #69)
- `spago build` and `spago test` can now pass options straight to `purs compile` (#66, #49)

## [0.6.1] - 2018-12-26

New features:
- Add initial windows support (#47, #48, #58): now `spago` should run fine on Windows. Unfortunately we're not distributing binaries yet, but the only installation method available is from source (with e.g. `stack install`)

Bugfixes:
- Don't overwrite files when doing `init`, just skip the copy if some file exists (#56)
- Print `git` output in case of failure when doing `install` (#54, #59)
- Include building `src/*` when running `test` (#50, #53)
- Make file embedding indipendent of the locale when compiling; now we just use Unicode

## [0.6.0] - 2018-12-16

First release under the name "spago".

Main changes from the previous "spacchetti-cli" incarnation:
- Rename `spacchetti-cli` → `spago` (#23)
- Publish on NPM under the new name `purescript-spago` (#35)
- Add some commands from `psc-package`:
  - `init` (#12): initialize a new sample project with a `spago.dhall` and a `packages.dhall` config files
  - `install` (#11, #32): concurrently fetch dependencies declared in `spago.dhall` file
  - `sources` (#13): print source globs
  - `build`: compile the project with `purs`
- Migrate old commands from `spacchetti-cli` that are specific to local psc-package projects:
  - `local-setup` is now `psc-package-local-setup`
  - `insdhall` is now `psc-package-insdhall`
  - `clean` is now `psc-package-clean`
- Add some commands from `purp` (#26):
  - `test`: compile and run a module from the `test/` folder
  - `bundle`: bundle all sources in a single file
  - `make-module`: export the above bundle so it can be `require`d from js
- Stop depending on `dhall` and `dhall-to-json` commands and instead depend on `dhall` and `dhall-json` libraries
- Freeze `spacchetti` package-set import in `packages.dhall`, so `dhall` caching works for subsequent executions
- Move to v4.0.0 of `dhall`
- Add integration tests for most of the commands (#31, #30)
