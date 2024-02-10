---
layout: post
title: Video Canvas and AI
---

Liquidsoap did not make it to FOSDEM this year, unfortunately. We had a nice example of advanced video use to present so here it is!

The code presented in this article is available here: https://github.com/savonet/ai-radio

## The setup

We are looking at a cleaned-up version of a code that has been contributed by several members of the awesome [Azuracast](https://www.azuracast.com/) project. We've been good friend
with them for a while and they've helped us grow a lot, from pushing the envelope on what to do with liquidsoap, to giving us the inspiration for setting up rolling-releases and, perhaps most
importantly, being patiently working with us to fix bugs on each new release. Thanks y'all!

Here's a screenshot of how our video will be looking like:

<img width="1280" alt="Screenshot 2024-02-10 at 11 21 50 AM" src="https://github.com/savonet/blog/assets/871060/f520ded1-4a6f-4438-afb6-ef5703938149">

What we have here is:
* A playlist of audio tracks
* A playlist of background videos
* A title frame on the top-right
* A cover image on the low-middle left
* A current track banner in the lower part with a timer and slider bar indicating the position in the track

Let's see how to set this up!

## Video canvas

The first thing we want is to be able to build this video script without having to worry about the final rendered size. This can be achieved with a new API from the `2.3.x` branch: **video canvas**.

Here's how they work:

```liquidsoap
let {px, vw, vh, rem, width, height} = video.canvas.virtual_10k.actual_720p
video.frame.width := width
video.frame.height := height
```
This API provides a _virtual_ video canvas of `10k` pixel width. Every pixel size in the virtual canvas is then converted to an _actual_ pixel size.
Here, we picked the `720p` actual canvas, which is a canvas of size `1280x720`. In this case, `1` virtual pixel is about `0.128` actual pixel.

If, later on, we want to switch to `1080p`, all we'd have to do is replace the code above by:
```liquidsoap
let {px, vw, vh, rem, width, height} = video.canvas.virtual_10k.actual_1080p
video.frame.width := width
video.frame.height := height
```

For conversion, the API provides convenience functions that are inspired from how CSS works:
* `px` converts from virtual pixels to actual pixels
* `vw` converts a percentage of the actual width, expressed as a number between `0.` and `1.` into actual pixels
* `vw` converts a percentage of the actual height, expressed as a number between `0.` and `1.` into actual pixels
* `rem` converts a percentage of the default font size, expressed as a number between `0.` and `1.` into actual pixels
* `width` and `height` are the actual canvas size

For convenience, a new `@` syntax has been introduced so that, instead of writting `px(237)`, you can write: `237 @ px`, which is much more readable.

Last thing: if you are using a release from the `2.2.x` branch, you can simply copy the code into your script. It is available [here](https://github.com/savonet/liquidsoap/blob/main/src/libs/video.liq#L768)

Let's see this in action next!

## Static video elements

First, let's setup our font and base video source:

```liquidsoap
# Like this font!
font = "/home/toots/font/MesloLGS NF Bold.ttf"

# Use a folder of videos:
background = playlist("/home/toots/ai-radio/background")
```

Now, we can add our first video element which is a transparent rectangle that is placed under the radio title on the top-right:

```liquidsoap
background =
  video.add_rectangle(
    color=0x333333,
    alpha=0.4,
    x=4609 @ px,
    y=234 @ px,
    width=5468 @ px,
    height=429 @ px,
    background
  )
```

Next, we add the radio name. This is a text with a backdrop, which is basically the same text but in black color and a `y` offset:

```liquidsoap
def add_text_with_backdrop(~x, ~y, ~size, ~color, text) =
  background =
    video.add_text(
      color=0x000000,
      font=font,
      x=x @ px,
      y=(y + 15) @ px,
      size=size @ rem,
      text,
      background
    )

  video.add_text(
    color=color,
    font=font,
    x=x @ px,
    y=y @ px,
    size=size @ rem,
    text,
    background
  )
end

background =
  add_text_with_backdrop(
    x=4687,
    y=250,
    size=2.15,
    color=0xFCB900,
    "Teardown The List Jockey"
  )
```
Finally, let's add the remaining static video elements:

```liquidsoap
# The yellow backdrop where the coverart will be shown
background =
  video.add_rectangle(
    color=0x333333,
    alpha=0.4,
    x=0 @ px,
    y=4375 @ px,
    width=1. @ vw,
    height=960 @ px,
    background
  )

# The full width current title banner
background =
  video.add_rectangle(
    color=0xfcb900,
    alpha=0.7,
    x=0 @ px,
    y=5015 @ px,
    width=1. @ vw,
    height=15 @ px,
    background
  )

# A nice horizontal line
background =
  video.add_rectangle(
    color=0xfcb900,
    x=210 @ px,
    y=2554 @ px,
    height=1609 @ px,
    width=1609 @ px,
    background
  )
```

Here's how our video looks so far:

<img width="1282" alt="Screenshot 2024-02-10 at 11 45 43 AM" src="https://github.com/savonet/blog/assets/871060/ae7314ee-65fa-428f-bd98-8ec7a8ac9bb7">

Time to add the dynamic elements!

## Adding dynamic elements

First thing first, we need an audio source!

```liquidsoap
radio = playlist("/home/toots/ai-radio/audio")
```

Next, we need to keep track of the song currently being played and its duration and position:

```liquidsoap
# Keep track of current title and artist
current_title = ref("")
current_artist = ref("")

def update_current_song(m) =
  current_title := m["title"]
  current_artist := m["artist"]
end
radio.on_metadata(update_current_song)

# Return current position as a percentage between 0. and 1.
def position() =
  source.elapsed(radio) / source.duration(radio)
end

# Return a formatted string representing the remaining time
def remaining() =
  time = source.remaining(radio)
  seconds = string.of_int(digits=2, int(time mod 60.))
  minutes = string.of_int(digits=2, int(time / 60.))
  "#{minutes}:#{seconds}"
end
```

This tracks all the information we need for our dynamic elements. The `string.of_int` is new in `2.3.x`. Again, if you are on one of the `2.2.x` version, you can 
import its code into your script. It is [here](https://github.com/savonet/liquidsoap/blob/main/src/libs/string.liq#L129)

Now, we can add our dynamic elements!

```liquidsoap
# Display current title
background =
  video.add_text(
    color=0xFCB900,
    font=font,
    speed=0,
    x=234 @ px,
    y=4437 @ px,
    size=1.5 @ rem,
    current_title,
    background
  )

# Display current artist
background =
  video.add_text(
    color=0xFCB900,
    font=font,
    speed=0,
    x=234 @ px,
    y=4710 @ px,
    size=1.5 @ rem,
    current_artist,
    background
  )

# Display progress bar
background =
  video.add_rectangle(
    color=0xfcb900,
    x=0 @ px,
    y=5285 @ px,
    height=50 @ px,
    width={position() @ vw},
    background
  )

# Display remaining time
background =
  video.add_text(
    size=rem(1.),
    x=234 @ px,
    y=5039 @ px,
    color=0xcccccc,
    font=font,
    {
      "Next in #{remaining()}"
    },
    background
  )
```

This is starting to look good:

<img width="1277" alt="Screenshot 2024-02-10 at 12 03 11 PM" src="https://github.com/savonet/blog/assets/871060/c5e0cdfc-9d81-4abd-9d7b-e915a6c68d13">

## Cover art

Last dynamic element is the song cover art. This another awesome piece of code contributed by [@vitoyucepi](https://github.com/vitoyucepi). It is also
a new API. Again, you can import its code if needed. It is defined [here](https://github.com/savonet/liquidsoap/blob/main/src/libs/extra/metadata.liq) and
[here](https://github.com/savonet/liquidsoap/blob/main/src/libs/extra/video.liq).

![sorry-folks-nothing-to-see-here-move-along-820x461](https://github.com/savonet/blog/assets/871060/92af8779-915d-4817-b991-db685aab7fa8)

That's right! This API is so elegant that, if your files have the coverart in the right metadata, all you have to do is:

```liquidsoap
# Mux video with the audio
radio = source.mux.video(video=background, radio)

# Add cover art!
radio =
  video.add_cover(
    x=234 @ px,
    y=2578 @ px,
    width=1562 @ px,
    height=1562 @ px,
    default="/home/toots/ai-radio/default-cover.jpg",
    radio
  )
```

That's it!

<img width="1275" alt="Screenshot 2024-02-10 at 12 09 24 PM" src="https://github.com/savonet/blog/assets/871060/4a6eca43-9ff2-449a-a611-70936360818d">

## HLS output

Well, that's not exactly it heh.. We need an output! 😆 Let's do a HLS output:

```
radio = mksafe(radio)

enc =
  %ffmpeg(
    format = "mpegts",
    %audio(
      codec = "aac",
      samplerate = 44100,
      channels = 2,
      b = "192k",
      profile = "aac_low"
    ),
    %video(codec = "libx264", preset = "ultrafast", g = 50)
  )

streams = [("radio", enc)]

output.file.hls(segment_duration=2., "/home/toots/ai-radio/hls", streams, radio)
```

## AI DJ

Well, now that we have a cool radio station with its video, let's add some headline-grabbing stuff designed to impress our friends: an automated AI DJ! We're gonna add an automated 
DJ that, every 4 songs, presents the songs that just played, how they connect with each other and introduces the next song!

For this section, we use the current commercially available services. Of course, y'all know that we are fervent supporters of open source technologies. We're just takign a shortcut for 
the sake of this presentation's brievety. There are open-source AI models, which might likely turn out better than the commercial ones eventually. There are also open-source speech synthesis 
projects, though it's not sure how well they compete with the commercial ones at this point (please correct me if I'm wrong here!).

This is actually not much in terms of liquidsoap code. What we need is to:
* Make an API call to the Open AI API to generate the text that our AI DJ will read.
* Make an API call to generate the audio speech that needs to be played. Here, we will also use Open AI's speech synthesis service.

First, and perhaps the most tricky, we need to keep track of the songs that is about to play. To do this,
we need to set our audio source to `prefetch=2` and use the `check_next` function. This is not ideal but it's a cool shortcut:

```liquidsoap
next_song = ref([])
def check_next(r) =
  ignore(request.resolve(r))
  request.read_metadata(r)
  next_song := request.metadata(r)
  true
end

radio = playlist("/home/toots/ai-radio/audio", prefetch=2, check_next=check_next)
```

Next, we need a function that, given the last 4 tracks and the next one generates a prompt for our AI call:

```liquidsoap
def mk_prompt(old, new) =
  old =
    list.map(
      fun (m) ->
        begin
          title = m["title"]
          artist = m["artist"]
          "#{title} by #{artist}"
        end,
      old
    )

  old =
    string.concat(
      separator=
        ", ",
      old
    )

  new_title = new["title"]
  new_artist = new["artist"]

  new =
    "#{new_title} by #{new_artist}"

  "You are a radio DJ, you speak in the style of the old 50s early rock'n'roll \
   DJs. The following songs were just played: #{old}. Next playing is #{new}. \
   Can you describe the musical characteristics of each song that ended and how \
   they connect with each other? Then introduce the next song. Make sure to \
   include style, year, instruments and cultural context and anecdotes and fun \
   facts. Limit your response to 200 words and make sure that it sounds \
   entertaining and fun."
end
```

Let's write a function that takes this prompt and returns a request URI to push into a queue:

```liquidsoap
def generate_speech(prompt) =
  # Fetch the text that the DJ should say:
  let {choices = [{message = {content}}]} =
    openai.chat(
      key=openai_api_key,
      [
        {
          role="system",
          content=
            "You are a helpful assistant."
        },
        {role="user", content=prompt}
      ]
    )

  tmp_file = file.temp("dj", ".mp3")

  on_data = file.write.stream(tmp_file)

  # Generate speech synthesis of the text
  openai.speech(key=openai_api_key, voice="onyx", on_data=on_data, content)

  request.create("annotate:title=\"AI DJ\":tmp:#{tmp_file}")
end
```

Couple of things to note here:
* This makes use of the new `openai` API. Again, if needed, you can import the code from [here](https://github.com/savonet/liquidsoap/blob/main/src/libs/extra/openai.liq)
* The returned URI uses two protocol: `annotate:` to add a title metadata and `tmp:` to mark the file as temporary. This makes sure that is deleted after being played.

We're now ready to plug in our DJ! Right before we start adding video dynamic element we can add:

```liquidsoap
# Queue of DJ speech requests
append_queue = request.queue()

# The list of past songs
past_songs = ref([])

def process_dj_metadata(m) =
  past_songs := [...past_songs(), m]

  # If the queue has 4 tracks, insert a DJ speech
  if
    list.length(past_songs()) == 4
  then
    songs_history = past_songs()
    past_songs := []
    prompt = mk_prompt(songs_history, next_song())

    # Run this in a thread queue to avoid blocking the main streaming thread
    thread.run({append_queue.push(generate_speech(prompt))})
  end
end

# Track the last songs
radio = source.on_metadata(radio, process_dj_metadata)

# Insert a speech request when needed
radio = fallback(track_sensitive=true, [append_queue, radio])
```

Let's hear our DJ!

<video controls style="width: 100%">
  <source src="https://github.com/savonet/blog/assets/871060/37cbf6c2-3383-4420-99cf-97bda3dbafe0" type="video/mp4">
</video>
