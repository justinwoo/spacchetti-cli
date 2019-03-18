# spago

[![Build Status](https://travis-ci.com/spacchetti/spago.svg?branch=master)][travis-spago]

*(IPA: /ˈspaɡo/)*

PureScript package manager and build tool powered by [Dhall][dhall] and
[package-sets][package-sets].


<img src="https://raw.githubusercontent.com/spacchetti/logo/master/spacchetti-icon.png" height="300px" alt="spacchetti logo">

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->


- [What does all of this mean?](#what-does-all-of-this-mean)
- [Installation](#installation)
- [Quickstart](#quickstart)
  - [Switching from `psc-package`](#switching-from-psc-package)
  - [Configuration file format](#configuration-file-format)
- [Commands](#commands)
  - [Package management](#package-management)
    - [Listing available packages](#listing-available-packages)
    - [Adding a dependency](#adding-a-dependency)
    - [Adding and overriding dependencies in the Package Set](#adding-and-overriding-dependencies-in-the-package-set)
    - [Verifying your additions and overrides](#verifying-your-additions-and-overrides)
    - [Upgrading the Package Set](#upgrading-the-package-set)
    - [Caching the Package Set](#caching-the-package-set)
  - [Building and testing a project](#building-and-testing-a-project)
  - [Bundling a project into a single JS file](#bundling-a-project-into-a-single-js-file)
    - [1. `spago bundle`](#1-spago-bundle)
    - [2. `spago make-module`](#2-spago-make-module)
    - [3. `spago build` + whatever JS bundler](#3-spago-build--whatever-js-bundler)
  - [Documentation](#documentation)
- [FAQ](#faq)
    - [Hey wait we have a perfectly functional `pulp` right?](#hey-wait-we-have-a-perfectly-functional-pulp-right)
    - [I miss `bower link`!](#i-miss-bower-link)
    - [I added a new package to the `packages.dhall`, but `spago` is not installing it. Why?](#i-added-a-new-package-to-the-packagesdhall-but-spago-is-not-installing-it-why)
    - [So if I use `spago make-module` this thing will compile all my js deps in the file?](#so-if-i-use-spago-make-module-this-thing-will-compile-all-my-js-deps-in-the-file)
    - [Why can't `spago` also install my npm dependencies?](#why-cant-spago-also-install-my-npm-dependencies)
    - [I still want to use `psc-package`, can this help me in some way?](#i-still-want-to-use-psc-package-can-this-help-me-in-some-way)
    - [I'm getting weird errors about `libtinfo.so.5`..](#im-getting-weird-errors-about-libtinfoso5)
    - [I added a git repo URL to my overrides, but `spago` thinks it's a local path 🤔](#i-added-a-git-repo-url-to-my-overrides-but-spago-thinks-its-a-local-path-)
    - [My `install` command is failing with some errors about "too many open files"](#my-install-command-is-failing-with-some-errors-about-too-many-open-files)
    - [The `bundle`/`test`/`run`/etc commands don't work, what do I do?](#the-bundletestrunetc-commands-dont-work-what-do-i-do)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## What does all of this mean?

`spago` aims to tie together the UX of developing a PureScript project.  
In this Pursuit (see what I did there) it is heavily inspired by [Rust's Cargo][cargo]
and [Haskell's Stack][stack], and builds on top of ideas from existing PureScript
infrastructure and tooling, as [`psc-package`][psc-package], [`pulp`][pulp] and
[`purp`][purp].

## Installation

> Right, so how can I get this thing?

The recommended installation methods for Windows, Linux or macOS are:
- `npm install -g spago` (see the latest releases on npm
  [here][spago-npm])
- Download the binary from the [latest GitHub release][spago-latest-release]
- Compile from source by cloning this repo and running `stack install`
- With Nix, using [easy-purescript-nix][spago-nix]

**Note:** we assume you already installed the [PureScript compiler][purescript].
If not, get it with `npm install -g purescript`, or the recommended method for your OS.

## Quickstart

Let's set up a new project!

```bash
$ mkdir purescript-unicorns
$ cd purescript-unicorns
$ spago init
```

This last command will create a bunch of files:

```
.
├── packages.dhall
├── spago.dhall
├── src
│   └── Main.purs
└── test
    └── Main.purs
```

Convention note: `spago` expects your source files to be in `src/` and your
test files in `test/`.  
It is possible to include additional source paths when running some commands,
like `build`, `test` or `repl`.

Let's take a look at the two [Dhall][dhall] configuration files that `spago` requires:
- `packages.dhall`: this file is meant to contain the *totality* of the packages
  available to your project (that is, any package you might want to import).  
  In practical terms, it pulls in the [official package-set][package-sets] as a base,
  and you are then able to add any package that might not be in the package set,
  or override esisting ones.
- `spago.dhall`: this is your project configuration. It includes the above package-set,
  the list of your dependencies, and any other project-wide setting that `spago` will
  use for builds.

### Switching from `psc-package`

Do you have an existing `psc-package` project and want to switch to `spago`?

No problem! If you run `spago init`, we'll port your existing `psc-package.json`
configuration into a new `spago.dhall` 😎

Note: `spago` won't otherwise touch your `psc-package.json` file, so you'll have to
remove it yourself.

You'll note that most of the `psc-package` commands are the same in `spago`, so porting
your existing build is just a matter of search-and-replace most of the times.

### Configuration file format

It's indeed useful to know what's the format (or more precisely, the [Dhall][dhall]
type) of the files that `spago` expects. Let's define them in Dhall:

```haskell
-- The basic building block is a Package:
let Package =
  { dependencies : List Text  -- the list of dependencies of the Package
  , repo = Text               -- the address of the git repo the Package is at
  , version = Text            -- git tag
  }

-- The type of `packages.dhall` is a Record from a PackageName to a Package
-- We're kind of stretching Dhall syntax here when defining this, but let's
-- say that its type is something like this:
let PackageSet =
  { console : Package
  , effect : Package
  ...                  -- and so on, for all the packages in the package-set
  }

-- The type of the `spago.dhall` configuration is then the following:
let Config =
  { name : Text               -- the name of our project
  , dependencies : List Text  -- the list of dependencies of our app
  , packages : PackageSet     -- this is the type we just defined above
  }
```

## Commands

For an overview of the available commands, run:

```bash
$ spago --help
```

You will see several subcommands (e.g. `build`, `test`); you can ask for help
about them by invoking the command with `--help`, e.g.:

```bash
$ spago build --help
```

This will give a detailed view of the command, and list any command-specific
(vs global) flags.

### Package management

We initialized a project and saw how to configure dependencies and packages, the
next step is fetching its dependencies.

If we run:

```bash
$ spago install
```

..then `spago` will download all the `dependencies` listed in `spago.dhall` (and
store them in the `.spago` folder).

#### Listing available packages

It is sometimes useful to know which packages are contained in our package set
(e.g. to see which version we're using, or to search for packages).

You can get a complete list of the packages your `packages.dhall` imports (together
with their versions and URLs) by running:

```bash
$ spago list-packages
```

By passing the `--filter` flag you can restrict the list to direct or transitive dependencies:

```bash
# Direct dependencies, i.e. only the ones listed in spago.dhall
$ spago list-packages --filter=direct

# Transitive dependencies, i.e. all the dependencies of your dependencies
$ spago list-packages -f transitive
```

#### Adding a dependency

You can add dependencies from your package-set by running:

```bash
$ spago install my-new-package another-package
```

#### Adding and overriding dependencies in the Package Set

Let's say I'm a user of the `simple-json` package. Now, let's say I stumble upon a bug
in there, but thankfully I figure how to fix it. So I clone it locally and add my fix.  
Now if I want to test this version in my current project, how can I tell `spago` to do it?

We have a `overrides` record in `packages.dhall` just for that!  
And in this case we override the `repo` key with the local path of the package.  
It might look like this:

```haskell
let overrides =
      { simple-json =
            upstream.simple-json // { repo = "../purescript-simple-json" }
      }
```

Note that if we `list-packages`, we'll see that it is now included as a local package:
```bash
$ spago list-packages
...
signal                v10.1.0   Remote "https://github.com/bodil/purescript-signal.git"
sijidou               v0.1.0    Remote "https://github.com/justinwoo/purescript-sijidou.git"
simple-json           v4.4.0    Local "../purescript-simple-json"
simple-json-generics  v0.1.0    Remote "https://github.com/justinwoo/purescript-simple-json-generics.git"
smolder               v11.0.1   Remote "https://github.com/bodil/purescript-smolder.git"
...
```

And since local packages are just included in the build, if we add it to the `dependencies`
in `spago.dhall` and then do `spago install`, it will not be downloaded:

```
$ spago install
Installing 42 dependencies.
...
Installing "refs"
Installing "identity"
Skipping package "simple-json", using local path: "../purescript-simple-json"
Installing "control"
Installing "enums"
...
```

Let's now say that we test that our fix works, and we are ready to Pull Request the fix.  
So we push our fork and open the PR, but while we wait for the fix to land on the next
package-set release, we still want to use the fix in our production build.

In this case, we can just change the override to point to some branch of our fork, like this:


```haskell
let overrides =
    { simple-json =
          upstream.simple-json
       // { repo = "https://github.com/my-user/purescript-simple-json.git"
          , version = "my-branch-with-the-fix"
          }
    }
```

**Note**: currently only "branches" and "tags" work as a `version`, and tags are
recommended over branches (as for example if you push new commits to a branch,
`spago` won't pick them up unless you delete the `.spago` folder).  
Commit hashes are not supported yet, but hopefully will be at some point.

If a package is not in the upstream package-set, you can add it in a similar way,
by changing the `additions` record in the `packages.dhall` file.  
E.g. if we want to add the `facebook` package:

```haskell
let additions =
  { facebook =
      mkPackage
        [ "console"
        , "aff"
        , "prelude"
        , "foreign"
        , "foreign-generic"
        , "errors"
        , "effect"
        ]
        "https://github.com/Unisay/purescript-facebook.git"
        "v0.3.0"
  }
```

The `mkPackage` function should be already included in your `packages.dhall`, and it will
expect as input a list of dependencies, the location of the package, and the tag you wish to use.

Of course this works also in the case of adding local packages. In this case you won't
care about the value of the "version" (since it won't be used), so you can put arbitrary
values in there.

And of course if the package you're adding has a `spago.dhall` file you can just import it
and pull the dependencies from there, instead of typing down the list of dependencies!

Example:

```haskell
let additions =
  { foobar =
      mkPackage
        (../foobar/spago.dhall).dependencies
        "../foobar"
        "local-fix-whatever"
  }
```

#### Verifying your additions and overrides

"But wait", you might say, "how do I know that my override doesn't break the package-set?"

This is a fair question, and you can verify that your fix didn't break the rest of the
package-set by running the `verify` command.

E.g. if you patched the `foreign` package, and added it as a local package to your package-set,
you can check that you didn't break its dependants (also called "reverse dependencies")
by running:

```bash
$ spago verify foreign
```

Once you check that the packages you added verify correctly, we would of course very much love
if you could pull request it to the [Upstream package-set][package-sets] ❤️

#### Upgrading the Package Set

The version of the package-set you depend on is fixed in the `packages.dhall` file
(look for the `upstream` var).

You can upgrade to the latest version of the package-set with the `package-set-upgrade`
command, that will automatically find out the latest version, download it, and write
the new url and hashes in the `packages.dhall` file for you.

Running it would look something like this:

```bash
$ spago package-set-upgrade
Found the most recent tag for "purescript/package-sets": "psc-0.12.3-20190227"
Package-set upgraded to latest tag "psc-0.12.3-20190227"
Fetching the new one and generating hashes.. (this might take some time)
Done. Updating the local package-set file..
```

If you wish to detach from tags for your package-set, you can of course point it to a
specific commit.  
Just set your `upstream` to look something like this:

```haskell
let upstream =
      https://github.com/purescript/package-sets/blob/81354f2ea1ac9493eb05dfbd43adc6d183bc4ecd/src/packages.dhall
```

#### Caching the Package Set

If you encounter any issues with the hashes for the package-set (e.g. the hash is not deemed
correct by `spago`), then you can have the hashes recomputed by running the `freeze` command:

```bash
$ spago freeze
```

However, this is a pretty rare situation and in principle it should not happen, and when
it happens it might not be secure to run the above command.  
To understand all the implications of this I'd invite you to read about
[the safety guarantees][dhall-hash-safety] that Dhall offers.

### Building and testing a project

We can build the project and its dependencies by running:

```bash
$ spago build
```

This is just a thin layer above the PureScript compiler command `purs compile`.  
The build will produce very many JavaScript files in the `output/` folder. These
are CommonJS modules, and you can just `require()` them e.g. on Node.

It's also possible to include custom source paths when building (`src` and `test` are always included):

```bash
$ spago build --path 'another_source/**/*.purs'

```

**Note**: the wrapper on the compiler is so thin that you can pass options to `purs`.
E.g. if you wish to output your files in some other place than `output/`, you can run

```bash
$ spago build -- -o myOutput/
```

If you wish to automatically have your project rebuilt when making changes to source files
you can use the `--watch` flag:

```bash
$ spago build --watch
```

If you want to run the program (akin to `pulp run`), just use `run`:
```bash
# The main module defaults to "Main"
$ spago run

# Or define your own module path to Main
$ spago run --main ModulePath.To.Main

# And pass arguments through to `purs compile`
$ spago run --main ModulePath.To.Main -- --verbose-errors
```

You can also test your project with `spago`:

```bash
# Test.Main is the default here, but you can override it as usual
$ spago test --main Test.Main
Build succeeded.
You should add some tests.
Tests succeeded.
```

And last but not least, you can spawn a PureScript repl!  
As with the `build` and `test` commands, you can add custom source paths
to load, and pass options to the underlying `purs repl` by just putting
them after `--`.  
E.g. the following opens a repl on `localhost:3200`:

```bash
$ spago repl -- --port 3200
```

### Bundling a project into a single JS file

For the cases when you wish to produce a single JS file from your PureScript project,
there are basically three ways to do that:

#### 1. `spago bundle`

This will produce a single, executable, dead-code-eliminated file:

```bash
# You can specify the main module and the target file, or these defaults will be used
$ spago bundle --main Main --to index.js
Bundle succeeded and output file to index.js

# We can then run it with node:
$ node .
```

#### 2. `spago make-module`

If you wish to produce a single, dead-code-eliminated JS module that you can `require` from
JavaScript:

```bash
# You can specify the main module and the target file, or these defaults will be used
$ spago make-module --main Main --to index.js
Bundling first...
Bundle succeeded and output file to index.js
Make module succeeded and output file to index.js

$ node -e "console.log(require('./index).main)"
[Function]
```

#### 3. `spago build` + whatever JS bundler

This is the case in which you have JS dependencies, and you need some other JS-specific tool
to bundle them in (i.e. this is about resolving the `require`s in your JS code)

In this case the flow might look like this:

```bash
# This will compile the PS to JS, and put the results in very many files in ./output
# Note: this _doesn't_ resolve the `require`s in the JS code
$ spago build

# Here any bundler is fine: parcel, webpack, browserify, etc
# Note: here the index.html is an example value, you should put the entrypoint here
$ parcel build index.html
```

More information about this can be found at [this FAQ entry](#so-if-i-use-spago-make-module-this-thing-will-compile-all-my-js-deps-in-the-file).

##### Skipping the Build Step

When running `spago bundle` and `spago make-module` the `build` step will also execute
since bundling depends on building first.
To skip this build you can add the `--no-build` flag.


### Documentation

To build documentation for your project and its dependencies (i.e. a "project-local
[Pursuit][pursuit]"), you can use the `docs` command:
```bash
$ spago docs
```

This will generate all the documentation in the `./generated-docs` folder of your project.
You might then want to open the `index.html` file in there.

## FAQ

#### Hey wait we have a perfectly functional `pulp` right?

Yees, however:
- `pulp` is a build tool, so you'll still have to use it with `bower` or `psc-package`.
- If you go for `bower`, you're missing out on package-sets (that is: packages versions
  that are known to be working together, saving you the headache of fitting package
  versions together all the time).
- If you use `psc-package`, you have the problem of not having the ability of overriding
  packages versions when needed, leading everyone to make their own package-set, which
  then goes unmaintained, etc.  
  Of course you can use the package-set-local-setup to solve this issue, but this is
  exactly what we're doing here: integrating all the workflow in a single tool, `spago`,
  instead of having to use `pulp`, `psc-package`, `purp`, etc.

#### I miss `bower link`!

Take a look at the [section on editing the package-set](#adding-and-overriding-dependencies)
for details on how to add or replace packages with local ones.

#### I added a new package to the `packages.dhall`, but `spago` is not installing it. Why?

Adding a package to the package-set just includes it in the set of possible packages you
can depend on. However if you wish `spago` to install it you should then add it to
the `dependencies` list in your `spago.dhall`.

#### So if I use `spago make-module` this thing will compile all my js deps in the file?

No. We only take care of PureScript land. In particular, `make-module` will do the
most we can do on the PureScript side of things (dead code elimination), but will
leave the `require`s still in.  
To fill them in you should use the proper js tool of the day, at the time of
writing [ParcelJS][parcel] looks like a good option.

If you wish to see an example of a project building with `spago` + `parcel`, a simple
starting point is the [TodoMVC app with `react-basic`][todomvc].
You can see in its `package.json` that a "production build" is just
`spago build && parcel build index.html`.  
If you open its `index.js` you'll see that it does a `require('./output/Todo.App')`:
the files in `output` are generated by `spago build`, and then the `parcel` build resolves
all the `require`s and bundles all these js files in.

Though this is not the only way to include the built js - for a slimmer build or for importing
some PureScript component in another js build we might want to use the output of `make-module`.

For an example of this in a "production setting" you can take a look at [affresco][affresco].  
It is a PureScript monorepo of React-based components and apps.  
The gist of it is that the PureScript apps in the repo are built with `spago build`
(look in the `package.json` for it), but all the React components can be imported from
JS apps as well, given that proper modules are built out of the PS sources.  
This is where `spago make-module` is used: the `build-purs.rb` builds a bundle out of every
single React component in each component's folder - e.g. let's say we `make-module` from
the `ksf-login` component and output it in the `index.js` of the component's folder; we can
then `yarn install` the single component (note it contains a `package.json`), and require it
as a separate npm package with `require('@affresco/ksf-login')`.

#### Why can't `spago` also install my npm dependencies?

A common scenario is that you'd like to use things like `react-basic`, or want to depend
on JS libraries like ThreeJS.
In any case, you end up depending on some NPM package.

And it would be really nice if `spago` would take care of installing all of these
dependencies, so we don't have to worry about running npm besides it, right?

While these scenarios are common, they are also really hard to support.
In fact, it might be that a certain NPM package in your transitive dependencies
would only support the browser, or only node. Should `spago` warn about that?  
And if yes, where should we get all of this info?

Another big problem is that the JS backend is not the only backend around. For example,
PureScript has a [C backend][purec] and an [Erlang backend][purerl] among the others.  
These backends are going to use different package managers for their native dependencies,
and while it's feasible for `spago` to support the backends themselves, supporting also
all the possible native package managers (and doing things like building package-sets for their
dependencies versions) is not a scalable approach.

So this is the reason why if you or one of your dependencies need to depend on some "native"
packages, you should run the appropriate package-manager for that (e.g. npm).  
For examples on how to do it, see the previous FAQ entry.

#### I still want to use `psc-package`, can this help me in some way?

Yes! We can help you setup your psc-package project to use the Dhall version of the package-set.

We have two commands for it:
- **`psc-package-local-setup`**: this command creates a `packages.dhall` file in your project,
  that points to the most recent package-set, and lets you override and add  arbitrary packages.  
  See the docs about this [here][package-sets].
- **`psc-package-insdhall`**: do the *Ins-Dhall-ation* of the local project setup: that is,
  generates a local package-set for `psc-package` from your `packages.dhall`, and points your
  `psc-package.json` to it.

  Functionally this is equivalent to running:

  ```sh
  NAME='local'
  TARGET=.psc-package/$NAME/.set/packages.json
  mkdir -p .psc-package/$NAME/.set
  dhall-to-json --pretty <<< './packages.dhall' > $TARGET
  echo wrote packages.json to $TARGET
  ```

#### I'm getting weird errors about `libtinfo.so.5`..

See [here](https://github.com/spacchetti/spago/issues/104#issue-408423391) for reasons and a fix.

#### I added a git repo URL to my overrides, but `spago` thinks it's a local path 🤔

This might happen if you copy the "git" URL from a GitHub repo and try adding it as a repo URL
in your package-set.  
However, `spago` requires URLs to conform to [RFC 3986](https://tools.ietf.org/html/rfc3986),
which something like `git@foo.com:bar/baz.git` doesn't conform to.

To have the above repo location accepted you should rewrite it like this:
```
ssh://git@foo.com/bar/baz.git
```

#### My `install` command is failing with some errors about "too many open files"

This might happen because the limit of "open files per process" is too low in your OS - as
`spago` will try to fetch all dependencies in parallel, and this requires lots of file operations.

You can limit the number of concurrent operations with the `-j` flag, e.g.:

```
$ spago install -j 10
```

To get a ballpark value for the `j` flag you can take the result of the `ulimit -n` command
(which gives you the current limit), and divide it by four.


#### The `bundle`/`test`/`run`/etc commands don't work, what do I do?

The rule of thumb is that in order for these commands to work then `spago build` must succeed first,
as most of the commands make use of the artifacts produced by `build` in the `output` folder.

So make sure `build` works first. If you still get a failure you might be encountering a `spago` bug.


[pulp]: https://github.com/purescript-contrib/pulp
[purp]: https://github.com/justinwoo/purp
[dhall]: https://github.com/dhall-lang/dhall-lang
[cargo]: https://github.com/rust-lang/cargo
[stack]: https://github.com/commercialhaskell/stack
[purec]: https://github.com/pure-c/purec
[parcel]: https://parceljs.org
[purerl]: https://github.com/purerl/purescript
[pursuit]: https://pursuit.purescript.org/
[todomvc]: https://github.com/f-f/purescript-react-basic-todomvc
[affresco]: https://github.com/KSF-Media/affresco/tree/4b430b48059701a544dfb65b2ade07ef9f36328a
[spago-npm]: https://www.npmjs.com/package/spago
[spago-nix]: https://github.com/justinwoo/easy-purescript-nix/blob/master/spago.nix
[purescript]: https://github.com/purescript/purescript
[psc-package]: https://github.com/purescript/psc-package
[package-sets]: https://github.com/purescript/package-sets
[travis-spago]: https://travis-ci.com/spacchetti/spago
[spago-issues]: https://github.com/spacchetti/spago/issues
[dhall-hash-safety]: https://github.com/dhall-lang/dhall-lang/wiki/Safety-guarantees#code-injection
[spago-latest-release]: https://github.com/spacchetti/spago/releases/latest
