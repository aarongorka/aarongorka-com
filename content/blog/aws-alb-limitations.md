---
title: "AWS ALB Limitations"
date: 2018-07-14T11:20:07+10:00
---

Some gripes on AWS Application Load balancers.

<!--more-->

# Cost

ALBs are not "serverless" and cost at least $20/month to run. This adds up quickly when you have many microservices, several environments, and potentially multiple deployments within each environment. Unfortunately, managing a single shared ALB is actually more difficult than spinning up a new one for each service.

# Listener Rules & Priority Numbers

Listener rules are difficult to manage in a decentralised manner. When you create a routing rule on an ALB e.g. "path `/foo` should be directed to Target Group `bar`", you need to specify a priority on that rule. When a request enters the ALB, it is matched against each rule in the order of priority until there is a match.

What this means, is that you cannot easily deploy a microservice with standalone configuration to a shared ALB. To create a rule, you must know which priority "slot" you will use (1-100), and the only real way to do this dynamically is to query the ALB to find out what rules already exist, and then pick a "slot" that is free.

Compared to microservice-native load balancing solutions like Traefik or Fabio (where a microservice merely needs to advertise itself to the load balnacer), this is quite clunky and can hamper your CI/CD efforts.

# Canary Deployments

ALB has no capability to route _portions_ of traffic to different target groups. In a canary deployment, you gradually route increasing amounts of traffic to your new deployment and use error rate monitoring to roll back if there's an issue. If you are using ALB's routing rules to do deployments (by changing the Target Group), you cannot implement canary deployments. The current recommendation is to use Route53 (DNS) to do canary deployments. This is not ideal as rollbacks are at the mercy of each client and are not instant or even guaranteed.

# ECS Services

You can only register one Target Group to an ECS Service.

This can impact the ability to have both internal and internet-facing addresses for a microservice, as an ALB can only be one or the other.
