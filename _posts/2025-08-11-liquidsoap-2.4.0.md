---
layout: post
title: Liquidsoap 2.4.0 — The people's release! 🧑‍🏭
---

# Liquidsoap 2.4.0 — The people's release! 🧑‍🏭

_⚠️ Note: This blog post was written with the help of a machine.. Because why not! But this sentence and everything else was reviewed by a human. Of course!..._

Liquidsoap 2.4.0 is almost here! This one is all about making your life easier — smoothing out rough edges, clearing up long-standing points of confusion, and giving you more tools to write clean, maintainable scripts.

You’ll see some changes that require a small update to your scripts — but each of them is here to solve problems that have tripped people up for years. Think of it as a little spring cleaning for your streaming setup. 🧹

Let’s walk through the most important changes.

## 🪝 Callbacks: Clearer, Safer, and All in One Place

Callbacks are now **standardized** and moved to a **dedicated section in the documentation**. No more hunting around wondering where each one lives or guessing how it’s supposed to work.

The big change: most callbacks are now **registered as methods** on your source or output, instead of as constructor arguments. This makes your code more modular — you can build your source, then wire up callbacks later when you have the data you need.

```liquidsoap
s = playlist("music.m3u")
s.on_metadata(synchronous=false, fun (m) -> log("New track: #{m["title"]}"))
```

Notice the `synchronous` parameter? It’s **required** now.

* `synchronous=true` → runs asynchronously in a separate task (safe if your callback might take time)
* `synchronous=false` → runs inside the main streaming loop (fast callbacks only!)

In the past, many users accidentally slowed down their whole stream because a callback took too long. Now you’re forced to think about it — and do the right thing. ✅

## ⚠️ Warnings When Overwriting Top-Level Variables

Ever accidentally do this?

```liquidsoap
request = ...
# Later...
request.create(...)  # 💥 Cryptic type error!
```

It was far too easy to overwrite important built-in modules (like `request`) and end up with confusing type errors. Now Liquidsoap will **warn you** before you shoot yourself in the foot. A small safeguard, big peace of mind.

## 🚫 No More `null()` Headaches

Previously, `null` was a function — you had to call `null()` to get a null value, or `null(value)` to wrap something. This confused a lot of people (and the typechecker wasn’t helping).

Now, `null` can be used directly:

```liquidsoap
my_var = null
```

Function form still works if you need it:

```liquidsoap
my_var = null("some value")  # Explicit nullable
```

Cleaner syntax, fewer “Wait, why isn’t this working?” moments.

## ✨ Destructuring & Enhanced Labelled Arguments

Function arguments just got way more flexible. You can now **destructure** right in the parameter list:

```liquidsoap
def print_data({ title, artist }) =
  log("Now playing: #{artist} — #{title}")
end
```

And with **enhanced labelled arguments**, you can keep APIs clear without shadowing important names:

```liquidsoap
def handle_track(~request:r) =
  log("Request URI: #{request.uri(r)}")
end
```

No more awkward renaming or risking collisions with top-level modules.

## ⏰ Cron Support for Scheduling Tasks

You asked for it: Liquidsoap now understands **cron** syntax. Schedule actions at precise times — just like your system cron job.

```liquidsoap
cron.add("0 * * * *", fun () ->
  q.push(request.create("hourly_jingle.mp3"))
)
```

Want something to happen exactly on the hour? Easy.
Need a special track every day at 5 PM? Done.
This is going to make time-based automation much more familiar and powerful.

## 🛠 Other Notable Changes

* **LUFS-based loudness correction** per track 🎚 — now unified with ReplayGain via `normalize_track_gain`.
* **`liquidsoap.script.path`** variable — find out where your running script lives.
* **Better memory usage** — initial compaction now on by default.
* **Improved source & clock naming** for clearer logs.
* Removed old, unmaintained **ImageLib** support.
* **New external decoder API** for safer, easier file-to-file decoding.
* Deprecated `insert_metadata` operator in favor of a default `insert_metadata` method.

## 🐛 Important Fixes

A few of the most impactful bug fixes:

* Autocue’s `start_next` now behaves as expected (but may slightly change existing output).
* Fixed crashes with **SRT on Windows**.
* Memory leak in **FFmpeg inline encoder** is gone.
* More reliable playlist reloads (no race conditions).
* No more mysterious errors for scripts in paths with non-ASCII characters.

## 📄 Migration Cheatsheet

If you’re upgrading an existing script, here are the key before/after changes you might need to make.

### 1. **Callbacks: moved to methods, `synchronize` required**

**Before:**

```liquidsoap
output.icecast(%vorbis, host="...", port=8000, password="...",
               mount="stream.ogg", on_connect=fun () -> log("Connected!"))
```

**After:**

```liquidsoap
o = output.icecast(%vorbis, host="...", port=8000, password="...",
                   mount="stream.ogg")
o.on_connect(synchronous=false, fun () -> log("Connected!"))
```

### 2. **`null` can be used directly**

**Before:**

```liquidsoap
x = null()
```

**After:**

```liquidsoap
x = null
```

### 3. **Destructuring & labelled arguments**

**Before:**

```liquidsoap
def handler(m) =
  let { title, artist } = m
  log("#{artist} — #{title}")
end
```

**After:**

```liquidsoap
def handler({ title, artist }) =
  log("#{artist} — #{title}")
```

**Renaming labelled arguments:**

```liquidsoap
def handle_track(~request:r) =
  log(request.uri(r))
end
```

### 4. **Top-level overwrite warnings**

No script changes needed — but if you see:

```
Warning: You are overwriting the top-level variable 'request'.
```

…consider renaming your variable.

### 5. **`insert_metadata` now a method**

**Before:**

```liquidsoap
s = insert_metadata(s)
s.insert_metadata([("title", "My Song")])
```

**After:**

```liquidsoap
s.insert_metadata([("title", "My Song")])
```

## Wrapping Up

Liquidsoap 2.4.0 may not be the flashiest release, but it’s one of the most **user-focused** in recent memory. By clearing up long-standing points of confusion, standardizing APIs, and adding features like cron support, we’ve made it easier than ever to write scripts that are both powerful and maintainable.

As always, check the [migration notes](https://www.liquidsoap.info/doc-dev/migrating.html) before upgrading — especially for callback changes — and enjoy a smoother scripting experience. 🚀
