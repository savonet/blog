---
layout: post
title: FOSDEM 2023 Takeaway
---

We had a great time at FOSDEM! It was really nice to get to meet and hang with all the people from the community, both coders, hacktivists and fellow
radio people!

You can watch our talk here:

<div style="display: grid; grid-template-columns: repeat(1, minmax(0, 1fr)); justify-items: center;">
<div style="padding:75% 0 0 0;position:relative;"><iframe src="https://player.vimeo.com/video/797189056?h=3f4a1abee7&amp;badge=0&amp;autopause=0&amp;player_id=0&amp;app_id=58479" frameborder="0" allow="autoplay; fullscreen; picture-in-picture" allowfullscreen style="position:absolute;top:0;left:0;width:100%;height:100%;" title="om_liquidsoap.mp4"></iframe></div><script src="https://player.vimeo.com/api/player.js"></script>
</div>

Being in Bruxelles was quite stimulating and we talked about several interesting area of development for Liquidsoap:

### Scheduling optimization

Clearly, there's a need for easier and more flexible scheduling. We've heard from several of the folks from radio world about how their existing scheduler work.

One of the experiement that we've been looking is to make it easier to schedule, say, 3 songs from one source at the top of the hour. We have some ideas to
achieve this but we would like first to offer a better fundamental building block than the current `fallback`/`switch` for that and this will have to be for
a future major release cycle.

It's also important here to mention that we are always eager to hear from actual users and to better understand the logic of the tools that they use
and how we could replicate and/or help fit into their ecosystem. Never hesitate to reach out!

### Multicore encoding

We've run a [quick experiment](https://github.com/savonet/liquidsoap/pull/2879) on multicore encoding using the new support from OCaml 5 and it was pretty amazing! I was able to encode 10 concurrent `1080p` videos
on my M1 pro, watching the CPU cores getting loaded up!

Unfortunately, though, there are some important pending changes in the code to make this suitable for production releases. This will, however, be the focus of 
the `2.3.x` release cycle and we are pretty stoked to see it happen!

Meanwhile, remeber that this really benefits specific circumstances such as when having multiple encoded output from a single source.

If you have several sources and outputs as separate entities, run them in separate scripts processes!

If you have a single encoding format shared with different outputs, try [shared encoding](https://www.liquidsoap.info/doc-2.1.3/cookbook.html#shared-encoding)!

### Runtime optimizations

We are aware that, as the standard library grows, boot time increases. We are currently exploring two paths:
* Caching resolved typechecks, which is what seems to be taking the most time
* Pruning the AST before running a script to avoid typechecking and holding unused script code in memory.

## What's next?

The `2.1.4` release is _very_ near! We'll be zipping up as many issues as possible in the next weeks or so and releasing it. This is expected to be the
very last `2.1.x` release so reach out to us if you have a pending issue that you would like to see addressed in this release. We'll do our best to get 
to it!

The `2.2.x` release cycle will also being imminently. All the features we wanted have been completed and we now need to write doc and have stabilization
period to chase potential bugs, regressions and such. This release will bring on a lot of nice new features, including the ability to mux and demux arbitrary
number of tracks anad to apply operators such as ffmpeg inline encoding, `add` and more at the track level!

User feedback and bug reports on all this will be quite valuable!
