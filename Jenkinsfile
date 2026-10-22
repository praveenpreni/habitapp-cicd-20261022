pipeline {
  agent { label 'java21-docker' }
  options {
    skipDefaultCheckout(true)
    disableConcurrentBuilds()
    timestamps()
    timeout(time: 45, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }
  parameters {
    string(name: 'PUSH_IMAGE', defaultValue: 'localhost:5000/habitapp', description: 'Docker daemon registry address')
    string(name: 'DEPLOY_IMAGE', defaultValue: 'localhost:5000/habitapp', description: 'Kubernetes registry address')
    string(name: 'GITOPS_URL', defaultValue: 'https://github.com/praveenpreni/habitapp-gitops-20261022.git', description: 'Deployment repository')
    string(name: 'REGISTRY_CREDENTIAL_ID', defaultValue: 'registry-creds', description: 'Scoped registry push credential')
    string(name: 'SMOKE_NETWORK', defaultValue: 'habitapp-lab', description: 'Network shared with the Jenkins agent')
  }
  stages {
    stage('Checkout') {
      steps {
        deleteDir()
        checkout scm
        script {
          env.IMAGE_TAG = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
          env.SMOKE_NAME = "habitapp-smoke-${env.BUILD_NUMBER}"
        }
      }
    }
    stage('Maven Build') { steps { sh 'mvn -B -ntp clean compile' } }
    stage('Unit Test and Package') {
      steps { sh 'mvn -B -ntp verify' }
      post { always { junit testResults: 'target/surefire-reports/*.xml', allowEmptyResults: false } }
    }
    stage('SonarQube Analysis') {
      steps {
        // Poll the gate so private-network webhook restrictions cannot stall CI.
        withSonarQubeEnv('sonarqube') {
          sh 'mvn -B -ntp sonar:sonar -Dsonar.qualitygate.wait=true -Dsonar.qualitygate.timeout=300'
        }
      }
    }
    stage('Quality Gate') {
      steps { timeout(time: 10, unit: 'MINUTES') { waitForQualityGate abortPipeline: true } }
    }
    stage('Docker Build and Smoke Test') {
      steps {
        sh '''
          docker build -f Dockerfile.ci -t "$PUSH_IMAGE:$IMAGE_TAG" .
          docker run -d --name "$SMOKE_NAME" --network "$SMOKE_NETWORK" "$PUSH_IMAGE:$IMAGE_TAG"
          trap 'docker rm -f "$SMOKE_NAME" >/dev/null 2>&1 || true' EXIT
          for i in $(seq 1 60); do
            if curl -fsS "http://$SMOKE_NAME:8080/actuator/health/readiness"; then
              exit 0
            fi
            sleep 2
          done
          docker logs "$SMOKE_NAME"
          exit 1
        '''
      }
    }
    stage('Push Image') {
      steps {
        script {
          if (params.REGISTRY_CREDENTIAL_ID.trim()) {
            withCredentials([usernamePassword(credentialsId: params.REGISTRY_CREDENTIAL_ID,
              usernameVariable: 'REG_USER', passwordVariable: 'REG_PASS')]) {
              sh '''
                set +x
                export DOCKER_CONFIG=$(mktemp -d)
                trap 'rm -rf "$DOCKER_CONFIG"' EXIT
                registry=${PUSH_IMAGE%%/*}
                printf '%s' "$REG_PASS" | docker login "$registry" --username "$REG_USER" --password-stdin
                docker push "$PUSH_IMAGE:$IMAGE_TAG"
              '''
            }
          } else {
            if (!params.PUSH_IMAGE.startsWith('localhost:5000/')) {
              error('A registry credential is required outside the isolated local registry')
            }
            sh 'docker push "$PUSH_IMAGE:$IMAGE_TAG"'
          }
        }
      }
    }
    stage('Update Helm Configuration') {
      steps {
        withCredentials([usernamePassword(credentialsId: params.GITOPS_URL.startsWith('https://github.com/') ? 'github-gitops' : 'gitops-http',
          usernameVariable: 'GIT_USER', passwordVariable: 'GIT_PASS')]) {
          sh '''
            set +x
            askpass=$(mktemp)
            trap 'rm -f "$askpass"' EXIT
            printf '%s\n' '#!/bin/sh' 'case "$1" in *Username*) printf "%s" "$GIT_USER";; *) printf "%s" "$GIT_PASS";; esac' > "$askpass"
            chmod 700 "$askpass"
            export GIT_ASKPASS="$askpass" GIT_TERMINAL_PROMPT=0
            git clone --branch main "$GITOPS_URL" gitops
            cd gitops
            export DEPLOY_IMAGE IMAGE_TAG
            yq -i '.image.repository = strenv(DEPLOY_IMAGE) | .image.tag = strenv(IMAGE_TAG)' environments/local/values.yaml
            helm lint charts/habitapp -f environments/local/values.yaml
            helm template habitapp charts/habitapp -f environments/local/values.yaml > /dev/null
            git config user.name 'HabitApp CI'
            git config user.email 'ci@habitapp.local'
            git add environments/local/values.yaml
            if ! git diff --cached --quiet; then
              git commit -m "Deploy HabitApp $IMAGE_TAG"
              git push origin HEAD:main
            fi
          '''
        }
      }
    }
  }
  post {
    always {
      archiveArtifacts artifacts: 'target/*.jar,target/site/jacoco/**', allowEmptyArchive: true
      sh 'if [ -n "$SMOKE_NAME" ]; then docker rm -f "$SMOKE_NAME" >/dev/null 2>&1 || true; fi'
      deleteDir()
    }
  }
}
