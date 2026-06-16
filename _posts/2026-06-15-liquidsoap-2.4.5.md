---
layout: post
title: "Liquidsoap 2.4.5: A Deep Dive into Streaming Performance"
---

Liquidsoap 2.4.5 is out! This is a maintenance release in the 2.4.x series,
bringing a handful of bug fixes, a couple of small new features, and, most
importantly, a focused round of performance work that cuts CPU usage by 10-25%
across the board on real workloads.

You can grab it and read the full changelog at
<https://github.com/savonet/liquidsoap/releases/tag/v2.4.5>.

We recommend that anyone running any 2.4.x release upgrades to 2.4.5 when
possible. As always, please test in a staging environment before deploying to
production.

This post takes a tour of what was optimized and, more importantly, *why* those
places were slow and what the fixes teach us about building real-time streaming
systems in general.

---

## What changed (quick summary)

<table>
  <thead>
    <tr><th>Area</th><th>Change</th></tr>
  </thead>
  <tbody>
    <tr><td>WeakQueue</td><td>Geometric-growth backing array + RW-lock</td></tr>
    <tr><td>Content-type dispatch</td><td>O(1) array lookup instead of queue scan</td></tr>
    <tr><td>Chunk length</td><td>Cached on construction; never recomputed</td></tr>
    <tr><td>Chunk lift</td><td>Length pre-computed at lift time</td></tr>
    <tr><td><code>content_length</code> / blit</td><td>Hot-path tightening</td></tr>
    <tr><td>Sync-source propagation</td><td>Push-based callbacks, O(1) per tick</td></tr>
    <tr><td>Comparison functions</td><td>Direct <code>Int</code> comparisons in hot paths</td></tr>
  </tbody>
</table>

## Benchmark results

To put numbers on these changes we ran a head-to-head comparison between
2.4.4 and 2.4.5 using six representative scripts. Each script ran at real-time
clock speed (normal streaming pace) for ten seconds while we measured CPU
seconds consumed. Lower CPU% means the same audio work costs less processor
time.

```
Benchmark             v2.4.4     v2.4.5     Change
----------------------------------------------------------------
simple                 10.5%      8.4%     -19.8%   baseline per-cycle cost
multi-output-10        11.6%      9.0%     -22.5%   one source to 10 outputs
audio-chunks           10.5%      8.9%     -15.0%   real audio + switch + amplify
add-8                  14.1%     12.7%      -9.9%   8 fan-in sources
large-add-32           24.1%     23.0%      -4.6%   32 sources, clock propagation
chain-20               89.8%     90.1%      +0.4%   20 deep amplify layers
```

The `chain-20` scenario is essentially flat, which makes sense: stacking twenty
`amplify` operators on one playlist source does not exercise any of the paths
that were changed. Everything else shows a real, measurable improvement.

---

## Background: how Liquidsoap represents audio data

Before diving into individual fixes it helps to understand how Liquidsoap
stores audio internally, because several optimizations hinge on the same idea.

### Frames and ticks

Liquidsoap processes audio in *frames*. A frame is a fixed-duration chunk of
data, by default about 23 ms (1024 stereo PCM samples at 44.1 kHz). The
streaming loop calls each active output once per frame; the output asks its
source for a frame, the source asks *its* source, and so on up the source graph
until something (a decoder, a generator, a hardware input) actually produces
samples. This recursive pull is called a *tick*.

### The chunk list

Physically, a frame is not a flat contiguous buffer. It is a list of *chunks*:

```ocaml
type 'a chunk = { data : 'a; offset : int; length : int option }

type ('a, 'b) chunks = {
  params        : 'a;           (* encoding parameters, e.g. sample rate *)
  mutable chunks       : 'b chunk list;
  mutable total_length : int;   (* cached sum of chunk lengths *)
}
```

Each chunk is a slice `(data, offset, length)` into a backing array that
may be shared with other frames. This design avoids copying audio data when a
frame is split, sub-sliced, or passed through operators that do not modify the
content. An operator like `amplify` that *does* modify samples will eventually
call `consolidate_chunks`, which allocates one new buffer, blits all chunks
into it, and replaces the list with a single chunk pointing at the fresh buffer.

This is a classic rope / copy-on-write idiom: cheap structural manipulation in
the common case, one unavoidable allocation only when you actually need a flat
buffer.

---

## Optimization 1: Caching chunk lengths ([#5135](https://github.com/savonet/liquidsoap/pull/5135), [#5140](https://github.com/savonet/liquidsoap/pull/5140))

The `chunk` type has a `length : int option` field. `None` means "the chunk
runs to the end of the backing array, starting at `offset`." Computing the
actual length then requires calling `C.length data - offset`, a method
dispatch into the content module.

Before 2.4.5, that computation happened on every access to chunk length.
Because chunk-length queries appear inside the hot paths of `sub`, `truncate`,
`content_length`, and the blit loop, this added up quickly.

The fix has two parts.

**On lift** ([#5135](https://github.com/savonet/liquidsoap/pull/5135)): When a decoder or generator calls `lift_data` to wrap a
freshly produced buffer into a content chunk, the length is computed once and
stored as `Some len` immediately. No later caller ever needs to re-derive it
from the backing array.

**Total length cached** ([#5140](https://github.com/savonet/liquidsoap/pull/5140)): The `chunks` record has a `total_length`
field that is kept in sync with the chunk list. Functions like `is_empty` and
`length` at the content level now return `total_length` directly, a single
field read, instead of summing the chunk list.

Together these two changes mean the inner loops of `sub` and `truncate` always
see `Some len` and never call into content-module method dispatch mid-loop.

---

## Optimization 2: O(1) content-type dispatch ([#5136](https://github.com/savonet/liquidsoap/pull/5136))

Liquidsoap supports multiple content types: PCM stereo audio, S16 audio,
MIDI, video, timed metadata. All are registered dynamically at startup.
Operators inspect a frame's type to decide how to handle it. Before 2.4.5 this
inspection went through a `Queue` of parser functions:

```ocaml
(* old approach, simplified *)
let kind_parsers = Queue.create ()

let kind_of_string s =
  try
    Queue.iter
      (fun fn -> match fn s with Some k -> raise (Parsed_kind k) | None -> ())
      kind_parsers;
    raise Invalid
  with Parsed_kind k -> k
```

Dispatching to the right handler meant iterating through every registered
content type until one matched. For operations that run once at startup
(parsing a format string from a config file) this is fine. For operations that
appear inside the per-frame hot path (determining whether two buffers are
compatible, looking up how to blit one type of data) it becomes expensive.

The fix assigns each content type a small integer ID at registration time.
Handlers are stored in a fixed-size array, indexed by that ID:

```ocaml
let format_handler_fns : (format_content Unifier.t -> format_handler) array =
  Array.make 16 dummy_format_handler_fn

let get_format_handler { id; content } =
  Array.unsafe_get format_handler_fns id   (* O(1), no scan *)
```

`Array.unsafe_get` skips the bounds check (safe here because `id` is assigned
by our own registration code and can never exceed the array size). The result
is a direct function call instead of a sequential scan through a queue:
O(1) instead of O(n) where n is the number of registered content types.

The same pattern is applied to `kind_handler_fns` and `data_handlers`.

---

## Optimization 3: WeakQueue with geometric growth ([#5118](https://github.com/savonet/liquidsoap/pull/5118))

Several subsystems in Liquidsoap keep collections of *sources*: the clock's
active-source list, output registrations, watcher queues. Sources may be
garbage-collected at any time (a dynamic source that stops playing has no other
references and should be collected without manual bookkeeping), so these
collections use *weak references*: references that do not prevent GC and
silently become `None` after the object is collected.

OCaml's standard library provides `Weak` arrays for this purpose, but it does
not include a higher-level weak queue. Liquidsoap had a `WeakQueue` abstraction
backed by a weak array. The old implementation allocated the array at exactly
the right size to hold its current elements, which meant every `push` triggered
a full copy of the entire backing array into a freshly allocated one.

For an output with ten sources registered, that was ten copies per push. And
the `multi-output-10` benchmark has exactly this pattern: one source observed
by ten outputs, each of which registers itself in the source's watcher list
every time it starts.

The new implementation borrows the standard trick from dynamic arrays
(OCaml's `Buffer`, C++ `std::vector`, Java's `ArrayList`): when the backing
array is full, double its capacity instead of growing by exactly one. This
makes the amortised cost of `push` O(1):

```ocaml
(* slow path: only reached when the array is truly full *)
let live_count = count_live arr size 0 0 in
let new_capacity =
  if live_count + 1 <= capacity then capacity  (* dead slots can be reused *)
  else max 1 (capacity * 2)                    (* geometric growth *)
in
let new_arr = Weak.create new_capacity in
copy_live arr size new_arr 0 0;
Weak.set new_arr live_count (Some v);
Atomic.set q.s { arr = new_arr; size = live_count + 1 }
```

Note the additional subtlety: before growing geometrically, the slow path
first *compacts* the array by counting live entries. If some weak references
have become `None` since the last compaction (because their objects were
garbage-collected), those dead slots are reclaimed without any allocation. Only
when every slot is genuinely alive does capacity double.

The resulting -22.5% CPU drop for `multi-output-10` is the single largest
individual improvement in this release.

---

## Optimization 4: Push-based sync-source propagation ([#5133](https://github.com/savonet/liquidsoap/pull/5133))

This one requires a bit of background on what "sync source" means in Liquidsoap.

### What is a sync source?

A streaming system needs something to control *how fast* it produces data. In
Liquidsoap this is called a **sync source**: an operator that imposes its own
pace on the clock. Examples:

- A hardware audio input (`input.alsa`) blocks on the sound card's hardware
  timer. The clock runs exactly as fast as samples arrive.
- A network input (`input.srt`) paces itself based on packet timestamps.
- A file playlist, a tone generator, or `blank` have no external constraint:
  the CPU drives the clock as fast as it can (or the clock governor sleeps
  between ticks to maintain real-time speed in automatic mode).

Each source advertises whether it is a sync source through a `self_sync` method.
The clock needs to know if *any* of its sources is a sync source at any moment,
so that it can switch between self-paced and CPU-paced modes.

### The old approach: scan every tick

Before 2.4.5, the clock determined its sync status by walking its list of
active sources once per tick:

```
every tick:
    is_self_sync = false
    for each active_source:
        if active_source.self_sync:
            is_self_sync = true
            break
```

For a script with 32 sources (`large-add-32`), that is 32 method calls on
every frame, roughly 50 times per second, i.e. 1600 calls per second just to
ask "is anything self-syncing right now?"

### The new approach: push-based callbacks

The fix inverts the flow. Each source registers an `on_sync_source_change`
callback with its parent and with the clock when it wakes up. When a source's
sync state changes (because a playlist switches to an SRT input, for example),
it calls the registered callbacks immediately. The clock updates `is_self_sync`
in O(1) as a direct response to that push:

```ocaml
(* at source wake-up time, registered once *)
s#on_sync_source_change (fun ~old:_ new_sync_source ->
    _update_clock_sync_source ~clock x ~name ~stack new_sync_source)
```

```ocaml
(* inside the tick loop: now just a field read *)
_after_tick ~self_sync:x.is_self_sync x
```

Sync-source state changes happen rarely: typically at startup, when a source
wakes or sleeps, or when a dynamic source appears or disappears. Between those
events the clock reads a single mutable `bool` that was set by the last push.
No scan, no method dispatch, no iteration over sources.

The graph walk is not just reversed here: it is eliminated from the hot path
entirely. Sources push; the clock stores; the tick reads one field.

---

## Optimization 5: Direct `Int` comparisons in hot paths

OCaml's polymorphic `(=)` and `compare` operators are implemented in C and
handle every possible type: floats, strings, arbitrary records, cyclic
structures. The type checker cannot inline them away even when comparing plain
integers.

In streaming hot paths (format compatibility checks, tick counters,
content-type IDs) all comparisons are between integers. Replacing `(=)` with
`Int.(=)` (or `(==)` for physical equality) lets the compiler emit a single
machine instruction instead of a C function call.

This change is invisible in the source diff but shows up in the profiler as a
reduction in call overhead across the entire tick loop.

---

## Other changes in 2.4.5

Beyond the performance work, 2.4.5 also includes:

- `request.queue` gained `remove` and `remove_request_id` methods (and a
  matching telnet command) so that enqueued requests can be cancelled
  programmatically ([#5237](https://github.com/savonet/liquidsoap/pull/5237)).
- Improved error messages in playlist parsers, giving better context when a
  playlist file is malformed.
- Mime-type defaults for AIFF and WavPack, so `protocol.http` resolves URLs
  to the correct extension instead of the generic `.osb` fallback.
- Fixed a crash when an external input (`input.process`, `input.ffmpeg`) hits
  EOF ([#5139](https://github.com/savonet/liquidsoap/issues/5139)).
- Fixed `harbor.remove_http_handler` incorrectly discarding all handlers
  instead of just the one being removed.
- Fixed a crash in `crossfade`/`cross` when `source.skip` is called from a
  non-clock thread ([#5194](https://github.com/savonet/liquidsoap/issues/5194)).
- Fixed a memory leak in `Strings.Mutable`
  ([#5231](https://github.com/savonet/liquidsoap/pull/5231)).

---

## Takeaways

Looking across all these changes, a few themes emerge.

**Profile first, then pick the right data structure.** The WeakQueue was not a
known bottleneck until profiling under a many-output workload revealed that
`push` was allocating on every call. A one-line change (double instead of
add-one) collapsed the cost.

**Invert the graph walk when events are rare.** The sync-source scan looked
reasonable (one pass over active sources each tick) until you count: 50
ticks/second x 32 sources = 1600 method calls per second for a fact that
changes perhaps twice per session. Callbacks push that work to the rare change
events and eliminate it from the tick hot path entirely.

**Compute once, cache everywhere.** Chunk lengths, `total_length`, format
handler lookups: each was being recomputed on every frame by following a chain
of method calls or iterating a list. Storing the result at construction time
and reading a field later is almost always the right trade when the computation
is pure and the result is stable.

**Pay for features only when you use them.** Polymorphic comparisons and
watcher guards: every operator was paying a small fixed cost for capabilities
that the vast majority of scripts never needed. Making those costs conditional
on actual use compounds across hundreds of sources and millions of ticks.

None of these are exotic techniques. They are the ordinary tools of performance
engineering applied carefully to a hot path that runs fifty times per second
and must do so reliably for days or weeks at a time.
