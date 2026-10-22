FROM maven:3.9.9-eclipse-temurin-21 AS maven
FROM docker:27.5.1-cli AS docker
FROM alpine/helm:3.17.3 AS helm
FROM mikefarah/yq:4.45.1 AS yq
FROM jenkins/jenkins:lts-jdk21
USER root
COPY --from=maven /usr/share/maven /opt/maven
COPY --from=docker /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker /usr/local/libexec/docker/cli-plugins /usr/local/libexec/docker/cli-plugins
COPY --from=helm /usr/bin/helm /usr/local/bin/helm
COPY --from=yq /usr/bin/yq /usr/local/bin/yq
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates && rm -rf /var/lib/apt/lists/*
ENV PATH="/opt/maven/bin:${PATH}"
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
COPY casc.yaml /usr/share/jenkins/ref/casc.yaml
ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/ref/casc.yaml
USER jenkins
