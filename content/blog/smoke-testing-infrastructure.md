---
title: "Smoke Testing Infrastructure"
date: 2019-05-24T11:23:20+10:00
featuredImage: "/sebastien-gabriel-182782-unsplash.jpg"
---

Some real-world examples on how to smoke test infrastructure.

<!--more-->

{{< load-photoswipe >}}
{{< figure src="/sebastien-gabriel-182782-unsplash.jpg" alt="Photo by Sebastien Gabriel on Unsplash https://unsplash.com/photos/TG-Ea4dvDm0" >}}

{{< blockquote link="http://softwaretestingfundamentals.com/smoke-testing/" >}}
The term ‘smoke testing’, it is said, came to software testing from a similar type of hardware testing, in which the device passed the test if it did not catch fire (or smoked) the first time it was turned on.
{{< / blockquote >}}

---

# Background

When deploying a CDN (Content Delivery System), you want to prevent the CDN from being bypassed and the origin contacted directly. In AWS, one method of achieving this is using WAF (Web Application Firewall). [This fantastic guide](https://www.cloudar.be/awsblog/using-the-application-load-balancer-and-waf-to-replace-cloudfront-security-groups/) details how to set up WAF, ALB and CloudFront to protect your origin. **TL;DR**: you send a secret header in every request from CloudFront, and the WAF attached to your ALB rejects any traffic without this secret header.

I have a client who needs to protect their origin from being accessed directly, so I wrote a Terraform module to create a regional WAF ACL which we would then attach to their ALB (Application Load Balancer). I can test that the syntax is correct with `terraform validate` and a `test.tfvars` file with some dummy parameters, but this doesn't necessarily prove that it will have the desired functionality when I deploy it.

# Why?

I could manually deploy and test the Terraform module; this is how I normally see organisations make infrastructure changes. But the benefits of [Continuous Integration][], [Continuous Delivery][] and [Continuous Deployment][] apply to infrastructure workflows just as much as software development.

  * Trunk-based development greatly simplifies git workflows
  * CI/CD pipelines reduce risk of human error
  * Continuous Deployment improves time to production
  * Greater confidence in making changes to infrastructure
  * **Reduce cognitive load required for changes**

[Continuous Integration]: https://en.wikipedia.org/wiki/Continuous_integration
[Continuous Delivery]: https://en.wikipedia.org/wiki/Continuous_delivery
[Continuous Deployment]: https://en.wikipedia.org/wiki/Continuous_deployment

# High Level Overview

The strategy for testing the WAF is simple:

  1. Deploy ephemeral infrastructure
  1. Send one request without the secret header, assert that the response is a 403
  1. Send one request with the secret secret header, assert that the response is a 200
  1. Teardown ephemeral infrastructure

# Framework

We're running our tests in Docker using the [3 Musketeers](https://3musketeers.io/) pattern: 

`docker-compose.yml`:
```yaml
services:
  terraform-python:
    image: "cmdlabs/terraform-utils:2.0.0"  # image with Terraform and Python
    entrypoint: []
    env_file: ".env"
    working_dir: "/work/test"
    volumes:
      - ".:/work"
```

`Makefile`:
```make
smokeTest:
    docker-compose run --rm terraform-python sh -c 'pip3 install -q tox && tox'
```

We use [tox](https://tox.readthedocs.io/en/latest/) to automagically configure our dependencies and [pytest](https://pytest.org/) to provide a nice framework for Python-based testing (detailed `assert` output, setup/teardown and improved exception output).

```ini
[tox]
envlist = py36
skipsdist=True

[testenv]
passenv = *
deps =
    requests
    pytest
    python-terraform
commands =
    pytest -s
```

The IaC (Infrastructure as Code) tool I'm using here is Terraform. Specifically, I'm testing a Terraform module, so there's nothing _actually deployed_ by this project to test (a separate project implements the module and deploys the infrastructure). I'm also deploying WAF, which by itself does nothing --- it needs to be attached to an ALB or CloudFront to do anything.

The strategy we can use here is to deploy some ephemeral infrastructure to provide the minimum functionality to test what the module does. We can take advantage of ALB's [fixed-response][] feature to avoid having to deploying a webserver to return the 200 response.

[fixed-response]: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-listeners.html#fixed-response-actions

That's where the `python-terraform` library comes in. We can use it to setup and teardown for the duration of the test.

The library is not even particularly good (it pretty much just parses the shell output of `terraform` :sweat_smile:), but it does work. Python has libraries for just about everything, and even if it doesn't, you can always just invoke shell commands (check out [sh](https://amoffat.github.io/sh/) as a nice wrapper). `requests` makes HTTP calls as simple as `curl`.

Here's what our setup/teardown looks like:

```python
# run setup before all tests, teardown after all tests finished
@pytest.fixture(scope="module")
def setup():
    workspace = "my-workspace" # using Terraform Workspaces
    tf = Terraform()

    # I already have a terraform.tf file in the working directory that defines the ALB
    tf.init(upgrade=True, raise_on_error=True)

    # idempotent workspace creation
    try:
        tf.workspace("select", workspace, raise_on_error=True)
    except:
        tf.workspace("new", workspace, raise_on_error=True)

    kwargs = {"auto_approve": True}
    try:
        # build the infrastructure!
        tf.apply(**kwargs, skip_plan=True, input=False, no_color=IsFlagged, capture_output=False, raise_on_error=True)
        outputs = tf.output(capture_output=True, raise_on_error=True)

        # setup is finished, pass the URL of the ALB to the test function and run tests
        yield outputs
    finally:
        # tests are finished, destroy the infrastructure
        tf.destroy(auto_approve=True, capture_output=False, raise_on_error=True)  
```

The actual test function is really simple. I'm testing that my WAF protects against requests directly to the origin and that requests from CloudFront (with a special header set) are allowed:

```python
def test_terraform(setup):
    url = setup['alb_url']['value']
    r = requests.get(url)
    assert(r.status_code == 403)
    r = requests.get(url, headers={"X-Origin-Verify": "my-secret-uuid"})
    assert(r.status_code == 200)
```

The output:

```console
$ docker-compose run --rm terraform-python sh -c 'pip3 install -q tox && tox'
You are using pip version 18.1, however version 19.1.1 is available.
You should consider upgrading via the 'pip install --upgrade pip' command.
py36 create: /work/test/.tox/py36
py36 installdeps: requests, pytest, python-terraform
py36 installed: atomicwrites==1.3.0,attrs==19.1.0,certifi==2019.3.9,chardet==3.0.4,idna==2.8,more-itertools==7.0.0,pluggy==0.11.0,py==1.8.0,pytest==4.4.1,python-terraform==0.10.0,requests==2.21.0,six==1.12.0,urllib3==1.24.3
py36 run-test-pre: PYTHONHASHSEED='1676464830'
py36 run-test: commands[0] | pytest -s
============================= test session starts ==============================
platform linux -- Python 3.6.8, pytest-4.4.1, py-1.8.0, pluggy-0.11.0
cachedir: .tox/py36/.pytest_cache
rootdir: /work/test
collected 1 item                                                               
 
test_terraform.py data.aws_vpcs.main: Refreshing state...
data.aws_subnet_ids.main: Refreshing state...
aws_security_group.main: Creating...
<Terraform creation logs...>
Apply complete! Resources: 9 added, 0 changed, 0 destroyed.
Outputs:
 
alb_url = http://test-20190508050651788900000002-385328424.ap-southeast-2.elb.amazonaws.com
.data.aws_vpcs.main: Refreshing state...
<Terraform destruction logs...>
aws_security_group.main: Destruction complete after 28s
 
Destroy complete! Resources: 9 destroyed.
 
========================== 1 passed in 228.79 seconds ==========================
___________________________________ summary ____________________________________
  py36: commands succeeded
  congratulations :)
```

# What to Test?

I don't see much value in writing a test that is just a 1:1 copy of the Terraform. Unit testing is an accepted paradigm in software development because unlike most IaC, you usually can't just eyeball to tell how it will behave in all cases.

I also don't see much value in asserting the existence of our resources after we've created them. At that point you're essentially testing whether or not the AWS APIs work, rather than any code you've written. If CloudFormation says `SUCCESS` then I'm pretty comfortable with assuming that the resources exist.

What I do find valuable is running smoke tests on real infrastructure in order to test:

  * Specific behaviour you require (WAF blocking the right requests!)
  * Outputs of complex IaC
  * E2E functionality and integration between all moving parts

Extensive coverage on IaC may end up being more work than it's worth, especially if any of the tests are flaky. Just testing the happy path will provide a lot of benefit without being a huge burden to maintain.

# Other Examples

  * Verifying data persistence on EBS using [Packer](https://www.packer.io/), CloudFormation, [stacker](https://github.com/cloudtools/stacker) and [Fabric](https://docs.fabfile.org/en/2.4/): https://github.com/aarongorka/ebs-pin
  * Verifying database creation/connectivity using [Kubernetes Jobs][]:

`job.yml`:
```yml
apiVersion: batch/v1
kind: Job
metadata:
  name: mongodb-test
  namespace: test
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: mongo
          image: mongo
          entrypoint: []
          command: ["mongo", "--nodb", "/work/test.js"]  # simple connectivity test
          volumeMounts:
            - mountPath: "/work"
              name: mongodb-test
              readOnly: true
      volumes:
        - name: mongodb-test
          secret:
            secretName: mongodb-test
  backoffLimit: 3
```


`test_mongo.py`:
```python
def test_db(setup): # setup creates secret and deletes the Job once done
    core_api = client.CoreV1Api(k8s_client)
    batch_api = client.BatchV1Api(k8s_client)    
    utils.create_from_yaml(k8s_client, "job.yml")

    # helper function using the https://github.com/litl/backoff library
    response = wait_for_success(batch_api, core_api, name, namespace)

    assert response is not None  # our container successfully ran whatever test it had to!
```

[Kubernetes Jobs]: https://kubernetes.io/docs/concepts/workloads/controllers/jobs-run-to-completion/

# Conclusion

Test your infrastructure by verifying the happy path of the complex logic you've written to improve confidence and reliability of your infrastructure deployments.
