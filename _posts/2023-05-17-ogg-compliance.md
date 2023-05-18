---
layout: post
title: Ogg bitstream compliance
---

One of the interesting thing with a long-term project is the ability to look back in the past, some times way far back and consider the consequences of certain
decisions. One example of that came up recently with ogg bitstream muxing and demuxing..

### Way back when..

Liquidsoap support for ogg streams started in 2007, about 16 years ago, the first release being dated Nov. 16th of that year. That's a long time ago!
Back then, there was only `libogg` and `libvorbis`, mostly. Other came and some left, `theora`, `schroedinger`, `speex`, `flac`, and the last one, `opus`.

Mostly, there days, we're dealing with `opus` (though it's more often used in `webm` container) and `vorbis`, some time `flac`. RIP `schroedinger`. Not sure
who still uses `speex`?

The library API ecosystem also was burgeoning and had just started. `FFmpeg` wasn't making stable releases and was recommending to check in their source code in your own
code..

The main library for creating ogg bitstreams was `libogg`, which is still pretty much unchanged. For all the associated codecs that can be used with it,
still to that day, only `libvorbis` has an explicit API to operate with `libogg`. `libFLAC` has a ogg stream mode but it's totally opaque and
not easy to integrate in a proper muxer.

Thus, when it was time to support multiplexed streams, we decided to implement our own ogg bitstream muxer and demuxer using `libogg`. It was new and exciting
for us to follow a specification and get to use all the fancy high-level tools that OCaml provided for it. 

This code hasn't changed much over the years. The ogg muxer is [here](https://github.com/savonet/liquidsoap/blob/main/src/core/ogg_formats/ogg_muxer.ml)
and the ogg demuxer is [here](https://github.com/savonet/ocaml-ogg/blob/main/src/ogg_decoder.ml). Also, the documentation for ogg bitstream is [here](https://xiph.org/ogg/doc/oggstream.html).

![stream](https://github.com/savonet/blog/assets/871060/891c63ef-473a-41ed-af78-1a4210f77773)
*an ogg bitstream*

The gist of ogg bitstream is: encoded data is organized in _packets_. Packets are organized in ogg _pages_, pages can contain anything between a fraction
of a packet to multiple packets. The stream is started with a page with a specific _bos_ (beginning of stream) flag and ended with a page with a corresponding _eos_ flag.

### The rub

Encoding a stream is quite different than encoding a file. In particular, one may assume that data is going to keep on coming until it doesn't. At this point,
which may come any time in the stream, one needs to close out the encoder, wrap the container and call it a day.

However, the problem with `libogg` is that its API is driven by _packets_. So, if you want to close a bitstream, you submit the last packet with a `eos`
(for _end of stream_) flag set and the muxer knows to force this packet into its own page (see doc above) and call it a day.

But, what happens if you are encoding a stream and you need to finish the stream but don't have any data available anymore? For instance, your
remote client just hung up?

This is the problem that we were faced with some ~16 years ago. `libvorbis`, being the only library actually interfacing directly with `libogg`, there
was a specific call that could be done with an empty audio packet. The library would close out the ogg bitstream and everything would be great. But, for all
other libraries, we were left on our own.

To make matter worst, `libogg` did not provide any function to close out a logical page without a packet. You _had_ to submit one last packet even though
the ogg spec actually allowed an empty _eos_ ogg page to be sent!

> Eos pages may be 'nil' pages, that is, pages containing no content but simply a page header with position information and the eos flag set in the page header.

Source: https://datatracker.ietf.org/doc/html/rfc3533#section-4

Our approach at the time was to try and stick with the official `libogg` API as much as possible so, looking at the available options, 
it felt like the only way out was, when trying to close a stream with no more data, to submit one last `eos` packet with zero data:

```c
  op.bytes = 0;
  op.packet = NULL;
  op.b_o_s = 0;
  op.e_o_s = 1;
  op.packetno = handler->packetno;
  op.granulepos = handler->granulepos;

  if (ogg_stream_packetin(os, &op) != 0)
    caml_raise_constant(*caml_named_value("ogg_exn_internal_error"));
```

This way the muxer would issue one last _eos_ page with this empty packet and the stream would close. We also expected that a packet
with no data would clearly indicate the end of the stream to any decoder, much like empty data signifies end of file when reading a unix socket.

### Fast forward

The problem with different implementations is that specs always have gray areas and, when one implementation becomes prominent, it becomes 
the de-facto implementation for unclear, dark corner of a specification.

So, fast forward 16 years, two things happened:
* The FFmpeg library became the de-facto reference implementation for many media situations and their implementation of ogg demuxing considers an empty packet as invalid data.
* The opus spec started using empty packets for packet loss control. This is not yet supported by FFMpeg but clearly invalidates our initial assumption.

This means that, while we weren't watching, all of the sudden most the rest of the internet started to use a different ogg bitstream implementation 
that wasn't compatible with our last _eos_ packet with empty data.

The problem was also particularly hard to identify because the ogg bistream convention for marking begining and end of logical tracks within a bitstream is pretty _bad_.
Essentially, a chained ogg bitstream is pretty much like the straight contatenation of ogg files (see doc above again). This is a bad spec because:
1. It is pretty reasonable in a lot of situations to treat opened file descriptors and network sockets the same way as they share the same API for reading. Thus, most decoders will naively think that decoding ends at the end of a chained track in an ogg stream because is exactly the same as the end of file.
2. This does not account for e.g. streams with multiple audio tracks. For instance, if a file contains a french audio track and an english audio track, how are we supposed to match those tracks in the next logical bitstream?  Typically, FFmpeg decided to [not support this use-case](https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/oggdec.c#L217).

Mainly because of #1, we probably discarded a bunch of reports claiming that a decoder was stopping at the end of a track as a bad case of ogg chained bitstream
decoding while it could also have been because our bitstreams were not compliant.. 🤯

### Problem solved

Once this was identified, a quick fix was pushed in [savonet/liquidsoap#3062](https://github.com/savonet/liquidsoap/pull/3062). The solution was to do what
we should have done in the first place: follow the spec and submit a final, empty ogg page.

However, because `libogg` does not provide any API to do so, we had to dabble into the internals of ogg pages and also the `libogg`
code to make it work. In fact, we are still using the empty packet trick but, this time, we also remove the resulting data from 
the newly generated ogg page:

```c
  ogg_packet op;
  op.packet = (unsigned char *)NULL;
  op.bytes = 0;
  op.b_o_s = 0;
  op.e_o_s = 1;
  op.granulepos = os->granulepos + 1;
  op.packetno = os->packetno + 1;
  ogg_stream_packetin(os, &op);

  if (!ogg_stream_pageout(os, &page))
    caml_raise_constant(*caml_named_value("ogg_exn_bad_data"));

  page.header[26] = 0;
  page.header_len = 27;
  page.body = NULL;
  page.body_len = 0;

  ogg_page_checksum_set(&page);
```

This solution is now implemented in the `main` branch as well as the current `rolling-release-v2.2.x` branch and builds. The fix will be released
with the `v2.2.0` release.

This fix impacts any user that encodes in any `ogg` format appart from `ogg/vorbis`. If you're one of them, feel to go ahead and checkout the [latest rolling-release-v2.2.x build](https://github.com/savonet/liquidsoap/releases/tag/rolling-release-v2.2.x) right now or,
if you want to play it safer, switch to `v2.2.0` once it is finally released.

