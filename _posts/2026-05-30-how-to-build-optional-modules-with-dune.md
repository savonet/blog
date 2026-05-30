---
layout: post
title: How to Build Optional Modules with Dune
---

Many dune-based projects have optional dependencies: a library that is only built when a particular system package is present, a set of executables that only make sense when an optional backend is available, etc.. In such situtions, how do you structure the build so that those components are silently skipped during normal development, while still failing loudly when someone explicitly tries to install a package that cannot be satisfied?

Dune makes many things easy, but optional dependencies driving the availability of libraries and executables at build time have historically been one of its rougher edges.

Dune 3.15 introduced support for `%{read:file}` inside `(enabled_if ...)` expressions on `(library ...)` stanzas, which finally made it possible to gate entire library stanzas on the result of a configure-time check. However, using this feature on libraries that belong to a named package triggered a spurious dependency cycle until [dune 3.23](https://github.com/ocaml/dune/releases/tag/3.23.0), where [PR #13833](https://github.com/ocaml/dune/pull/13833) fixed the underlying bug in how `enabled_if` was evaluated for packaged libraries.

With those pieces in place, here is the full set of techniques needed to get everything working cleanly. We apply them to the [ocaml-xiph](https://github.com/savonet/ocaml-xiph) repository, where multiple optional ogg-related packages — vorbis, flac, speex, opus, theora — are built together but some of the underlying C libraries might not be available at build time:

- `dune build` silently skips libraries whose C dependencies are missing
- `dune build -p speex` (or any individual package) fails loudly if the C library is not found
- Example executables are only compiled when their library is available

---

## Step 1: A shared detection script

The first step is a single shared `detect/detect.ml` that handles all availability checks:

```ocaml
let write_sexp file lines =
  let oc = open_out file in
  output_string oc "(";
  output_string oc (String.concat " " lines);
  output_string oc ")";
  close_out oc

let write_bool file value =
  let oc = open_out file in
  output_string oc (if value then "true" else "false");
  close_out oc

let () =
  match Array.to_list Sys.argv |> List.tl with
    | name :: packages ->
        let open Configurator.V1 in
        let c = create "xiph-detect" in
        let available, cflags, libs =
          match Pkg_config.get c with
            | None -> (false, [], [])
            | Some pc -> (
                match Pkg_config.query pc ~package:(String.concat " " packages) with
                  | None -> (false, [], [])
                  | Some conf -> (true, conf.cflags, conf.libs))
        in
        write_bool (name ^ "_available") available;
        write_sexp (name ^ "_c_flags.sexp") cflags;
        write_sexp (name ^ "_c_library_flags.sexp") libs
    | _ ->
        Printf.eprintf "Usage: detect <name> <package...>\n";
        exit 1
```

It takes a name and one or more pkg-config package names, queries pkg-config, and writes three output files:

- `{name}_available` — `true` or `false`
- `{name}_c_flags.sexp` — compiler flags as a sexp list
- `{name}_c_library_flags.sexp` — linker flags as a sexp list

All libraries are detected from a single `detect/dune` file:

```dune
(executables
 (names detect check)
 (libraries dune-configurator))

(rule
 (targets ogg_available ogg_c_flags.sexp ogg_c_library_flags.sexp)
 (action (run ./detect.exe ogg ogg)))

(rule
 (targets speex_available speex_c_flags.sexp speex_c_library_flags.sexp)
 (action (run ./detect.exe speex speex ogg)))

; ... and so on for vorbis, opus, flac, theora
```

Libraries that need endianness detection (flac, opus) keep a minimal `config/discover.ml` that only generates the endianness header, separate from the pkg-config detection.

---

## Step 2: Conditionally enabling library stanzas

With `{name}_available` written as a file, we can use dune's `(enabled_if ...)` to gate each library stanza:

```dune
(library
 (name speex)
 (public_name speex)
 (enabled_if (= %{read:../detect/speex_available} true))
 (libraries ogg)
 (foreign_stubs
  (language c)
  (names speex_stubs)
  (flags (:include ../detect/speex_c_flags.sexp)))
 (c_library_flags
  (:include ../detect/speex_c_library_flags.sexp)))
```

The `%{read:file}` variable reads a file's content as a string at build time. Support for it in `(enabled_if ...)` on `(library ...)` stanzas was added in dune 3.15, but using it on a library that belongs to a named package triggered a spurious dependency cycle until **dune 3.23**, where [PR #13833](https://github.com/ocaml/dune/pull/13833) fixed the underlying bug. In practice, **dune ≥ 3.23** is required for this to work correctly.

Decoder sub-libraries that depend on the base library get `(optional)` instead. Dune will automatically skip them when their dependency is not built:

```dune
(library
 (name speex_decoder)
 (public_name speex.decoder)
 (optional)
 (libraries ogg.decoder speex)
 (modules speex_decoder))
```

---

## Step 3: `(allow_empty)` for graceful degradation

With `(enabled_if ...)` in place, if speex is not available, no stanzas in the `speex` package are active. Dune will then refuse to build, complaining:

```
Error: The package speex does not have any user defined stanzas attached to it.
```

Adding `(allow_empty)` to the package definition in `dune-project` silences this:

```dune
(package
 (name speex)
 (allow_empty)
 ...)
```

Now `dune build` silently skips speex when the C library is absent.

---

## Step 4: The `(enabled_if)` bug for executables

While `(enabled_if (= %{read:...} ...))` works for `(library ...)` stanzas since dune 3.15, it does **not** work for `(executable ...)` stanzas even in dune 3.23 ([issue #14789](https://github.com/ocaml/dune/issues/14789)):

```
Error: Only architecture, system, model, os_type, ccomp_type, profile,
ocaml_version, context_name, arch_sixtyfour and env variables are allowed in
this 'enabled_if' field. Please upgrade your dune language to at least 3.15.
```

This is a dune bug — the allowlist for `(enabled_if ...)` is not applied consistently across stanza types.

### Workaround: dynamic dune includes

The solution is to dynamically generate a dune include file at build time that only contains the executable stanzas when the library is available.

Each library gets an `examples/gen/` directory with:

**`has_speex.yes.ml`** and **`has_speex.no.ml`**:
```ocaml
let available = true  (* or false *)
```

**`gen.ml`** — emits dune stanzas conditionally:
```ocaml
let executable name modules libraries =
  Printf.printf "(executable\n (name %s)\n (modules %s)\n (libraries %s))\n\n"
    name modules (String.concat " " libraries)

let () =
  if Has_speex.available then begin
    executable "speex2wav" "speex2wav" ["speex"; "speex.decoder"; "ogg.decoder"];
    executable "wav2speex" "wav2speex" ["speex"];
    print_string {|(rule (alias runtest) ...)|}
  end
```

**`gen/dune`** — uses `(select ...)` to detect library availability at build time, then generates the include file:
```dune
(executable
 (name gen)
 (modules gen has_speex)
 (libraries
  (select has_speex.ml from
   (speex -> has_speex.yes.ml)
   (-> has_speex.no.ml))))

(rule
 (target examples.inc)
 (action
  (with-stdout-to examples.inc (run ./gen.exe))))
```

The `(select ...)` mechanism picks the `.yes.ml` or `.no.ml` source file based on whether the library is available in the build graph — this works correctly even for libraries in the same workspace that are disabled via `(enabled_if ...)`.

The example source files live in `examples/bin/` (not `examples/` directly), and `examples/bin/dune` contains just:
```dune
(dynamic_include ../gen/examples.inc)
```

> **Important**: the `bin/` subdirectory is necessary. If the `(dynamic_include ...)` and the `gen/` directory are siblings within the *same* parent directory that dune is computing, you get a dependency cycle. Moving the source files into `bin/` breaks the cycle.

---

## Step 5: Strict validation for `dune build -p`

With `(allow_empty)`, `dune build -p speex` silently succeeds when speex is not available — which is unhelpful if someone is explicitly trying to install the package.

The fix uses two dune primitives together: `(alias install)` and `(with-stdin-from ...)`.

`(alias install)` rules are built when running `dune build -p speex` (or `dune build @install`), but **not** during plain `dune build`. This makes them the right place for strict validation.

We add a small `detect/check.ml`:

```ocaml
let () =
  let name = Sys.argv.(1) in
  let available = String.trim (input_line stdin) in
  if available <> "true" then (
    Printf.eprintf "Error: %s C library not found via pkg-config.\n" name;
    exit 1)
```

And in each library's dune file:

```dune
(rule
 (alias install)
 (package speex)
 (action
  (with-stdin-from
   ../detect/speex_available
   (run ../detect/check.exe speex))))
```

`(with-stdin-from file ...)` pipes the content of `speex_available` into `check.exe` via stdin. If the content is `false`, the build fails with a clear error message.

Result:
```
$ dune build -p speex
Error: speex C library not found via pkg-config.
```

While `dune build` continues to pass silently.

---

## Summary

| Goal | Mechanism |
| - | - |
| Detect C library availability | Shared `detect.exe` using `dune-configurator` + pkg-config |
| Disable library stanzas when unavailable | `(enabled_if (= %{read:...} true))` (dune ≥ 3.23) |
| Suppress "empty package" error | `(allow_empty)` in `dune-project` |
| Conditionally compile example executables | Dynamic dune include via `(select ...)` + `gen.exe` + `(dynamic_include ...)` |
| Fail `dune build -p pkg` when C lib missing | `(alias install)` rule + `(with-stdin-from ...)` + `check.exe` |

The executable `(enabled_if ...)` limitation is a dune bug, tracked at [issue #14789](https://github.com/ocaml/dune/issues/14789). Until it is fixed, the dynamic include workaround is the recommended approach.
