module Utils
  ( checkFixture
  , checkFileHasInfix
  , checkFileExist
  , readFixture
  , getHighestTag
  , git
  , outputShouldEqual
  , rmtree
  , runFor
  , shouldBeFailure
  , shouldBeFailureInfix
  , shouldBeSuccess
  , shouldBeSuccessInfix
  , shouldBeSuccessOutput
  , shouldBeSuccessOutputWithErr
  , shouldBeSuccessStderr
  , shouldBeFailureStderr
  , shouldBeEmptySuccess
  , spago
  , withCwd
  , withEnvVar
  ) where

import qualified Control.Concurrent as Concurrent
import qualified Control.Exception  as Exception
import           Data.Maybe         (fromMaybe)
import qualified Data.Text          as Text
import qualified Data.Text.Encoding as Text.Encoding
import           Data.Text.Encoding.Error (lenientDecode)
import           Prelude            hiding (FilePath)
import           System.Directory   (removePathForcibly, doesFileExist)
import qualified System.Process     as Process
import           Test.Hspec         (HasCallStack, shouldBe, shouldSatisfy)
import           Turtle             (ExitCode (..), FilePath, Text, cd, empty, encodeString, export,
                                     inproc, limit, need, pwd, readTextFile, strict)
import qualified Turtle.Bytes


withCwd :: FilePath -> IO () -> IO ()
withCwd dir cmd = do
  oldDir <- pwd
  Exception.bracket_ (cd dir) (cd oldDir) cmd

withEnvVar :: Text -> Text -> IO () -> IO ()
withEnvVar var value cmd = do
  oldValue <- need var
  Exception.bracket_
    (export var value)
    (export var (fromMaybe "" oldValue))
    cmd

proc :: Text -> [Text] -> IO (ExitCode, Text, Text)
proc cmd args = do
  let b2t
        = Text.replace "\r\n" "\n" -- take care of Windows newlines
        . Text.Encoding.decodeUtf8With lenientDecode
  (c, out, err) <- Turtle.Bytes.procStrictWithErr cmd args empty
  pure (c, b2t out, b2t err)

spago :: [Text] -> IO (ExitCode, Text, Text)
spago = proc "spago"

git :: [Text] -> IO (ExitCode, Text, Text)
git = proc "git"

runFor :: Int -> String -> [String] -> IO ()
runFor us cmd args = do
  p <- Process.spawnProcess cmd args
  Concurrent.threadDelay us
  Process.terminateProcess p

shouldBeSuccess :: HasCallStack => (ExitCode, Text, Text) -> IO ()
shouldBeSuccess result@(_code, _stdout, _stderr) = do
  -- print $ "STDOUT: " <> _stdout
  -- print $ "STDERR: " <> _stderr
  result `shouldSatisfy` (\(code, _, _) -> code == ExitSuccess)

outputShouldEqual :: HasCallStack => Text -> (ExitCode, Text, Text) -> IO ()
outputShouldEqual expected (_,output,_) = do
  output `shouldBe` expected

shouldBeSuccessOutput :: HasCallStack => FilePath -> (ExitCode, Text, Text) -> IO ()
shouldBeSuccessOutput expected (code, stdout, _stderr) = do
  expectedStdout <- readFixture expected
  code `shouldBe` ExitSuccess
  stdout `shouldBe` expectedStdout

shouldBeSuccessStderr :: HasCallStack => FilePath -> (ExitCode, Text, Text) -> IO ()
shouldBeSuccessStderr expected (code, _stdout, stderr) = do
  expectedStderr <- readFixture expected
  code `shouldBe` ExitSuccess
  stderr `shouldBe` expectedStderr

shouldBeSuccessOutputWithErr :: HasCallStack => FilePath -> FilePath -> (ExitCode, Text, Text) -> IO ()
shouldBeSuccessOutputWithErr expected expectedErr (code, stdout, stderr) = do
  expectedStdout <- readFixture expected
  expectedStderr <- readFixture expectedErr
  code `shouldBe` ExitSuccess
  stdout `shouldBe` expectedStdout
  stderr `shouldBe` expectedStderr

shouldBeSuccessInfix :: HasCallStack => Text -> (ExitCode, Text, Text) -> IO ()
shouldBeSuccessInfix expected (code, stdout, _stderr) = do
  code `shouldBe` ExitSuccess
  stdout `shouldSatisfy` (Text.isInfixOf expected)

shouldBeEmptySuccess :: HasCallStack => (ExitCode, Text, Text) -> IO ()
shouldBeEmptySuccess result = do
  result `shouldBe` (ExitSuccess, "", "")

shouldBeFailure :: HasCallStack => (ExitCode, Text, Text) -> IO ()
shouldBeFailure result@(_code, _stdout, _stderr) = do
  -- print $ "STDOUT: " <> _stdout
  -- print $ "STDERR: " <> _stderr
  result `shouldSatisfy` (\(code, _, _) -> code == ExitFailure 1)

shouldBeFailureStderr :: HasCallStack => FilePath -> (ExitCode, Text, Text) -> IO ()
shouldBeFailureStderr expected (code, _stdout, stderr) = do
  expectedContent <- readFixture expected
  code `shouldBe` ExitFailure 1
  stderr `shouldBe` expectedContent

shouldBeFailureInfix :: HasCallStack => Text -> (ExitCode, Text, Text) -> IO ()
shouldBeFailureInfix expected result = do
  result `shouldSatisfy` (\(code, _stdout, stderr) -> code == ExitFailure 1 && Text.isInfixOf expected stderr)

readFixture :: FilePath -> IO Text
readFixture path =
  readTextFile $ "../fixtures/" <> path

checkFixture :: HasCallStack => FilePath -> IO ()
checkFixture path = do
  actual <- readTextFile path
  expected <- readFixture path
  actual `shouldBe` expected

checkFileExist :: HasCallStack => FilePath -> IO ()
checkFileExist path = do 
    exist <- doesFileExist $ encodeString path 
    exist `shouldBe` True

checkFileHasInfix :: HasCallStack => FilePath -> Text -> IO ()
checkFileHasInfix path needle = do
  actual <- readTextFile path
  actual `shouldSatisfy` Text.isInfixOf needle

rmtree :: FilePath -> IO ()
rmtree = removePathForcibly . encodeString

getHighestTag :: IO (Maybe Text)
getHighestTag = do
  tag <- strict $ limit 1 $ inproc "git" ["tag", "--list", "--sort=-version:refname", "v*"] empty
  pure $ case Text.strip tag of
    ""   -> Nothing
    tag' -> Just tag'
