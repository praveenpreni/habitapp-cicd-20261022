#Requires -Version 7.0
[CmdletBinding()]
param([string]$JavaHome = $env:JAVA_HOME, [int]$Port=28081)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
if (-not $JavaHome) { throw 'Pass -JavaHome pointing to JDK 21.' }
& (Join-Path $JavaHome 'bin/java.exe') -jar (Join-Path $projectRoot 'target/habit-tracker.jar') --server.address=127.0.0.1 "--server.port=$Port"
