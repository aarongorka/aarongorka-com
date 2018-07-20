---
title: "Mass CloudFormation Template Validation"
date: 2018-07-18T23:39:31+10:00
featuredImage: "/media/IMG_20170711_142233.jpg"
---

Ever needed to do CI on a centralised CloudFormation repository, and struggled to get template validation done **quickly**? Here's how you can do it.

{{% figure src="/media/IMG_20170711_142233.jpg" %}}

## Why?

Ideally, Infrastructure as Code lives in the repo alongside the code that gets deployed on to it. Sometimes reality is different, and you have a lot of CloudFormation templates all in one repository. As part of our CI pipeline, we want a stage that will validiate the syntax of these templates, and as quickly as possible.

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
FILES := $(shell find . \( -name "*.y*ml" -o -name "*.json" \))

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

This solution uses [cfn-python-lint](https://github.com/awslabs/cfn-python-lint), which is called by running `cfn-lint -t "<FILENAME>"`. On failure it outputs the failing lines and exits with a non-0 exit code, making it perfect for CI pipelines. cfn-python-lint runs completely locally, in contrast to the AWS CLI (`aws cloudformation validate-template...`) which requires API calls to AWS. This is not only slow and requires authentication, but can contribute to the total API call rate of your account - causing API call throttling in unrelated (potentially production) services.

Now we need to run this against all of our templates, however cfn-python-lint only runs against a single template. We will take advantage of the capabilities of Make to parallelise it. First, we build a list of any YAML or JSON files under the working directory. If this was picking up unrelated files, we exclude them by appending `-not -name ".gitlab-ci.yml"` to the find command. The list of generated files is stored in the `$(FILES)` variable. For each entry in the `$(FILES)` variable, we call `cfn-lint`. Normally this would execute sequentially, so we use the `-j` flag to run in parallel. This drastically increases the speed at which we can validate templates. `.PHONY` is used to work around the [incremental build](http://www.evanjones.ca/makefile-dependencies.html) feature of Make.

This all runs inside the `amaysim/cfn-python-lint:0.3.3` container which has all the dependencies to run cfn-python-lint preinstalled. docker-compose is used to manage the various flags needed to run the image such as mount points and the entrypoint.

The docker-compose command itself is stored as a Make target, providing a target that we can then call: `make test`.
