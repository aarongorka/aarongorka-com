---
title: "VPC Endpoints Without the Magic"
date: 2021-05-19T11:31:15+10:00
---

A short summary of the two types of VPC Endpoints and how they work.

<!--more-->

# TL;DR

There are two types of VPCEs:

  1. Gateway (routed)
  2. Interface (DNS)

## Gateway

Updates your route tables to route traffic intended for the IPs of a given service through Amazon's SDN instead of the internet.

This endpoint behaves similarly to the [VPC DNS endpoint](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resolver.html) in that they cannot be hit from outside the VPC; even with VPC peering, DirectConnect or a VPN, these endpoints can only be hit from instances within the VPC. Gateway endpoints are only available for two AWS services (S3 and DynamoDB) and [incur no additional charges](https://docs.aws.amazon.com/vpc/latest/privatelink/vpce-gateway.html#gateway-endpoint-pricing).

## Interface

Provisions an ENI within your VPC and an Amazon-managed private hosted zone is associated with your VPC.

When your VPC DNS endpoint is queried, the private zone will take precedence and instead of recursively resolving to the authoritative resolver for the zone, the query will resolve to the IPs of the ENI.

Private hosted zones cannot be _directly_ hit from outside the VPC, but it is possible to put a recursive resolver in front of your VPC DNS to enable sharing of interface endpoints across VPCs such as in [this solution](https://docs.aws.amazon.com/whitepapers/latest/building-scalable-secure-multi-vpc-network-infrastructure/centralized-access-to-vpc-private-endpoints.html).

---

One notable "side-effect" of inteface endpoints is that they will route all requests that match a DNS pattern: whether they're for a service you own or not. An example of this is API Gateway. Creating an interface endpoint for `com.amazonaws.us-east-1.execute-api` means that any request for `*.execute-api.us-east-1.amazonaws.com` (for example, a 3rd party service that also happens to be using API Gateway) will be routed to the AWS management plane endpoint (which will _not_ serve requests for said 3rd party service).
