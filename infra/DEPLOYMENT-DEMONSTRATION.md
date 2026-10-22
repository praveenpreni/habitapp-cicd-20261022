# Deployment and rollback evidence

Run this only after the initial Jenkins build succeeds and Argo CD shows the baseline version as Synced and Healthy. These are executable demonstration steps awaiting the working Docker runtime, not completed results.

1. Run `Enable-Monitoring.ps1`. Collect baseline evidence with `Collect-Evidence.ps1`. Record the baseline image from `kubectl -n habitapp get deployment habitapp -o jsonpath='{.spec.template.spec.containers[0].image}'` using the project-local kubeconfig.
2. In a separate PowerShell window, start an availability log:

```powershell
$log='availability.csv'
'time,status' | Set-Content $log
while ($true) {
  $time=(Get-Date).ToUniversalTime().ToString('o')
  try { $status=(Invoke-WebRequest http://localhost:28080/ -TimeoutSec 5 -NoProxy).StatusCode }
  catch { $status='ERROR' }
  "$time,$status" | Add-Content $log
  Start-Sleep 2
}
```

3. Change `src/main/resources/static/release.txt` to a distinct release label. Commit the change in the application repository and push it to its configured lab or GitHub remote using the existing credential flow. Trigger the Jenkins job again. Keep the source commit, Jenkins build URL, new registry tag and deployment Git promotion commit.
4. Watch `kubectl -n habitapp rollout status deployment/habitapp --timeout=300s`. Confirm two ready replicas, a changed image SHA, Argo CD Synced and Healthy, and the new release label at `http://localhost:28080/release.txt`. Collect evidence into a separate folder using `Collect-Evidence.ps1 -RunName new-version`.
5. In the deployment repository, revert the promotion commit using `git revert PROMOTION_COMMIT`. Push the revert using the same configured Git credentials. Argo CD reconciles the restored image. Wait for readiness, confirm the original image and original release label, and run `Collect-Evidence.ps1 -RunName rollback`.
6. Stop the HTTP monitor with Ctrl+C. Review every recorded status before making an availability claim. Keep the log with both the new-version and rollback evidence. If the rollout fails, retain events and previous-container logs before reverting the promotion commit.

Do not use `kubectl rollout undo` while Argo CD self-healing is active. Revert the desired state in Git. No rollback can restore data lost from the application's in-memory storage.
