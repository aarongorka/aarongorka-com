---
title: "gVisor on ECS"
date: 2019-03-19T12:21:36+11:00
featuredImage: "/chris-panas-1362304-unsplash.jpg"
description: "Securing multi-tenanted workloads on ECS using gVisor"
---

Google's [gVisor][] exists to provide a **true sandbox** for your Docker containers. It replaces `runc`, the default Docker runtime which recently had a serious vulnerability [^1].

In theory gVisor is a **drop-in** replacement for `runc`, but does it actually work with [Amazon ECS][]?

[Amazon ECS]: https://aws.amazon.com/ecs/
[^1]: https://www.openwall.com/lists/oss-security/2019/02/11/2

<!--more-->

{{< load-photoswipe >}}
{{< figure src="/chris-panas-1362304-unsplash.jpg" alt="chris panas https://unsplash.com/@chrispanas" >}}

## What is gVisor?

{{< blockquote link="https://github.com/google/gvisor" >}}
gVisor is a user-space kernel for containers. It limits the host kernel surface accessible to the application while still giving the application access to all the features it expects.
{{< / blockquote >}}

[gVisor]: https://github.com/google/gvisor

Docker does not provide a strict security boundary between containers like VMs do. Containers on the same host share the kernel, and can make syscalls directly to the host. When multi-tenanting (running multiple applications on a single host) your VMs, this is an issue --- when one of your applications is compromised, you are one exploit away from having **all your applications** compromised.

Recently, one of these exploits [^1] was found in Docker.

{{< blockquote link="https://kubernetes.io/blog/2019/02/11/runc-and-cve-2019-5736/" >}}
When running a process as root (UID 0) inside a container, that process can exploit a bug in runc to gain root privileges on the host running the container. This then allows them unlimited access to the server as well as any other containers on that server.
{{< / blockquote >}}

gVisor mitigates this vulnerability by replacing the vulnerable component, `runc`.

## Installing gVisor

As a drop-in replacement, installing gVisor is trivial:

```bash
curl -LsO  https://storage.googleapis.com/gvisor/releases/nightly/latest/runsc
chmod +x runsc
mv runsc /usr/local/bin
cat <<EOF >> /etc/docker/daemon.json
{
    "runtimes": {
        "runsc": {
            "path": "/usr/local/bin/runsc"
       }
    }
}
EOF
systemctl restart docker
```

You can now run containers with gVisor by adding the `--runtime=runsc` flag to your Docker commands.

**This alone isn't particularly useful**, as we are relying on ECS to orchestrate and run containers for us. Unfortunately, we cannot pick and choose the runtime directly from ECS. [The feature request for this is still open](https://github.com/aws/amazon-ecs-agent/issues/1084). [One of the comments](https://github.com/aws/amazon-ecs-agent/issues/1084#issuecomment-357689366) provides us a hint for a workaround: **overriding the default runtime**. All we need to do is add one additional value to the Docker configuration file:

```json
{
    "default-runtime": "runsc",
    "runtimes": {
        "runsc": {
            "path": "/usr/local/bin/runsc"
       }
    }
}
```

After restarting Docker, we can see that containers are now sandboxed using gVisor:

```console
$ docker run -d nginx
Unable to find image 'nginx:latest' locally
latest: Pulling from library/nginx
f7e2b70d04ae: Pull complete
08dd01e3f3ac: Pull complete
d9ef3a1eb792: Pull complete
Digest: sha256:98efe605f61725fd817ea69521b0eeb32bef007af0e3d0aeb6258c6e6fe7fc1a
Status: Downloaded newer image for nginx:latest
74cdfe0c0c1b1520b662d946c98883190b885f456ab3c082104521b88460a37c
$ ps aux | grep '[r]unc'
$ # no results
$ ps aux | grep '[r]unsc'
root     29540  0.0  0.0  10800  5004 ?        Sl   10:29   0:00 containerd-shim -namespace moby -workdir /var/lib/containerd/io.containerd.runtime.v1.linux/moby/74cdfe0c0c1b1520b662d946c98883190b885f456ab3c082104521b88460a37c -address /run/containerd/containerd.sock -containerd-binary /usr/bin/containerd -runtime-root /var/run/docker/runtime-runsc
root     29553  0.0  0.0 119304 11404 ?        Sl   10:29   0:00 runsc-gofer --root=/var/run/docker/runtime-runsc/moby --debug=false --log=/run/containerd/io.containerd.runtime.v1.linux/moby/74cdfe0c0c1b1520b662d946c98883190b885f456ab3c082104521b88460a37c/log.json --log-format=json --debug-log= --debug-log-format=text --file-access=exclusive --overlay=false --network=sandbox --log-packets=false --platform=ptrace --strace=false --strace-syscalls= --strace-log-size=1024 --watchdog-action=LogWarning --panic-signal=-1 --log-fd=3
gofer --bundle /run/containerd/io.containerd.runtime.v1.linux/moby/74cdfe0c0c1b1520b662d946c98883190b885f456ab3c082104521b88460a37c --spec-fd=4 --io-fds=5 --io-fds=6 --io-fds=7
--io-fds=8 --apply-caps=false --setup-root=false
nfsnobo+ 29557  2.6  0.1 166480 22572 ?        Ssl  10:29   0:01 runsc-sandbox --root=/var/run/docker/runtime-runsc/moby --debug=false --log=/run/containerd/io.containerd.runtime.v1.linux/moby/74cdfe0c0c1b1520b662d946c98883190b885f456ab3c082104521b88460a37c/log.json --log-format=json --debug-log= --debug-log-format=text --file-access=exclusive --overlay=false --network=sandbox --log-packets=false --platform=ptrace --strace=false --strace-syscalls= --strace-log-size=1024 --watchdog-action=LogWarning --panic-signal=-1 --log-fd=3 boot --bundle=/run/containerd/io.containerd.runtime.v1.linux/moby/74cdfe0c0c1b1520b662d946c98883190b885f456ab3c082104521b88460a37c --controller-fd=4 --spec-fd=5 --start-sync-fd=6 --io-fds=7 --io-fds=8 --io-fds=9 --io-fds=10 --stdio-fds=11 --stdio-fds=12 --stdio-fds=13 --cpu-num 8 74cdfe0c0c1b1520b662d946c98883190b885f456ab3c082104521b88460a37c
```

## Running `ecs-agent`

Because gVisor only implements a limited set of Linux's syscalls, some things do not work with it. Anything expected to interact with the system on a lower level may not work as expected.

An example that immediately becomes apparent is the agent that ECS uses to manage your EC2 instances. On [Amazon ECS-Optimized Amazon Linux 2][] the [ECS agent][] is normally started by the ecs-init systemd service, and runs a Docker container itself. Because it needs low level access to the system it runs on, it does not play nicely with gVisor.

[ECS agent]: https://github.com/aws/amazon-ecs-agent
[Amazon ECS-Optimized Amazon Linux 2]: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/al2ami.html

This is OK, because we are not aiming to sandbox the ECS agent itself. The `docker` client allows us to specify an alternative runtime, so we can force the ECS agent to run with `runc`, Docker's default runtime:

`docker run --runtime=runc [...]`

Unfortunately the ecs-init service is rather opaque, so we can't override it in an elegant way. Completely disabling it and starting the ECS agent manually (with an additional runtime flag) provides the desired effect.

```bash
systemctl stop ecs  # the ecs-init service will try to start the ecs-agent with gVisor, which doesn't work. We must force stop it and run ecs-agent with runc
systemctl disable ecs
docker run --name ecs-agent \
    --runtime=runc \
    --detach=true \
    --restart=on-failure:10 \
    --volume=/var/run/docker.sock:/var/run/docker.sock \
    --volume=/var/log/ecs:/log \
    --volume=/var/lib/ecs/data:/data \
    --net=host \
    --env-file=/etc/ecs/ecs.config \
    --env=ECS_LOGFILE=/log/ecs-agent.log \
    --env=ECS_DATADIR=/data/ \
    --env=ECS_ENABLE_TASK_IAM_ROLE=true \
    --env=ECS_ENABLE_TASK_IAM_ROLE_NETWORK_HOST=true \
    amazon/amazon-ecs-agent:latest
```

Normally, manually invoking a process that is usually managed by an init system and expecting it to stay up is a Bad Idea. In this case, the Docker daemon manages the uptime of the ECS agent and will restart it if it fails.

## Putting it all together

All together, your userdata or AMI baking script will look something like this:

```bash
curl -LsO  https://storage.googleapis.com/gvisor/releases/nightly/latest/runsc
chmod +x runsc
mv runsc /usr/local/bin
cat <<EOF >> /etc/docker/daemon.json
{
    "default-runtime": "runsc",
    "runtimes": {
        "runsc": {
            "path": "/usr/local/bin/runsc"
       }
    }
}
EOF
systemctl restart docker
systemctl stop ecs  # the ecs-init service will try to start the ecs-agent with gVisor, which doesn't work. We must force stop it and run ecs-agent with runc
systemctl disable ecs
docker run --name ecs-agent \
    --runtime=runc \
    --detach=true \
    --restart=on-failure:10 \
    --volume=/var/run/docker.sock:/var/run/docker.sock \
    --volume=/var/log/ecs:/log \
    --volume=/var/lib/ecs/data:/data \
    --net=host \
    --env-file=/etc/ecs/ecs.config \
    --env=ECS_LOGFILE=/log/ecs-agent.log \
    --env=ECS_DATADIR=/data/ \
    --env=ECS_ENABLE_TASK_IAM_ROLE=true \
    --env=ECS_ENABLE_TASK_IAM_ROLE_NETWORK_HOST=true \
    amazon/amazon-ecs-agent:latest
```

The result is completely transparent. Any service you run on ECS will start normally and appear in the AWS console as if you were using out of the box Docker, but under the hood you are running `runsc` instead of `runc`.

## Bonus: resource reservation

I had gVisor running on several clusters for a few weeks without any apparent issues. During this time, the [runc vulnerability][] was announced and I was pretty chuffed with myself.

[runc vulnerability]: https://www.openwall.com/lists/oss-security/2019/02/11/2

One day, I noticed some strange behaviour on one of our nonprod clusters. Our EC2 instances were getting disconnected from ECS left and right, causing containers to fail to schedule. I started investigating and found that one of our applications had gone out of control and was consuming 100% of the **host's** CPU. The ECS agent was under such severe resource contention that it could not maintain a connection to the ECS control plane.

This shouldn't be possible. We make heavy use of [multi-tenanting and resource reservation][] to prevent these kinds of issues. A single application being able to take down the cluster undermines the idea of multi-tenanting.

[multi-tenanting and resource reservation]: {{< relref "ecs-autoscaling-tips.md#enforce-reservations-on-ecs-services" >}}

It turns out that gVisor was [not enforcing resource quotas][]. Denial of Service is a type of security risk, so it didn't make much sense to patch one small hole only to open up a massive one elsewhere. I ended up having to remove gVisor from the cluster to make it stable again.

[not enforcing resource quotas]: https://github.com/google/gvisor/issues/107

Since then, support for [cgroup settings][] has been added to gVisor.

[cgroup settings]: https://github.com/google/gvisor/commit/29cd05a7c66ee8061c0e5cf8e94c4e507dcf33e0

## Conclusion

gVisor is absolutely worth looking in to for high risk environments that still want to take advantage of containers and multi-tenanting.

As it is not a fully mature project, you will need to test for any missing features. You will also need to test [whether it works](https://github.com/google/gvisor#will-my-container-work-with-gvisor) for your organisation's applications.

Thanks to [Melchi Salins](https://medium.com/@melchi.salins) for his article [Securing your CaaS using Google's gVisor](https://medium.com/momenton/securing-your-caas-using-googles-gvisor-d6e0cd0ae230) that inspired me to start looking in to this.
