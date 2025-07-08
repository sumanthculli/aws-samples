
---

## Tech Spec: Karpenter Node Provisioning for Developer Workloads


### 1. Overview

This document provides guidance for developer teams on how to effectively schedule their applications on the organization's EKS cluster. The Platform team has implemented **Karpenter**, an open-source node provisioning project, to automate the scaling of our Kubernetes cluster.

Instead of a fixed set of nodes, Karpenter dynamically launches new EC2 instances based on the specific requirements of your application pods. This ensures efficient resource utilization, cost optimization, and faster pod scheduling.

To facilitate this, we have pre-configured several `NodePools` that cater to different use cases (e.g., production, batch processing, development). Your responsibility is to signal to Kubernetes which type of node your application requires by using `nodeSelectors`, `tolerations`, and **`topologySpreadConstraints`** in your workload manifests.

### 2. Core Concepts for Developers

To use this system effectively, you need to understand three key Kubernetes concepts:

*   **Taints and Tolerations:** A **Taint** is a property we place on a `NodePool` to "repel" pods from being scheduled on the nodes it creates. A **Toleration** is a property you add to your pod's specification that allows it to be scheduled on a node with a matching taint. **This is the primary mechanism you will use to run your pods on the correct node type.**

*   **Node Selector / Node Affinity:** A **`nodeSelector`** is a simple way to constrain pods to only be scheduled on nodes with specific labels. We have labeled our Karpenter `NodePools` so you can explicitly request them.

*   **Topology Spread Constraints:** This feature allows you to control how pods are spread across failure domains like regions or **Availability Zones (AZs)**. This is crucial for building highly available applications. You will use this to ensure your application's pods are distributed across our three configured AZs.

### 3. Available Node Pools

The Platform Team has configured the following `NodePools` for your use. These pools are configured to allow Karpenter to launch nodes in any of our three primary AZs (`us-east-1a`, `us-east-1b`, `us-east-1c`).

| NodePool Name | Use Case & Pricing Model | Key Label for `nodeSelector` | Taint & Required `toleration` | Recommended For |
| :--- | :--- | :--- | :--- | :--- |
| `general-purpose-ondemand` | **Production (On-Demand)** - Stable, reliable, highest-cost. | `karpenter.sh/nodepool: general-purpose-ondemand` | **Taint:** `workload-type=general-purpose:NoSchedule` <br><br> **Toleration:** <br> `key: "workload-type"`<br>`operator: "Equal"`<br>`value: "general-purpose"`<br>`effect: "NoSchedule"` | User-facing APIs, stateful services, databases, and any critical production workload that cannot tolerate interruption. |
| `compute-optimized-spot` | **Cost-Optimized (Spot)** - Low-cost, can be interrupted with a 2-minute warning. | `karpenter.sh/nodepool: compute-optimized-spot` | **Taint:** `workload-type=spot-compute:NoSchedule` <br><br> **Toleration:** <br> `key: "workload-type"`<br>`operator: "Equal"`<br>`value: "spot-compute"`<br>`effect: "NoSchedule"` | Batch jobs, CI/CD runners, dev/test environments, stateless applications, and any workload designed to be fault-tolerant. |
| `memory-optimized-ondemand` | **High-Memory (On-Demand)** - For workloads needing significant RAM. Stable and reliable. | `karpenter.sh/nodepool: memory-optimized-ondemand` | **Taint:** `workload-type=memory-intensive:NoSchedule` <br><br> **Toleration:** <br> `key: "workload-type"`<br>`operator: "Equal"`<br>`value: "memory-intensive"`<br>`effect: "NoSchedule"` | In-memory caches (e.g., Redis), data processing applications, large JVM-based applications, or any service with high memory requests. |

**Note on Reserved Instances (RIs):** The Platform Team manages RIs. If your workload requests an `On-Demand` instance type that matches our available RIs, Karpenter will automatically utilize them, giving you the benefit of the cost savings without any change to your manifest.

### 4. How to Schedule Your Workloads: Examples

To schedule your application onto a specific `NodePool`, you **must add a `nodeSelector` and a `toleration`**. For high availability, you **should also add `topologySpreadConstraints`**.

The following examples now include all three configurations.

---

#### **Example 1: Deploying a Production API to the `general-purpose-ondemand` Pool (HA)**

This is the standard for any critical, user-facing service, now with a strict high-availability policy.

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-production-api
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-production-api
  template:
    metadata:
      labels:
        app: my-production-api
    spec:
      # =================== KARPENTER CONFIGURATION ===================
      nodeSelector:
        karpenter.sh/nodepool: general-purpose-ondemand
      tolerations:
      - key: "workload-type"
        operator: "Equal"
        value: "general-purpose"
        effect: "NoSchedule"
      # ===============================================================

      # ============ HIGH AVAILABILITY (AZ SPREAD) CONFIG =============
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: "topology.kubernetes.io/zone"
        whenUnsatisfiable: "DoNotSchedule" # Enforce the spread strictly
        labelSelector:
          matchLabels:
            app: my-production-api # Must match the pods we are spreading
      # ===============================================================
      containers:
      - name: api-container
        image: my-company/my-api:1.2.3
        resources:
          # IMPORTANT: Resource requests are critical for Karpenter!
          requests:
            cpu: "250m"
            memory: "512Mi"
          limits:
            cpu: "500m"
            memory: "1Gi"
```

---

#### **Example 2: Running a Batch Job on the `compute-optimized-spot` Pool (HA-Aware)**

This job will attempt to spread across AZs but will still run if it cannot, prioritizing job completion.

```yaml
# batch-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: daily-data-processor
spec:
  template:
    metadata:
      labels:
        # Label is needed for the topologySpreadConstraint's labelSelector
        app: daily-data-processor
    spec:
      # =================== KARPENTER CONFIGURATION ===================
      nodeSelector:
        karpenter.sh/nodepool: compute-optimized-spot
      tolerations:
      - key: "workload-type"
        operator: "Equal"
        value: "spot-compute"
        effect: "NoSchedule"
      # ===============================================================

      # ============ HIGH AVAILABILITY (AZ SPREAD) CONFIG =============
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: "topology.kubernetes.io/zone"
        whenUnsatisfiable: "ScheduleAnyway" # Prioritize scheduling over strict spreading
        labelSelector:
          matchLabels:
            app: daily-data-processor
      # ===============================================================
      containers:
      - name: processor
        image: my-company/data-processor:latest
        resources:
          requests:
            cpu: "1"
            memory: "2Gi"
      restartPolicy: Never
  backoffLimit: 4
```

### 5. Best Practices & Important Considerations

1.  **ALWAYS Set Resource Requests:** Karpenter decides what size of EC2 instance to launch based on the sum of pending pods' `spec.containers.resources.requests`. If you do not set requests, Karpenter cannot provision an appropriately sized node, and your pod may remain `Pending`.

2.  **Ensure High Availability with Topology Spread Constraints:**
    *   **Purpose:** To protect your service from an AWS Availability Zone failure, you should spread your pods across multiple AZs.
    *   **Key:** Use `topologyKey: "topology.kubernetes.io/zone"`. Karpenter automatically labels nodes with the AZ they are in.
    *   **`whenUnsatisfiable`:** This field is critical.
        *   `DoNotSchedule` (Recommended for Production): The scheduler will not schedule a pod if it violates the `maxSkew`. This *enforces* high availability. Use this for critical services.
        *   `ScheduleAnyway` (Recommended for Jobs/Non-critical): The scheduler will *try* to spread pods but will schedule them even if it can't. This prioritizes getting the workload running over perfect distribution.

3.  **Design for Spot Interruption:** If you use the `compute-optimized-spot` pool, your application **must** be designed to handle the 2-minute Spot Instance interruption notice. Your application should be stateless or able to gracefully shut down and checkpoint its state.

4.  **Use Liveness and Readiness Probes:** Proper health checks are essential. They ensure that traffic is not routed to a pod that isn't ready and that failing pods are restarted, which may trigger Karpenter to replace a faulty node.

5.  **Cost Allocation:** All nodes provisioned by Karpenter are automatically tagged with the `karpenter.sh/nodepool` label. This allows the Platform team to track costs and attribute them to the corresponding workload types.

6.  **Do Not Create Your Own `NodePools`:** The management of `EC2NodeClass` and `NodePool` resources is the responsibility of the Platform team. If the available pools do not meet your needs, please file a request on our [Platform JIRA Board](link-to-jira).

### 6. Support

For questions, issues, or requests for new `NodePool` types, please reach out to us on the `#platform-support` Slack channel or create a ticket in our JIRA project.

---
### Appendix A: Example `NodePool` Configuration (For Reference)

This is an example of the configuration used by the Platform Team to define the `general-purpose-ondemand` NodePool. You do not need to interact with this directly.

```yaml
# nodepool-general-purpose.yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: general-purpose-ondemand
spec:
  template:
    metadata:
      labels:
        # This label is used in your workload's nodeSelector
        karpenter.sh/nodepool: general-purpose-ondemand
        workload-class: "production"
    spec:
      # This taint repels pods without the matching toleration
      taints:
        - key: workload-type
          value: general-purpose
          effect: NoSchedule
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
        # This requirement allows Karpenter to launch nodes in any of these AZs
        - key: "topology.kubernetes.io/zone"
          operator: In
          values: ["us-east-1a", "us-east-1b", "us-east-1c"]
        - key: "karpenter.k8s.aws/instance-category"
          operator: In
          values: ["c", "m", "r"] # General purpose instance categories
        - key: "karpenter.k8s.aws/instance-generation"
          operator: Gt
          values: ["4"] # Use modern instance generations
      nodeClassRef:
        name: default-nodeclass # References the EC2NodeClass
  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: "168h" # 7 days
  limits:
    cpu: "1000"
```
