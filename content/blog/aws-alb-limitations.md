---
title: "AWS ALB Limitations"
date: 2018-07-14T11:20:07+10:00
---

AWS Application Load Balancer has a few limitations that may not be obvious. Keep these limitations in mind when considering what load balancing solution best suits your needs.

<!--more-->

# Cost

ALBs are not "serverless" and cost at least $20/month to run. This adds up quickly when you have many microservices, several environments, and potentially multiple deployments within each environment. The performance capabilities of a single ALB are quite high, so you will want to share them where possible.

# Routing Rules & Priority Numbers

When you create a routing rule on an ALB e.g. "path `/foo` should be directed to Target Group `bar`", you need to specify a priority on that rule. When a request enters the ALB, it is matched against each rule in the order of priority until there is a match.

What this means, is that you cannot easily deploy a microservice with standalone configuration to a shared ALB. To create a rule, you must know which priority "slot" you will use (1-100), and the only real way to do this dynamically is to query the ALB to find out what rules already exist, and then pick a "slot" that is free.

Compared to microservice-native load balancing solutions like Traefik or Fabio (where a microservice merely needs to advertise itself to the load balnacer), this is quite clunky and will hamper CI/CD.

# Canary Deployments

In a canary deployment, you gradually route increasing amounts of traffic to your new deployment and use error rate monitoring to roll back if there's an issue. If you are using ALB's routing rules to do deployments (by changing the Target Group), you cannot implement canary deployments. The current recommendation is to use Route53 (DNS) to do canary deployments. This is not ideal as rollbacks are at the mercy of each caching server and are not instant or even guaranteed.

# ECS Services

You can only register one Target Group to an ECS Service.

This can impact the ability to have both internal and internet-facing addresses for a microservice, as an ALB can only be one or the other.
