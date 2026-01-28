<img src="https://r2cdn.perplexity.ai/pplx-full-logo-primary-dark%402x.png" style="height:64px;margin-right:32px"/>

# Help me in this design , I have MOBILE  application traffic originating from internet and going to my NLB on AWS and goes thru the ISTIO MESH on my eks cluster and reache the app and makes some on Prem database calls , what are the tools and cw alarms I can use to measure any issues and latency?

You want end‑to‑end latency and issue detection from mobile → NLB → Istio/EKS → on‑prem DB. Here’s a concise tool/metrics stack and key CloudWatch alarms for each hop.

## 1. NLB edge (internet → AWS)

Use native NLB metrics in CloudWatch for front‑door health and latency.[^1][^2]

Key metrics (namespace: `AWS/NetworkELB`):[^2][^1]

- **TCP_ClientTLSNegotiationErrorCount**, `TCP_ELBResetCount`, `TCP_TargetResetCount` (connectivity resets).
- `ActiveFlowCount`, `NewFlowCount` (sudden drops/spikes).
- `ProcessedBytes` and `ConsumedLCUs` (load vs capacity).
- If you can, front with ALB for HTTP(S) and use `TargetResponseTime` as a direct latency metric.[^3]

Critical CloudWatch alarms:

- NLB health / availability
    - Alarm when `HealthyHostCount` drops below expected (per AZ).
    - Alarm when `UnHealthyHostCount` > 0 for more than N minutes.
- NLB‑level latency / errors
    - If using ALB in front, alarm on `TargetResponseTime` p95 or p99 > X ms for Y periods.[^3]
    - Alarm on `TCP_ELBResetCount` or `TCP_TargetResetCount` suddenly spiking above baseline.

These give you: “Is the problem at the edge or behind the NLB?”

## 2. Istio service mesh layer (NLB → mesh → app)

Istio exposes standard telemetry covering latency, traffic and errors.[^4]

Core Istio metrics (via Prometheus / AMP, Grafana, Kiali, etc.):[^5][^6][^4]

- **Latency**
    - `istio_request_duration_milliseconds_bucket` or `istio_request_duration_seconds` to compute p50/p90/p95/p99 per service/route.[^6][^5]
- **Traffic**
    - `istio_requests_total` by source/destination, response_code.[^4]
- **Errors**
    - `istio_requests_total{response_code=~"5..|4.."} ` for error rate, `istio_upstream_rq_5xx` for upstream failures.[^6][^4]

Practical alerts (Prometheus rules or AMP → CloudWatch):[^7][^5][^6][^4]

- Per critical API (the mobile‑facing virtual service):
    - P95 or P99 `istio_request_duration_*` > X ms for Y minutes.
    - Error rate > Z% (based on `istio_requests_total`) for Y minutes.
- Mesh health:
    - Envoy sidecar not scraping/exporting metrics (e.g., `up{job="istio-envoy"}` == 0).

These tell you: “Is the latency inside the cluster / between microservices?”

## 3. App and DB calls (in‑cluster → on‑prem)

You need visibility into the application and the network path to on‑prem.

### 3.1 Distributed tracing

Use Jaeger/Tempo/X-Ray (or vendor APM) with Istio trace propagation:[^7][^6][^4]

- Capture spans for:
    - Ingress → gateway → app → database client library.
- Measure:
    - HTTP handler duration, DB query duration, and network call duration as separate spans.
- Alert on:
    - P95 DB span duration > X ms.
    - Percentage of traces where DB span > some threshold.

This gives pinpoint: “Is DB the bottleneck vs app vs network?”

### 3.2 On‑prem DB metrics into CloudWatch

Use CloudWatch agent / hybrid monitoring to push on‑prem DB and OS metrics into CloudWatch.[^8][^9]

- Install SSM + CloudWatch agent on DB hosts and send:
    - CPU, memory, disk, network RTT/throughput to AWS.[^9]
    - DB‑native metrics (e.g., connections, slow queries) via StatsD/Prometheus → CloudWatch or Prometheus connector.[^8][^9]

CloudWatch alarms on DB side:[^9][^8]

- CPU > 80–90% for sustained period.
- Connection count > N (near max).
- Slow query count / query latency metric above SLO (if exported).

These answer: “Is on‑prem DB saturated or slow?”

## 4. Hybrid network path (EKS VPC ↔ on‑prem)

For Direct Connect/VPN latency and packet loss, use CloudWatch Network Monitor synthetic probes.[^10]

Capabilities:[^10]

- Deploy a monitor in the VPC to continuously probe an on‑prem endpoint via DX or VPN.
- Exposes metrics like round‑trip latency, packet loss, and Network Health Indicator into CloudWatch.[^10]

Key alarms:[^10]

- RTT latency above SLO (p95) for given monitor.
- Packet loss > small threshold for N minutes.
- NHI below healthy threshold (if configured).

That tells you: “Is the DX/VPN path itself degraded?”

## 5. End‑to‑end SLOs and synthetic checks

To bridge gaps, add synthetic HTTP checks and app‑level SLIs.

### 5.1 HTTP synthetics

Use Route 53 health checks or a synthetic monitoring tool to hit the mobile entry endpoint:[^11]

- Monitor HTTP 200 rate and end‑to‑end latency from outside AWS.
- CloudWatch alarms on:
    - Health check failure rate > 0 for N minutes.
    - Latency above SLO (e.g., >1s) from multiple regions.[^11]


### 5.2 CloudWatch SLO dashboards

In CloudWatch dashboards, combine:[^12][^1][^2][^3][^4]

- NLB/ALB metrics: `HealthyHostCount`, `TargetResponseTime` (if ALB).
- Istio metrics: P95/P99 `istio_request_duration_*`, error rate.
- DB metrics: CPU, slow queries, DB latency.
- Network Monitor metrics: RTT, packet loss.

Use `tmXX` (trimmed mean) or percentile statistics for latency panels where relevant, since they’re robust against outliers for web latency.[^12]

***

If you share a bit more detail (DX vs VPN, ALB in front of NLB or pure NLB, tracing stack preference), I can suggest concrete metric names, sample PromQL and 2–3 specific alarm JSONs you can drop into Terraform/CloudFormation.
<span style="display:none">[^13][^14][^15]</span>

<div align="center">⁂</div>

[^1]: https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-cloudwatch-metrics.html

[^2]: https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-monitoring.html

[^3]: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-cloudwatch-metrics.html

[^4]: https://istio.io/latest/docs/concepts/observability/

[^5]: https://tetrate.io/blog/key-metrics-to-monitor-the-istio-data-plane

[^6]: https://newrelic.com/blog/apm/monitoring-istio-service-mesh

[^7]: https://oneuptime.com/blog/post/2026-01-08-istio-network-latency-tracing/view

[^8]: https://aws.amazon.com/blogs/aws/new-use-amazon-cloudwatch-to-consolidate-hybrid-multi-cloud-and-on-premises-metrics/

[^9]: https://aws.amazon.com/blogs/mt/how-to-monitor-hybrid-environment-with-aws-services/

[^10]: https://aws.amazon.com/blogs/networking-and-content-delivery/monitor-hybrid-connectivity-with-amazon-cloudwatch-network-monitor/

[^11]: https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/monitoring-health-check-latency.html

[^12]: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Statistics-definitions.html

[^13]: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/US_AlarmAtThresholdELB.html

[^14]: https://stackoverflow.com/questions/43984902/how-to-get-latency-metric-from-aws-cloudwatch-application-elb

[^15]: https://help.drata.com/en/articles/9828801-test-293-aws-classic-load-balancer-latency-monitored

