---
title: "CMS"
date: 2020-10-21T11:43:57+11:00
draft: true
---

# StatefulSets in ASGs

  * StatefulSets are an appropriate solution to a stateful CMS, but the toolkit is ASGs
  * Index orchestration
  * Persistent storage

## Index Orchestration

  * A set number of instances should be in service at any given time to account for licensing and attachment of persistent storage
  * Instances are numbered with an index of 1-4, hence "index orchestration"

The process is as follows:

    1. Userdata executes `index_orchestration.py`
    1. Determine which indexes in the set of `[1, 2, 3, 4]` are currently allocated via boto3's `client.describe_instances()`
    1. Determine how many instances are waiting to be allocated an index, backoff if there are too many
    1. If the instance does not have an index assigned, create a tag on the instance
    1. Create a DNS record with the index in it pointing directly to the instance

Initially this solution was provided by a Lambda that watched scaling events, but because the solution was so heavily dependent on it, it had to be synchronous so that the proceeding scripts could rely on it existing.

While this wasn't hard to get up and running, there were many edge cases where we hadn't considered permutations of the various states that the ASG could be in, such as multiple instances waiting for an index, or the ASG incrementing the desired count above the amount of available indexes during rolling updates. One workaround for this was to tag the ASG with the maximum number of indexes (4) rather than relying on the desired count to accurately reflect this. 

## Persistent Storage

Persistent storage is achieved for the StatefulSet ASG by using  https://github.com/aarongorka/ebs-pin. It enables an EBS snapshot to "float" between AZs by taking snapshots and recreating the volume when necessary.

Painfully, the CMS did not have any kind of properly defined separation between application code and state. While there was a directory that held _most_ of the state, some files outside of this directory were also modified during install. Therefore, the application needed to be (re)installed on every single boot. This significantly increased the boot time and subsequently, the deploy time.

To make matters even worse, patches for this application required a reboot before taking affect. Patched versions of the application were not available, all updates needed to be installed as in-place patches. This even further increased the boot/deploy time (more on that later).

Some challenges were had here around being able to clean up volumes/snapshots; specfically the requirement to clean up snapshots when tags were added or removed between deployments, but _not_ to cleanup the backups which inherited the tags of thevolume. The result was a matrix of scenarios in which a given snapshot would be cleaned up based on, and logic that operated on the union of existing and desired tags:

```python
    def test_can_delete_snapshot(self):
                                       # tags on snapshot                   # tags known by CLI (ebs-pin)
        assert ec2.can_delete_snapshot(["Team"],                            ["Name", "UUID", "Team"])   == False    # not ebs-pin, can't delete
        assert ec2.can_delete_snapshot(["Name", "UUID", "Team"],            ["Name", "UUID", "Team"])   == True     # the same, can delete
        assert ec2.can_delete_snapshot(["Name", "UUID", "Team", "Backup"],  ["Name", "UUID", "Team"])   == False    # has backup tag, can't delete
        assert ec2.can_delete_snapshot(["Name", "UUID", "Backup"],          ["Name", "UUID"])           == False    # has backup tag, can't delete
        assert ec2.can_delete_snapshot(["Name", "UUID", "Backup"],          ["Name", "UUID", "Team"])   == False    # has backup tag, can't delete
        assert ec2.can_delete_snapshot(["Name", "UUID"],                    ["Name", "UUID", "Team"])   == True     # CLI has new tag, can delete
```

# Deterministic Startup

  * `set_hmac.py`
  * Retries and backoff

### `cfn-signal`

To allow for continuous deployment of the application, a reliable and deterministic method of deploying applications and the ability to know _when_ the application had finished booted. The standard approach for this when dealing with ASGs is a combination of:

  * [Userdata]
  * [cfn-signal]
  * [AutoScalingRollingUpdate UpdatePolicy] with [WaitOnResourceSignals]

[Userdata]: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html
[cfn-signal]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-signal.html
[AutoScalingRollingUpdate UpdatePolicy]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-attribute-updatepolicy.html#cfn-attributes-updatepolicy-rollingupdate
[WaitOnResourceSignals]: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-attribute-updatepolicy.html#cfn-attributes-updatepolicy-rollingupdate-waitonresourcesignals

In short, this achieves a similar deployment strategy to [Kubernete's rolling update]. The caveat here is that `cfn-signal` does not automatically wait for healthchecks to pass, it fires immediately at the end of the script. Any logic that is used to determine whether the application has finished booting needs to be implemented ourselves.

[Kubernete's rolling update]: https://kubernetes.io/docs/tutorials/kubernetes-basics/update/update-intro/

### `poll_tg_health.py`

A simple script, it finds the TG (Target Group) for the calling instance and waits for the healthchecks for that instance to be "in service".

This was relatively painless, the only mildly inconvenient part being that there is no convenient API for finding the TG for an application, and that 2 TGs may exist at the same for a stack when the TG needs updating (replacing), necessitating quite a few API calls.

### Waiting for the CMS to start

The CMS that we're dealing with is quite unusual for an application that needs to be run in the cloud. It:

  * Has no API to tell whether it has started
  * Does not even know when it has started
  * Does not reliably start at all
  * Does not reliably fail in the same way when it doesn't start
  * Does not reliably fail, can get stuck indefinitely

A significant amount of engineering went in to a solution that "waits for the CMS to start". The approach was as follows:

  * Poll a broad range single easily-accessible endpoints and assert on expected functionality
  * Require successive sequential successes before reporting OK
  * Use backoffs and retries to achieve resilience during the boot process
  * Restart the CMS and begin polling again when a defined timeout is reached

Some of the issues encountered were setting appropriate timeouts (especially as the application got slower and slower to boot as more things were added to it) and bizarre failure scenarios; in one case it was found that prematurely hitting the login page would cause the application to break forever, forcing a redeployment/reinstall.

### Ping endpoints

When running a stack that sends a request through many reverse proxies, it's useful to be able to see what component in the stack is able to serve requests. It's also useful for healthchecks (specifically liveness probes, not that ALB distinguishes the two) so that downstream failures do not cause cascading failures.

In Apache HTTPD this was achieved with:

```
Alias "/ping" "/var/www/html/ping"
<Directory /var/www/html/>
    Options Indexes FollowSymLinks MultiViews
    Require all granted
</Directory>
```

As well as a plaintext file at `/var/www/html/ping` containing "pong". This probably isn't required in a default HTTPD installation, but it was necessary for coexistance with the rest of the reverse proxying configuration.

In Nginx, it's even more simple:

```
location /nginx-health {
    return 200 "healthy\n";
    access_log off;
}
```

# User/authentication Management

With some of the orchestration more closely related to the application, there was a requirement to have service accounts automatically created, as well as having credentials to privileged service accounts accessible to various scripts. [AWS Systems Manager Parameter Store] allows us to securely store credentials in an encrypted form, grant access with fine grained RBAC and easily retrieve them with 2-3 lines of code.

```python
client = boto3.client("ssm")
response = client.get_parameter(
    Name=f'/cms/{env}/admin-password',
    WithDecryption=True
)
```

or in BASH:

```bash
response="$(aws ssm get-parameter --region "ap-southeast-2" --with-decryption --name "/cms/${ENV}/admin-password")"
password="$(echo $response | jq --raw-output '.Parameter.Value')"
```

A script run on boot idempotently creates the service account with credentials fetched from Parameter Store, and scripts run after that that need to use the account can fetch the credentials. This works pretty well and is simple to implement.

But further requirements exponentially increase the complexity of the solution. We now have a requirement to _automatically periodically rotate credentials_. You see, because we only set the password once and never updated it, the credentials were effectively static, and started to be stored elsewhere (CI/CD systems, people's memory).

To achieve this, we have yet again borrowed from the concepts of Kubernetes and implemented these requirements as [controllers].

The controller in question watches the (desired) state of [Parameter Store], where we store the credentials of the service accounts. It regularly compares what is in Parameter Store to the (current) state by authenticating as that user. If the current state is found to not match the desired state, we must update that account's password. This is where it got quite tricky, because this automation also needed to be applied to the superuser account, and we were trying to log in to account when the password we fetched was wrong.

Luckily, two things allow us to work around this

  * The password for the superuser that the application is delivered with (yes, it's configured with an insecure default). Therefore, we can loop 
  * Parameter Store stores the previous values (history) of a parameter

Therefore, we can implement a cron job to run a script that queries the history of the password, and tries each one starting from the most recent until the current password is set. Then, we can now log in with the current password, and then update it to the desired password.

[controllers]: https://kubernetes.io/docs/concepts/architecture/controller/
[AWS Systems Manager Parameter Store]: https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html

# More Controllers

In addition to syncing passwords, we also have a controller that asserts that the "cluster" is configured. I use the word "cluster", because for parts of the CMS, there must be a 1:1 mapping between individual servers (as opposed to using load balancing).

This 1:1 connectivity is also implemented as a cron job running a script on each EC2 instance which asserts that configuration for connectivity is configured appropriately, with some extra code to achieve this in an idempotent fashion.

# Nginx TLS Termination

Because this application is clustered, each individual server is significant (unlike a stateless, horizontally scaling, cloud-native application) and occasionally the ability to directly troubleshoot/communicate with each instance is required.

This oneliner was userful to generate a self-signed cert:

```bash
openssl req -x509 -newkey rsa:4096 -subj '/CN=localhost' -nodes -keyout /etc/pki/tls/private/localhost.key -out /etc/pki/tls/certs/localhost.crt -days 365 && \
```

One issue encountered with this was that some implementations of TLS required that the SAN value be correct, despite the fact that this certificate was never in any trust store to begin with.

Normally adding SAN configuration requires creating a configuration file, but using [process substitution] we can create add SAN attributes to the oneline without it being too tedious:

```bash
<...> -extensions 'v3_req' -config <(cat /etc/pki/tls/openssl.cnf ; printf "\n[v3_req]\nkeyUsage = keyEncipherment, dataEncipherment\nextendedKeyUsage = serverAuth\nsubjectAltName = @alt_names\n[alt_names]\nDNS.1 = ${hostname}\nDNS.2 = localhost")
```

[process substitution]: https://en.wikipedia.org/wiki/Process_substitution

Another issue was the [NSPOSIXErrorDomain:100] with HTTP/2, Nginx, Apache HTTPD and Safari.

Fixing it was matter of removing the header as suggested in the article:

```
Header unset Upgrade
```

Testing as more interesting, with the [requests] library not supporting HTTP/2. It raises questions in my mind whether it's appropriate to keep using this library given most things will be speaking HTTP/2. [httpx] seems like quite a good drop-in replacement despite being in beta, supporting the same API as requests.

```python
import httpx

def test_cms_http2_upgrade_header():
    client = httpx.Client(http2=True)
    response = client.get(url=f"{url}/home")
    assert "Upgrade" not in response.headers
```

[requests]: https://requests.readthedocs.io/
[httpx]: https://github.com/encode/httpx
[NSPOSIXErrorDomain:100]: https://megamorf.gitlab.io/2019/08/27/safari-nsposixerrordomain-100-error-with-nginx-and-apache/

# Cache Invalidation

As a mostly-static website, caching in a Content Delivery Network (CDN) was a critical part of achieving a responsive website. The CDN of choice was [AWS CloudFront], which is essentially a full-site caching reverse proxy. Because it is a full-site CDN (as opposed to one that is _only_ used to deliver specific, static assets such as images, videos, javascript files, etc.) the content cached is not always long-lived and may need to be updated on-demand. This is where invalidation becomes extremely useful, as we can force a refresh of any asset on the CDN when the CMS determines than an update has been published.

Invalidating CloudFront _can_ be pretty straightforward:

`invalidate.py`:
```python
cloudfront.create_invalidation(
    DistributionId=distribution_id,
    InvalidationBatch={
	"Paths": {
	    "Quantity": len(invalidation_paths),
	    "Items": invalidation_paths,
	},
	"CallerReference": caller_reference,
    },
)
```

Where this became complex is:

  * There was no single trigger for content invalidation
  * There was no correlation ID between each of the servers triggering their invalidation
  * AWS does throttle the amount of concurrent invalidations at some point
  * The stack involved other applications which were dependent on the CMS and were _also_ making invalidations

To be able to deduplicate invalidations that occurred between servers without any kind of correlation ID, the best we could do was deduplicate based on time, with calls within a minute considered duplicates:

```python
import time
unix_time = int(time.time())
caller_reference = unix_time - unix_time % 60
```

An alternative approach was to invalidate only from a server with a specific index assigned, but this had other implications given the architecture.

In the invalidation script, pattern matching was used on the path to invoke various workflows, such as paths that didn't quite match the provided path due to rewrite rules, invalidating APIs and triggering invalidation workflows in other systems.

Finally, functionality to invalidate a list of _redirects_ caused some headache. A plaintext list of redirects (hundreds of them) was configured in the CMS, and [httxt2dbm] used to translate those in to Apache HTTPD redirect configuration. This took some additional engineering to create invalidations for, needing to parse the plaintext list of redirects and create an invalidation from that. This was fine, until we realised that the new list of redirects would not contain any redirects that were _removed_ from the list, and therefore would persist for the TTL of that cache behaviour. This was resolved by keeping a list of redirects previously used and creating a union of the two to find out what needed to be invalidated.

[AWS CloudFront]: https://aws.amazon.com/cloudfront/
[httxt2dbm]: https://httpd.apache.org/docs/2.4/programs/httxt2dbm.html

# Testing

In an attempt to move towards Continuous Delivery, testing was a critical part in achieveing this. The framework used for testing was a combination of [pipenv] for dependency management and [pytest] for running the tests/assertions.

[pytest]: https://docs.pytest.org/en/latest/
[pipenv]: https://github.com/pypa/pipenv

I'll break this up by the type of testing:

## Smoke Tests

This is where the most important testing happened; we could tell very quickly whether certain things were working or not.

    * Ping

### Ping

The most basic test, we assert that the webserver is reachable. If it does not pass, we fail the pipeline and do not continue promoting through each environment.

```python
import requests

def test_cms_ping_200():
    r = requests.get(f"{cms}/ping")
    assert "pong" in r.text
    assert r.status_code == 200
```

Testing slightly more of the stack, we now asset on content in the CMS. Having both these tests us to tell at a glance when there is an issue with the CMS vs. an issue with the webservers.

```
def test_cms_content_200():
    r = requests.get(f"{cms}/home")
    assert "Welcome to the homepage!" in r.text
    assert r.status_code == 200
```

### CORS

As a CMS that would have assets loaded by many 3rd parties, asserting that we had the correct CORS behaviour allowed us to be confident in what can sometimes be a complex subject.

```python
def test_cms_cors_allow_google_com():
    """Ensure that https://google.com is permitted in CORS"""

    origin = "https://google.com"
    headers = {"Origin": origin}
    r = requests.get(url=f"{cms}/logo.png", headers=headers)
    assert r.headers["Access-Control-Allow-Origin"] == origin
    assert r.status_code == 200

def test_cms_cors_deny_bad_actor():
    """Test access control origin for wicar.org, an example malicous website"""

    origin = "https://wicar.org"
    headers = {"Origin": origin}
    r = requests.get(url=f"{cms}/logo.png", headers=headers)
    assert "Access-Control-Allow-Origin" not in r.headers
    assert r.status_code == 200

def test_cms_no_default_cors():
    """Test no origin header, no CORS"""

    r = requests.get(url=f"{cms}/logo.png")
    assert "Access-Control-Allow-Origin" not in r.headers
    assert r.status_code == 200
```

A similar suite of tests were also added to the CloudFront pipeline given the nature of the configuring headers in CloudFront.

### DNS

Because the index orchestration solution had been written explicitly for this solution, thoroughly testing it was critical to ensure we could rely on it and worry about other things.

```
def test_dns_matches_index():
    """Loop through all ASGs and all indexes within those ASGs and compare DNS records with tags"""

    asg_names = ["app1", "app2", "app3"]
    for asg_name in asg_names:
        indexes = get_asg_indexes(asg_name)  # get the _max_ indexes for that ASG
        for index in indexes:
            record = f"{index}-{asg_name}.example.com"
            dns_ip = socket.gethostbyname(record)  # actual DNS lookup
            index_ip = get_instance_ip_by_index(
                asg_name, index
            )  # IP of instance with index tag
            assert dns_ip == index_ip
```

Fun fact: this fails once every few hundred deploys and I have no idea why. Despite making a synchronous call to update DNS in Route53, an incorrect DNS value is returned for a given record every now and then.

A similar test exists for EBS volumes, which also assets that they are tagged correctly.

### E2E content creation test

While the smoke tests very efficiently give a picture of the application's current health, they do not necessarily stress the integrations between the components of the application.

This test is far more complex than any of the smoke tests, and also far more prone to being "flaky". A good amount of time was spent in to ensuring that this test was resilient to intermittent failures that we were not interested in worrying about, and only telling us when the integration between components was broken.

```python
import pytest
import uuid
test_uuid = str(uuid.uuid4())

@pytest.fixture(scope="module")  # invoke as setup for test functions
def setup_e2e():
    wait_for_cluster_configuration()  # wait for the controllers to finish configuring connectivity
    delete_page()  # ensure we are starting from scratch
    pages = get_pages()
    if "/smoketest" not in pages:  # create page not idempotent
        create_page(test_uuid=test_uuid)
    replicate_content()
    wait_for_replication()
    yield  # code after yield is teardown
    delete_page()

# an example of using retries with backoff to make a test ignore intermittent unvailablility
@backoff.on_exception(
    backoff.expo,
    (
        AssertionError,
        requests.exceptions.HTTPError,
        requests.exceptions.ReadTimeout,
        KeyError,
        json.decoder.JSONDecodeError,
    ),
    max_time=120,
)
def create_page(uuid):
    auth = get_auth()
    r = requests.post(url, headers=headers, params={"action": "createPage", "title": test_uuid, auth=auth)
    r.raise_for_status()

@pytest.mark.parametrize(
    "execution_number", range(10)
)  # test a few times to try hit a few different instances
def test_content(setup_e2e, execution_number):
    url = f"{cms}/smoketest.html"
    r = requests.get(url)
    assert f"Smoke Test {test_uuid}" in r.text
    assert r.status_code() == 200
```

This is quite abbreviated, but it demonstrates a few things:

  * Using `pytest.fixture` to create a setup function for tests
  * Using `yield` in the setup to create teardown steps
  * Making the test resilient to uninteresting errors using [backoff]
  * Using `pytest.mark.parametrize` to run a single test many times if behaviour is not consistent
  * An end-to-end workflow of creating a page, invoking replication to test connectivity between components, testing the unique string (UUID) for this particular test and cleaning up afterwards


[backoff]: https://github.com/litl/backof://github.com/litl/backoff 

### Unit Tests

Finally, we have unit tests. A lot of the work in unit testing code is put in to mocking external calls. These external calls are basically either `requests` or `boto3`.

To mock boto3:

```python
def test_get_index():
    """get_index should retry query and return a number"""

    client = boto3.client("ec2")
    stubber = Stubber(client)
    response = {
        "Reservations": [
            {"Instances": [{"InstanceId": "i-1234567890abcdef0", "Tags": []}]}
        ]
    }
    stubber.add_response("describe_instances", response)
    response = {
        "Reservations": [
            {
                "Instances": [
                    {
                        "InstanceId": "i-1234567890abcdef0",
                        "Tags": [
                            {
                                "Key": "index",
                                "Value": "1",
                            }
                        ],
                    }
                ]
            }
        ]
    }
    stubber.add_response("describe_instances", response)
    stubber.activate()
    assert (
        index_orchestration.get_index(v_instance_id="i-abcdefgh1234", ec2=client)
        == "1"
    )
    stubber.assert_no_pending_responses()
```

This test validates that the function can deal with the data returned from boto3, that it performs a retry when needed, and that it is not making unexpected API calls (`assert_no_pending_responses()`).

The trick to easily testing boto3 is to pass around `client`s as a parameter, or to inject a mock like so:

```python
client = boto3.client("ssm")
stubber = Stubber(client)
with patch("boto3.client", return_value=client):
    my_module.my_function()
```

To mock requests, the [responses] library is immensely useful:

```python
import responses

@responses.activate
def test_home_page():
    """Assert that the origin is CMS when the response to /home is 200"""

    event = origin_request_event  # Lambda@Edge origin-request event
    context = {}

    responses.add(responses.HEAD, "https://cms-origin.example.com/home", status=200)
    request = lambda_function.lambda_handler(event, context)
    assert request["origin"]["custom"]["domainName"] == "cms-origin.example.com"
    mock_file.assert_called()
    assert len(responses.calls) == 1
```

This test validates that based on the response code returned by `requests`, the origin is modified to a particular domain name and no further requests are made. What is this Lambda function actually doing? See the [#Origin Routing Lambda] section below.

[responses]: https://github.com/getsentry/responses

### Configuration

Another use-case we had for testing is to test configuration, where an application accepts many different configurations but we want to enforce some behaviours.

One example was a situation where we were creating two very similar resources, but they needed separate configuration files. It would be very easy for these configuration files to drift, and if they did it would cause some unintuitive behaviour that would undoutably waste a lot of someone's time.

We could have also written something that templated a given file, which would ensure that the two were in sync (and I've done this many times before), but this was nice in that it meant both files were human-readable, easily distinguished and there was no abstraction on top of the files to manage.

```python
def test_config_files_are_same():
    with open("../config-1.yml", "r") as fh:
        config_1 = yaml.safe_load(fh)
    with open("../config-2.yml", "r") as fh:
        config_2 = yaml.safe_load(fh)
    # everything except the following fields should be the same
    # if they're not, someone probably updated one without updating the other

    keys_to_ignore = ["configuration_value_1", "some_other_config_key"]
    delete_keys_from_dict(config_1, keys_to_ignore)
    delete_keys_from_dict(config_2, keys_to_ignore)

    assert config_1 == config_2
```

In retrospect this is pretty similar to something like [conftest] or [Open Policy Agent], but instead of writing in [rego] we can leverage existing patterns and language to assert correct configuration.

[conftest]: https://www.conftest.dev/
[Open Policy Agent]: https://www.openpolicyagent.org/
[rego]: https://www.openpolicyagent.org/docs/latest/policy-language/

# Pipeline

The pipeline for this application follows principles from [trunk-based development]; only commits to master trigger deployments to integrated environments. However, commits to all feature branches (that is, branches that aren't master) will trigger a pipeline that creates a review environment: a short-lived deployment of the application within the dev environment that have no inbound integrations. This concept is also known as a [review app].

The pipeline roughly follows the following structure:

  * Unit tests
  * Build AMI
  * Deploy dev and then system test dev
  * Deploy staging, system test staging
  * etc., repeat for each environment until production

[multi-branch pipeline]: https://www.jenkins.io/doc/book/pipeline/multibranch/
[declarative pipeline syntax]: https://www.jenkins.io/doc/book/pipeline/syntax/#declarative-pipeline
[trunk-based development]: https://trunkbaseddevelopment.com/continuous-delivery/
[review app]: https://docs.gitlab.com/ee/ci/review_apps/

One of the most unfortunate consequences of this approach for this particular application was the _pipeline duration_. I would normally like to say that 1 hour is approaching the limit of what I'd consider to be appropriate for CI/CD. In theory, the total pipeline duration doesn't actually matter if your deployment procedure is robust, because you can simply not care about what happens once you've pushed your code (it will arrive in production eventually and you can feature toggle on your features at some stage). But no pipeline is ever bug free, and least of all this one. Because of the duration it took to boot the application, the feedback cycle was _awful_. This combined with enterprise requirements for an absurd _6 environments_, the total pipeline duration was:

((10 minutes per boot * 3 boots = 30 minutes per instance) * 2 batches of instances * 6 environments = **6 hours**

:(

# Review App Cleanup Lambda

As part of having a review app workflow, you need to consider review app cleanup. Cleanup can't be part of the pipeline, because it needs to happen asynchronously to any deployment activities. A developer will want to keep their review app running as long as their short-lived feature branch is alive, so it can't be tied to any of the events in a pipeline (e.g. finished deployment/testing) and it also shouldn't influence the outcome of the deployment. The event you want to clean up on is on _branch deletion_ (either that, or successful merge of a pull request) or when a branch is "stale" and you just want to clean up ([GitLab] is the one exception here in that it _does_ handle this kind of workflow).

Ideally a solution here can have two capabilities;

  * The ability to trigger from webhooks (from your git provider)
  * The ability to run on a schedule

Running on webhooks allows you to delete review apps when their respective branch is deleted, and running on a timer allows you to delete stale branches (with the caveat that you need to be able to determine how old resources are).

Admittedly, we didn't achieve this ideal state. Something that got us 90% of the way there was a Lambda function on a 1-day schedule that cleaned up all review apps. It adds some overhead to feature branches that take more than 1 day, but is otherwise kind of "good enough".

The implementation was as simple as

```python
def handler(event, context):
    clean_cms_stacks()
    clean_ebs_pin_volumes()
    clean_ebs_pin_snapshots()
    clean_cms_dns_records()
```

where each function looked for specific naming conventions/tags to find related resources to clean up (and more importantly, to leave resources for other apps alone).

[GitLab]: https://docs.gitlab.com/ee/ci/environments/index.html#environments-auto-stop

# Origin Routing Lambda

As part of a rush to deliver MVP for this project, there was very little consideration for the routing capabilities that come with CloudFront out of the box. CloudFront really only does routing based on prefix (it _can_ do a wildcard in the middle of the path, but most behaviours I've seen are prefix match).

Here we had two separate origins. A path e.g. `/blog` would route traffic to origin 1, with all pages under it going to origin 1 e.g. `/blog/my-page`. The complication was when there was a requirement for arbitrary pages to route to **origin 2** under the same prefix, e.g. `/blog/other-page`, _without changing the CloudFront behaviour configuration_. The requirement for not changing the cache behaviours in CloudFront was needed for two reasons:

  * It required a code change, which was not always accessible to those updating pages in the CMS
  * The number of pages required far exceeded the soft limit for the number of cache behaviours and even if we increased them, it did not seem sustainable going forward

This was pretty problematic and things didn't look too good. We were able to start thinking of solutions by rephrasing the problem slightly:

>I want CloudFront to serve pages from origin 2 when they exist, and serve pages from origin 1 when they are absent in origin 1

One solution was [origin failover with Origin Groups] which happened to have the right behaviour for routing between origins, but something told me that using this solution for highly available infrastructure to implement business logic wasn't the right way to go. I'm glad we made this call, because in hindsight it would not have worked out (keep reading).

Ultimately we landed on Lambda@Edge (L@E). There are even [examples in the official documentation] for this use-case, so it seemed like the right way to go. To elaborate on how this would work when a user requested a page from CloudFront:

  * For the given path, make a "preflight" request to origin 2
  * If the page exists in origin 2, the origin is changed to origin 2
  * If the page does not exist, leave the origin configuration as-is (origin 1)

This solution has a few benefits:

  * It required no code changes when a page from origin 2 needed to be displayed (as opposed to having to e.g. upload a list of pages to display somewhere for the L@E to read)
  * By configuring the L@E as origin-request, it is only triggered when the response is not in cache
  * By using a `HEAD` request for the prelight check, the amount of data transferred from the origin is minimal, resulting in a very low overhead (50-100ms)
  * By having this logic in code (as opposed to an out of the box solution like origin failover) we were able to have flexibility in the logic. This was a double-edged sword, with any kind of logic adding significant cognitive burden.

[origin failover with Origin Groups]: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/high_availability_origin_failover.html
[examples in the official documentation]: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/lambda-examples.html#lambda-examples-content-based-S3-origin-based-on-query


  * L@E IP ranges
  * Caching API calls
  * `.html` redirects
  * Packaging
