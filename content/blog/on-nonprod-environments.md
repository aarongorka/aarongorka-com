---
title: "On Nonprod Environments"
date: 2018-08-03T10:06:38+10:00
---

Nonprod environments can have a huge impact on the speed at which you can reliably deliver software to your customers. Here are some points to help remove that friction and get deploying to production as fast as possible.

<!--more-->

## Avoid Naming Your Environments Dev Or Test

The problem with Dev(elopment) and Test(ing) as environment names is that they have well-defined meanings in languages and frameworks like Ruby on Rails and Nodejs. It's unintuitive that you don't use `devDependencies` when deploying to your "dev" environment. This is because we deploy an _immutable artifact_ to all environments --- it is the same artifact that will go to production, and we don't want our `devDependencies` included in it. 

This can become even more confusing when you do in fact need your `devDependencies` for deployment. For example, when using the Serverless framework, you do not want to bundle the Serverless utility itself with your application, but it needs to be installed during your deployment stage. You need your `devDependencies` installed for dev but you don't want `devDependencies` for in your artifact which is deployed to dev. This isn't something a new engineer is going to understand without being walked through it.

Then you have environment variables like `RAILS_ENV` and `NODE_ENV`. If I'm deploying to the "dev" environment, I should set `RAILS_ENV` to "development", right? Again, you run in to the earlier problem, where we don't have our development gems in the immutable artifact we are deploying to "dev". If we set `RAILS_ENV=development`, Rails will try to load development gems and will fail to boot. Best practice here is to hardcode `RAILS_ENV=production` in to your Dockerfile.

## Strictly Curate Your Environments

No man is an island, and development teams are no exception. Unless your app operates in a vacuum, it will need to integrate with other applications in the organisation.

Without strictly defining and enforcing the nonprod environments that you have, integrating your apps becomes a mess of broken redirects and invalid authentication tokens. When you receive errors from upstream applications, you'll never be sure where that error came from and where to look for logs. Was it UAT1 or UAT2? Which Dev environment is live right now? Nobody is ever quite sure which URL to use to access a particular application. Data becomes inconsistent as you log in as a user that exists in one environment but not the other.

The solution to all of these problems is to use **static integrated environments**. This means that nonprod environments are decided at an organisation level, and all applications must be deployed to each of these environments. You can still have multiple deployments to a single environment (v1, v2, etc...), but there should be one _official_ version that receives traffic for that environment. Use consistent naming conventions and there will never be any confusion as how to access a given application.

One solution to help achieve this is to provide a centralised entrypoint for the organisation (in the form of reverse proxy or service mesh), and then have one of these per-environment. Each application is allocated a _path_. This allows you to easily swap out the backend services (to new versions or new platforms) without having to update every single application that integrates with it. The environment is obvious at a glance. Using a consistent entrypoint removes all ambiguity when configuring a new application for integration.

## Your Nonprod Environment Is Not A Playground

If you ever find yourself deploying a change to an environment without really knowing if it will work, consider whether you need to change your approach to testing. Nonprod environments are not sandboxes, and engineers should be able to adequately test locally before deploying.

Conversely, if you ever find yourself hesitating to deploy a feature to your nonprod environments, consider whether you need a feature toggling service. If you ever find yourself deviating from [trunk based development](https://trunkbaseddevelopment.com) and deploying branches that aren't merged to the trunk, you need to invest in feature toggling capabilities. This will enable you to deploy to your nonprod environments without doing a "big bang" release that may affect other development teams.

Another good justification for feature toggles is if you are using a "preprod" environment to showcase changes to product owners. Rather than limiting release velocity by forcing everyone to deploy to an additional environment, use feature toggles in production to show how it would _actually_ look like in production.

## The Fallacy Of Environment Disparity

Everyone has experienced this --- the lack of parity between production and nonprod environments. You set out to complete a minor task and after implementing it in a nonprod environment, you find that production has a completely different set of circumstances. Untold hours of engineering effort go wasted in making features work in both sets of circumstances.

Inevitably, someone suggests that a certain feature isn't required in the nonprod environments for a new service being created. "We don't need CDN caching in QA", "we can save money by sharing the database in all our nonprod environments" or "we don't need WAF in UAT". It is ironic that these suggestions come from the same people that have suffered from poor choices in the past, but somehow we always end up thinking that cutting corners will be cost-efficient.

**No one ever saved money by removing parity between production and nonprod environments.** 

At best you are incurring debt that accumulates interest every time someone has to troubleshoot or work around this disparity. At some point, the rate at which you accumulate debt becomes so large (due to production outages, irreproducible bugs, etc.) that you will need to pay this debt off by re-introducing parity. It is actually simpler if you toss out the idea of having separate architectures to begin with and _always deploy the same thing in every environment_. This is what we already do with _immutable artifacts_, and all the reasons we do this also apply to infrastructure.

If it's ever brought up that this is too much work, consider whether you are lacking automation in the form of Infrastructure as Code or Continuous Integration/Deployment. If it's ever brought up that a feature is too expensive to implement in nonprod (e.g. node-based pricing for monitoring software), reconsider how you are doing the cost comparison. A solution that is free to implement in nonprod will be 1/3rd the cost of one that isn't if you have 3 environments.

Here are some examples of commonly overlooked aspects of architecture in nonprod environments:

  * Logging
  * Monitoring
  * CDN infrastructure
  * Security (Web Application Firewalls, authentication)
  * Autoscaling and performance

## Security Begins In Nonprod

You can not afford to leave security concerns until you deploy to production. If your application is internet-facing, and your nonprod environments are not, you are testing your security in production. 

The idea that it is safe to expose your production environment (which holds customer or other sensitive data) but it is not safe to expose your nonprod environment (which holds dummy data) is a viewpoint that doesn't really hold up under scrutiny. Build your applications to be secure enough to put on the internet right from the beginning (including nonprod) and there's no last-minute concerns about security when you do go to production.

# Summary

After you implement these concepts, deploying to production becomes a much smaller burden --- even if you're dealing with a fragile, monolithic app. Your confidence (and therefore speed) will increase when you can reliably test. The result is that you can get those features out to customers a lot quicker and deliver value.
