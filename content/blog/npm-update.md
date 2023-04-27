---
title: "`npm update`, but actually useful"
date: 2023-04-27T12:01:47+10:00
---

Intuitively, to update a package using [npm](https://www.npmjs.com/), you might assume you need to run something like:

```bash
npm update
```

This command does [nothing](https://stackoverflow.com/questions/39758042/npm-update-does-not-do-anything). The correct command is:

```bash
npm install <package name>@latest
```

<!--more-->

As a human being who occasionally needs to update libraries in a software project, I expect my package manager to have some shortcut to do this. I want:

  * Determine the latest version for all libraries (or, if specified, a single specific library)
  * Said versions installed locally
  * The package file (`package.json`, `requirements.txt`, etc.) to be updated with the now-installed version
  * The package lockfile to be updated

Supposedly this just isn't possible with npm, according to the first 4 answers in the [top Stack Overflow question](https://stackoverflow.com/questions/39758042/npm-update-does-not-do-anything/67957330) for this topic. The [5th answer](https://stackoverflow.com/a/67957330/2640621) gives us a hint to something that works for doing a package at a time, but needs to resort to xargs to update all packages at once.

```bash
npm outdated | cut -d" " -f1 | tail -n +2 | sed 's/$/@latest/' | xargs npm i
```

:shrug:
