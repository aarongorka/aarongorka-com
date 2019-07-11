---
title: "Git Revert Last n Commits"
date: 2019-07-11T10:24:07+10:00
---

To revert the last _n_ commits using git:

```bash
git revert HEAD~3..HEAD
```

<!--more-->

Where `HEAD~3` resolves to the 3rd most recent commit, `HEAD` resolves to the most recent commit, and `..` between the two fills in every commit in between.

You can also add `--no-commit` to stage it all as one commit.
