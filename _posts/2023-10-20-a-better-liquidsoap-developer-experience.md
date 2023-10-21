---
layout: post
title: A better liquidsoap developer experience! 🤖
---

(Jump to [the configuration part](#tldr) if you want to skip the story!)

I have to admit: I am sort of a cave dweler when it comes to developer setup. For years, my only setup was `vim`, with minimal syntax coloring and _very_ little bells and whistles.
I like it like that, I feel like automation, for me, gets in the way of thinking. It might take you a minute to go look at the doc or type a long chunk of text etc. But, 
during that time, my brain is active and thinking about what I am actually doing.

![tumblr_pyal42orWz1re6c9lo2_540](https://github.com/savonet/blog/assets/871060/a16a25ff-c11e-4137-9f08-18a5f4b359fc)

However, not everyone is like that and, for too long, we have not focused on quality of life for liquidsoap script developers so, this has been the focus since 
the release of version `2.2.0` and here's what we have for y'all now!

## Syntax highlighting

This was the simplest part! There seems to be two form of support to bring syntax highlighting to coding editors and they are both based on a _grammar_, which is a programmatic
way to explain to the code editor how to parse a liquidsoap script.

We already have a grammar in the code to parse and run scripts. However, our grammar is not _error resilient_. This is because, if a script has a syntax error, 
the interpreter will stop processing it and report the error to the user.

<img width="382" alt="Screenshot 2023-10-20 at 7 47 34 PM" src="https://github.com/savonet/blog/assets/871060/a2bed1b5-31c6-41db-b57f-ec4127adf948">


However, when working inside a code editor, the script will, most of the time, be broken. Nevertheless, we would like the editor to be able to output something sensible!

The topic of error recovery with grammars and state machines is a complicated academic topic. However, for engineers, well, something _good enough_ is usually.. enough.. 😄

Here are the two categories of grammar with error resilience that are currently used by editors.

### Regexp-based grammars

These grammars are very simple and do not have much context when parsing the code. They detect specific code parts based on recognizable patterns such as
`let foo = ...` in liquidsoap scripts. They are naturally error resilient but also cannot say much about the code beside identifying specific token and variables.

Also, they look pretty ugly:
```json
{
  "name": "keyword.control.trycatch.js",
  "match": "(?<![_$[:alnum:]])(?:(?<=\\.\\.\\.)|(?<!\\.))(catch|finally|throw|try)(?![_$[:alnum:]])(?:(?=\\.\\.\\.)|(?!\\.))"
},
```
(This is an extract from the [`javascript` regexp-based grammar for `vscode`](https://github.com/microsoft/vscode/blob/main/extensions/javascript/syntaxes/JavaScript.tmLanguage.json).

We now have one such grammar! It is available at [savonet/vscode-liquidsoap](https://github.com/savonet/vscode-liquidsoap) and is used
to provide syntax highlighting on `vscode`! 

<img width="683" alt="Screenshot 2023-10-20 at 7 37 13 PM" src="https://github.com/savonet/blog/assets/871060/5bb21d1e-19d1-4163-a6d0-564054bb9142">

There is also a [pending PR](https://github.com/saranrapjs/sublime-liquidsoap-syntax/pull/1) to update the syntax for the Sublime editor, which uses the same syntaxes

### Tree-sitter

The latest, hot stuff on the topic of grammars for code editor is [tree-sitter](https://github.com/tree-sitter/tree-sitter). Originally used in the [atom editor](https://github.com/atom/atom) (RIP! 🪦), 
the project provides an API to write [LR parsers](https://en.wikipedia.org/wiki/LR_parser) and is really good at error recovery.

This one was nice for us because our grammar is already written in a LR parser style so the lift was pretty straight forward! This work was done in [tree-sitter-liquidsoap](https://github.com/savonet/tree-sitter-liquidsoap).

Unfortunately, however, there does not seem to be widespread support (yet!) for `tree-sitter` tools in code editors. There is a really good one for neovim in [nvim.tree-sitter](https://github.com/nvim-treesitter/nvim-treesitter),
which supports liquidsoap scripts now!

<img width="629" alt="Screenshot 2023-10-20 at 7 38 06 PM" src="https://github.com/savonet/blog/assets/871060/fc613951-6bff-4991-be42-6c91b8cdc3b9">

However, `tree-sitter` is really promising. The cleanliness of the syntactic tree it produces is really impressive and can be used for multiple things, including code context and language server implementation (more on that later!). 
See by yourself:

![ast](https://github.com/savonet/blog/assets/871060/986a0a64-c87c-49d9-acc5-331873c66e34)

## Github

A big part of this work was to, finally, get syntax highlighting on github, to help making pull requests, issues and conversations more readable. However, the [pull request to add liquidsoap support](https://github.com/github-linguist/linguist/pull/6565)
seems to be stuck for now until we can prove that enough people do use the language (which we already know!). If you have some liquidsoap scripts you are using, please feel free to push them to github!

![giphy](https://github.com/savonet/blog/assets/871060/8a2cafde-da5c-4f27-846b-6d194e90d99d)

## Formatting

Another great tool for developers is code formatting. This was an interesting project! We had to change the way we represent our syntactic terms to be able to 
export terms that are as close as possible to the actual code  including things such as comments, and etc. so they can be reformatted.

To acheive this, we had to introduce a transformation layer that resembles what `webpack` and `typescript` can do in the Javascript world.

During parsing, we generate very rich syntactic terms that look like this:
```ocaml
parsed_ast =
  [ `If of _if
  | `Inline_if of _if
  | `If_def of if_def
  | `If_version of if_version
  | `If_encoder of if_encoder
  | `While of _while
  | `For of _for
  | `Iterable_for of iterable_for
  | `List of list_el list
  | `Try of _try
  | `Regexp of string * char list
  | `Time_interval of time_el * time_el
  | `Time of time_el
  | `Def of _let * t
  | `Let of _let * t
  | `Binding of _let * t
  | `Cast of t * type_annotation
  | `App of t * app_arg list
  | `Invoke of invoke
  | `Fun of fun_arg list * t
  | `RFun of string * fun_arg list * t
```
Of course, at runtime, we do not care about the different between the syntactic `if ... then ... else ... end` (the `` `If`` above) and `... ? ... : ...` (the `` `Inline_if``), they have the exact same
runtime behavior. So, these detailed parsed terms are converted to a much reduced set of runtime terms that look like this:

```ocaml
type 'a ast =
  [ `Ground of ground
  | `Tuple of 'a list
  | `Null
  | `Open of 'a * 'a
  | `Var of string
  | `Seq of 'a * 'a ]

type t = runtime_ast term

and runtime_ast =
  [ `Let of let_t
  | `List of t list
  | `Cast of t * Type.t
  | `App of t * (string * t) list
  | `Invoke of invoke
  | `Encoder of encoder
  | `Fun of (t, Type.t) func
  | t ast ]
```

Meanwhile, we can then export the detailed parser syntactic terms and use this to generated formatted code. This is done in [liquidsoap-prettier](https://github.com/savonet/liquidsoap-prettier).

As the name suggests, we are using the [prettier](https://prettier.io/) API to format our code. Our initial intent was to write a prettier plugin but prettier requires
a local configuration and not all `liquidsoap` projects want to have a node `package.json` associated with them so we simply wrote a `liquidsoap-prettier` binary that does the job:

```shell
$ liquidsoap-prettier --write /path/to/file.liq
```

The binary is pretty straight forward to integrate. There is a PR pending for [nvim.formatter](https://github.com/mhartington/formatter.nvim/pull/296) that shows one such example.

The programmatic API is also implemented in the [vscode-liquidsoap](https://marketplace.visualstudio.com/items?itemName=savonet.vscode-liquidsoap) where code formatting, thus, come right out of the box with no
configuration needed!

![format](https://github.com/savonet/blog/assets/871060/0b94000e-dc97-43fb-a78c-f869a06eeba9)

We also wrote a [pre-commit wrapper](https://github.com/savonet/pre-commit-liquidsoap) for it that we are already using to format liquidsoap code in all git commits!

Please note that formatting proved to be the most challenging part of this work. There might still be corner cases with the formatter so feel free to report any issue and examples of weird formatting. Thanks!

### Next: language server

The next step would be to implement a [Language server](https://microsoft.github.io/language-server-protocol/) that could be used to provide the 
developer with in-editor information such as:
* Documentation about code values
* Suggested function variables
* Type of any given value
* etc.

However, this a **lot** of work and, for now, we want to bring the focus back to pending new features. Also, here too, being error tolerant might prove
challenging. We can definitely get a lot of information from a script that can be fully parsed and typed but, what do we do when it has partial errors?

It seems that the `tree-sitter` grammar might prove very useful for this as it is really good at getting a decent AST out of partially broken code and
has a programmatic API to walk through the resulting tree.

### TL;DR

Let's talk about how to use all this stuff now!

#### VScode

This is the easiest one! Just install the [savonet.vscode-liquidsoap](https://marketplace.visualstudio.com/items?itemName=savonet.vscode-liquidsoap) extension. And voila!

#### neovim

Here's a config that works currently for syntax highlighting with `neovim`:

```shell
$ cat ~/.config/nvim/init.vim
call plug#begin()
Plug 'nvim-treesitter/nvim-treesitter'
" Replace with mhartington/formatter.nvim when https://github.com/mhartington/formatter.nvim/pull/296
" has merged
Plug 'toots/formatter.nvim'
call plug#end()

lua require("config/tree-sitter")
lua require("config/formatter")
```

Then:
```shell
$ cat ~/.config/nvim/lua/config/tree-sitter.lua
require'nvim-treesitter.configs'.setup {
  ensure_installed = { "liquidsoap" },
  highlight = {
    enable = true
  }
}
```
And:
```shell
cat ~/.config/nvim/lua/config/formatter.lua
require("formatter").setup {
  logging = true,
  log_level = vim.log.levels.DEBUG,
  filetype = {
    liquidsoap = {
      require("formatter.filetypes.liquidsoap").liquidsoap_prettier
    }
  }
}
```

Also, note that the filetype for `liquidsoap` was only added in `vim` and `neovim` as part of this
project so, by the time you are reading this, it may or may not be supported out of the box. If not, you can add this:

```shell
$ cat ~/.config/nvim/ftdetect/liq.vim
autocmd BufNewFile,BufRead *.liq set filetype=liquidsoap
```

#### Others?

If you are using another code editor, feel free to send us the configuration you use with these tools! Eventually, we want to
compile all these instructions and add them to the public documentation!

Happy liquidsoap hacking! 
