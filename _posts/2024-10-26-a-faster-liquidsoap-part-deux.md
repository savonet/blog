---
layout: post
title: A Faster Liquidsoap (part 2)
---

_The memory part_

![Fun gif](https://github.com/user-attachments/assets/6e06ebb3-7e1e-4cd3-a546-919ca762b4e1)

## TL;DR

If you are lazy, here's the key information in this post:

**⚠️ Make sure to enable script caching or set `settings.init.compact_before_start` to `true` to optimize memory consumption! ⚠️**

Now, let's get to our in-depth stuff!

### Introduction

Now that we've explored the optimization of script loading in [the first part](../2024-06-13-a-faster-liquidsoap) of
this series, it's time to look at the memory side of things!

For reference, here's a memory consumption chart we presented before:

<table>
  <thead>
    <tr>
      <th>Version</th>
      <th>Memory consumption</th>
      <th>Startup time</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><code>1.3.3</code> (docker image: <code>debian:buster</code>)</td>
      <td><code>64MB</code></td>
      <td><code>0.091s</code></td>
    </tr>
    <tr>
      <td><code>1.4.3</code> (docker image: <code>savonet/liquidsoap:v1.4.3</code>)</td>
      <td><code>95MB</code></td>
      <td><code>0.163s</code></td>
    </tr>
    <tr>
      <td><code>2.2.5</code> (docker image: <code>savonet/liquidsoap:v2.2.5</code>)</td>
      <td><code>190MB</code></td>
      <td><code>3.879s</code></td>
    </tr>
    <tr>
      <td><code>2.3.x</code> (docker dev image from May 9, 2024)</td>
      <td><code>206MB</code></td>
      <td><code>5.942s</code></td>
    </tr>
  </tbody>
</table>

Memory consumption in Liquidsoap has been a topic for a while and one that, admittedly, we had not seriously tackled for
too long.

The `2.3.x` release was a great opportunity to catch up with this. It turned out that, with the new script caching, we
can get initial memory consumption close to the `1.3.x` levels!

But first, let's look at **how to check memory usage**. Because, well, it turns out that this isn't easy at all.

## The labyrinth of memory allocation

We've had a lot of discussions about how memory is allocated in Liquidsoap over the years.
[One of the most recent ones](https://github.com/savonet/liquidsoap/issues/4058) was a great opportunity to realize that
it is, in fact, very tricky to actually _measure_ how much memory a process is consuming.

Here's a rough rundown of how memory is allocated that might explain that a bit.

### Memory pages

Memory is organized into fixed-size chunks called _pages_. On Linux, a page is typically 4 KB, while on Apple Silicon,
it is usually 16 KB.

Each process is associated with a collection of memory pages that are assigned to it by the OS kernel. When the process
requests memory allocation, the OS looks for available memory on the currently allocated pages and, if there is not
enough, allocates more pages for the process.

Once a page has had some of its memory used by the process, it is considered _dirty_. Before a page can be reclaimed,
the process must free all the memory on that page.

![Paged Memory Illustration](https://github.com/user-attachments/assets/f617f88d-4a7c-4214-bb9d-6d57cfaf3bd5)

When a process requests `1024` bytes of memory, it may result in `4k` bytes being allocated instead. Similarly, if a
process releases `1024` bytes of memory, its effective memory usage may not decrease. This can happen if the page
containing that memory still has other sections in use.

### Shared memory

Not all memory used by a process belongs to it! Typically, when a process loads a dynamic library, the binary code from
that library is potentially shared across all processes using it.

Technically, this means that the binary code from the library is loaded in _shared memory pages_. The kernel can
associate these pages with multiple processes that load the same shared library.

On Linux, you can see the list of the shared dynamic libraries a process uses by calling `ldd`. On macOS, it is `otool`.
Here's an example with Liquidsoap:

```shell
% otool -L _build/default/src/bin/liquidsoap.exe                                                                                                                      18:48:21
_build/default/src/bin/liquidsoap.exe:
  /opt/homebrew/opt/libvorbis/lib/libvorbis.0.dylib (compatibility version 5.0.0, current version 5.9.0)
  /opt/homebrew/opt/libvorbis/lib/libvorbisfile.3.dylib (compatibility version 7.0.0, current version 7.8.0)
  /opt/homebrew/opt/libvorbis/lib/libvorbisenc.2.dylib (compatibility version 3.0.0, current version 3.12.0)
  /opt/homebrew/opt/theora/lib/libtheoraenc.1.dylib (compatibility version 3.0.0, current version 3.2.0)
  /opt/homebrew/opt/theora/lib/libtheoradec.1.dylib (compatibility version 3.0.0, current version 3.4.0)
  /opt/homebrew/opt/libogg/lib/libogg.0.dylib (compatibility version 0.0.0, current version 0.8.5)
  /usr/lib/libsqlite3.dylib (compatibility version 9.0.0, current version 351.4.0)
  /usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1345.120.2)
  /opt/homebrew/opt/openssl@3/lib/libssl.3.dylib (compatibility version 3.0.0, current version 3.0.0)
  /opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib (compatibility version 3.0.0, current version 3.0.0)
  /opt/homebrew/opt/srt/lib/libsrt.1.5.dylib (compatibility version 1.5.0, current version 1.5.3)
  /opt/homebrew/opt/speex/lib/libspeex.1.dylib (compatibility version 7.0.0, current version 7.2.0)
  /usr/lib/libc++.1.dylib (compatibility version 1.0.0, current version 1700.255.5)
  /opt/homebrew/opt/sound-touch/lib/libSoundTouch.1.dylib (compatibility version 2.0.0, current version 2.0.0)
  /opt/homebrew/opt/libshine/lib/libshine.3.dylib (compatibility version 4.0.0, current version 4.1.0)
  /opt/homebrew/opt/sdl2_ttf/lib/libSDL2_ttf-2.0.0.dylib (compatibility version 2201.0.0, current version 2201.0.0)
  /opt/homebrew/opt/sdl2/lib/libSDL2-2.0.0.dylib (compatibility version 3001.0.0, current version 3001.8.0)
  /opt/homebrew/opt/sdl2_image/lib/libSDL2_image-2.0.0.dylib (compatibility version 801.0.0, current version 801.2.0)
  /usr/lib/libffi.dylib (compatibility version 1.0.0, current version 32.0.0)
  /opt/homebrew/opt/libsamplerate/lib/libsamplerate.0.dylib (compatibility version 3.0.0, current version 3.2.0)
  /opt/homebrew/opt/opus/lib/libopus.0.dylib (compatibility version 11.0.0, current version 11.1.0)
  /opt/homebrew/opt/mad/lib/libmad.0.dylib (compatibility version 3.0.0, current version 3.1.0)
  /opt/homebrew/opt/liblo/lib/liblo.7.dylib (compatibility version 13.0.0, current version 13.0.0)
  /opt/homebrew/opt/lame/lib/libmp3lame.0.dylib (compatibility version 1.0.0, current version 1.0.0)
  /opt/homebrew/opt/gd/lib/libgd.3.dylib (compatibility version 4.0.0, current version 4.11.0)
  /opt/homebrew/opt/flac/lib/libFLAC.12.dylib (compatibility version 14.0.0, current version 14.0.0)
  /opt/homebrew/opt/ffmpeg/lib/libswresample.5.dylib (compatibility version 5.0.0, current version 5.3.100)
  /opt/homebrew/opt/ffmpeg/lib/libswscale.8.dylib (compatibility version 8.0.0, current version 8.3.100)
  /opt/homebrew/opt/ffmpeg/lib/libavdevice.61.dylib (compatibility version 61.0.0, current version 61.3.100)
  /opt/homebrew/opt/ffmpeg/lib/libavutil.59.dylib (compatibility version 59.0.0, current version 59.39.100)
  /opt/homebrew/opt/ffmpeg/lib/libavformat.61.dylib (compatibility version 61.0.0, current version 61.7.100)
  /opt/homebrew/opt/ffmpeg/lib/libavfilter.10.dylib (compatibility version 10.0.0, current version 10.4.100)
  /opt/homebrew/opt/ffmpeg/lib/libavcodec.61.dylib (compatibility version 61.0.0, current version 61.19.100)
  /opt/homebrew/opt/fdk-aac/lib/libfdk-aac.2.dylib (compatibility version 3.0.0, current version 3.3.0)
  /opt/homebrew/opt/faad2/lib/libfaad.2.dylib (compatibility version 2.0.0, current version 2.11.1)
  /opt/homebrew/opt/libtiff/lib/libtiff.6.dylib (compatibility version 8.0.0, current version 8.0.0)
  /opt/homebrew/opt/libpng/lib/libpng16.16.dylib (compatibility version 61.0.0, current version 61.0.0)
  /opt/homebrew/opt/jpeg-turbo/lib/libjpeg.8.dylib (compatibility version 8.0.0, current version 8.3.2)
  /opt/homebrew/opt/giflib/lib/libgif.dylib (compatibility version 0.0.0, current version 7.2.0)
  /opt/homebrew/opt/jack/lib/libjack.0.1.0.dylib (compatibility version 0.1.0, current version 1.9.22)
  /opt/homebrew/opt/libao/lib/libao.4.dylib (compatibility version 6.0.0, current version 6.1.0)
  /usr/lib/libcurl.4.dylib (compatibility version 7.0.0, current version 9.0.0)
```

Yeah, that's **a lot!**

The more shared libraries your process has, the more shared memory it will use. However, all the processes using the
same libraries also reuse this memory.

![Shared Memory Illustration](https://github.com/user-attachments/assets/34bf149f-b198-42b4-a4ab-731df23a709a)

This means that if you have `10` Liquidsoap processes, each using `100MB` of memory, including shared memory, the total
memory used on the system is not actually `1000MB` because a significant portion is shared!

### Shared memory and docker processes?

Before proceeding, it's important to note that for memory sharing from dynamic libraries between programs, the system
must recognize that the programs are indeed loading the same shared libraries.

This is all pretty clear when all the programs run on the same OS but, what happens with `docker`?

Indeed, when a program runs inside a container, it executes _alongside_ the container's files, including the shared
libraries, in isolation from other programs.

So, how do we know that several processes running on different containers from the same image will be able to reuse the
same shared memory?

![Docker Shared Memory Illustration](https://github.com/user-attachments/assets/eb1029c9-7614-45ee-a549-b6d7dce55570)

It turns out that this aspect of docker is not very well documented.
This [stack overflow answer](https://stackoverflow.com/a/40096194) has some details on this for us:

> Actually, processes A & B that use a shared library libc.so _can_ share the same memory. Somewhat un-intuitively it
> depends on which docker storage driver you're using. If you use a storage driver that can expose the shared library
> files as originating from the same device/inode when they reside in the same docker layer then they will share the
> same virtual memory cache pages. When using the aufs, overlay or overlay2 storage drivers then your shared libraries
> will share memory but when using any of the other storage drivers they will not.
>
> I'm not sure why this detail isn't made more explicitly obvious in the Docker documentation. Or maybe it is, but I've
> just missed it. It seems like a key differentiater if you're trying to run dense containers.

Well, I'm sure that, by now, you're starting to see how tracking memory consumption can be tricky.

But we're not done! Let's dive more.

### Page cache

This was mentioned in the previous part. It turns out that, when accessing data from storage devices such as hard
drives, the data is also read and written using pages.

And, in order to optimize the application's activity, the OS keeps some of the disk's pages in memory, synchronizing
them periodically with the underlying device.

![File Page Cache](https://github.com/user-attachments/assets/edf3c828-4a75-4e3c-883b-a4b83669753f)

The logic governing how disk pages are cached in memory also creates memory usage that can be assigned to the
application from which the application has no control.

On Linux, it is possible to force the OS to flush the page cache. This is a good thing to do on a regular basis when
tracking a process's memory usage to ensure that an observed memory increase is not due to the OS caching too many
pages. [This medium blog post](https://medium.com/@bobzsj87/demist-the-memory-ghost-d6b7cf45dd2a) provides an excellent
example of such issues.

### OCaml memory

Last for this list (for now!), Liquidsoap also uses the OCaml compiler. One feature of the compiler is that it can
handle some low-level memory allocation and freeing automatically.

Under the hood, the OCaml compiler adds a runtime library to the compiled program that tracks when data is allocated by
the program and when it is no longer used. Once it detects that the data is no longer used, it can free it without
requiring the programmer to do it.

While this is really convenient and can help ensure that OCaml programs are memory safe, this also includes another
layer that is not entirely controllable by the application, typically when memory collection happens and how much and
how long memory is allocated before it can be freed.

This is even more important in the case of Liquidsoap because, by nature of its streaming loop, the application
constantly allocates memory under very short streaming cycles (typically the duration of a frame).

If memory collection occurs too frequently, CPU usage noticeably increases. Conversely, if it happens too infrequently,
memory usage rises.

We [explored these issues in a previous post](../2023-07-09-memory-management) and gave an example of parameters that
govern this trade-off. In the future, we would like to explore alternative memory allocation strategies to better
control short-term memory allocations inside the application.

### How to report memory usage

Now that we've seen different elements of memory usage, how can we report memory usage? It turns out that this is tricky
and OS-dependent!

In Linux, if you use `top` or a similar tool, the most common measure of memory consumption is `RSS` for
[_Resident set size_](https://en.wikipedia.org/wiki/Resident_set_size).

One important thing about RSS memory usage is that it includes shared memory. So, if `10` processes each use `30MB` of
RSS memory, the total memory used by the system will not be `300MB`.

Moreover, if a program like Liquidsoap depends on many shared libraries, the total reported `RSS` memory may be quite
large; however, it might not accurately reflect the actual memory the application occupies.

Likewise, in [the previously mentioned issue](https://github.com/savonet/liquidsoap/issues/4058), it took us a while to
realize that the tool our user was using to report the process's memory usage from their virtualized environment was
also including the page cache, leading to the wrong observations regarding the memory effectively allocated by the
application itself.

In the [ocaml-mem_usage](https://github.com/savonet/ocaml-mem_usage) module, we implemented several OS-specific methods
to measure the memory used by the application and separate shared memory from private memory.

This is exposed programmatically using `runtime.memory()` and `runtime.memory().pretty` for human-readable values:

```shell
% liquidsoap 'print(runtime.memory().pretty)'
{
  process_virtual_memory="419.68 GB",
  process_physical_memory="389.35 MB",
  process_private_memory="354.73 MB",
  process_swapped_memory="0 B"
}
```

(yes, this is `354MB` of private memory. More on this later!)

In the values above, the shared memory used by the process can be computed by removing the private memory from the total
physical memory used.

Generally, we **strongly** recommend using these APIs to investigate memory usage. Also, our code could be wrong or
missing some OS-specific stuff, so feel free to report and contribute to it!

## Memory optimizations in Liquidsoap

Let's see now how we can optimize memory usage in Liquidsoap!

### Optional features

As we mentioned, shared libraries increase the process's memory usage. Most of this increase comes from shared memory,
but some also arise from memory allocated by the shared libraries, even if their features are not used.

Thus, the first thing to optimize memory usage is to compile only the features that you use. This also reduces the risk
of fatal errors!

Here's a breakdown of memory usage in Liquidsoap with only one optional feature enabled:

![memory per feature](https://github.com/user-attachments/assets/2452a0a2-7f0a-484f-8805-6429d6202535)

Please note that this graph was created using a development branch of Liquidsoap and does not necessarily reflect the
memory usage of the final `2.3.0` release!

As we can see, memory usage is generally consistent, except for `ffmpeg`, which is expected due to its numerous shared
libraries.

Clearly, if you are not using any of the `ffmpeg` features and memory usage is a concern, be sure to build without
`ffmpeg` enabled. And, for good measure, any other optional components you do not use.

### Jemalloc

In previous releases, we had enabled [jemalloc](https://jemalloc.net/) by default but forgot to do our homework!

While `jemalloc` is very good for optimizing memory allocations for things like small allocations and quick reclaim,
which is great for short-term memory allocations like those done in `ffmpeg`, it turns out that it is **not** a tool for
optimizing the overall amount of allocated memory.

Here's the same breakdown as above, but with `jemalloc` enabled:

![memory per feature with jemalloc](https://github.com/user-attachments/assets/2e2ff67f-59dd-4cd4-a656-4176b2c3a2dc)

Thus, we recommend not enabling `jemalloc` if memory footprint is a concern for your application.

### Script caching and memory usage optimization

Finally, let's explore optimizing memory usage through the _script caching_ feature, which is available starting with
Liquidsoap version `2.3.0`.

Here's a script reproducing the example from the previous section:

```liquidsoap
def f() =
  print(runtime.memory().pretty)
end

thread.run(delay=1., f)

output.dummy(blank())
```

This script generates the following output the first time it is run:

```shell
2024/10/11 19:38:24 [startup:3] Loading stdlib from cache!
2024/10/11 19:38:24 [startup:3] stdlib cache retrieval: 0.11s
2024/10/11 19:38:24 [startup:3] Typechecking main script: 0.00s
2024/10/11 19:38:24 [startup:3] Evaluating main script: 0.01s

...

{
  process_virtual_memory="419.56 GB",
  process_physical_memory="388.83 MB",
  process_private_memory="354.19 MB",
  process_swapped_memory="0 B"
}
```

But the second time:

```shell
2024/10/11 19:38:32 [startup:3] main script hash computation: 0.03s
2024/10/11 19:38:32 [startup:3] Loading main script from cache!
2024/10/11 19:38:32 [startup:3] main script cache retrieval: 0.04s
2024/10/11 19:38:32 [startup:3] Evaluating main script: 0.02s

...

{
  process_virtual_memory="419.05 GB",
  process_physical_memory="106.76 MB",
  process_private_memory="72.14 MB",
  process_swapped_memory="0 B"
}
```

Not only does it run significantly faster and consume `5x` less memory, but it also approaches the memory usage of
version `1.3.3`!

The reason is rooted in our [previous post](../2024-06-13-a-faster-liquidsoap) about caching: script type-checking is
very resource intensive, so when loading the script from the cache, we avoid an initial step that requires a lot of
memory allocations!

The memory used during the type-checking phase is usually reclaimed after the script starts. Still, due to OCaml's
memory allocation logic and the OS's own page caching logic, this memory might linger for a while.

Thus, we **strongly** recommend caching your scripts before running them in production!

If, for some reason, script caching is not available, you can also set `settings.init.compact_before_start` to `true`:

```liquidsoap
settings.init.compact_before_start := true
```

This will run the OCaml memory compaction algorithm before starting your script. In the best cases, this will result
in about the same initial memory consumption before starting your script. However, the script will still consume
a large amount of memory before starting and startup time will be delayed.
