---
layout: post
title: Precise scheduling of tracks
---

After responding to a [user request](https://github.com/savonet/liquidsoap/discussions/2972) about scheduling a top of the hour source, it seemed like this would
be a good opportunity to document a little bit more how to properly schedule time-specific tracks with liquidsoap and also investigate the CPU usage from
the current scheduling implementation used in this response.

### The problem

We want to have a source that plays a single track at the top of each hour. Maybe it is a jingle or a bell, who knows!

In this post, we will not cover how to integrate this source in your streaming system, which can be done with a `switch` or `smooth_add` and more.

We will focus instead on creating a source that will be ready and available at the top of each hour with a prepared track that can be played immediately.

For this purpose, we use `request.queue`. Sources created using this operator can be used to push new requests at any given time.

However, once pushed, requests need to resolved, which means downloading the file if needed and checking that we can decode it with the expected content.

For this reason, a request will not be immediately available when pushed to the queue. Thus, we need to make sure we push new requests ahead of time
to make sure that they will be ready at the top of the hour.

Let's say, at minute `30` of each hour. Should be enough time right? 🙂

### Implementation

Here's our implementation. Should be pretty straight forward!

```liquidsoap
# Top of the hour queue
top_of_the_hour = request.queue(id="top_of_the_hour")

# When we're at minute `30`, queue a new song to make sure it is fully prepared at the top the next hour
def queue_announcement()
  next_hour = time.local().hour+1

  announcement_file = "/path/to/#{next_hour}.mp3"

  request = request.create(announcement_file)

  top_of_the_hour.push(request)
end
thread.when({30m}, queue_announcement)

# Now create a source that will be ready and play a single request at the top of each hour:
top_of_the_hour = switch([
  ({0m}, top_of_the_hour)
])
```

### Performances impact

One trick in the above code is `thread.when`. Internally, liquidsoap runs a bunch of asynchronous task queues. The implementation for `thread.when`
creates a recurrent queue that checks on the given predicate and executes the callback when the predicate goes from `false` to `true`.

This works fine but can have consequences on the CPU usage if we are polling too often. For this reason, it seemed interesting to investigate CPU usage in
relation to thread polling interval. Also a good opportunity to take advantage of our internal metrics!

Here's the code to generate the data. It needs the latest `rolling-release-v2.2.x` or `main` to take advantage of the cpu usage metric:

```liquidsoap
# Start everything after 1s to let the
# process parse and typecheck the standard
# library and etc.
thread.run(delay=1., fun () -> begin
  t = time()

  # Decrease interval over time
  def every() =
    if time () <= t + 10. then
      1.
    elsif time () <= t + 20. then
      0.5
    elsif time () <= t + 30. then
      0.1
    elsif time () <= t + 40. then
      0.05
    elsif time () <= t + 50. then
      0.01
    elsif time () <= t + 60. then
      0.005
    else
      0.001
    end
  end

  # This is our (empty) recurrent task
  thread.run(every=every, fun () -> ())

  cpu_usage = runtime.cpu.usage_getter()

  # Output cpu usage and interval to stdout each second
  thread.run(delay=1., every=1., fun () -> begin
    let { total } = cpu_usage()
    process.stderr.write("#{time()-t} #{every()} #{total*100.}\n")
  end)
end)
```

This can be run as:
```sh
% liquidsoap --force-start /path/to/test.liq 2> /path/to/plot.dat
```

We can now plot the resulting data:


![cpu_usage](https://user-images.githubusercontent.com/871060/227742334-61669241-df8e-4b0b-a521-58835b0efd3b.png)

Looks like up-to `0.1` seconds, we should pretty fine and the default for the operator is `0.5`!

