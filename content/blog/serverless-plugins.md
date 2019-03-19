---
title: "Serverless Plugins"
date: 2018-07-12T23:37:04+10:00
aliases: ["/blog/serverless-plugins.html"]
---

Here are some cool plugins for [Serverless](https://serverless.com):

  1. [serverless-log-forwarding](https://github.com/amplify-education/serverless-log-forwarding)

    >I want a log solution that is both durable and has powerful search capabilities
 
    CloudWatch Logs is reliable, but that's about it. You need something that you can search and analyse logs with, and this plugin is the bridge between Lambda and your log aggregation system.
 
  2. [serverless-plugin-aws-alerts](https://github.com/ACloudGuru/serverless-plugin-aws-alerts)

    Building a full suite of alerts for a Serverless application is not simple, but this gives you a big head start. It alerts on the 4 main metrics (one being errors) that are already provided by CloudWatch Metrics. Just install and configure a destination SNS topic that sends to your alert aggregation system.

  3. [serverless-plugin-tracing](https://github.com/alex-murashkin/serverless-plugin-tracing)

    >What is causing my Lambda to run for so long?

    Automatically enables X-Ray on specified Lambdas. I had my doubts on whether or not X-Ray would be worth the effort of setting up, but I'm glad I gave it a go. It takes next to no effort to set up and gives you awesome insight on external calls to e.g. MySQL or a HTTP endpoint.
