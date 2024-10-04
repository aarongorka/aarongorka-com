---
title: "How Not to Do Healthchecks"
date: 2024-10-05T05:02:00+10:00
draft: true
---

Just because I see it all too often, so here's some examples.

<!--more-->

## Server/container-terminating healthchecks

Examples would be:

  * Liveness probes in Kubernetes
  * ALB healthchecks on an ASG with [loadbalancer health checks enabled](https://docs.aws.amazon.com/autoscaling/ec2/userguide/health-checks-overview.html#elastic-load-balancing-health-checks)

Intuitively, you add some code to your healthcheck endpoint that checks if you have connectivity to downstream services like your database or a 3rd party API or even just some other internal microservice. However...

  * Does restarting your server help availability if the database is down?
  * Does restarting your server help fix issues with other services?
  * Do you want _all_ of your servers restarting (endlessly) if a e.g. third party endpoint goes down?
  * What happens when all your microservices in an organisation have this behaviour?

Hopefully the obvious answer is no, but it does leave the question of "but how do I stop unhealthy servers from routing traffic if there's a network issue or something"?

Unfortunately ALB doesn't give you anything to help with this (as always with AWS services, you _could_ come up with something yourself to do this but I've never seen anyone bother), but at least in Kubernetes we have...

## "Stop serving traffic" healthchecks

The only example I have of this is:

  * Readiness probes in Kubernetes

Unlike the other kind of healthcheck, these don't cause a storm of restarting instances when there's a problem - so it's fine to check connectivity to downstream services.

Yes, there are scenarios where splitting these two checks out means you might miss automatically restarting a server when it would fix the problem, but you can compensate for that with monitoring and on average you'll be better off anyway.
