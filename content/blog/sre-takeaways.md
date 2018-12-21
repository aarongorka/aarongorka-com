---
title: "Google SRE Book Takeaways"
date: 2018-12-21T19:18:05+11:00
featuredImage: "/media/sre.png"
---

>SRE is what happens when you ask a software engineer to design an operations team.

I just finished reading through the (first) [Google SRE book](https://landing.google.com/sre/). While a lot of it is what we take for granted today, there were a few worthwhile takeaways for me.

<!--more-->

{{< load-photoswipe >}}
{{< figure src="/media/sre.png" attrlink="https://landing.google.com/sre/" >}}

## Automatic not automated

I really liked this distinction between automatic and automation. A lot of what people do can be described as automated; for example, writing a script that can clean up some malformed data. It saves time compared to having to click through dialogues and brings consistency.

But hooking that script up to an event source and having it be reliable enough to be run without any intervention is also sometimes called automation. The term _self-healing_ is also used, but it doesn't quite capture the scope that _automatic_ does.

This phrase makes it quite clear on what you're trying to achieve.

## Reduce familiarity (fatigue/contempt)

Reducing familiarity is a concept that I have come to believe in more and more through my career. The idea that you can keep a fresh perspective on whatever you're working on is really big in my mind.

Being able to bring new ideas to the table isn't possible if you've not had the opportunity to experience anything new.

## Google built APIs for software that didn't have them

The idea that you can use software written elsewhere but you must provide APIs for integration is great idea.

Looking back, I now have a lot more empathy for those trying to integrate with [software that doesn't provide an API](https://www.nagios.org/).

## Google had "tens of thousands of lines of shell script owned by dozens of teams".

>SREs moved from writing shell scripts in their home directories to building peer-reviewed RPC servers with fine-grained ACLs.

Funny to see that even Google has these problems.

## Unusual branching strategy

I really like [trunk based development][]. I will try to advocate for it where ever I can, and on all the projects I've been involved on it just works.

But branching strategies aren't one-size-fits-all, and it's good to see a use case where trunk based development isn't the best solution. Google need the capability to deploy several versions of a single application. They also need to be able to patch each individual version.

[trunk based development]: https://trunkbaseddevelopment.com/

## Monorepo. Not using git. 86TB repository.

I often hear that monorepos are great and that Google uses them. Some of the benefits are great; searching, refactoring, updating libraries and their dependees in one go.

The reality is that Google solves the tooling side of things by writing their own tools. This isn't realistic for any other organisation.

Pipelines in monorepos are not impossible, for example Gitlab [^1] does support them. Jenkins however, does not [^2] --- as do many other tools, I imagine.

[^1]: https://gitlab.com/gitlab-org/gitlab-ce/issues/18157
[^2]: https://issues.jenkins-ci.org/browse/JENKINS-43749

# Conclusion

Definitely a book worth reading for anyone in the DevOps or Cloud Engineering space.
