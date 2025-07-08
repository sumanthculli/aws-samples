Of course. Here is a comprehensive technical specification document tailored for your developer community. You can copy and paste this into your internal wiki (like Confluence) or a Markdown document.

---

## **Technical Specification: Working with Bottlerocket on EKS**

**Document Owner:** [Your Team/Name]

**Last Updated:** [Date]

**Audience:** Developers and SREs working with the EKS cluster.

### 1. Introduction & Purpose

This document provides technical guidance for developers interacting with our AWS EKS cluster, which now utilizes **Bottlerocket AMIs** for its worker nodes. The purpose is to clarify the key differences between Bottlerocket and the traditional EKS Optimized AMI and to provide a standard operating procedure for troubleshooting and debugging nodes.

A key takeaway is that Bottlerocket is designed for security and operational consistency, which changes how you interact with the underlying node. Direct SSH access is disabled by default in favor of a more secure, container-based access method.

### 2. Bottlerocket vs. EKS Optimized AMI: A Comparison

While both are used for EKS worker nodes, they are fundamentally different in their philosophy and architecture. Understanding these differences is crucial for effective development and troubleshooting.

| Feature / Aspect | Bottlerocket AMI | EKS Optimized AMI (Amazon Linux 2) | Developer Impact & Why It Matters |
| :--- | :--- | :--- | :--- |
| **Operating System Base** | Minimal Linux, custom-built with only essential components for running containers. | General-purpose Amazon Linux 2, stripped down but still a full-featured OS. | **Reduced Attack Surface:** Bottlerocket has fewer packages and utilities, making it inherently more secure. You won't find `yum`, `python`, or other common tools on the host. |
| **Package Management** | **None.** There is no package manager like `yum` or `apt-get` on the host. | `yum` is available for installing and managing packages. | **Immutability & Consistency:** You cannot install new software on a running Bottlerocket node. This ensures all nodes are identical and prevents configuration drift. All tools must come from containers. |
| **Filesystem** | Primarily a **read-only** root filesystem. Key writable paths are `tmpfs`. | Standard read-write Linux filesystem. | **Security & Predictability:** Prevents unauthorized changes or malware from persisting on the root filesystem. Configuration is applied at boot time, not changed on the fly. |
| **Update Mechanism** | **Atomic, image-based updates.** The entire OS image is replaced on update and a reboot is performed. | **Package-based updates.** `yum update` updates individual packages. | **Reliability:** Updates are transactional. A failed update can be automatically rolled back to the previous working version, preventing broken nodes. |
| **Access Method** | **Out-of-band via AWS SSM Session Manager.** You access a "control container" or "admin container," not a standard shell. | Standard **SSH access** using an EC2 key pair. | **Enhanced Security:** Access is managed through IAM permissions, not SSH keys. All sessions can be logged and audited through AWS CloudTrail and Session Manager logs. |
| **Security** | Designed with **security-first principles:** SELinux is enforced, minimal packages, read-only rootfs. | A secure general-purpose OS, but requires more manual hardening. | **Lower Operational Overhead:** Many security best practices are built-in, reducing the need for custom security configurations on the node itself. |

**In Summary:** Think of the EKS Optimized AMI as a traditional server you manage. Think of a Bottlerocket node as a secure, immutable appliance whose only job is to run containers.

---

### 3. How to Access and Troubleshoot a Bottlerocket Node

Since you cannot `ssh` into a Bottlerocket node, you must use the **AWS Systems Manager (SSM) Session Manager** to access a special-purpose **admin container**. This container is disabled by default for maximum security, but we have enabled it on our non-production nodes to facilitate debugging.

The admin container runs with elevated privileges and has access to the host's tools and namespaces, allowing you to perform debugging tasks as if you were on the host itself.

#### 3.1. Prerequisites

1.  **AWS CLI Installed and Configured:** Your local AWS CLI must be configured with credentials that have `ssm:StartSession` permissions.
2.  **Session Manager Plugin for AWS CLI:** You must have the [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) installed.
3.  **`kubectl` Access:** You need `kubectl` configured to communicate with our EKS cluster.

#### 3.2. Step-by-Step Guide to Accessing a Node

**Step 1: Identify the Node and its EC2 Instance ID**

First, find the name of the Kubernetes node you want to inspect.

```bash
# List all nodes to find the one you're interested in
kubectl get nodes -o wide
```

Once you have the node name (e.g., `ip-192-168-50-100.ec2.internal`), describe it to get its AWS EC2 Instance ID.

```bash
# Replace <node-name> with the actual node name
NODE_NAME="<node-name>"
INSTANCE_ID=$(kubectl get node $NODE_NAME -o jsonpath='{.spec.providerID}' | cut -d'/' -f5)
echo "Instance ID: $INSTANCE_ID"
```

**Step 2: Start an SSM Session**

Now, use the `INSTANCE_ID` to start a secure session. This command will launch the admin container on the target node and drop you into a shell inside it.

```bash
# Replace <instance-id> with the ID from the previous step
# Replace <aws-region> with our cluster's region (e.g., us-east-1)
aws ssm start-session --target <instance-id> --region <aws-region>
```

Upon successful connection, you will see a prompt like this:

```
Starting session with SessionId: [session-id]

          |~~~~~~~|
          |       |

      .   |       |   .
      \\  |       |  //
       \\ |       | //
    ((   \\|_______|//   ))
   ((     |         |     ))
   ((      \       /      ))
    ((      \_____/      ))
     ))                 ((
      __                 __
     /  \ R O C K E T /  \
    |====U===========U====|
    |_____________________|
```

You are now inside the **admin container**.

#### 3.3. Performing Basic Debugging Actions

Inside the admin container, you have a shell with a set of pre-installed debugging tools. To access the host's system and files, you must use the `sheltie` command.

**`sheltie`: Your Gateway to the Host**

`sheltie` is a command that gives you a root shell with access to the host's namespaces. This is how you "break out" of the admin container to inspect the host OS.

```bash
# Run this immediately after connecting
sheltie
```
Your prompt will change to `[root@<instance-id> /]#`. You are now effectively root on the Bottlerocket host. **Use this shell with care.**

---

#### 3.4. Common Troubleshooting Scenarios

Here are recipes for common debugging tasks. **All commands below should be run inside the `sheltie` shell.**

**1. Viewing System and Kubelet Logs**

Bottlerocket uses `journald` for all system-level logging. The `journalctl` command is your primary tool.

```bash
# View all logs from the kubelet service in real-time
journalctl -u kubelet -f

# View all logs from the container runtime (containerd)
journalctl -u containerd -f

# View all kernel logs
journalctl -k

# View all logs since the last boot
journalctl -b
```

**2. Inspecting Node Certificates**

Kubernetes client/server certificates are stored in standard locations. You can view them to debug TLS handshake issues.

```bash
# List the PKI directory
ls -l /etc/kubernetes/pki/

# Inspect the kubelet client certificate using openssl
openssl x509 -in /var/lib/kubelet/pki/kubelet-client-current.pem -text -noout

# Check the Kubelet's CA certificate
ls -l /etc/kubernetes/pki/ca.crt
```

**3. Network Debugging**

The admin container includes standard networking tools.

```bash
# Check IP addresses and network interfaces
ip a

# View the node's routing table
ip route

# Check for listening ports (use `ss` as netstat may not be present)
ss -tulpn

# Run a tcpdump to inspect traffic on an interface (e.g., eth0)
# Very useful for debugging CNI or service connectivity issues
tcpdump -i eth0 host 10.100.0.10 and port 443
```

**4. Checking Kubelet and Containerd Status**

Use `systemctl` to check the status of the core services.

```bash
# Check if the kubelet service is running and view recent logs
systemctl status kubelet

# Check the containerd service
systemctl status containerd
```

**5. Exploring the Filesystem**

Remember, most of the filesystem is read-only.

```bash
# Check disk usage (note the tmpfs mounts)
df -h

# Find the Kubelet's configuration file
cat /var/lib/kubelet/config.yaml

# Explore container logs (if not shipped off-host)
ls -l /var/log/containers
```

---

### 4. Quick Reference: Common Commands

| Task | Command (run inside `sheltie`) |
| :--- | :--- |
| **Enter host shell** | `sheltie` |
| **View Kubelet logs** | `journalctl -u kubelet -f` |
| **View Containerd logs** | `journalctl -u containerd -f` |
| **Check Kubelet status** | `systemctl status kubelet` |
| **List network interfaces** | `ip a` |
| **Check listening ports** | `ss -tulpn` |
| **Capture network traffic** | `tcpdump -i <interface> <expression>` |
| **List mounted filesystems**| `df -h` |
| **Inspect Kubelet config** | `cat /var/lib/kubelet/config.yaml` |

---
