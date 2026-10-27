# HabitApp CI/CD delivery

## Repositories

- Application: https://github.com/praveenpreni/habitapp-cicd-20261022
- Deployment: https://github.com/praveenpreni/habitapp-gitops-20261022

The source repository includes README.md, pom.xml, src/, Dockerfile, Dockerfile.ci, Jenkinsfile, charts/habitapp/, environments/, argocd/ and infra/.

## Pipeline

Jenkins checks out a source revision, compiles with Maven, runs 16 tests, packages the JAR, analyzes the source with SonarQube and waits for the Quality Gate. The Docker stage uses the multi-stage Dockerfile, smoke-tests Actuator readiness on container port 8080, and publishes a source-SHA image. Jenkins validates Helm, updates the image tag in deployment Git and pushes the promotion commit. Argo CD owns deployment reconciliation; the delivery pipeline does not run kubectl or helm upgrade.

Dockerfile.ci is retained as an alternative for packaging a prebuilt JAR. Both Dockerfiles run the Java application as UID/GID 10001. The currently prepared pipeline uses Dockerfile; consult the matching Jenkins build console and report for execution results.

## Application access

HabitApp listens on container port 8080. The local Kubernetes Service is NodePort 30080, mapped by kind to http://127.0.0.1:28080. A pod port-forward on host 28081 is used for deterministic per-pod functional tests. The chart also supports optional ingress; the demonstrated local environment uses NodePort. Localhost URLs require the lab to be running. A former temporary tunnel is not a permanent hosting endpoint.

## Helm and Argo CD

The reusable chart provides Deployment, Service, ConfigMap, optional Ingress and PodDisruptionBudget templates. values.yaml configures replicas, image, resources, environment, probes, service type, ingress, existingSecret and imagePullSecrets. Sensitive Secret values are provisioned outside Git. registry-pull is the existing Kubernetes image-pull Secret; it is not a chart template containing credentials.

Argo CD renders the Helm chart and reconciles it with namespace habitapp. This does not create Helm CLI release history. AppProject limits source repositories, destination namespace and resource kinds. The application Pod disables service-account token automounting and uses non-root identity, seccomp, a read-only root filesystem and dropped capabilities. The default application service account has no permission to read Secrets.

## Rollback and verification

Revert the image-promotion commit in deployment Git and push the revert. Argo CD reconciles that desired state. Capture the Git revision, image, Synced/Healthy status, ready replicas, rollout result and HTTP health throughout recovery. Restore the intended image with another Git commit. Do not use kubectl rollout undo while GitOps self-healing is active.

The separate habitapp-runtime-verification Jenkins job executes read-only diagnostics and registry checks. It does not deploy resources or alter Git. Its actual execution console records workloads, image tags, strategy, probes, resources, CPU/memory, startup logs, UID and authorization checks.

## Runtime and production scope

The demonstrated environment is a local single-node kind cluster. The registry is authenticated but uses isolated local HTTP. Jenkins has privileged Docker-socket access and SonarQube uses an evaluation database. Production requires an isolated image builder, supported external SonarQube database, registry TLS, durable infrastructure and controlled access.

Habit data is held in process memory. Replicas do not share records, and restarts clear data. Infrastructure health does not establish persistent data availability. A shared database and backup/recovery design are required for production use.

Generated credentials, kubeconfig and GitHub authentication stay in .local/ or the user's credential store. Never commit or package credential values.
