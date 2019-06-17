module SpagoSpec (spec) where

import           Control.Concurrent (threadDelay)
import           Prelude            hiding (FilePath)
import qualified System.IO.Temp     as Temp
import           Test.Hspec         (Spec, around_, describe, it, shouldBe)
import           Turtle             (cp, decodeString, mkdir, mktree, mv, readTextFile, testdir,
                                     writeTextFile)
import           Utils              (checkFixture, readFixture, runFor, shouldBeFailure,
                                     shouldBeFailureOutput, shouldBeSuccess, shouldBeSuccessOutput,
                                     spago, withCwd)


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
      readTextFile "src/Main.purs" >>= (`shouldBe` "Something")

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


  describe "spago install" $ do

    it "Subsequent installs should succeed after failed install" $ do

      spago ["init"] >>= shouldBeSuccess
      -- Run `install` once and kill it soon to simulate failure
      runFor 5000 "spago" ["install", "-j", "3"]
      -- Sleep for some time, as the above might take time to cleanup old processes
      threadDelay 1000000
      spago ["install", "-j", "10"] >>= shouldBeSuccess

    it "Spago should be able to add dependencies" $ do

      writeTextFile "psc-package.json" "{ \"name\": \"aaa\", \"depends\": [ \"prelude\" ], \"set\": \"foo\", \"source\": \"bar\" }"
      spago ["init"] >>= shouldBeSuccess
      spago ["install", "-j10", "simple-json", "foreign"] >>= shouldBeSuccess
      mv "spago.dhall" "spago-install-success.dhall"
      checkFixture "spago-install-success.dhall"

    it "Spago should not add dependencies that are not in the package set" $ do

      writeTextFile "psc-package.json" "{ \"name\": \"aaa\", \"depends\": [ \"prelude\" ], \"set\": \"foo\", \"source\": \"bar\" }"
      spago ["init"] >>= shouldBeSuccess
      spago ["install", "foo", "bar"] >>= shouldBeFailureOutput "missing-dependencies.txt"
      mv "spago.dhall" "spago-install-failure.dhall"
      checkFixture "spago-install-failure.dhall"

    it "Spago should not allow circular dependencies" $ do

      writeTextFile "psc-package.json" "{ \"name\": \"aaa\", \"depends\": [ \"prelude\" ], \"set\": \"foo\", \"source\": \"bar\" }"
      spago ["init"] >>= shouldBeSuccess
      writeTextFile "spago.dhall" "{- Welcome to a Spago project!  You can edit this file as you like.  -} { name = \"my-project\" , dependencies = [ \"effect\", \"console\", \"psci-support\", \"a\", \"b\" ] , packages = ./packages.dhall // { a = { version = \"a1\", dependencies = [\"b\"], repo = \"/fake\" }, b = { version = \"b1\", dependencies = [\"a\"], repo = \"/fake\" } } }"
      spago ["install"] >>= shouldBeFailureOutput "circular-dependencies.txt"

    it "Spago should be able to install a package in the set from a commit hash" $ do

      spago ["init"] >>= shouldBeSuccess
      mv "packages.dhall" "packagesBase.dhall"
      writeTextFile "packages.dhall" "let pkgs = ./packagesBase.dhall in pkgs // { simple-json = pkgs.simple-json // { version = \"d45590f493d68baae174b2d3062d502c0cc4c265\" } }"
      spago ["install", "simple-json"] >>= shouldBeSuccess

    it "Spago should be able to install a package not in the set from a commit hash" $ do

      spago ["init"] >>= shouldBeSuccess
      mv "packages.dhall" "packagesBase.dhall"
      writeTextFile "packages.dhall" "let pkgs = ./packagesBase.dhall in pkgs // { spago = { dependencies = [\"prelude\"], repo = \"https://github.com/spacchetti/spago.git\", version = \"cbdbbf8f8771a7e43f04b18cdefffbcb0f03a990\" }}"
      spago ["install", "spago"] >>= shouldBeSuccess

    it "Spago should not be able to install a package from a not-existing commit hash" $ do

      spago ["init"] >>= shouldBeSuccess
      mv "packages.dhall" "packagesBase.dhall"
      writeTextFile "packages.dhall" "let pkgs = ./packagesBase.dhall in pkgs // { spago = { dependencies = [\"prelude\"], repo = \"https://github.com/spacchetti/spago.git\", version = \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\" }}"
      spago ["install", "spago"] >>= shouldBeFailure

  describe "spago build" $ do

    it "Spago should build successfully" $ do

      spago ["init"] >>= shouldBeSuccess
      spago ["build"] >>= shouldBeSuccess

    it "Spago should pass options to purs" $ do

      spago ["init"] >>= shouldBeSuccess
      spago ["build", "--", "-o", "myOutput"] >>= shouldBeSuccess
      testdir "myOutput" >>= (`shouldBe` True)

    it "Spago should build successfully with sources included from custom path" $ do

      spago ["init"] >>= shouldBeSuccess
      mkdir "another_source_path"
      mv "src/Main.purs" "another_source_path/Main.purs"
      spago ["build", "--path", "another_source_path/*.purs"] >>= shouldBeSuccess

    it "Spago should not install packages when passing the --no-install flag"

      spago ["init"] >>= shouldBeSuccess
      spago ["build", "--no-install"] >>= shouldBeFailure
      spago ["install"] >>= shouldBeSuccess
      spago ["build", "--no-install"] >>= shouldBeSuccess

    it "Spago should add sources to config when key is missing" $ do

      configV1 <- readFixture "spago-configV1.dhall"
      spago ["init"] >>= shouldBeSuccess
      -- Replace initial config with the old config format (without 'sources')
      writeTextFile "spago.dhall" configV1

      spago ["build"] >>= shouldBeSuccess
      mv "spago.dhall" "spago-configV2.dhall"
      checkFixture "spago-configV2.dhall"

  describe "spago test" $ do

    it "Spago should test successfully" $ do

      spago ["init"] >>= shouldBeSuccess
      -- Note: apparently purs starts caching the compiled modules only after three builds
      spago ["build"] >>= shouldBeSuccess
      spago ["build"] >>= shouldBeSuccess
      spago ["test"] >>= shouldBeSuccessOutput "test-output.txt"


  describe "spago run" $ do

    it "Spago should run successfully" $ do

      spago ["init"] >>= shouldBeSuccess
      -- Note: apparently purs starts caching the compiled modules only after three builds
      spago ["build"] >>= shouldBeSuccess
      spago ["build"] >>= shouldBeSuccess
      spago ["run", "--verbose"] >>= shouldBeSuccessOutput "run-output.txt"


  describe "spago bundle" $ do

    it "Spago should fail but should point to the replacement command" $ do

      spago ["bundle", "--to", "bundle.js"] >>= shouldBeFailureOutput "bundle-output.txt"


  describe "spago bundle-app" $ do

    it "Spago should bundle successfully" $ do

      spago ["init"] >>= shouldBeSuccess
      spago ["bundle-app", "--to", "bundle-app.js"] >>= shouldBeSuccess
      checkFixture "bundle-app.js"


  describe "spago make-module" $ do

    it "Spago should fail but should point to the replacement command" $ do

      spago ["make-module", "--to", "make-module.js"] >>= shouldBeFailureOutput "make-module-output.txt"


  describe "spago bundle-module" $ do

    it "Spago should successfully make a module" $ do

      spago ["init"] >>= shouldBeSuccess
      spago ["build"] >>= shouldBeSuccess
      -- Now we don't remove the output folder, but we pass the `--no-build`
      -- flag to skip rebuilding (i.e. we are counting on the previous command
      -- to have built stuff for us)
      spago ["bundle-module", "--to", "bundle-module.js", "--no-build"] >>= shouldBeSuccess
      checkFixture "bundle-module.js"
