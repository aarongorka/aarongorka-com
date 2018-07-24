---
title: "Local Log Visualisation"
date: 2018-07-15T21:32:10+10:00
featuredImage: "/media/20160716_145825.jpg"
draft: true
---

{{< load-photoswipe >}}
{{< figure src="/media/20160716_145825.jpg" >}}

Logging is key in observability in a microservices architecture. Without good logs, you often have no real way of troubleshooting other than relying on tribal knowledge, guesswork and luck. A common pattern that I like is verbose, structured logging in JSON. This makes the data being logged from your microservice easy to aggregate and consume and therefore useful in troubleshooting.


Such log output can commonly look like this:
