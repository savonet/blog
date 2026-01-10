---
layout: post
title: Liquidsoap 2.4.1 is out!
---

# Liquidsoap 2.4.1 is out!

Liquidsoap `2.4.1` is out! This is the first bugfix release of the `2.4.x` release cycle.

You can grab it and read the detailed changelog [here](https://github.com/savonet/liquidsoap/releases/tag/v2.4.1).

Most of the heavy lifting in terms of internal rewrite and new features has now been done we are now fully committed to bringing more stability and long-term enhancements to the framework.

This release should be safe to upgrade to for all users on the `2.4.0` release. In general, we strongly suggest migrating your code to our latest release: our resources are limited and the latest stable release if where we put all our efforts to fix bugs.

As usual, we do recommend testing the release on a staging/testing environment before pushing it to your production runtime.

A few new things with this release, mostly to facilitate user's life:
* Initial metadata support for the `%ffmpeg` encoder to help support container-level setup such as DVB Service and Provider names (see: [#4665](https://github.com/savonet/liquidsoap/issues/4665))
* `start`/`stop` server/telnet commands for outputs
* A new `settings.syslog.level` to help set the syslog level.

Other important enhancements concern clocks and dynamic source collection, which is still a hotspot for us. If you're using a lot of dynamic sources and outputs, make sure to keep in touch with us, we want to keep making this as stable and usable as possible but we do not always think about all the possible use-case!

Lastly, the issues where large covert art binary data kept showing up in logs when logging metadata should finally be fixed! These strings are now tagged as binary internally and filtered out during logging/printing!

## Supported FFmpeg versions

In the future, we want to keep supporting the last two major FFmpeg releases. Currently, this means version `7` and `8`.

Now that `2.4.1` is out, we have some pending changes that will break compatibility with FFmpeg versions before `7`.

This is important because we want to keep track of the improvement and changes upstream and to make sure that we keep bringing new features to
our users.

This can be challenging, however, because distributions do not always move as fast as FFmpeg releases. In such cases, we recommend using docker images
which should allow to run a build from a more recent OS on your host's OS.

## Supported OS versions for binary release assets

For the same reason, and also because of limited bandwidth, we want to keep supporting the latest LTS and most recent release of our Debian and Ubuntu
release builds. The most recent OS and versions are now described in our [README](https://github.com/savonet/liquidsoap?tab=readme-ov-file#supported-oses-for-pre-built-binary-assets)

This means that we have to keep updating our build images to reflect the latest such releases. We try our best not to but this could possibly impact bugfix
releases as well.

Again, if this is a concern, please consider using `docker` to deploy your script. This way you should always be able to upgrade to the latest binary image
regardless of your host's OS.
