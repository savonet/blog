---
layout: post
title: Liquidsoap 2.1.4 and rolling release 2.2.x are out!
---

Liquidsoap `2.1.4` [is out](https://github.com/savonet/liquidsoap/releases/tag/v2.1.4)! 🎉

Liquidsoap Rolling Release `2.2.x` is [now available](https://github.com/savonet/liquidsoap/releases/tag/rolling-release-v2.2.x)! 🎉

The `2.1.4` release contains important bug fixes, including a last-minute memory issue with http requests and queries that was introduced in `2.1.3`. All users are encouraged to migrate to it but make sure to use a staging environment before pushing to production just in case! Full changelog is [here](https://github.com/savonet/liquidsoap/blob/v2.1.4/CHANGES.md#214-2022-03-01)

Next, we would like to shift our focus to the `2.2.x` release cycle. We are done with the changes there and will now focus on fixing issues there. We do encourage new projects to start with it and users to report issues. We will prioritize these issues over other ones.

The `2.2.x` release contains some exciting changes, in particular a switch to `dune` as the build system and a new support for multitrack decoder/demuxing/muxing/encoding. You can read more about it [here](https://www.liquidsoap.info/doc-dev/multitrack.html). Full changelog is [here](https://github.com/savonet/liquidsoap/blob/main/CHANGES.md#220-unreleased).

Lastly, based on feedback, it looks like a spring date for the next [liquidshop](http://www.liquidsoap.info/liquidshop/) would be best for everyone. We will start working on it soon and hope to see all y'all there!
