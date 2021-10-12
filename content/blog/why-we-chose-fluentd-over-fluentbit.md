---
title: "Why We Chose Fluentd Over Fluent Bit"
date: 2021-10-12T09:40:25+11:00
featuredImage: "/fluent-compare-chart.png"
---

Fluent Bit is a log shipping agent, designed to be lightweight and run in distributed environments. So why did we pick Fluentd, which is written in Ruby and predates Fluent Bit?

<!--more-->

{{< load-photoswipe >}}

{{< blockquote link="https://www.fluentd.org/architecture" >}}
**Fluentd** is an open source data collector, which lets you unify the data collection and consumption for a better use and understanding of data.
{{< /blockquote >}}

{{< blockquote link="https://fluentbit.io/" >}}
**Fluent Bit** is an open source Log Processor and Forwarder which allows you to collect any data like metrics and logs from different sources
{{< /blockquote >}}


Sounds pretty similar, right? Intuitively, you'd pick the option that's more modern and is written in a lower-level language. The solution that seems to be gaining a lot of popularity and advertises being particularly compatible with Kubernetes.

{{< figure src="/fluent-compare-chart.png" alt="https://logz.io/blog/fluentd-vs-fluent-bit/" >}}

Which is what we did.

And when we set it up, it seemed to be working fine.

But as we continued to onboard more applications, we started seeing more and more issues. All somewhat minor, but enough to make us seriously reconsider what we had just implemented. I'm probably missing a few here, but some of them:

  * Constant timeouts on uploading to S3. Nothing out of the ordinary for these files, no resource contention in CPU/memory/network, no useful error messages to investigate (even at full debug log level).
  * No compression when posting documents to Elasticsearch. This is pretty expensive at scale.
  * [Memory leak](https://github.com/fluent/fluent-bit/issues/3204) when uploading to S3
  * [Annoying hacks](https://github.com/fluent/fluent-bit/issues/1775) required to separate logs in to different Elasticsearch indexes
  * Elasticsearch mapping errors are not logged unless you turn on [`Trace_Error`](https://github.com/fluent/fluent-bit/issues/1942#issuecomment-727109055)
  * Error counter metric [does not increase on error](https://github.com/fluent/fluent-bit/issues/1935)
  * Unlimited retry value on Elasticsearch output by default
  * Constant tweaks required to buffer-related values try and fix scaling issues
  * No support for Elasticsearch [data streams](https://github.com/uken/fluent-plugin-elasticsearch#configuration---elasticsearch-output-data-stream)

After migrating to Fluentd, basically all of these issues went away. We also now have access to a much more flexible configuration syntax (if perhaps a bit unreadable), and a much wider ecosystem of plugins should we need them.
