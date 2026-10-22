# HabitApp CI and CD implementation

The application now has real tests, dedicated health endpoints, container packaging, a Jenkins pipeline, a reusable Helm chart, and Argo CD configuration. Jenkins publishes the tested JAR in a SHA-tagged image and changes deployment Git. Argo CD alone deploys the application.

## Verified in this workspace on 22 October 2026

- Java 21 Maven clean verify passed: 15 tests, zero failures, errors or skips.
- Executable habit-tracker.jar was packaged successfully.
- Direct JVM execution returned HTTP 200 for the dashboard, API, liveness and readiness.
- Helm lint passed and local and ingress-enabled configurations rendered successfully.
- Docker Compose configuration validated without starting containers.
- Jenkinsfile passed Groovy syntax compilation. Jenkins runtime execution is still required.
- Both PowerShell setup scripts passed syntax parsing. Their Docker-dependent execution is still required.

Docker Desktop 4.96.2 now starts successfully and the user has verified its Linux engine in Windows PowerShell. Codex commands still receive a named-pipe permission error. No Docker image build, Jenkins pipeline run, SonarQube result, registry publication, Kubernetes deployment, or Argo CD synchronization has been claimed as completed.

## Local application

Use JDK 21 and Maven 3.9.9. In PowerShell 7:

```powershell
./scripts/Verify-Local.ps1 -JavaHome 'PATH_TO_JDK_21' -MavenCommand 'PATH_TO_MAVEN/bin/mvn.cmd'
./scripts/Run-Local.ps1 -JavaHome 'PATH_TO_JDK_21'
```

The direct application URL is http://localhost:28081. The application default and container port remain 8080. Ports 8080 and 18080 were already occupied during inspection, so this project uses separate host ports and leaves existing services alone.

## Start the local delivery lab after Docker is repaired

Prerequisites: functioning Docker Desktop Linux engine, PowerShell 7, Git, kubectl, internet access and adequate memory. Plan approximately 10 to 12 GB of available Docker memory for the combined lab; the actual need depends on workload and service versions.

```powershell
./infra/Initialize-Lab.ps1
```

The script provisions local Git through Gitea, an isolated registry, SonarQube, Jenkins and a kind cluster. It creates separate application and GitOps repositories, configures the SonarQube webhook and Jenkins credentials, bootstraps Argo CD, and triggers the initial build. It uses a project-local kubeconfig and does not change your existing cluster contexts. Existing containers with the same project names must be reviewed before running it.

Service addresses:

| Service | Local URL |
| --- | --- |
| Gitea repositories | http://localhost:13000/lab |
| Jenkins lab | http://localhost:8081 |
| SonarQube | http://localhost:9000 |
| Container registry | http://localhost:5000/v2/ |
| Kubernetes application after successful synchronization | http://localhost:28080 |

Jenkins and SonarQube use admin; Gitea uses lab. Random passwords are generated into .local/state.json, and the Sonar token is stored there too. Never share or commit .local. The local repositories are public only inside the isolated lab network, with host ports bound to loopback. No GitHub repository has been created or changed by these scripts.

The local bootstrap is implementation code awaiting execution against a working Docker engine. Review actual startup errors and correct configuration as needed; a static check cannot establish end-to-end success.

## GitHub and production promotion

Publish the source and the separate charts/environments deployment repository to repositories you own. Replace Gitea URLs in the Jenkins job, pipeline parameters and Argo CD project/application. Configure repository access credentials with narrowly scoped permissions, HTTPS, trusted certificates and protected branches. Reconfigure the pipeline environment values file path for each environment when extending beyond the local chart.

Use an authenticated TLS registry and a scoped push credential. The local lab now generates registry credentials for Jenkins and a registry-pull Secret for Kubernetes. It still uses local HTTP and must remain isolated. Production requires TLS, immutable tags or digests, approved base-image digests, vulnerability scanning and artifact signing. Latest lab Jenkins and SonarQube tags need approved version/digest pins for repeatability before a production deployment.

Jenkins in this isolated lab runs with Docker socket access and root inside its container so it can build images. This grants control over the Docker daemon. Run trusted source only; production should use isolated disposable build agents with a dedicated image builder. SonarQube bootstrap checks are disabled for the local lab only; production needs supported host limits and an external supported database.

## Rolling update and rollback

The chart uses two replicas, zero unavailable replicas and one surge replica. Readiness gates traffic, a startup probe protects slow starts, and the process has graceful termination. Monitor timestamped HTTP checks throughout a deployment before claiming availability.

To recover, revert the faulty promotion commit in the deployment repository and push it. Argo CD then restores the previous image from Git. Do not rely on kubectl rollout undo while self-healing is active. Capture the old/new image, Git commit, Argo CD revision, pod readiness and response logs.

## Data limitation

HabitApp still uses process-local in-memory storage. Replicas do not share habits and restarts clear data. Infrastructure availability does not establish data durability or consistent application behavior across replicas. A shared database, migration strategy and backup/restore checks are required before real production use. The original daily-streak algorithm also applies to weekly-frequency habits; business semantics for weekly streaks require separate product decisions.

## Collect evidence

After a successful Jenkins build and healthy Argo CD synchronization:

```powershell
./infra/Collect-Evidence.ps1
```

The script saves workload configuration, CPU and memory, restart counts, events, application logs, Argo CD state, Secret metadata without values, registry tags, HTTP responses, Jenkins console output and SonarQube Quality Gate results under a timestamped evidence directory. First run infra/Enable-Monitoring.ps1 to install Metrics Server in the isolated kind cluster. Add screenshots from the live Jenkins and SonarQube interfaces and review the captured states before reporting success. Follow infra/DEPLOYMENT-DEMONSTRATION.md to collect separate baseline, new-version and rollback evidence.

Argo CD renders this Helm chart and owns its Kubernetes resources. There is no Helm CLI release history for that deployment. For a separate Helm CLI demonstration, deploy to a different namespace and remove that test release afterwards.

## References

- Application: https://github.com/Vennilavanguvi/HabitApp
- Jenkins SonarQube integration: https://www.jenkins.io/doc/pipeline/steps/sonar/
- kind local registry configuration: https://kind.sigs.k8s.io/docs/user/local-registry/
- Argo CD automated sync: https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/
- Docker Desktop WSL setup: https://docs.docker.com/desktop/features/wsl/
