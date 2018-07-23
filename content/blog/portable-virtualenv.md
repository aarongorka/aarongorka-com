---
title: "Portable Virtualenv"
date: 2018-07-12T23:01:43+10:00
featuredImage: "/media/IMG_20171107_152915.jpg"
---

Ever wanted to move a Python virtualenv around but found it didn't work? Here's how you can create a portable virtualenv for Python 3.6.

<!--more-->

{{< load-photoswipe >}}
{{< figure src="/media/IMG_20171107_152915.jpg" >}}

```bash
python3.6 -m venv --copies venv
sed -i '43s/.*/VIRTUAL_ENV="$(cd "$(dirname "$(dirname "${BASH_SOURCE[0]}" )")" \&\& pwd)"/' venv/bin/activate
sed -i '1s/.*/#!\/usr\/bin\/env python/' venv/bin/pip*
```

Done! Now you can copy your venv across directories, servers, or even mount inside a Docker container (my usecase).

## How does this work?

  * `python3.6 -m venv --copies venv`

I'd previously created virtualenvs using the `virtualenv` application, but this seems to be the new, recommended way of creating them.

  * `sed -i '43s/.*/VIRTUAL_ENV=...`

This is the important part. Normally, the path that you create the virtualenv in is hardcoded in this file, which is what breaks when you move it.

To fix this, we use a neat hack that grabs the location of the bash script from within the bash script (`${BASH_SOURCE[0]}`), then cd to the directory two parents above. Printing the working directory after that means that whenever you `source venv/bin/activate`, the path is always correct - even after moving it.

We then use sed to replace the 43rd line - which is consistently the same line each time you create a virtualenv (luckily).

  * `sed -i '1s/.*/#!\/usr\/bin\/env python/' venv/bin/pip*`

The `pip` binaries installed normally have the path to the python binaries hardcoded. This updates them to use the settings set by sourcing the `activate` script.
