# Enterprise Kubernetes Deployment for Watsonx Code Assistant

This directory contains configuration files for deploying Watsonx Code Assistant in an enterprise Kubernetes environment, providing scalability, reliability, and advanced resource management.

## Prerequisites

- Kubernetes 1.19+
- kubectl configured to connect to your cluster
- NVIDIA GPU Operator installed (for GPU acceleration)
- Storage class capable of provisioning persistent volumes

## Deployment Instructions

1. Build and push the Docker image to your registry:
   ```bash
   docker build -t <your-registry>/watsonx-code-assistant:latest .
   docker push <your-registry>/watsonx-code-assistant:latest
   ```

2. Update the image reference in `deployment.yaml` to point to your registry.

3. Apply the Kubernetes manifests:
   ```bash
   kubectl apply -f kubernetes/
   ```

4. Monitor the deployment:
   ```bash
   kubectl get pods -l app=watsonx-code-assistant
   kubectl logs -l app=watsonx-code-assistant
   ```

## Resource Configuration

The default configuration allocates:
- 1 GPU
- 4 CPU cores (max)
- 8GB RAM (max)

Adjust these values in `deployment.yaml` based on your cluster capabilities and workload requirements.

## Scaling

For larger teams or higher throughput, you can scale the deployment:
```bash
kubectl scale deployment watsonx-code-assistant --replicas=3
```

Note: When scaling beyond one replica, ensure you've configured a shared storage solution for model files.

## Monitoring

Add the following annotations to enable Prometheus monitoring:
```yaml
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/path: "/metrics"
    prometheus.io/port: "5000"
```

## Security Considerations

- The deployment uses a LoadBalancer service type by default. Consider using an Ingress with TLS for production environments.
- Implement network policies to restrict pod-to-pod communication.
- Use Kubernetes secrets for sensitive configuration values.
