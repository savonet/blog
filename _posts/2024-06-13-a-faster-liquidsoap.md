---
layout: post
title: A Faster Liquidsoap
---

# A Faster Liquidsoap

_(also with less memory consumption!)_

![giphy](https://github.com/savonet/blog/assets/871060/7053e175-f51f-401f-949d-c49c68676fc9)

As the project grows in functionality, community and maturity, we are now facing issues that are more typical of established 
software where the focus has to shift on making things for _the same_ but, also, _more efficiently_!

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

## Cost analysis

The type-checking phase is, by far, the most time-, cpu-, and memory-consuming. This is because there are _a lot_ of things to check and
we now have _a lot_ of functions, methods, settings etc. 

Over the recent years, our standard library has grown exponentially.

Initially, we had a tiny `utils.liq` containing only about `50` top-level functions (version `0.9.2`)
These were mostly for convenience and backward compatibility.

As time went on, we expanded the available API to welcome as many user-requested feature as we
could and to accomodate a growing set of abstractions such as tracks vs. sources etc.
Nowadays, we have about `2000` functions in the standard library!

This was also reinforced by our commitment to move as many functionalities as we could from the core OCaml code. This helps make the core code
more robust and the library more flexible for users.

Adding more functionality to the standard library means increasing the memory footprint and CPU usage, both during the typechecking phase and because of
the memory required to keep all the standard library's function during the script's execution.

Lastly, the language has also gained more powerful abstractions. The addition of _methods_, developped by [@smimram](https://github.com/smimram) around `2020`,
has really pushed the language to a much more mature and usable level. However, this has also resulted in added CPU and memory consumption due to the 
added complexity in the type-checking phase.

The functionalities improvements have had 3 main consequences:
* Increase the startup time.
* Increase the startup memory peak.
* Increase the runtime memory footprint, that is, the memory retained when the script is running after cleaning up the memory used during the script loading phases.

It's hard to compare exactly how much memory is consumed between version because this also includes _shared memory_, which is the memory used to 
load shared libraries and the project has also 
added a lot more of those in recent years, most importantly via `ffmpeg`.

Nonetheless, here are some numbers, based on running the simple script `output.dummy(blank)`. Startup time is computed using `time liquidsoap 'print("bla")'`.

| Version | Memory consumption| Startup time |
|---------|-------------------|--------------|
| `1.3.3` (docker image: `debian:buster`) | `64Mo` | `0.091s` |
| `1.4.3` (docker image: `savonet/liquidsoap:v1.4.3`) | `95Mo` | `0.163s` |
| `2.2.5` (docker image: `savonet/liquidsoap:v2.2.5`) | `190Mo` | `3.879s` |
| `2.3.x` (compiled from the latest `main` branch) | `94Mo` | `0.89s` |

As you can see it was high time we did something about this!

Thankfully, the latest `main` branch is now almost on par with the `1.4.3`
on memory footprint. I'm suspecting there wasn't much difference between `1.4.3` and `1.3.3` overall and inclined to think that the
difference is due to the loaded shared memory. Typically, the debian packages is not built with `ffmpeg` enabled.

Startup time is not quite back to what it used to be but it's clearly much, much better. Also, we expect that the improved startup time will be mostly 
constant as the number of API function increases due to the nature of the optimization we've put in place.

Let's talk about those now!

## Optimizing script loading

