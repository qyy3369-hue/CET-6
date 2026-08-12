param(
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$appProject = Join-Path $projectRoot "Windows\Goals.Windows\Goals.Windows.csproj"
$testProject = Join-Path $projectRoot "Windows\Goals.Windows.SmokeTests\Goals.Windows.SmokeTests.csproj"
$output = Join-Path $projectRoot "Windows\Release\Goals-win-x64"

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw "未找到 .NET SDK。请安装 .NET 10 SDK 后重试。"
}

$env:DOTNET_CLI_TELEMETRY_OPTOUT = "1"
dotnet run --project $testProject -c $Configuration --nologo
dotnet publish $appProject -c $Configuration -r win-x64 --self-contained true -o $output --nologo

Write-Output "Windows 便携版已生成：$output"
