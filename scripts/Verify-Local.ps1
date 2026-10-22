#Requires -Version 7.0
[CmdletBinding()]
param([string]$JavaHome = $env:JAVA_HOME, [string]$MavenCommand = 'mvn')
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$true
$projectRoot=Split-Path $PSScriptRoot -Parent
if (-not $JavaHome) { throw 'Pass -JavaHome pointing to JDK 21.' }
$env:JAVA_HOME=$JavaHome
& (Join-Path $JavaHome 'bin/java.exe') -version
$evidence=Join-Path $projectRoot 'evidence'
New-Item -ItemType Directory -Force $evidence | Out-Null
& $MavenCommand -B -ntp -f (Join-Path $projectRoot 'pom.xml') clean verify 2>&1 | Tee-Object (Join-Path $evidence 'maven-build.log')
Write-Host 'Maven build and tests completed. The executable JAR is in target/habit-tracker.jar.'
