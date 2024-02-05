---
layout: post
title: Liquidsoap v2.2.4 is out! 🎊
---

Liquidsoap version `2.2.4` is out! Check it [here](https://github.com/savonet/liquidsoap/releases/tag/v2.2.4)

This is the fourth release in the `2.2.x` release cycle and this one includes a little more than bugfixes!

While the current `main`/`v2.3.x` cycle is starting to look pretty good (more on that in a future post!), it felt important to ship some changes fixing important issues
but also to addressing larger changes that felt too big for a bug fix but also important enough to be pushed before the `v2.3.x` cycle could bring them on.

In this post, we present some of the most important changes with this release. Note that this release does contain important bug fixes that we strongly recommend
for production if you are on the `2.2.x` release branch. However, make sure to read the following and test it in your staging/preview environment
before deploying to production!

## Pops and clicks in add

One issue that was causing a lot of pain was the presence of some audio artifact in some `crossfade` transitions. This was reported in [#3318](https://github.com/savonet/liquidsoap/issues/3318).

The culprit turned out to be a tiny missed amount of data when the `add` operator was updated to support tracks and muxing. During each streaming cycle.
liquidsoap fills a frame that is usually about `0.04s` long. When adding data from two sources, the new code was only adding the min of the two source's frame
data, leading to tiny amount of audio data, perhaps about `0.01s` or less, missing. 

This was also a tricky bug to reproduce: it would only happen when computing crossfading transitions that differed in a tiny amount of data between the buffered data from the ending and starting track 
(see below for an explanation). However, to the human hear, this was immediately audible!

<img width="700" alt="Screenshot 2024-02-05 at 11 00 53 AM" src="https://github.com/savonet/blog/assets/871060/fcefe013-6466-4775-8e27-8016baec27d1">

This should be fixed with this release. We have had some more sparse report of pops and clicks so we will keep an eye on it. Also, it's important to note that pops
and clicks can still happen if, for instance, a song is cut abruptely.

Which brings us to our next topic!

## Cue cut

The historical mechanism for pre-processing tracks to remove initial parts and cut out ending was historically to use the `cue_cut` operator. Based on specific
metadata, this operator would do an initial `seek` on its underlying source when a track started and call `skip` when reaching the cue out point.

This wqas working but also caused multiple issues:
* It wasn't clear where to put `cue_cut` in scripts. Putting it at the wrong spot would cause confusing issues, skipping on the wrong source and etc.
* `cue_cut` was confusing underlying operators. For instance, a `playlist` knows to start fetching a new request when the current one is near its end. However, `cue_cut` skipping would surprise the operator which would, then, be caught without a prepared request

In situations like that, it is sometimes a better choice to admit that the initial paradigm was wrong. In fact, the whole cueing mechanism was always meant
for file-based requests only. So, it made sense to move it there and only there.

With this release, `cue_cut` has been removed and the cueing mechanism has been moved to the request resolution/decoding layer. This means that, 
when passing the cue cut metadata (see doc [here](https://www.liquidsoap.info/doc-2.2.4/seek.html#cue-points)), the resolved requests comes with 
cue points already applied, making its duration correct and etc.

Please note, however, that the cueing mechanism operates at the container level. The content of the request could be video only, encoded ffmpeg data etc.
In particular, it cannot do a finer zero crossing analysis. This means that pops and clicks can occur if the cueing points are at wrong spot. Therefore, we
do recommend following a cue cut request with a `crossfade` to make sure that they transition smoothly!

## Fade inner functionings

Another regular pain point and confusing aspect of liquidsoap script is how crossfade work. In this release, we are bringing some much needed added
flexibility to those. But, first, let's have a look at how crossfade work:

* When a track starts, if it has the `liq_cross_duration` metadata, the crossfade duration is set to this values _for the next crossfade_. Otherwise it uses its default. Let's call this value `cross_duration`.
* During the track's playback, liquidsoap tries its best to keep a constant buffer of the next `cross_duration` seconds.
* When detecting that the track has ended, liquidsoap has a certain amount of data buffered from the ending track. This is usually close to `cross_duration`. Let's call this value `buffered_before`.
* Next, `liquidsoap` buffers some data from the starting track. This will be as close as possible to `buffered_before` but can be slightly different. It can also be much less if the track is too short. Let's call this value `buffered_after`.
  * ⚠️ **Note** ⚠️ : A new track that is shorter than `cross_duration` should be considered a programming error. In particular, all its data will be consumed when computing its `fade.in` transition and no data will be available to compute its `fade.out` transition!
* Temporary sources are then created using `buffered_before` and `buffered_after` data. These sources are passed to the transition function and its result is injected between the ending and starting track, becoming the actual crossfade transition.

It is important to keep this in mind when considering the right crossfade parameters to use. In particular, as seen above, `cross_duration` should never
exceed the next track's duration. This is a little tricky to enforce since `cross_duration` is set at the beginning of the ending track when it might not yet been known which
track will come next. This chould, however, be a constraint to keep around when actually computing the next track.

Likewise, `fade.in` and `fade.out` duration should never exceed `cross_duration`.

Another tricky thing then becomes: how to include short tracks in a source with crossfade, for instance jingles? In this case, we do recommend to tag the request
with specific metadata. You should then be able to define your own transition based on that tag and, for instance, use a sequence. The API has the default
crossfade transitions exported as `cross.simple` and `cross.smart` so this is not too hard to do. Here's an example:

```liquidsoap
def simple_crossfade_with_jingles(old, new) =
  if old.metadata["type"] === "jingle" or new.metadata["type"] == "jingle" then

    # Note: you might still want to apply a fade.in or fade.out on the non-jingle
    # source here to smooth out potential cue-cut points!
    sequence([old.source, new.source])
  else
    cross.simple(old, new)
  end
end

s = cross(simple_crossfade_with_jingles, s)
```

## New fade parameters

### Fade delay

Another issue with crossfade is, then, how to time the `fade.in` with regard to the `fade.out`. Before this release, there was no easy 
way to delay the `fade.in` and `fade.out` to adjust their relative positions within the computed buffer. This is now possible with the addition 
of a `delay` parameter! This parameter can be passed when calling `fade.in` and `fade.out` and also overriden using `liq_fade_in_delay` and `liq_fade_out_delay` metadata.

It works slightly differently for `fade.in` and `fade.out`:
* For `fade.in`, the delay is added as _initial silence_ before the track starts with the `fade.in` applied
* For `fade.out`, the delay pushes back the start time of the `fade.out`.

### Fade curve

This is more of a minor point but the fade algorithm supports a notion of curve for `exp` and `log` fades. The higher the number, the steeper
the curve. This parameter is now also available as initial `fade.in` and `fade.out` parameter as well as `liq_fade_in_curve` and `liq_fade_out_curve` overriding metadata

### Fade type

Another minor point but a breaking one: `liq_fade_type` metadata override name has been split and renamed to: `liq_fade_in_type` and `liq_fade_out_type` to 
make it possible to specify different type of fade for the ending and begining track.

### Example

Here's an illustration of the new parameters:

![fades](https://github.com/savonet/blog/assets/871060/9b832994-da9b-4ea4-b5a9-e071ba219558)

This crossfade transition is generated by the following request annotations:

```
annotate:liq_cross_duration=5.,liq_fade_out_delay=2.,liq_fade_out=3.,liq_fade_out_type="exp",liq_fade_out_curve=10:/path/to/track.mp3
annotate:liq_fade_in_delay=2.,liq_fade_in=2.,liq_fade_in_type="lin":/path/to/other-track.mp3
```

## Other notable changes

Other notable bugfixes and changes in this release are:
* Added support for HLS metadata when using encoders other than `%ffmpeg`, namely `%mp3`, `%shine` and `%fdkaac`
* Fixed a nasty bug with file headers when saving files using `output.file`
* Squashed a memory leak when doing a lot of dynamic sources creation

And some more..

Check out this release! We're pretty happy about it! 

Next, we'll be focusing on adding multi-core support to the `v2.3.x` branch. This should be the last big change before we can start stabilizing it and considering
it for release!
