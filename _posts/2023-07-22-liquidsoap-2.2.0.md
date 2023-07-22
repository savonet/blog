---
layout: post
title: Liquidsoap 2.2.0 is out! 🎉
---

We are delighted to announce the release of **Liquidsoap 2.2.0**! It is now available on [our release page](https://github.com/savonet/liquidsoap/releases/tag/v2.2.0)
and should be available [via opam](https://opam.ocaml.org/packages/liquidsoap) shortly!

This release comes almost 4 months after the last stable release from the `2.1.x` release cycle and 14 months (!) after forking
the `2.2.x` release branch! It includes some exciting changes in track muxing/demuxing, HLS, sound processing and more. 
See below for a detailed list!

## ✨ New features

Here are the highlights:

### 🎛️ Multitrack

This is by far the biggest change in this relase! This brings the ability to demux and remux tracks inside sources, making it possible
to:
* Encode video with multiple audio tracks
* Create audio-only and audio/video streams from the same content, for instance a regular audio stream and one with the studio's video.
* Drop or specify which metadata or track marks track should be used.
* Apply specific audio effect or encoding to different tracks

And much more! The full documentation is [here](https://www.liquidsoap.info/doc-2.2.0/multitrack.html). We plan on expanding this
support in the future in particular to allow track selection based on language, encoded content etc.

### 🏷️ HLS metadata

At last! We now support metadata in HLS streams using a timed ID3 stream for `mpegts` container and plain ID3v2 tags for 
`adts`, `mp3`, `ac3` and `eac3` formats. There is currently no support for metadata with `mp4` containers.

This feature is **enabled by default** so you might want to check if it impacts your listeners before pushing it 
to production. It can be turned off by setting `id3` to false on your HLS streams.

Full documentation is [here](https://www.liquidsoap.info/doc-2.2.0/hls_output.html#metadata).

### 🎨 Colored logs

Small change but not the least important! Logs are now colored by default when printed on the console. This finally makes it possible
to read logs with high level of details!

We are aware of the need for more developer tooling and quality of life improvements! In the next release cycle, we hope to work on code
formatting, highlighting and more!

### 🕸️ New HTTP API

Interacting with your scripts is essential and, for this, web interfaces and APIs are really useful. In order to make
our HTTP server easier to use, we wrote a new web API that is very close to node express' API and should be fairly easy to
use! The documentation is [here](https://www.liquidsoap.info/doc-dev/harbor_http.html#nodeexpress-api)

These changes also included a revamping of our SSL support which is now modular and with a new TLS optional support!

### 🎚️ Native stereotool support

While commited to open-source through and through, we also do want to meet our users where they are. To this end, it
seems that a lof of them want to use the proprietary stereotool audio processing. Up until this version, the only option
was via the external command line encoder and this was not satisfactory. 

With this release, it is now possible to use the shared library distributed by the author, which provides support for 
an new `stereotool` internal operator that is much easier to integrate. See the documentation [here](https://www.liquidsoap.info/doc-dev/stereotool.html).

### 📟 Records enhancements

As part of the language changes requred for multitrack, we now support the following operations on records:

Record spread:
```liquidsoap
let {foo, bar, ...rest} = someRecord

let otherRecord = { bla = "blo", ...someRecord }
```

Additionally, we now support optional record methods, for instance:

```liquidsoap
def f(x) =
  if x?.foo == null() then
    print("x does not have method foo")
  else
    print("x has method foo")
  end
end
```

### 🪢 Support for YAML parsing/rendering

Following the recent [JSON parsing](https://www.liquidsoap.info/doc-2.2.0/json.html) feature, we now support [YAML parsing](https://www.liquidsoap.info/doc-2.2.0/yaml.html)
in a very similar was as json.

### 🔮 Memory optimization

While we are aware that memory consumption with this release may have increased a bit due to on-going changes, we have done our best to introduce more
ways to control it and understand its usage.

In particular, we now support the alternative [jemalloc]() memory allocator, enabled in all our release assets and configurable via the internal settings.

We also introduced two new audio content formats, `pcm_s16` and `pcm_f32` that can be used to store audio
internally as, resp., 16-bit signed integers or 32-bit floating point numbers. Our default internal format being OCaml's
native 64-bit floating point numbers.

We also added a new `track.audio.defer` operator that can be used to buffer large amount of audio data without impacting performances.

You can read more about memory utilization in liquidsoap [here](https://www.liquidsoap.info/doc-dev/memory.html).

### 🐪 Switch to `dune` and javascript runtime

While perhaps more exciting to developers, the project has now fully moved to the OCaml `dune` builder. This 
provides an extra level of flexibility, In particular, we were able to extract the code that is specific to the
liquidsoap language, that is everything that pertains to parsing/evaluating/type checking without the streaming and
system specific operators and export it as an [online playground](https://www.liquidsoap.info/try/). We're not sure yet
what we'll do with it. It might be possible, for instance, to write a javascript backend to use liquidsoap scripts 
with the [Web media APIs](https://developer.mozilla.org/en-US/docs/Web/Media)!

## 🕵️ Versioning and release assets

For a little over a year now, we have switched to _rolling release cycles_ with maintenance and bugfixes applying
only to the current release cycle. Regular releases are tagged `vX.Y.Z` (for instance `v2.2.0`) on github and docker while on-going releases are tagged
`rolling-release-vX.Y.Z`.

When an initial release, for instance `2.2.0`, is being worked on, bugfixes and user issues were being addressed for users using the `2.1.x`
releases. While we would like to extend support, this is the best that we can do with our limited resources!

At any given time, the `rolling-release-vX.Y.Z` denotes the released being worked on. For stable releases branches, this would be for instance, 
`rolling-release-v2.2.1` after release `v2.2.0`. For a yet-to-be released initial version, this would be for instance `rolling-release-v2.3.x`.
We try our best to make those releases as bug-free as possible. Using one of them to test your production script also guarantees the fastest response
to bugs and issues!

For release assets, we try to maintain two packages for debian and ubuntu distributions, one with the latest LTS or stable and one with a recent
release. The new `minimal` assets are, as the name suggests, _minimal_ builds. They contain a limited set of features and standard library operators.
Minimal builds are intended for most production run and should limit the risk for issues such as segfault and etc. If your script can run with it,
we recommend it over the fully featured builds. 

For each release asset, you can consult the associated `.config` file to see which features are enabled.

Docker release images are located at: `savonet/liquidsoap:v2.2.0`. The release tag may be updated if needed. You can use git sha-based images to pick
a fixed build, e.g. `savonet/liquidsoap:<sha>`

Lastly, we may update the list of release assets on the github release page. If you are looking for permanent release asset links make sure to checkout
[savonet/liquidsoap-release-assets](https://github.com/savonet/liquidsoap-release-assets).

## 🧮 Migration guide

We listed most of the migration issues you might run into on [this page](https://www.liquidsoap.info/doc-2.2.0/migrating.html). The detailed changelog
below may also help.

As a reminder, we strongly recommend to test your script in a stagging environment, even between minor releases, to make sure that
everything is working correctly before pushing a new liquidsoap version to production!

## 📖 Changelog

The full shebang! 

### 2.2.0 (2023-07-21)

New:

- Added support for less memory hungry audio formats, namely
  `pcm_s16` and `pcm_f32` (#3008)
- Added support for native osc library (#2426, #2480).
- SRT: added support for passphrase, pbkeylen, streamid,
  added native type for srt sockets with methods, moved stats
  to socket methods, added `socket()` method on srt input/outputs
  (#2556)
- HLS: Added support for ID3 in-stream metadat (#3154) and
  custom tags (#2898).
- Added support for FLAC metadata (#2952)
- Added support for YAML parsing and rendering (#2855)
- Added support for the proprietary shared stereotool library (#2953)
- Added TLS support via `ocaml-tls` (#3074)
- Added `video.align`.
- Added `string.index`.
- Added support for ffmpeg decoder parameters to allow decoding of
  raw PCM stream and file (#3066)
- Added support for unit interactive variables: those call a handler when their
  value is set.
- Added support for id3v2 `v2.2.0` frames and pictures.
- Added `track.audio.defer` to be used to buffer large amount of audio data (#3136)
- Added `runtime.locale.force` to force the system's locale (#3231)
- Added support for customizable, optimized `jemalloc` memory allocator (#3170)
- Added `source.drop` to animate a source as fast as possible..
- Added in house replaygain computation:
  - `source.replaygain.compute` to compute replaygain of a source
  - `file.replaygain` to compute the replaygain of a file
- Added support for ImageLib to decode images.
- Added support for completion in emacs based on company (#2652).
- Added syntactic sugar for record spread: `let {foo, gni, ..y} = x`
  and `y = { foo = 123, gni = "aabb", ...x}` (#2737)
- Added `file.{copy, move}` (#2771)
- Detect functions defining multiple arguments with the same label (#2823).
- Added `null.map`.
- References of type `'a` are now objects of type `(()->'a).{set : ('a) -> unit}`. This means that you should use `x()` instead of `!x` in order to get
  the value of a reference. Setting a reference can be done both by `x.set(v)`
  and `x := v`, which is still supported as a notation (#2881).
- Added `ref.make` and `ref.map`.
- Added `video.board`, `video.graph`, `video.info` (#2886).
- Added the `pico2wave` protocol in order to perform speech synthesis using
  [Pico TTS](https://github.com/naggety/picotts) (#2934).
- Added `settings.protocol.gtts.lang` to be able to select `gtts`' language,
  added `settings.protocol.gtts.options` to be able to add any other option (#3182)
- Added `settings.protocol.pico2wave.lang` to be able to select `pico2wav` language (#3182)
- Added `"metadata_url"` to the default list of exported metadata (#2946)
- Added log colors!
- Added `list.filter_map` and `list.flatten`.
- Added `medialib` in order to store metadata of files in a folder and query
  them (#3115).
- Added `--unsafe` option (#3113). This makes the startup much faster but
  disables some guarantees (and might even make the script crash...).
- Added `string.split.first` (#3146).
- Added `string.getter.single` (#3125).

Changed:

- Switched to `dune` for building the binary and libraries.
- Changed `cry` to be a required dependency.
- Changed default character encoding in `output.harbor`, `output.icecast`
  `output.shoutcast` to `UTF-8` (#2704)
- BREAKING: all `timeout` settings and parameters are now `float` values
  and in seconds (#2809)
- BREAKING: in `output.{shoutcast,icecast}`:
  - Old `icy_metadata` renamed to `send_icy_metadata` and changed to a nullable `bool`. `null` means guess.
  - New `icy_metadata` now returns a list of metadata to send with ICY updates.
  - Added `icy_song` argument to generate default `"song"` metadata for ICY updates. Defaults
    to `<artist> - <title>` when available, otherwise `artist` or `title` if available, otherwise
    `null`, meaning don't add the metadata.
  - Cleanup, removed parameters that were irrelevant to each operator, i.e. `icy_id` in `output.icecast` and etc.
  - Make `mount` mandatory and `name` nullable. Use `mount` as `name` when `name` is `null`.
- `reopen_on_error` and `reopen_on_metadata` in `output.file` and related operators are now callbacks to
  allow dynamic handling.
- Added `reopen` method to `output.file`.
- Added support for a Javascript build an interpreter.
- Removed support for `%define` variables, superseded by support for actual
  variables in encoders.
- Cancel pending append when skipping current track on `append` source.
- Errors now report proper stack trace via their `trace` method, making it
  possible to programmatically point to file, line and character offsets
  of each step in the error call trace (#2712)
- Reimplemented `harbor` http handler API to be more flexible. Added a new
  node/express-like registration and middleware API (#2599).
- Switched default persistence for cross and fade-related overrides
  to follow documented behavior. By default, `"liq_fade_out"`, `"liq_fade_skip"`,
  `"liq_fade_in"`, `"liq_cross_duration"` and `"liq_fade_type"` now all reset on
  new tracks. Use `persist_overrides` to revert to previous behavior
  (`persist_override` for `cross`/`crossfade`) (#2488).
- Allow running as root by default when docker container can be detected using
  the presence of a `/.dockerenv` file.
- `id3v2` argument of `%mp3` encoder changed to `"none"` or version number to allow
  to choose the metadata version. `true` is still accepted and defaults to version
  `3`. Switched to our internal implementation so that it does not require `taglib`
  anymore.
- Moved HLS outputs stream info as optional methods on their respective encoder.
- Changed `self_sync` in `input.ffmpeg` to be a boolean getter, changed `self_sync`
  in `input.http` to be a nullable boolean getter. Set `self_sync` to `true` in
  `input.http` when an icecast or shoutcast server can be detected.
- Add `sorted` option to `file.ls`.
- Add `buffer_length` method to `input.external.rawaudio` and
  `input.external.wav` (#2612).
- Added full `OCaml` backtrace as `trace` to runtime errors returned from OCaml code.
- Removed confusing `let json.stringify` in favor of `json.stringify()`.
- Font, font size and colors are now getters for text operators (`video.text`,
  `video.add_text`, etc.) (#2623).
- Add `on_cycle` option to `video.add_text` to register a handler when cycling
  (#2621).
- Renamed `{get,set}env` into `environment.{get,set}`
- Renamed `add_decoder`, `add_oblivious_decoder` and `add_metadata_resolver`
  into, respectively, `decoder.add`, `decoder.oblivious.add`, `decoder.metadata.add`
- Deprecated `get_mime`, added `file.mime.libmagic` and `file.mime.cli`, made
  `file.mime` try `file.mime.libmagic` if present and `file.mime.cli` otherwise,
  changed eturned value when no mime was found to `null()`.
- Return a nullable float in `request.duration`.
- Removed `--list-plugins-json` and `--list-plugins-xml` options.
- Added `--list-functions-json` option.
- Removed built-in use of `strftime` conversions in output filenames, replaced
  by an explicit call to `time.string` (#2593)
- Added nullable default to `{int,float,bool}_of_string` conversion functions, raise
  an exception if conversion fails and no default is given.
- Deprecated `string_of` in favor of `string` (#2700).
- Deprecated `string_of_float` in favor of `string.float` (#2700).
- Added `settings.protocol.youtube_dl.timeout` to specify timeout when using
  `youtube-dl` protocol (#2827). Use `yt-dlp` as default binary for the
  protocol.
- The `sleeper` operator is now scripted (#2899).
- Reworked remote request file extension resolution (#2947)
- REMOVED `osx-secure-transport`. Doubt it was ever used, API deprecated
  upstream (#3067)
- Renamed `rectangle` to `add_rectangle`, and similarly for `line`.

Fixed:

- The randomization function `list.shuffle` used in `playlist` was incorrect and
  could lead to incorrectly randomized playlists (#2507, #2500).
- Fixed srt output in listener mode to allow more than one listener at a time and
  prevent listening socket from being re-created on listener disconnection (#2556)
- Fixed race condition when switching `input.ffmpeg`-based urls (#2956)
- Fixed deadlock in `%external` encoder (#3029)
- Fixed crash in encoders due to concurrent access (#3064)
- Fixed long-term connection issues with SSL (#3067)

