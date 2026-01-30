---
layout: post
title: Shared encoders with Liquidsoap 2.4.0!
---

# Shared encoders with Liquidsoap 2.4.0!

[Liquidsoap 2.4.0 is out](https://github.com/savonet/liquidsoap/releases/tag/v2.4.0) and one feature that was greatly
improved (read: is now working!) is _shared encoders_!

This means that you should now be able to encode once and pass the result to different outputs.

For instance, you can now encode once in all the audio formats that you want to use and send the output to both Icecast
and HLS without having to do multiple encodings.

Here's how this works:

```liquidsoap
# The source we'll encode:
s = playlist("/path/to/playlist")

s = mksafe(s)

# Encode the source inline to the various audio formats:

aac_low =
  ffmpeg.encode.audio(
    %ffmpeg(%audio(codec = "aac", b = "48k")), s
  )

aac_high =
  ffmpeg.encode.audio(
    %ffmpeg(%audio(codec = "aac", b = "192k")), s
  )

mp3 =
  ffmpeg.encode.audio(
    %ffmpeg(%audio(codec = "libmp3lame", b = "128k")),
    s
  )

# Output to icecast
output.icecast(mount="aac_low", %ffmpeg(format = "adts", %audio.copy), aac_low)
output.icecast(mount="aac_high", %ffmpeg(format = "adts", %audio.copy), aac_high)
output.icecast(mount="mp3", %ffmpeg(format = "mp3", %audio.copy), mp3)

# Now prepare all the HLS streams.
# The trick here is to combine all audio
# tracks with the different content into
# a single multitrack source and select the
# audio that you want in each stream:
streams =
  [
    (
      "aac_low",
      %ffmpeg(
        format = "mpegts",
        %audio_aac_low.copy,
        %audio_aac_high.drop,
        %audio_mp3.drop
      )
    ),
    (
      "aac_high",
      %ffmpeg(
        format = "mpegts",
        %audio_aac_low.drop,
        %audio_aac_high.copy,
        %audio_mp3.drop
      )
    ),
    (
      "mp3",
      %ffmpeg(
        format = "mpegts",
        %audio_aac_low.drop,
        %audio_aac_high.drop,
        %audio_mp3.copy
      )
    )
  ]

# Now, create the multitrack source:
let {audio = aac_low, metadata = m, track_marks = tm} = source.tracks(low)
let {audio = aac_high} = source.tracks(high)
let {audio = audio_mp3} = source.tracks(mp3)

s =
  source(
    {
      audio_aac_low=aac_low,
      audio_aac_high=aac__high,
      audio_mp3=audio_mp3,
      metadata=m,
      track_marks=tm
    }
  )

# And output it!
output.file.hls("/path/to/hls", streams, s)
```

One important note when sending to different outputs, however, is that not all containers can accept the same encoded
bitstream!
If you start doing a lot of encoded outputs like this, you might want to start reading about ffmpeg's notion of _extra
data_ and take a look at things like
the [`h264_mp4toannexb` bitstream filter](https://ffmpeg.org/ffmpeg-bitstream-filters.html#h264_005fmp4toannexb) (which
we should also support!).

Lastly, with a little more effort, you can also mux the encoded audio with some video and have an audio+video output in
all the various audio formats with a single video encoding.

Lots of exciting possibilities!
