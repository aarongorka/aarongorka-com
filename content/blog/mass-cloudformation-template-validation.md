---
title: "Mass CloudFormation Template Validation"
date: 2018-07-18T23:39:31+10:00
featuredImage: "/media/IMG_20170711_142233.jpg"
---

Ever needed to do CI on a centralised CloudFormation repository, and struggled to get template validation done **quickly**? Here's how you can do it.

<!--more-->

{{< load-photoswipe >}}
{{% figure src="/media/IMG_20170711_142233.jpg" %}}

## Why?

Ideally, Infrastructure as Code lives in the repo alongside the code that gets deployed on to it. Sometimes reality is different, and you have a lot of CloudFormation templates all in one repository.

Amazon have historically provided a CloudFormation template validation tool using the AWS CLI (`aws cloudformation validate-template --template-body file://myfile.yml`). This method has some limitations:

  * Requires you to be authenticated
  * Is slow due to network latency
  * Running in parallel risks API throttling
  * Raises error on long (but still valid) templates
  * Misses non-fatal errors (duplicate keys, unused parameters, etc.)

I wanted a tool that could be run both on our CI platform and locally, and required no internet access. For a while I tried running [cfn-lint](https://github.com/martysweet/cfn-lint). It struggled to cope with the large library of questionably maintained CloudFormation templates that I needed to validate. One day, I stumbled across [**cfn-python-lint**](https://github.com/awslabs/cfn-python-lint).

## Files

docker-compose.yml
```yaml
version: '3'
services:
  cfn-python-lint:
    image: amaysim/cfn-python-lint:0.3.3
    network_mode: "none"
    entrypoint: ''
    working_dir: /srv/app
    volumes:
      - .:/srv/app:Z
```

Makefile
```make
FILES := $(shell find . \( -name "*.y*ml" -o -name "*.json" \) -not -name "docker-compose.yml")

test:
	docker-compose run cfn-python-lint make -j 8 _test

_test: $(FILES)

$(FILES):
	cfn-lint -t "$@"
.PHONY: $(FILES)
```

## How To Run

Make sure you have **Make**, **docker-compose** and **Docker** installed, then run:

`make test`

## Explanation

cfn-python-lint is run by calling`cfn-lint -t "<FILENAME>"`. On failure it outputs the failing lines and exits with a non-0 exit code, making it perfect for CI pipelines.

However, _cfn-python-lint can only run against a single template at a time_, which is far too slow. We will take advantage of the capabilities of **Make** to parallelise it.

First, we use the `find` command to build a list of any YAML or JSON files under the working directory. If this was picking up unrelated files, we can exclude them by appending `-not -name ".gitlab-ci.yml"` to the find command.

 The list of generated files is stored in the `$(FILES)` variable. For each entry in the `$(FILES)` variable, we call `cfn-lint`. Normally this would execute sequentially, so we use the `-j` flag to run in parallel. This drastically increases the speed at which we can validate templates. `.PHONY` is used to work around the [incremental build](http://www.evanjones.ca/makefile-dependencies.html) feature of Make.

This all runs inside the [amaysim/cfn-python-lint:0.3.3](https://hub.docker.com/r/amaysim/cfn-python-lint/) container which has all the dependencies to run cfn-python-lint preinstalled. docker-compose is used to manage the various flags needed to run the image such as mount points and the entrypoint.

The docker-compose command itself is stored as a Make target call locally or in our CI tool:

>`make test`

## Example

{{< asciinema "/asciinema/tmpv5rxjz5b-ascii.cast" >}}
