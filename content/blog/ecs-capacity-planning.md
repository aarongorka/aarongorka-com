---
title: "ECS Capacity Planning"
date: 2018-07-20T10:26:49+10:00
featuredImage: "/media/20160716_145825.jpg"
---

ECS has a lot of inputs; there's a lot of gotchas in creating a platform that can scale to meet any demand. Here's a methodical approach to creating a multi-tenanted ECS platform that can scale to meet any kind of demand.

<!--more-->

{{< load-photoswipe >}}
{{< syntax >}}
{{< figure src="/media/20160716_145825.jpg" >}}

Before we start, here's some terms I'll be using throughout this post, in [Plain English](https://www.expeditedssl.com/aws-in-plain-english) fashion:

Instance
: EC2 Instances; servers hosted by Amazon. Even Serverless code has to run somewhere, and so do Docker containers.

Service
: An [ECS Service](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs_services.html) is where you define how many Tasks you want running or how you want to scale them. Like an Auto Scaling Group, but for containers.

Task
: Tasks consist of one or more Docker containers deployed to an Instance. [Task Definitions](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definitions.html) define what a Task looks like. Comparable to what a `docker-compose.yml` defines.

## Scale EC2 Instances On Reservation, Not Utilisation

Your Autoscaling Group (or Spot Fleet) should scale off of **reservation** instead of utilisation. This is a departure from what is typical in traditional EC2-based applications which scale off of CPU utilisation. When you deploy a Service, you have the option to specify CPU and memory reservations. When the Service spins up an Task, the Instance dedicates memory and CPU to that Task.

Without reserving resources, we do not limit the number of containers deployed to an EC2 instance. This has obvious performance implications.

## Automagic Scaling Policies: Target Tracking

[Target Tracking](https://docs.aws.amazon.com/autoscaling/ec2/userguide/as-scaling-target-tracking.html) is the 3rd iteration of scaling methods that AWS has created, after [Simple Scaling and Step Scaling](https://docs.aws.amazon.com/autoscaling/ec2/userguide/as-scaling-simple-step.html). All you need to do is plug in a desired number for a metric, and AWS will figure out the rest for you. For example, you can specify that you want 60% `MemoryReservation` on your ECS Cluster at all times, and AWS will do its best to maintain that number by creating or terminating instances. Although you are forgoing some control over Instance creation/termination, it works well for this use case.

One problem with this is that the integration in to Spot Fleet is a bit immature:

{{< figure src="/media/Screenshot from 2018-07-21 21-46-54.png" caption="What are we scaling off of again?" >}}

You can't configure it through the console, but CloudFormation works fine:

```yaml
  ServiceScalingPolicyCPU:
    Type: AWS::ApplicationAutoScaling::ScalingPolicy
    Properties:
      PolicyName: !Sub '${AWS::StackName}-scale-cpu'
      PolicyType: TargetTrackingScaling
      ScalingTargetId: !Ref SpotFleetScalingTarget
      TargetTrackingScalingPolicyConfiguration:
        TargetValue: !Ref TargetTrackingTargetValue
        ScaleInCooldown: !Ref ScaleInCooldown
        ScaleOutCooldown: !Ref ScaleOutCooldown
        CustomizedMetricSpecification:
          MetricName: CPUReservation
          Namespace: AWS/ECS
          Statistic: Average
          Dimensions:
            - Name: ClusterName
              Value:
                Fn::ImportValue: !Sub "ecs-${ClusterName}-ECSCluster"

  ServiceScalingPolicyMemory:
    Type: AWS::ApplicationAutoScaling::ScalingPolicy
    DependsOn: ServiceScalingPolicyCPU  # Spot Fleet requires that we create scaling policies sequentially
    Properties:
      PolicyName: !Sub '${AWS::StackName}-scale-memory'
      PolicyType: TargetTrackingScaling
      ScalingTargetId: !Ref SpotFleetScalingTarget
      TargetTrackingScalingPolicyConfiguration:
        TargetValue: !Ref TargetTrackingTargetValue
        ScaleInCooldown: !Ref ScaleInCooldown
        ScaleOutCooldown: !Ref ScaleOutCooldown
        CustomizedMetricSpecification:
          MetricName: MemoryReservation
          Namespace: AWS/ECS
          Statistic: Average
          Dimensions:
            - Name: ClusterName
              Value:
                Fn::ImportValue: !Sub "ecs-${ClusterName}-ECSCluster"
```

Note that we're scaling on **both memory and CPU**. Target Tracking will match the higher of the two metrics, preventing infinite scaling loops when both metrics are in breach in the opposite direction.

## Reserve Enough Reservation For Scaling/Deployments

It may be tempting to try and achieve a high reservation utilisation across your ECS Cluster. If you had an average of 90% reservation across your ECS Cluster, it would mean you were getting awesome cost efficiency --- probably a magnitude higher than you would with normal EC2 instances set to scale at 50% CPU.

The problem with this is that it can cause deployments and scaling to fail. When ECS tries to deploy new Tasks, it tries to find an instance with sufficient free capacity (free reservation). 

>If ECS fails to find a suitable instance, _it fails and does **nothing**_.

ECS logs the error to the Service's event section, but ECS does not automatically deploy additional EC2 instances to create free capacity. Even if we create additional capacity, ECS makes no attempt to retry to the deployment.

{{< figure src="/media/insufficient-reservation.png" >}}

Workarounds exist [^1] [^2] [^3], but the best approach is to avoid this problem by _always having enough capacity to deploy_. In practice, you may need up to 40% capacity free at all times, especially if you are doing blue/green deployments.

[^1]: https://medium.com/prodopsio/how-to-scale-in-ecs-hosts-2d0906d2ba
[^2]: https://garbe.io/blog/2017/04/12/a-better-solution-to-ecs-autoscaling/
[^3]: https://github.com/structurely/ecs-autoscale

Another thing to note is that the larger your cluster is, the less likely you are to have issues with spare capacity.

## Deploying Memory Hogs

Another thing to look out for is having enough spare capacity to deploy the largest Task in your ECS Cluster. Although you may have enough total reservation free across the cluster, it may be spread across several instances. A situation can arise where there is no single EC2 instance with capacity to deploy a large application, even though the cluster has plenty of reservation to spare.

{{< figure src="/media/Screenshot from 2018-07-21 23-22-12.png" caption="Although this cluster as a whole has at least 5000 CPU units to spare, a Task that requires it will fail to deploy.">}}

A solution to this is to use the **binpack** [placement strategy](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ecs-service.html#cfn-ecs-service-placementstrategies). This ensures that ECS fills up each instance (as much as possible) before it deploys to the next instance. We can even use the AZ spread strategy at the same time to ensure that we have redudnancy across AZs before binpacking on to a single instance.

```yaml
  ECSServiceLB:
    Type: AWS::ECS::Service
    Properties:
      PlacementStrategies:
        - Type: spread
          Field:  attribute:ecs.availability-zone
        - Type: binpack
          Field: memory
#      ...
```

Again, the larger your cluster is, the less likely you are to have this issue.

## Use Spot Fleet For Production Critical Workloads

[Spot Fleet](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-fleet.html) savings are amazing, and since your application is [12 factor](https://12factor.net/), having an instance suddenly shut down is no problem. Make sure you use a few different instance classes (and even generations) and there is no reason to not use Spot Instances, even in production. Especially in production!

You **will** want to deploy [connection draining](https://aws.amazon.com/blogs/compute/how-to-automate-container-instance-draining-in-amazon-ecs/) to prevent dropped connections when your spot instances get terminated.

## Container Autoscaling

Finally, we arrive at the container layer! Now that we have a ECS Cluster that will scale to meet any demand we throw at it, we can scale our containers on _utilisation_.

Target Tracking also works well here. A nice feature is the ability to set multiple metrics to scale on, and Target Tracking will scale to meet the highest one. For example, you may set your application to scale at 60% CPU and 90% memory utilisation. This ensures that your application is not bottlenecked by either resource.

```yaml
  ServiceScalingPolicyCPU:
    Type: AWS::ApplicationAutoScaling::ScalingPolicy
    Properties:
      PolicyName: !Sub '${AWS::StackName}-scale-target-cpu'
      PolicyType: TargetTrackingScaling
      ScalingTargetId: !Ref 'ServiceScalingTarget'
      TargetTrackingScalingPolicyConfiguration:
        TargetValue: 60
        ScaleInCooldown: 180
        ScaleOutCooldown: 60
        PredefinedMetricSpecification:
          PredefinedMetricType: ECSServiceAverageCPUUtilization

  ServiceScalingPolicyMem:
    Type: AWS::ApplicationAutoScaling::ScalingPolicy
    Properties:
      PolicyName: !Sub '${AWS::StackName}-scale-target-mem'
      PolicyType: TargetTrackingScaling
      ScalingTargetId: !Ref 'ServiceScalingTarget'
      TargetTrackingScalingPolicyConfiguration:
        TargetValue: 90
        ScaleInCooldown: 180
        ScaleOutCooldown: 60
        PredefinedMetricSpecification:
          PredefinedMetricType: ECSServiceAverageMemoryUtilization
```

For optimal scaling, set `ScaleOutCooldown` as low as possible a value, but high enough that a new container has enough time to impact the average of the metric that it's scaling on. Set `ScaleInCooldown` much longer to prevent flapping.

## SLA-based Scaling

Scaling on CPU or memory is okay, but is it _really_ what we're trying to deliver to our customers? Responsive services are what the customer wants. You will probably have alerting on the response time of your web application, so why not automate remediation of high response times? We can configure Target Tracking to add containers when response time is high.

{{< figure src="/media/Screenshot from 2018-07-21 22-54-59.png" caption="The console isn't ready for this kind of scaling." >}}

Again, the console can't handle Target Tracking with custom metrics yet, but CloudFormation works fine:

```yaml
  ServiceScalingPolicy:
    Type: AWS::ApplicationAutoScaling::ScalingPolicy
    Properties:
      PolicyName: !Sub '${AWS::StackName}-scale-target'
      PolicyType: TargetTrackingScaling
      ScalingTargetId: !Ref 'ServiceScalingTarget'
      TargetTrackingScalingPolicyConfiguration:
        TargetValue: !Ref AutoscalingTargetValue
        ScaleInCooldown: 180
        ScaleOutCooldown: 60
        CustomizedMetricSpecification:
          MetricName: TargetResponseTime
          Namespace: AWS/ApplicationELB
          Statistic: Average
          Dimensions:
            - Name: TargetGroup
              Value: !GetAtt ALBTargetGroup.TargetGroupFullName
            - Name: LoadBalancer
              Value:
                Fn::ImportValue: !Sub "ecs-${ClusterName}-${Name}-${Environment}-ALBFullName"
```

This is effective in scaling your containers in response to load. There are some considerations when taking this approach:

  * High deviations in response times between endpoints may cause erratic scaling
  * Applications with latency that aren't resource constrained and have external constraints may warrant some additional care. Make sure the number of containers has a limit you don't mind reaching, and that sudden scaling will not e.g. bring down the database due to an excessive number of connections.
  * Applications with sporadic traffic may have issues with scaling down, as **Target Tracking does not scale down on 0 requests** (`INSUFFICIENT_DATA`). This applies to your nonprod environments too.

## Enforce Reservations On ECS Services

Without reserving resources on an ECS Service, containers can be in contention for resources, resulting in unpredictable behaviour. All ECS Services should have both memory and CPU reservations. If an application has a sidecar container, you should also allocate an appropriate percentage of those resources to the "essential" container, or you risk the sidecar consuming too many resources and causing service degradation.

Note here how we've reserved the majority of the CPU (700) and memory (1536) for the "Web-App" container in this Task Definition:

```json
{
    "containerDefinitions": [
        {
          "essential": true,
          "image": "myorg/webapp:latest",
          "name": "Web-App",
          "cpu": 700,
          "memory": 1536,
          "portMappings": [
            {
              "containerPort": 80
            }
          ]
        },
        {
          "image": "myorg/sidecar:latest",
          "name": "Sidecar",
        }
    ],
    "family": "Web-App-${ENV}",
    "volumes": [],
    "memory": "2048",
    "cpu": "1024"
}
```

## Minimise Per-Container Reservations

{{< figure src="/media/Screenshot from 2018-07-22 11-41-13.png" caption="This task has good memory reservation, but we're wasting a lot of CPU." >}}

Keep containers as small as possible to ensure smooth scaling and deployment. The smaller your containers are, the closer you are to optimal resource efficiency and the less likely you are to have issues deploying new tasks.

Reducing resources allocated to each Task does not mean your application will be less responsive. Each container still needs to be able to handle baseline load. The difference is that when introducing load beyond that, we don't need to spec a single container to be able to handle it --- ECS will spin up additional Tasks with autoscaling.

A systematic approach you can take to achieve this is to gradually decrease CPU and memory reservation until the **max utilisation** metric (as opposed to average) starts to creep up. Once it starts approaching 100%, you will notice service degradation as individual containers become resource starved.

## Conclusion

To create a stable ECS platform, we need the following:

  * Scale Instances on both memory and CPU reservation
  * Allow a sufficient buffer for scaling and deployments
  * Configure reservation on all Tasks
  * Prefer many smaller containers to few large ones

With this, we now have a platform that rivals Fargate in its ability to scale, but at 1/10th [^4] of the cost.

[^4]: [Heroku vs ECS Fargate vs EC2 On-Demand vs EC2 Spot Pricing Comparison](https://blog.boltops.com/2018/04/22/heroku-vs-ecs-fargate-vs-ec2-on-demand-vs-ec2-spot-pricing-comparison) shows that a Spot m5.xlarge is 1/14th the price of an equivalent Fargate Task.
