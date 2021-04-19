---
title: "VPN to any EC2 Instance using SSH"
date: 2021-04-19T10:25:25+10:00
---

A horrible hack that allows you to create a VPN tunnel from your workstation to any of your EC2 instances -- **even one you don't have direct network access to**, such as an instance in a private subnet.

<!--more-->

Ever needed to connect to something that was only accessible from an EC2 instance, but you wanted to connect to it _from your workstation_? Perhaps an [RDS](https://aws.amazon.com/rds/) database in a private subnet? The [Intance Metadata Service](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instancedata-data-retrieval.html)? The [VPC DNS endpoint](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-dns.html)? A service only exposed by a [VPC endpoint](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints.html)?

Look no further.

## Prerequisites

  1. [AWS Systems Manager Session Manager][] configured on the target EC2 instances
  1. [EC2 Instance Connect][] configured on the target EC2 instances
  1. IAM permissions to connect to the instance with these two services
  1. [sshuttle][], the [AWS CLI](https://aws.amazon.com/cli/), the [Session Manager plugin for the AWS CLI](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) and [jq](https://github.com/stedolan/jq) installed on your workstation

## How To

`~/.ssh/config`:
```ini
Host i-*
    User ec2-user
    ProxyCommand sh -c "aws ec2-instance-connect send-ssh-public-key --instance-id %h --availability-zone "$(aws ec2 describe-instances --instance-ids %h --output json | jq -r '.Reservations[].Instances[].Placement.AvailabilityZone')" --instance-os-user ec2-user --ssh-public-key file://${HOME}/.ssh/id_rsa.pub && aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters 'portNumber=%p'"
```

```bash
sshuttle --ssh-cmd "ssh -F ${HOME}/.ssh/config" --auto-nets --dns --remote i-1234567890abcdef0
```

## Explanation

  1. First, we use [EC2 Instance Connect][] to push a SSH pubkey to an instance. This solution relies on the capabilities of SSH, so we need to be able to authenticate to the instance's `sshd` daemon. To be able to run `aws ec2-instance-connect send-ssh-public-key`, we also need to know the Availability Zone of the instance (why does the API require this? I have no idea), so we run `aws ec2 describe-instances` in a subshell along with `jq` to fetch it.
  2. Then we use [AWS Systems Manager Session Manager][] to [create a tunnel to the instance's SSH port](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started-enable-ssh-connections.html). This traffic is proxied over Amazon's management plane, rather than needing the instance to e.g. have a public IP address and security groups configured to open port 22. This is what allows us to connect to an instance even if it's in a private subnet.
  3. Wrap the above commands in `~/.ssh/config` for convenience using the handy `ProxyCommand` directive. The command specified here will be run whenever you target an instance ID with `ssh`, e.g. `ssh i-1234567890abcdef0`. At this point, with the correct credentials, we can now connect to our SSH instance.
  4. Finally, use [sshuttle][] to create a VPN connection to the instance. `sshuttle` is a tool that allows you to create a VPN connection to a server with the only requirement being that you can SSH to it. We tell `sshuttle` to use our `~/.ssh/config` so that the `ProxyCommand` is invoked prior to connecting, enable automatic network routing discovery (`sshuttle` selectively routes traffic through the tunnel), and then specify the instance to connect to. Additionally, you can specify specific CIDRs/IPs to proxy e.g. `sshuttle --ssh-cmd "ssh -F ${HOME}/.ssh/config" --auto-nets --dns --remote i-1234567890abcdef0 10.0.0.0/8 169.254.169.254/32`.

[sshuttle]: https://github.com/sshuttle/sshuttle
[AWS Systems Manager Session Manager]: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html
[EC2 Instance Connect]: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Connect-using-EC2-Instance-Connect.html
