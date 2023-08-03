---
title: "Fixing Security for Terraform Plan"
#date: 2021-10-15T11:11:36+11:00
date: 2023-08-03T16:18:23+10:00
featuredImage: "/tfstate.png"
---

So you want to lock down your Terraform state?

<!--more-->

![State picture](/tfstate.png)

## Problem Scenarios

>### "I don't want a malicious actor to read secrets that have been put in to Terraform state"

You'll need to deny the ability for all your engineers to read state. To do this effectively it means not only denying their user role, but any indirect method they may have too such as through CI on feature branches.

At this point, you need to either have approvals to run a `plan` (as you would on a public, open source project) or just forget about running plan on feature branches at all (of which, neither options are real practical).

Alternatively, you could deny read on only production and allow `plan` on non-prod workloads - but running against production is really the most valuable part of a plan.

  * ❌ Denying read on secrets denies the ability to `terraform plan`
  * ❌ Denying read on production state denies you production `terraform plan`

>### "I don't want an engineer to accidentally nuke a stack due to reading the wrong state file"

It's a common story; an engineer copypastes an Infrastructure as Code repository so they can inhert all the nice boilerplate that has been written for linting and the pipeline and testing, and then they `rm -rf` the existing Terraform and write their own resources. Much easier than figuring out all of the files required and writing them out by hand!

... Except they forgot to update the [backend](https://developer.hashicorp.com/terraform/language/settings/backends/configuration) and change the [key](https://developer.hashicorp.com/terraform/language/settings/backends/s3#key) to reference a new project. When Terraform runs, it sees that _none_ of the resources in the state file are defined in the `.hcl` files and decides that they all need to be deleted. In an automated, zero-touch pipeline, this is pretty disastrous.

You can deny read to state, but your CI runners still need access to it to... Do deployments. You likely don't have individual roles per _pipeline_, so there's no real effective option here.

  * ❌ Denying read on state denies the ability to do deployments

>### "I don't want a malicious actor to craft a state file that pwns my CI"

By adding in a [`local-exec`](https://developer.hashicorp.com/terraform/language/resources/provisioners/local-exec) provisioner you can basically execute whatever you want if you can write to the state file. Easy way to compromise a CI server or an engineer's workstation.

So controlling who can write to the state file is important. There's no real way around this. At a minimum, you'll need your privileged CI runners to be able to write to it (so they can do deployments). You may also want to separate write permissions by environment, so that your dev deployments can't write to the prod stack's state.

`local-exec` is awful in any case and it would be great if you could get rid of it and every other method of calling arbitrary shell commands. [Dynamic resource providers](https://www.pulumi.com/docs/concepts/resources/dynamic-providers/) are a much nicer way of doing this but I suppose even that doesn't mitigate this problem given you can then execute arbitrary NodeJS.

  * ✅ Denying write on state to low privilege users is a sensible tradeoff

## There is a way

One of the big problems here is that Terraform _always_ wants access to secrets to run a plan. This doesn't need to be the case though; Terraform already knows how to plan when it doesn't know the certain values beforehand (for example, before you've created dependent resources) and will mark them as "computed".

Additionally, your options for encrypting the statefile is either encrypting the entire thing or none of it. With something like Pulumi's [secrets](https://www.pulumi.com/docs/concepts/secrets/#programmatically-creating-secrets) and [alternate encryption providers](https://www.pulumi.com/docs/concepts/secrets/#available-encryption-providers) you can encrypt _just_ the secret values in state, and then deny access to the key that has encrypted them using whatever access control your encryption provider has.

With these two changes, you can now have unprivileged runners or users do plans without needing access to secrets. It won't be a full plan; but it's likely good enough.

Or, just stop putting secrets in state.

## Sensible defaults

The other thing that would be nice to see is a default flag on Terraform that prevents you from giving yourself a heart attack because you've run your new Terraform project against the (wrong!) production statefile.

If you're running a plan/apply and every single resource in the statefile is being deleted (and new ones are being created), in probably 99.99% of cases this will not be intended. There's probably some other heuristics you could use for this, like state age, or number of updates, or size. For edge case scenarios where this is the intended action, it seems reasonable enough to add a flag (`--please-delete-all-my-resources`) to confirm you're cool with this.

## Conclusion

  * ✅ Denying write on state to low privilege users is a sensible tradeoff
  * ❌ Anything else beyond that is probably not worth your time
  * Hopefully Terraform and co. come out with some features for this
  * Just don't put secrets in state if you can
