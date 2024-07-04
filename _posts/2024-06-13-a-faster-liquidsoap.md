---
layout: post
title: A Faster Liquidsoap (part 1)
---

_The fast part_

![giphy](https://github.com/savonet/blog/assets/871060/7053e175-f51f-401f-949d-c49c68676fc9)

As the project grows in functionality, community and maturity, we are now facing issues that are more typical of established 
software where the focus has to shift on making things do _the same thing_ but, also, _more efficiently_!

The variety of use-case and user interest toward liquidsoap was clearly visible at this year's [Liquidshop](https://www.liquidsoap.info/liquidshop/4/).
We were very excited to welcome presentations about new use of the software such as the brand new **autocue**, interesting perspectives on the meaning of radio and its current demographics
and potential use and more. Make sure to go see the recorded presentations if you want to learn more!

On our end, we have been focused on making `2.3.x` ready for production and, one of the thing that has been a growing issue with each release 
has been the time to load a script as well as the average memory footprint. Well, good news, these issues have been greatly improved. Let's see what we did
there!

## How your script is loaded

Conceptually, there are 3 main steps when starting liquidsoap with a user-prodided script:

1. The script is **parsed**, producing a _term_
2. The term is **type-checked**.
3. The term is **evaluated**, producing a _value_

During the parsing phase, your script, represented as a string, i.e. a sequence of characters, is processed into 
a representation that can be manipulated in the code. Typically, this code:
```liquidsoap
(123, "aabb")
```
becomes something of the form:
```ocaml
`Pair (`Int 123, `String "aabb")
```
Parse errors and other errors related to the syntax of your script are raised during this phase, typically when your script
contains invalid syntax, for instance:
```liquidsoap
# Correct syntax is: { foo = 123 }
x = { foo: 123 }
```

During the type-checking phase, we check that your code is _safe to run_. There's a lot to unpack here but, conceptually, 
we make sure that, for instance, if a function takes an integer as input, it is never called with a string:
```liquidsoap
def f(x) =
  x + 1
end

# Typing error here!
f("aabb")
```

Typing errors are raised during the type-checking phase. This is most likely also where most of the errors you will see from your script will come from.
Please, be patient with it, they are there to make sure your script eventually runs smoothly!

During the evaluation phase, a term, which is nothing more than a computer-friendly representation of your initial script,
is eventually executed and converted into an actual value. For ground term such as integers and strings as shown above, this
does not do anything but, for terms such as:
```liquidsoap
s = sine()
```
The evaluation phase is when the `sine` source actually gets created. During this phase, runtime errors are raised, for instance when a source 
is fallible and an output expects it to never fail.

## The standard library

Before your script is run, we also have to parse, type-check and evaluate the _standard library_. The standard library is a set of functions
and other definitions such as _protocols_, _decoders_ and more that are defined using the scripting language.

Much of liquidsoap's standard functionalities, such as `playlist` are in fact defined as liquidsoap scripting code. This has allowed us to reduce the size of the OCaml code and lot and, with it, the complexity of the core engine.

However, this is also comes at a cost: not all users use the full set of functionalities provided by the standard library yet, it is always evaluated in full.

In the past, we have tried to reduce the parts of it that are expected for most users by separating between core and extra APIs. However, there is still **a lot** in the core standard library!

## Cost analysis

The type-checking phase is, by far, the most time-, cpu-, and memory-consuming. This is because there are **a lot** of things to check and
we now have **a lot** of functions, methods, settings etc. 

Indeed, over the recent years, our standard library has grown exponentially.

Initially, we had a tiny `utils.liq` containing only about `50` top-level functions (version `0.9.2`)
These were mostly for convenience and backward compatibility.

As time went on, we expanded the available API to welcome as many user-requested feature as we
could and to accomodate a growing set of abstractions such as tracks vs. sources etc.
Nowadays, we have about `2000` functions in the standard library!

Adding more functionality to the standard library means increasing the memory footprint and CPU usage, both during the typechecking phase and because of
the memory required to keep all the standard library's function during the script's execution. 

Lastly, the language has also gained more powerful abstractions. The addition of _methods_, developped by [@smimram](https://github.com/smimram) has really pushed the language to a much more mature and usable level. However, this has also resulted in added CPU and memory consumption due to the 
added complexity in the type-checking phase.

The functionalities improvements have had 3 main consequences:
* Increase the startup time.
* Increase the startup memory peak.
* Increase the runtime memory footprint, that is, the memory retained when the script is running after cleaning up the memory used during the script loading phases.

It's hard to compare exactly how much memory is consumed between version because this also includes _shared memory_, which is the memory used to 
load shared libraries and the project has also 
added a lot more of those in recent years, most importantly via `ffmpeg`.

This will be discussed in-depth in part 2 of this post series!

Here are some rought numbers, based on running the simple script `output.dummy(blank)`. Startup time is computed using `time liquidsoap 'print("bla")'`. 

| `1.3.3` (docker image: `debian:buster`) | `64Mo` | `0.091s` |
| `1.4.3` (docker image: `savonet/liquidsoap:v1.4.3`) | `95Mo` | `0.163s` |
| `2.2.5` (docker image: `savonet/liquidsoap:v2.2.5`) | `190Mo` | `3.879s` |
| `2.3.x` (docker dev image from May 9, 2024) | `206Mo` | `5.942s` |

These numbers are not necessarily the most accurate. There are computed using a M3 macbook with `docker`. The `2.3.x` numbers are obtained a `amd64` docker image as this is the only type available for dev builds.

Nonetheless, as you can see, it was high time we had a pass at optimizing this!

## Optimizing script loading

The idea for script optimization is simple: if your script has been type-checked once and nothing has changed (liquidsoap binary, standard library), then you should not have to type-check it again on subsequent runs as we already know that it is safe!

Technically, this called for a _caching_ layer that is, to save the result of the typechecking the script and re-use it when possible.

To acheive this, we do two things:
1. We keep a hash of the full script. This is a short string that indicates wether the script has changed. If a script generates a hash for which we have a cache, then we can skip the type-checking phase and read directly from the cache.
2. We store the result of the typechecking. Reading from the stored value should be much faster than re-doing the whole type-checking.

To implement these changes we had to do a couple of code changes and implementations:
1. Make sure that the script is loaded all at once. Before caching, we would load, typecheck and store in memory the standard library before doing the same for the user script. Because we need to account for any code change when computing the script's hash, we are now evaluating a single script with the standard library inserted at the beginning of it. This also makes it possible to cleanup all the standard library's functionalities that are not used by the user script!
2. Next, we used [ppx_hash](https://github.com/janestreet/ppx_hash), a really cool OCaml ppx that makes it possible to simply annotate the OCaml code to automatically generate fast hashing functions. Using it, we were able to compute a fast hash of the user script after consolidating it with the standard library.
3. Lastly, we used OCaml's [Marshal](https://ocaml.org/manual/5.2/api/Marshal.html) module which is a very versatile and powerful module that makes it possible to store and retrieve entire OCaml values. It is fast and super abstract. All we have to do is write and read from a cache file!

Finally, it should be mentioned that we are not just caching the user script! We are also caching the standard library itself. This makes it possible to also type-check other scripts much faster as we can simply pull the cached version of the standard library and only type-check the new script itself!

## Outcome

The results are pretty stunning!

Here's a log on first run, when the script hasn't been cached:
```
2024/07/03 14:31:41 [startup:3] main script hash computation: 0.03s
2024/07/03 14:31:41 [startup:3] main script cache retrieval: 0.03s
2024/07/03 14:31:41 [startup:3] stdlib hash computation: 0.03s
2024/07/03 14:31:41 [startup:3] stdlib cache retrieval: 0.03s
2024/07/03 14:31:41 [startup:3] Typechecking stdlib: 3.37s
2024/07/03 14:31:41 [startup:3] Typechecking main script: 0.00s
```

And here it is after caching:
```
2024/07/03 14:32:59 [startup:3] main script hash computation: 0.02s
2024/07/03 14:32:59 [startup:3] Loading main script from cache!
2024/07/03 14:32:59 [startup:3] main script cache retrieval: 0.05s
```

Lastly, here it is for a new script, re-using the standard library cache:

```
2024/07/03 14:33:27 [startup:3] main script hash computation: 0.02s
2024/07/03 14:33:27 [startup:3] main script cache retrieval: 0.02s
2024/07/03 14:33:27 [startup:3] stdlib hash computation: 0.03s
2024/07/03 14:33:27 [startup:3] Loading stdlib from cache!
2024/07/03 14:33:27 [startup:3] stdlib cache retrieval: 0.10s
2024/07/03 14:33:27 [startup:3] Typechecking main script: 0.00s
```

😳

In production, you should be able to run liquidsoap once using the `--cache-only` option and preemptively compute your script's cache. Then, all subsequent
run of the script should use the cache and be super fast!

For more details, please check out the [cache documentation](https://www.liquidsoap.info/doc-dev/language.html#caching). In particular, you should pay attention to the different cache locations and file permissions!

### How about memory usage?

Another really cool advantage of the caching system is that, when running the script from the cached data,
we do not have to allocate all the memory required during type-checking. This results in an overall reduced memory footprint.

However, this is not enough to understand the whole picture with memory usage. As it turns out, memory consumption is
rather complex and this will be the topic of our next post..

![giphy](https://github.com/savonet/blog/assets/871060/bd274b82-0182-47f3-bfe7-cb018c4d15f0)
