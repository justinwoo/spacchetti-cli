{-
Welcome to a Spago project!
You can edit this file as you like.
-}
{ backend = "echo hi from backend> alternate-backend-output.txt"
, name = "aaa"
, dependencies = [ "prelude", "console", "effect", "psci-support" ]
, packages = ./packages.dhall
, sources = [ "src/**/*.purs", "test/**/*.purs" ]
}
