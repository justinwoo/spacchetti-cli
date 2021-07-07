module SpagoSpec (spec) where

import           Control.Concurrent (threadDelay)
import qualified Data.Text          as Text
import           Prelude            hiding (FilePath)
import qualified System.IO.Temp     as Temp
import           Test.Hspec         (Spec, around_, describe, it, shouldBe, shouldNotSatisfy,
                                     shouldNotBe, shouldReturn, shouldSatisfy)
import           Turtle             (ExitCode (..), cd, cp, decodeString, empty, encodeString,
                                     mkdir, mktree, mv, pwd, readTextFile, rm, shell,
                                     shellStrictWithErr, testdir, writeTextFile, (</>))
import           Utils              (checkFileHasInfix, checkFixture, checkFileExist, outputShouldEqual,
                                     readFixture, runFor, shouldBeFailure, shouldBeFailureInfix,
                                     shouldBeFailureStderr, shouldBeSuccess, shouldBeSuccessOutput,
                                     shouldBeSuccessOutputWithErr, shouldBeSuccessStderr, spago,
                                     withCwd, withEnvVar)


setup :: IO () -> IO ()
setup cmd = do
  Temp.withTempDirectory "test/" "spago-test" $ \temp -> do
    -- print ("Running in " <> temp)
    withCwd (decodeString temp) cmd

spec :: Spec
spec = around_ setup $ do

  describe "spago init" $ do

    it "Spago should have set up a project" $ do

      spago ["init"] >>= shouldBeSuccess

    it "Spago should refuse to overwrite an existing project without -f" $ do

      spago ["init"] >>= shouldBeSuccess
      spago ["init"] >>= shouldBeFailure

    it "Spago should not overwrite files when initing a project" $ do

      mktree "src"
      writeTextFile "src/Main.purs" "Something"
      spago ["init"] >>= shouldBeSuccess
      readTextFile "src/Main.purs" `shouldReturn` "Something"

    it "Spago should always succeed in doing init with force" $ do

      spago ["init"] >>= shouldBeSuccess
      spago ["init", "-f"] >>= shouldBeSuccess

    it "Spago should import config from psc-package" $ do

      writeTextFile "psc-package.json" "{ \"name\": \"aaa\", \"depends\": [ \"prelude\" ], \"set\": \"foo\", \"source\": \"bar\" }"
      spago ["init"] >>= shouldBeSuccess
      cp "spago.dhall" "spago-psc-success.dhall"
      checkFixture "spago-psc-success.dhall"

    it "Spago should not import dependencies that are not in the package-set" $ do

      writeTextFile "psc-package.json" "{ \"name\": \"aaa\", \"depends\": [ \"prelude\", \"foo\", \"bar\" ], \"set\": \"foo\", \"source\": \"bar\" }"
      spago ["init", "-f"] >>= shouldBeSuccess
      cp "spago.dhall" "spago-psc-failure.dhall"
      checkFixture "spago-psc-failure.dhall"

    it "Spago should import configs from Bower" $ do

      shellStrictWithErr "git clone https://github.com/justinwoo/purescript-simple-json.git ." empty
      shellStrictWithErr "git checkout v8.0.0" empty
      spago ["init"] >>= shouldBeSuccess
      mv "spago.dhall" "spago-bower-import.dhall"
      checkFixture "spago-bower-import.dhall"

    it "Spago should strip comments from spago.dhall and packages.dhall" $ do

      spago ["init", "--no-comments"] >>= shouldBeSuccess

      cp "spago.dhall" "spago-no-comments.dhall"
      checkFixture "spago-no-comments.dhall"

      -- We don't want fixture for packages.dhall to avoid having to maintain upstream package-set URL in fixture
      dhallSource <- readTextFile "packages.dhall"
      dhallSource `shouldNotSatisfy` (Text.isInfixOf "{-") -- comments not present
      dhallSource `shouldSatisfy` (Text.isInfixOf "let upstream") -- some dhall stuff is present

    it "Spago should use user-specified tag if it exists instead of latest release" $ do
      spago ["init", "--tag", "psc-0.13.4-20191025"] >>= shouldBeSuccess

      mv "packages.dhall" "packages-older-tag.dhall"
      checkFixture "packages-older-tag.dhall"

    it "Spago should use template/packages.dhall file if user-specified tag does not exist" $ do
      spago ["init", "--tag", "does-not-exist"] >>= shouldBeSuccess

      originalPackage <- readTextFile "packages.dhall"
      let [originalPackageSetUrl]
            = map Text.strip
            $ filter (not . null . Text.breakOnAll "https://github.com/purescript/package-sets")
            $ Text.lines originalPackage

      mv "packages.dhall" "original-packages.dhall"

      spago ["init", "--force"] >>= shouldBeSuccess

      templatePackages <- readTextFile "../../templates/packages.dhall"
      let [templatePackageSetUrl]
            = map Text.strip
            $ filter (not . null . Text.breakOnAll "https://github.com/purescript/package-sets")
            $ Text.lines templatePackages

      originalPackageSetUrl `shouldBe` templatePackageSetUrl

  describe "spago install" $ do

    it "Subsequent installs should succeed after failed install" $ do

      spago ["init"] >>= shouldBeSuccess
      -- Run `install` once and kill it soon to simulate failure
      runFor 5000 "spago" ["install", "-j", "3"]
      -- Sleep for some time, as the above might take time to cleanup old processes
      threadDelay 1000000
      spago ["install", "-j", "10"] >>= shouldBeSuccess

    it "Spago should warn that config was not changed, when trying to install package already present in project dependencies" $ do

      spago ["init"] >>= shouldBeSuccess
      spago ["install"] >>= shouldBeSuccess
      spago ["install", "effect"] >>= shouldBeSuccessStderr "spago-install-existing-dep-stderr.txt"

    it "Spago should strip 'purescript-' prefix and give warning if package without prefix is present in package set" $ do

      spago ["init"] >>= shouldBeSuccess
      spago ["install", "safe-coerce"] >>= shouldBeSuccess
      spago ["install", "purescript-newtype"] >>= shouldBeSuccessStderr "spago-install-purescript-prefix-stderr.txt"
      -- dep added without "purescript-" prefix
      checkFileHasInfix "spago.dhall" "\"newtype\""

    it "Spago should be able to add dependencies" $ do

      writeTextFile "psc-package.json" "{ \"name\": \"aaa\", \"depends\": [ \"prelude\" ], \"set\": \"foo\", \"source\": \"bar\" }"
      spago ["init"] >>= shouldBeSuccess
      spago ["-j 10", "install", "simple-json", "foreign"] >>= shouldBeSuccess
      mv "spago.dhall" "spago-install-success.dhall"
      checkFixture "spago-install-success.dhall"

    it "Spago should not add dependencies that are not in the package set" $ do

      writeTextFile "psc-package.json" "{ \"name\": \"aaa\", \"depends\": [ \"prelude\" ], \"set\": \"foo\", \"source\": \"bar\" }"
      spago ["init"] >>= shouldBeSuccess
      spago ["install", "foo", "bar"] >>= shouldBeFailureStderr "missing-dependencies.txt"
      mv "spago.dhall" "spago-install-failure.dhall"
      checkFixture "spago-install-failure.dhall"

    it "Spago should not allow circular dependencies" $ do

      writeTextFile "psc-package.json" "{ \"name\": \"aaa\", \"depends\": [ \"prelude\" ], \"set\": \"foo\", \"source\": \"bar\" }"
      spago ["init"] >>= shouldBeSuccess
      writeTextFile "spago.dhall" "{- Welcome to a Spago project!  You can edit this file as you like.  -} { name = \"my-project\" , dependencies = [ \"effect\", \"console\", \"psci-support\", \"a\", \"b\" ] , packages = ./packages.dhall // { a = { version = \"a1\", dependencies = [\"b\"], repo = \"https://github.com/fake/fake.git\" }, b = { version = \"b1\", dependencies = [\"a\"], repo = \"https://github.com/fake/fake.git\" } } }"
      spago ["install"] >>= shouldBeFailureStderr "circular-dependencies.txt"

    it "Spago should be able to install a package in the set from a commit hash" $ do

      spago ["init"] >>= shouldBeSuccess
      mv "packages.dhall" "packagesBase.dhall"
      writeTextFile "packages.dhall" "let pkgs = ./packagesBase.dhall in pkgs // { simple-json = pkgs.simple-json // { version = \"d45590f493d68baae174b2d3062d502c0cc4c265\" } }"
      spago ["install", "simple-json"] >>= shouldBeSuccess

    it "Spago should be able to install a package version by branch name with / in it" $ do

      spago ["init"] >>= shouldBeSuccess
      mv "packages.dhall" "packagesBase.dhall"
      writeTextFile "packages.dhall" "let pkgs = ./packagesBase.dhall in pkgs // { metadata_ = { dependencies = [\"prelude\"], repo = \"https://github.com/spacchetti/purescript-metadata.git\", version = \"spago-test/branch-with-slash\" }}"
      spago ["install", "metadata_"] >>= shouldBeSuccess

    it "Spago should be able to install a package not in the set from a commit hash" $ do

      spago ["init"] >>= shouldBeSuccess
      mv "packages.dhall" "packagesBase.dhall"
      writeTextFile "packages.dhall" "let pkgs = ./packagesBase.dhall in pkgs // { spago = { dependencies = [\"prelude\"], repo = \"https://github.com/purescript/spago.git\", version = \"cbdbbf8f8771a7e43f04b18cdefffbcb0f03a990\" }}"
      spago ["install", "spago"] >>= shouldBeSuccess

    it "Spago should not be able to install a package from a not-existing commit hash" $ do

      spago ["init"] >>= shouldBeSuccess
      mv "packages.dhall" "packagesBase.dhall"
      writeTextFile "packages.dhall" "let pkgs = ./packagesBase.dhall in pkgs // { spago = { dependencies = [\"prelude\"], repo = \"https://github.com/purescript/spago.git\", version = \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\" }}"
      spago ["install", "spago"] >>= shouldBeFailure

    it "Spago should be able to update dependencies in an alternative config" $ do

      spago ["init"] >>= shouldBeSuccess
      writeTextFile "alternative1.dhall" "./spago.dhall // {dependencies = [\"prelude\"]}"
      spago ["-x", "alternative1.dhall", "install", "simple-json"] >>= shouldBeSuccess
      checkFixture "alternative1.dhall"

    it "Spago should fail when the alternate config file doesn't exist" $ do
      spago ["init"] >>= shouldBeSuccess
      spago ["install", "-x", "test.dhall"] >>= shouldBeFailureStderr "alternate-config-missing.txt"

    it "Spago should install successfully when the config file is in another directory" $ do

      spago ["init"] >>= shouldBeSuccess
      rm "spago.dhall"
      mkdir "nested"
      writeTextFile "./nested/spago.dhall" "{ name = \"nested\", sources = [ \"src/**/*.purs\" ], dependencies = [ \"effect\", \"console\", \"psci-support\" ] , packages = ../packages.dhall }"
      spago ["install", "--config", "./nested/spago.dhall"] >>= shouldBeSuccess

    it "Spago should not change the alternative config if it does not change dependencies" $ do

      spago ["init"] >>= shouldBeSuccess
      writeTextFile "alternative2.dhall" "./spago.dhall // { sources = [ \"src/**/*.purs\" ] }\n"
      spago ["-x", "alternative2.dhall", "install", "simple-json"] >>= shouldBeSuccess
      spago ["-x", "alternative2.dhall", "install", "simple-json"] >>= shouldBeSuccessStderr "alternative2install-stderr.txt"
      checkFixture "alternative2.dhall"

    it "Spago should install successfully when there are local dependencies sharing the same packages.dhall" $ do

      -- Create local 'lib-a' package that depends on lib-c
      mkdir "lib-a"
      cd "lib-a"
      spago ["init"] >>= shouldBeSuccess
      rm "spago.dhall"
      writeTextFile "spago.dhall" $ "{ name = \"lib-a\", dependencies = [\"console\", \"effect\", \"prelude\", \"lib-c\"], packages = ../packages.dhall }"
      cd ".."

      -- Create local 'lib-b' package that has its dependencies in a separate file
      mkdir "lib-b"
      cd "lib-b"
      spago ["init"] >>= shouldBeSuccess
      rm "spago.dhall"
      writeTextFile "spago.dhall" $ "{ name = \"lib-b\", dependencies = ./spago-deps.dhall, packages = ../packages.dhall }"
      writeTextFile "spago-deps.dhall" "[\"console\", \"effect\", \"prelude\"]"
      cd ".."

      -- Create local 'lib-c' package
      mkdir "lib-c"
      cd "lib-c"
      spago ["init"] >>= shouldBeSuccess
      rm "spago.dhall"
      writeTextFile "spago.dhall" $ "{ name = \"lib-c\", dependencies = [\"console\", \"effect\", \"prelude\"], packages = ../packages.dhall }"
      cd ".."

      -- Create 'app' package that depends on 'lib-a' and 'lib-b'
      spago ["init"] >>= shouldBeSuccess
      rm "spago.dhall"
      writeTextFile "spago.dhall" "{ name = \"app\", dependencies = [\"console\", \"effect\", \"prelude\", \"lib-a\", \"lib-b\"], packages = ./packages.dhall }"
      packageDhall <- readTextFile "packages.dhall"
      writeTextFile "packages.dhall" $ packageDhall <> " // { lib-a = ./lib-a/spago.dhall as Location, lib-b = ./lib-b/spago.dhall as Location, lib-c = ./lib-c/spago.dhall as Location }"

      spago ["install"] >>= shouldBeSuccess

    it "Spago should not warn about freezing remote imports if they can be located from spago.dhall" $ do

      spago ["init"] >>= shouldBeSuccess
      -- Do an initial installation so that it's easier to compare subsequent output
      spago ["install"] >>= shouldBeSuccess

      mkdir "elsewhere"
      writeTextFile "elsewhere/a.dhall" "let p = ./b.dhall in p"
      mv "packages.dhall" "elsewhere/b.dhall"
      spagoDhall <- readTextFile "spago.dhall"
      writeTextFile "spago.dhall" $ Text.replace "./packages.dhall" "./elsewhere/a.dhall" spagoDhall
      spago ["install"] >>= shouldBeSuccessStderr "ensure-frozen-success.txt"

  describe "spago sources" $ do

    it "Spago should print both dependencies and project sources" $ do

      spago ["init"] >>= shouldBeSuccess
      spago ["sources"] >>= shouldBeSuccessOutput "sources-output.txt"

  describe "spago build" $ do

    it "Spago should build successfully" $ do

      spago ["init"] >>= shouldBeSuccess
      spago ["build"] >>= shouldBeSuccess

    it "Spago should pass options to purs" $ do

      spago ["init"] >>= shouldBeSuccess
      spago ["build", "--purs-args", "-o myOutput"] >>= shouldBeSuccess
      testdir "myOutput" `shouldReturn` True

    it "Spago should pass multiple options to purs" $ do

      spago ["init"] >>= shouldBeSuccess
      spago ["build", "--purs-args", "-o", "--purs-args", "myOutput"] >>= shouldBeSuccess
      testdir "myOutput" `shouldReturn` True

    it "Spago should build successfully with sources included from custom path" $ do

      spago ["init"] >>= shouldBeSuccess
      mkdir "another_source_path"
      mv "src/Main.purs" "another_source_path/Main.purs"
      spago ["build", "--path", "another_source_path/*.purs"] >>= shouldBeSuccess

    it "Spago should not install packages when passing the --no-install flag" $ do

      spago ["init"] >>= shouldBeSuccess
      spago ["build", "--no-install"] >>= shouldBeFailure
      spago ["install"] >>= shouldBeSuccess
      spago ["build", "--no-install"] >>= shouldBeSuccess

    it "Spago should add sources to config when key is missing" $ do

      configV1 <- readFixture "spago-configV1.dhall"
      spago ["init"] >>= shouldBeSuccess
      -- Replace initial config with the old config format (without 'sources')
      mv "spago.dhall" "spago-old.dhall"
      writeTextFile "spago.dhall" configV1

      spago ["install"] >>= shouldBeSuccess
      mv "spago.dhall" "spago-configV2.dhall"
      checkFixture "spago-configV2.dhall"

    it "Spago should create a local output folder" $ do

      -- Create root-level packages.dhall
      mkdir "monorepo"
      cd "monorepo"
      spago ["init"] >>= shouldBeSuccess
      rm "spago.dhall"

      -- Create local 'lib-a' package that uses packages.dhall on top level (but also has it's own one to confuse things)
      mkdir "lib-a"
      cd "lib-a"
      spago ["init"] >>= shouldBeSuccess
      rm "spago.dhall"
      writeTextFile "spago.dhall" $ "{ name = \"lib-1\", dependencies = [\"console\", \"effect\", \"prelude\"], packages = ./packages.dhall }"
      rm "packages.dhall"
      writeTextFile "packages.dhall" $ "../packages.dhall"
      spago ["build"] >>= shouldBeSuccess
      testdir "output" `shouldReturn` True

      cd ".."
      testdir "output" `shouldReturn` False

    it "Spago should use the main packages.dhall even when another packages.dhall is further up the tree" $ do

      -- Create root-level packages.dhall that directs to middle one
      mkdir "monorepo-1"
      cd "monorepo-1"
      spago ["init"] >>= shouldBeSuccess
      rm "spago.dhall"
      rm "packages.dhall"
      writeTextFile "packages.dhall" $ "./monorepo-2/packages.dhall"

      -- Create local 'monorepo-2' package that is the real root
      mkdir "monorepo-2"
      cd "monorepo-2"
      spago ["init"] >>= shouldBeSuccess
      rm "spago.dhall"
      writeTextFile "spago.dhall" $ "{ name = \"lib-1\", dependencies = [\"console\", \"effect\", \"prelude\"], packages = ./packages.dhall }"
      spago ["build"] >>= shouldBeSuccess
      testdir "output" `shouldReturn` True

       -- Create local 'monorepo-3' package that uses packages.dhall on top level
      mkdir "monorepo-3"
      cd "monorepo-3"
      spago ["init"] >>= shouldBeSuccess
      rm "spago.dhall"
      writeTextFile "spago.dhall" $ "{ name = \"lib-1\", dependencies = [\"console\", \"effect\", \"prelude\"], packages = ./packages.dhall }"
      rm "packages.dhall"
      writeTextFile "packages.dhall" $ "../../packages.dhall"
      spago ["build"] >>= shouldBeSuccess
      testdir "output" `shouldReturn` True

      cd ".."
      testdir "output" `shouldReturn` True

      cd ".."
      testdir "output" `shouldReturn` False

    it "Spago should find the middle packages.dhall even when another file is further up the tree" $ do

      -- Create root-level module to confuse things
      mkdir "monorepo-root"
      cd "monorepo-root"
      spago ["init"] >>= shouldBeSuccess
      rm "spago.dhall"
      writeTextFile "spago.dhall" $ "{ name = \"lib-extra\", dependencies = [\"console\", \"effect\", \"prelude\"], packages = ./packages.dhall }"

      -- get rid of duplicate Main module
      cd "src"
      rm "Main.purs"
      writeTextFile "Main.purs" $ "module OtherMain where \n import Prelude\n import Effect\n main :: Effect Unit\n main = pure unit"
      cd ".."

      -- create real root
      mkdir "subfolder"
      cd "subfolder"
      spago ["init"] >>= shouldBeSuccess
      packageDhall <- readTextFile "packages.dhall"
      writeTextFile "packages.dhall" $ packageDhall <> " // { lib-extra = ../spago.dhall as Location }"

      -- Create local 'lib-a' package that uses packages.dhall in middle folder
      mkdir "lib-a"
      cd "lib-a"
      spago ["init"] >>= shouldBeSuccess
      rm "spago.dhall"
      writeTextFile "spago.dhall" $ "{ name = \"lib-1\", dependencies = [\"lib-extra\",\"console\", \"effect\", \"prelude\"], packages = ../packages.dhall }"
      rm "packages.dhall"
      spago ["build"] >>= shouldBeSuccess

      -- don't use nested folder
      testdir "output" `shouldReturn` True

      -- use middle one
      cd ".."
      testdir "output" `shouldReturn` False

      -- not the trick root folder
      cd ".."
      testdir "output" `shouldReturn` False

    describe "import checking" $ do

      it "Spago should fail on direct project imports from transitive dependencies" $ do
        spago ["init"] >>= shouldBeSuccess
        rm "spago.dhall"
        writeTextFile "spago.dhall" $ "{ name = \"check-imports\", dependencies = [\"effect\", \"lists\"], packages = ./packages.dhall }"
        rm "src/Main.purs"
        writeTextFile "src/Main.purs" "module Main where\nimport Prelude\nimport Data.Maybe\nimport Data.List\nmain = unit"
        rm "test/Main.purs"
        spago ["build"]
        spago ["--no-psa", "build"] >>= shouldBeFailureStderr "check-direct-import-transitive-dependency.txt"

      it "Spago should warn on unused dependencies" $ do
        spago ["init"] >>= shouldBeSuccess
        rm "spago.dhall"
        writeTextFile "spago.dhall" $ "{ name = \"check-imports\", dependencies = [\"effect\", \"prelude\"], packages = ./packages.dhall }"
        rm "src/Main.purs"
        writeTextFile "src/Main.purs" "module Main where\nimport Prelude\nmain :: Unit\nmain = unit"
        rm "test/Main.purs"
        spago ["build"]
        spago ["--no-psa", "build"] >>= shouldBeSuccessStderr "check-unused-dependency.txt"

      it "Spago should not warn on unused dependencies when building deps-only" $ do
        spago ["init"] >>= shouldBeSuccess
        rm "spago.dhall"
        writeTextFile "spago.dhall" $ "{ name = \"check-imports\", dependencies = [\"effect\", \"prelude\"], packages = ./packages.dhall }"
        rm "src/Main.purs"
        writeTextFile "src/Main.purs" "module Main where\nimport Prelude\nmain :: Unit\nmain = unit"
        rm "test/Main.purs"
        spago ["build"]
        spago ["--no-psa", "build", "--deps-only"] >>= shouldBeSuccessStderr "spago-build-succeeded-stderr.txt"

    describe "alternate backend" $ do

      it "Spago should use alternate backend if option is specified" $ do
        configWithBackend <- readFixture "spago-configWithBackend.dhall"
        spago ["init"] >>= shouldBeSuccess
        mv "spago.dhall" "spago-old.dhall"
        writeTextFile "spago.dhall" configWithBackend

        spago ["-j", "5", "build"] >>= shouldBeSuccess
        checkFixture "alternate-backend-output.txt"

      it "Passing `--codegen corefn` with backend option should fail" $ do
        configWithBackend <- readFixture "spago-configWithBackend.dhall"
        expectedErr <- readFixture "codegen-opt-with-backend.txt"
        spago ["init"] >>= shouldBeSuccess
        mv "spago.dhall" "spago-old.dhall"
        writeTextFile "spago.dhall" configWithBackend

        spago ["-j", "5", "build"] >>= shouldBeSuccess
        spago ["build", "--purs-args", "--codegen", "--purs-args", "corefn"] >>= shouldBeFailureInfix expectedErr
        spago ["build", "--purs-args", "--codegen", "--purs-args", "docs"] >>= shouldBeFailureInfix expectedErr

    it "Spago should run a before command" $ do

      spago ["init"] >>= shouldBeSuccess

      dir <- pwd
      let dumpFile = dir </> "testOutput"
      spago ["build", "--before", "echo before>> " <> ( Text.pack $ encodeString dumpFile )] >>= shouldBeSuccess
      test <- readTextFile dumpFile
      test `shouldBe` "before\n"

    it "Spago should run a then command" $ do

      spago ["init"] >>= shouldBeSuccess

      dir <- pwd
      let dumpFile = dir </> "testOutput"
      spago [ "build"
            , "--then", "echo then>> " <> ( Text.pack $ encodeString dumpFile )
            , "--else", "echo else>> " <> ( Text.pack $ encodeString dumpFile )
            ] >>= shouldBeSuccess
      test <- readTextFile dumpFile
      test `shouldBe` "then\n"

    it "Spago should run a before command before a then command" $ do

      spago ["init"] >>= shouldBeSuccess

      dir <- pwd
      let dumpFile = dir </> "testOutput"
      spago [ "build"
            , "--before", "echo before>> " <> ( Text.pack $ encodeString dumpFile )
            , "--then", "echo then>> " <> ( Text.pack $ encodeString dumpFile )
            ] >>= shouldBeSuccess
      test <- readTextFile dumpFile
      test `shouldBe` "before\nthen\n"

    it "Spago should run an else command if there is an error in the build" $ do

      spago ["init"] >>= shouldBeSuccess

      dir <- pwd
      let dumpFile = dir </> "testOutput"
      rm "src/Main.purs"
      writeTextFile "src/Main.purs" "Invalid Purescript code"
      spago [ "build"
            , "--then", "echo then>> " <> ( Text.pack $ encodeString dumpFile )
            , "--else", "echo else>> " <> ( Text.pack $ encodeString dumpFile )
            ] >>= shouldBeFailure
      test <- readTextFile dumpFile
      test `shouldBe` "else\n"


    it "Spago should run an else command if there is an error in the run file" $ do

      spago ["init"] >>= shouldBeSuccess
      spago ["install", "exceptions"] >>= shouldBeSuccess

      dir <- pwd
      let dumpFile = dir </> "testOutput"
      rm "src/Main.purs"
      writeTextFile "src/Main.purs" "module Main where\nimport Effect.Exception\nmain = throw \"error\""
      spago [ "run"
            , "--else", "echo else>> " <> ( Text.pack $ encodeString dumpFile )
            ] >>= shouldBeFailure
      test <- readTextFile dumpFile
      test `shouldBe` "else\n"

    it "Spago should run multiple commands in order" $ do

      spago ["init"] >>= shouldBeSuccess

      dir <- pwd
      let dumpFile = dir </> "testOutput"
      spago [ "build"
            , "--before", "echo before1>> " <> ( Text.pack $ encodeString dumpFile )
            , "--before", "echo before2>> " <> ( Text.pack $ encodeString dumpFile )
            , "--then", "echo then1>> " <> ( Text.pack $ encodeString dumpFile )
            , "--then", "echo then2>> " <> ( Text.pack $ encodeString dumpFile )
            ] >>= shouldBeSuccess
      test <- readTextFile dumpFile
      test `shouldBe` "before1\nbefore2\nthen1\nthen2\n"

    it "Spago should fail the build if a before command fails" $ do

      spago ["init"] >>= shouldBeSuccess
      spago [ "build"
            , "--before", "exit 1"
            ] >>= shouldBeFailure

    it "Spago should fail the build if a then command fails" $ do

      spago ["init"] >>= shouldBeSuccess
      spago [ "build"
            , "--then", "exit 1"
            ] >>= shouldBeFailure

    it "Spago should still fail the build if an else command fails" $ do

      spago ["init"] >>= shouldBeSuccess
      rm "src/Main.purs"
      writeTextFile "src/Main.purs" "Invalid Purescript code"
      spago [ "build"
            , "--else", "exit 1"
            ] >>= shouldBeFailure

  describe "spago test" $ do

    it "Spago should test successfully" $ do

      spago ["init"] >>= shouldBeSuccess
      spago ["build"] >>= shouldBeSuccess
      spago ["--no-psa", "test"] >>= shouldBeSuccessOutputWithErr "test-output-stdout.txt" "test-output-stderr.txt"

    it "Spago should fail nicely when the test module is not found" $ do

      spago ["init"] >>= shouldBeSuccess
      mv "test" "test2"
      spago ["test"] >>= shouldBeFailureInfix "Module 'Test.Main' not found! Are you including it in your build?"

    it "Spago should test in custom output folder" $ do

      spago ["init"] >>= shouldBeSuccess
      spago ["test", "--purs-args", "-o", "--purs-args", "myOutput"] >>= shouldBeSuccess
      testdir "myOutput" `shouldReturn` True

    it "Spago should test successfully with a different output folder" $ do

      -- Create root-level packages.dhall
      mkdir "monorepo"
      cd "monorepo"
      spago ["init"] >>= shouldBeSuccess
      rm "spago.dhall"

      -- Create local 'lib-a' package that uses packages.dhall on top level (but also has it's own one to confuse things)
      mkdir "lib-a"
      cd "lib-a"
      spago ["init"] >>= shouldBeSuccess
      rm "spago.dhall"
      writeTextFile "spago.dhall" $ "{ name = \"lib-1\", dependencies = [\"console\", \"effect\", \"prelude\"], packages = ./packages.dhall }"
      rm "packages.dhall"
      writeTextFile "packages.dhall" $ "../packages.dhall"
      spago ["test"] >>= shouldBeSuccess
      testdir "output" `shouldReturn` True

      cd ".."
      testdir "output" `shouldReturn` False


  describe "spago upgrade-set" $ do

    it "Spago should migrate package-sets from src/packages.dhall to the released one" $ do

      spago ["init"] >>= shouldBeSuccess
      mv "packages.dhall" "packages-expected.dhall"
      packages <- readTextFile "packages-expected.dhall"
      let [packageSetUrl]
            = map Text.strip
            $ filter (not . null . Text.breakOnAll "https://github.com/purescript/package-sets")
            $ Text.lines packages
      writeTextFile "packages.dhall" "https://github.com/purescript/package-sets/releases/download/psc-0.13.4-20191025/packages.dhall sha256:f9eb600e5c2a439c3ac9543b1f36590696342baedab2d54ae0aa03c9447ce7d4"
      spago ["-v", "upgrade-set"] >>= shouldBeSuccess
      newPackages <- Text.strip <$> readTextFile "packages.dhall"
      newPackages `shouldBe` packageSetUrl

    it "Spago should migrate a package set from an alternative repository from src/packages.dhall" $ do

      spago ["init"] >>= shouldBeSuccess
      writeTextFile "packages.dhall" "https://github.com/purerl/package-sets/releases/download/erl-0.13.6-20200713/packages.dhall sha256:6b1dcfe05ee95229b654462bf5d36864f9a0dfbc2ac120192aaa25f9fceb9967"
      spago ["-v", "upgrade-set"] >>= shouldBeSuccess
      newPackages <- Text.strip <$> readTextFile "packages.dhall"
      newPackages `shouldNotBe` "https://github.com/purerl/package-sets/releases/download/erl-0.13.6-20200713/packages.dhall"
      newPackages `shouldSatisfy` Text.isPrefixOf "https://github.com/purerl/package-sets/releases/download"

    it "Spago should migrate package-set from src/packages.dhall to the user-specified one if it exists" $ do
      -- initialize the project, so that it uses latest package set release
      spago ["init"] >>= shouldBeSuccess

      spago ["-v", "upgrade-set", "--tag", "psc-0.13.4-20191025"] >>= shouldBeSuccess
      mv "packages.dhall" "packages-older-tag.dhall"
      checkFixture "packages-older-tag.dhall"

    it "Spago should not migrate to the user-specified package-set if does not exist" $ do
      -- initialize the project, so that it uses latest package set release
      spago ["init"] >>= shouldBeSuccess

      originalPackages <- readTextFile "packages.dhall"
      let [originalPackageSetUrl]
            = map Text.strip
            $ filter (not . null . Text.breakOnAll "https://github.com/purescript/package-sets")
            $ Text.lines originalPackages

      spago ["-v", "upgrade-set", "--tag", "does-not-exist"] >>= shouldBeSuccess
      packages <- readTextFile "packages.dhall"
      let [packageSetUrl]
            = map Text.strip
            $ filter (not . null . Text.breakOnAll "https://github.com/purescript/package-sets")
            $ Text.lines packages

      packageSetUrl `shouldBe` originalPackageSetUrl

  describe "spago run" $ do

    it "Spago should run successfully" $ do

      spago ["init"] >>= shouldBeSuccess
      spago ["build"] >>= shouldBeSuccess

      shell "psa --version" empty >>= \case
        ExitSuccess -> spago ["-v", "run"] >>= shouldBeSuccessOutput "run-output.txt"
        ExitFailure _ ->  spago ["-v", "run"] >>= shouldBeSuccessOutput "run-output.txt"

    it "Spago should be able to not use `psa`" $ do

      spago ["init"] >>= shouldBeSuccess
      spago ["--no-psa", "build"] >>= shouldBeSuccess
      spago ["-v", "--no-psa", "run"] >>= shouldBeSuccessOutput "run-output.txt"

    it "Spago should pass stdin to the child process" $ do

      spago ["init"] >>= shouldBeSuccess
      cp "../fixtures/spago-run-stdin.purs" "src/Main.purs"
      spago ["install", "node-buffer", "node-streams", "node-process"] >>= shouldBeSuccess
      spago ["build"] >>= shouldBeSuccess
      shellStrictWithErr "echo wut| spago run" empty >>= shouldBeSuccessOutput "spago-run-passthrough.txt"

    it "Spago should use exec-args" $ do

      spago ["init"] >>= shouldBeSuccess
      cp "../fixtures/spago-run-args.purs" "src/Main.purs"
      spago ["install", "node-process", "arrays"] >>= shouldBeSuccess
      spago ["build"] >>= shouldBeSuccess
      spago ["run", "--exec-args", "hello world"] >>= shouldBeSuccessOutput "run-args-output.txt"

    it "Spago should use node-args" $ do

      spago ["init"] >>= shouldBeSuccess
      cp "../fixtures/spago-run-args.purs" "src/Main.purs"
      spago ["install", "node-process", "arrays"] >>= shouldBeSuccess
      spago ["build"] >>= shouldBeSuccess
      spago ["run", "--node-args", "hello world"] >>= shouldBeSuccessOutput "run-args-output.txt"

    it "Spago should prefer exec-args" $ do

      spago ["init"] >>= shouldBeSuccess
      cp "../fixtures/spago-run-args.purs" "src/Main.purs"
      spago ["install", "node-process", "arrays"] >>= shouldBeSuccess
      spago ["build"] >>= shouldBeSuccess
      spago ["run", "--exec-args", "hello world", "--node-args", "hallo welt"] >>= shouldBeSuccessOutput "run-args-combined-output.txt"

  describe "spago script" $ do

    -- At that time, we should add more tests checking the output of the script

    it "Spago script should create file in directory where it is executed" $ do

      spago ["script", "../fixtures/spago-script-make-file.purs", "-d", "node-fs", "-d", "node-buffer"] >>= shouldBeSuccess
      checkFixture "spago-script-result.txt"

  describe "spago bundle" $ do

    it "Spago should fail but should point to the replacement command" $ do

      spago ["bundle", "--to", "bundle.js"] >>= shouldBeFailureStderr "bundle-stderr.txt"


  describe "spago bundle-app" $ do

    it "Spago should bundle successfully" $ do

      spago ["init"] >>= shouldBeSuccess
      spago ["bundle-app", "--to", "bundle-app.js"] >>= shouldBeSuccess
      checkFixture "bundle-app.js"

    it "Spago should bundle successfully with source map" $ do

      spago ["init"] >>= shouldBeSuccess
      spago ["bundle-app", "--to", "bundle-app-src-map.js", "--source-maps"] >>= shouldBeSuccess
      checkFixture "bundle-app-src-map.js"
      checkFileExist "bundle-app-src-map.js.map"

  describe "spago make-module" $ do

    it "Spago should fail but should point to the replacement command" $ do

      spago ["make-module", "--to", "make-module.js"] >>= shouldBeFailureStderr "make-module-stderr.txt"


  describe "spago bundle-module" $ do

    it "Spago should successfully make a module" $ do

      spago ["init"] >>= shouldBeSuccess
      spago ["build"] >>= shouldBeSuccess
      -- Now we don't remove the output folder, but we pass the `--no-build`
      -- flag to skip rebuilding (i.e. we are counting on the previous command
      -- to have built stuff for us)
      spago ["bundle-module", "--to", "bundle-module.js", "--no-build"] >>= shouldBeSuccess
      checkFixture "bundle-module.js"

    it "Spago should successfully make a module with source map" $ do

      spago ["init"] >>= shouldBeSuccess
      spago ["build"] >>= shouldBeSuccess

      spago ["bundle-module", "--to", "bundle-module-src-map.js", "--no-build", "--source-maps"] >>= shouldBeSuccess
      checkFixture "bundle-module-src-map.js"
      checkFileExist "bundle-module-src-map.js.map"

  describe "spago graph" $ do

    it "spago graph modules - dot" $ do

      spago ["init", "--tag", "psc-0.14.0-20210409"] >>= shouldBeSuccess
      spago ["graph", "modules"] >>= shouldBeSuccessOutput "graph-modules.dot"

    it "spago graph modules - json" $ do

      spago ["init", "--tag", "psc-0.14.0-20210409"] >>= shouldBeSuccess
      spago ["graph", "modules", "--json"] >>= shouldBeSuccessOutput "graph-modules.json"

    it "spago graph packages - dot" $ do

      spago ["init", "--tag", "psc-0.14.0-20210409"] >>= shouldBeSuccess
      spago ["graph", "packages"] >>= shouldBeSuccessOutput "graph-packages.dot"

    it "spago graph packages - json" $ do

      spago ["init", "--tag", "psc-0.14.0-20210409"] >>= shouldBeSuccess
      spago ["graph", "packages", "--json"] >>= shouldBeSuccessOutput "graph-packages.json"

  describe "spago ls packages" $ do

    it "Spago should ls packages successfully" $ do

      spago ["init"] >>= shouldBeSuccess
      mv "packages.dhall" "packages-old.dhall"
      writeTextFile "packages.dhall" "https://github.com/purescript/package-sets/releases/download/psc-0.13.4-20191025/packages.dhall sha256:f9eb600e5c2a439c3ac9543b1f36590696342baedab2d54ae0aa03c9447ce7d4"
      spago ["ls", "packages"] >>= shouldBeSuccessOutput "list-packages.txt"

    it "Spago should ls packages in JSON successfully" $ do

      spago ["init"] >>= shouldBeSuccess
      mv "packages.dhall" "packages-old.dhall"
      writeTextFile "packages.dhall" "https://github.com/purescript/package-sets/releases/download/psc-0.13.4-20191025/packages.dhall sha256:f9eb600e5c2a439c3ac9543b1f36590696342baedab2d54ae0aa03c9447ce7d4"
      spago ["ls", "packages", "--json"] >>= shouldBeSuccessOutput "list-packages.json"

  describe "spago path output" $ do
    it "Spago should output the correct path" $ do
      -- Create local 'monorepo-1' package that is the real root
      mkdir "monorepo-1"
      cd "monorepo-1"
      spago ["init"] >>= shouldBeSuccess

       -- Create local 'monorepo-2' package that uses packages.dhall on top level
      mkdir "monorepo-2"
      cd "monorepo-2"
      spago ["init"] >>= shouldBeSuccess
      rm "packages.dhall"
      writeTextFile "packages.dhall" $ "../packages.dhall"
      spago ["path", "output"] >>= outputShouldEqual "output\n"
      pure ()

  describe "spago verify-set" $ do
    it "Spago should fail when there is no spago.dhall or packages.dhall" $ do
      spago ["init"] >>= shouldBeSuccess
      rm "spago.dhall"
      rm "packages.dhall"
      spago ["verify-set"] >>= shouldBeFailureStderr "verify-set-failure-no-files.txt"

    it "Spago should fail when packages.dhall is malformed" $ do
      spago ["init"] >>= shouldBeSuccess
      mv "packages.dhall" "packages-old.dhall"
      writeTextFile "packages.dhall" $ "abcdef"
      spago ["verify-set"] >>= shouldBeFailure

  describe "global cache" $ do
    it "Spago should create global cache directory if it does not exist" $ do
      withEnvVar "XDG_CACHE_HOME" "./nonexisting-cache" $
        spago ["repl"] >>= shouldBeSuccess
