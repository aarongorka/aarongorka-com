---
title: "Gitlab Monorepo Pipelines"
date: 2019-09-18T10:45:00+10:00
featuredImage: "/gitlab_dag.png"
draft: true
---

Using GitLab's DAG feature to build monorepo pipelines.

<!--more-->

{{< load-photoswipe >}}
{{< figure src="/gitlab_dag.png" >}}

---

Top-level `.gitlab-ci.yml`:
```yaml
---
stages:
  - diff-and-build
  - ops
  - dev
  - dev-test
  - preprod
  - mgmt
  - mgmt-test
  - prod

include:
  - '/elasticsearch/.gitlab-ci.yml'
  - '/fluentbit/.gitlab-ci.yml'
  - '/kibana/.gitlab-ci.yml'
  - '/terraform/.gitlab-ci.yml'
```

Example of child `.gitlab-ci.yml`:
```yaml
build-and-push-kibana:
  stage: diff-and-build
  environment:
    name: docker-kibana
  script:
    - echo "Building a Docker image!"

diff-dev-kibana:
  stage: diff-and-build
  script:
    - echo 'Running helm diff...'

diff-mgmt-kibana:
  stage: diff-and-build
  script:
    - echo 'Running helm diff...'

deploy-dev-kibana:
  stage: dev
  environment:
    name: dev-kibana
  script:
    - echo 'Running helm upgrade...'
  only: [ master ]
  needs:
    - build-and-push-kibana
    - diff-dev-kibana
    - diff-mgmt-kibana

test-dev-kibana:
  stage: dev-test
  script:
    - echo 'Running smoke test...'
  only: [ master ]
  needs:
    - deploy-dev-kibana

deploy-mgmt-kibana:
  stage: mgmt
  environment:
    name: mgmt-kibana
  script:
    - echo 'Running helm upgrade...'
  only: [ master ]
  needs:
    - test-dev-kibana

test-mgmt-kibana:
  stage: mgmt-test
  script:
    - echo 'Running smoke test...'
  only: [ master ]
  needs:
    - deploy-mgmt-kibana
```

## Visualisation

Generating a diagram:

{{< gist aarongorka f454fcdab27ace61ce9bcfdab49829ca >}}

With stages included:

{{< figure src="/gitlab_dag_stages.png" >}}

## `only:changes`

https://docs.gitlab.com/ee/ci/yaml/#onlychangesexceptchanges

{{< figure src="/gitlab_full_dag_ui.png" >}}

Feature branch stage:
```
build-and-push-kibana:
  only:
    changes:
      - "*"  # run pipeline if a root-level file like Makefile or docker-compose.yml is changed
      - "kibana/**/*"  # run pipeline if any files under kibana/ have changed
```

Master-only stage:
```
deploy-dev-kibana:
  only:
    refs:
      - master  # only run if there are changes and we're on master branch
    changes:
      - "*"
      - "kibana/**/*"
  needs:
    - build-and-push-kibana
    - diff-dev-kibana
    - diff-mgmt-kibana
```

Merge request/feature branch pipelines always run all stages because the destination branch is unknown (to do a diff) before you create a Merge Request. Hoping for a feature to set the branch to do diffs against in the future.

{{< figure src="/gitlab_pr_pipeline.png" >}}

After merging, only the relevant pipeline is run:

{{< figure src="/gitlab_pr_post_merge.png" >}}
