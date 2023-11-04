---
layout: post
title: Liquidsoap 2.2.2 is out!
---

Liquidsoap `2.2.2` is out! You can grab the latest build assets here: https://github.com/savonet/liquidsoap/releases/tag/v2.2.2

This is the second bugfix release of the 2.2.x release cycle. The most important fix is related to pop/clicks heard during crossfade ([#3318](https://github.com/savonet/liquidsoap/issues/3318)) and the ffmpeg decoder failing with files and streams with unknown codecs.

This is the first release since we improved developers tools so feel free to also take this opportunity to update your developer setup!

As usual, we recommend trying this version with a staging/preview system before putting it on production. Beside that, this release should improve the stability of all scripts running on the 2.2.x release branch.

We want to thank all contributors, bug reporters and patient users who have helped us bring all these improvements!

Full changelog:

# 2.2.2 (2023-11-02)

New:

- Added `string.escape.html` ([#3418](https://github.com/savonet/liquidsoap/issues/3418), [@ghostnumber7](https://github.com/ghostnumber7))
- Add support for getters in arguments of `blank.detect` ([#3452](https://github.com/savonet/liquidsoap/issues/3452)).
- Allow float in source content type annotation so that it possible to write: `source(audio=pcm(5.1))`

Changed:

- Trim urls in `input.ffmpeg` by default. Disable using `trim_url=false` ([#3424](https://github.com/savonet/liquidsoap/issues/3424))
- Automatically add HLS-specific ffmpeg parameters to `%ffmpeg` encoder ([#3483](https://github.com/savonet/liquidsoap/issues/3483))
- BREAKING: default `on_fail` removed on `playlist` ([#3479](https://github.com/savonet/liquidsoap/issues/3479))

Fixed:

- Allow `channel_layout` argument in ffmpeg encoder to set the number of channels.
- Improved support for unitary minus, fix runtime call of optional methods ([#3498](https://github.com/savonet/liquidsoap/issues/3498))
- Fixed `map.metadata` mutating existing metadata.
- Fixed reloading loop in playlists with invalid files ([#3479](https://github.com/savonet/liquidsoap/issues/3479))
- Fixed main HLS playlist codecs when using `mpegts` ([#3483](https://github.com/savonet/liquidsoap/issues/3483))
- Fixed pop/clicks in crossfade and source with caching ([#3318](https://github.com/savonet/liquidsoap/issues/3318))
- Fixed pop/clicks when resampling using `libsamplerate` ([#3429](https://github.com/savonet/liquidsoap/issues/3429))
- Fixed gstreamer compilation. Remember that gstreamer features are DEPRECATED! ([#3459](https://github.com/savonet/liquidsoap/issues/3459))
- Fixed html character escaping in `interactive.harbor` ([#3418](https://github.com/savonet/liquidsoap/issues/3418), [@ghostnumber7](https://github.com/ghostnumber7))
- Fixed icecast not reconnecting after erroring out while closing connection in some circumstances ([#3427](https://github.com/savonet/liquidsoap/issues/3427))
- Fixed parse-only mode ([#3423](https://github.com/savonet/liquidsoap/issues/3423))
- Fixed ffmpeg decoding failing on files with unknown codecs.
- Fixed a crash due to `wait_until` timestamp being in the past when using `posix-time2`
- Make sure that temporary files are always cleaned up in HLS outputs ([#3493](https://github.com/savonet/liquidsoap/issues/3493))
