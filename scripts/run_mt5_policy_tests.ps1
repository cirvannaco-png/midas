$ErrorActionPreference = "Stop"

if (-not (Test-Path $env:METAEDITOR)) { throw "METAEDITOR is not set to an installed MetaEditor64 executable." }
if (-not (Test-Path $env:MQL5ROOT)) { throw "MQL5ROOT is not set to the installed MQL5 data directory." }

$scriptsRoot = Join-Path $env:MQL5ROOT "Scripts\development\EA"
$testsRoot = Join-Path $scriptsRoot "tests"
$includesRoot = Join-Path $scriptsRoot "includes"
$filesRoot = Join-Path $env:MQL5ROOT "Files"
New-Item -ItemType Directory -Force -Path $testsRoot, $includesRoot, $filesRoot, "artifacts" | Out-Null

# Preserve each test's relative ../includes layout and bring in the complete
# modular include tree; these suites deliberately use no broker credentials.
Copy-Item -Path "development/EA/includes/*" -Destination $includesRoot -Recurse -Force
Copy-Item -Path "development/EA/tests/*.mq5" -Destination $testsRoot -Force
Copy-Item -Path "development/EA/tests/TestHarness.mqh" -Destination $testsRoot -Force

$includeArg = '/include:"' + $env:MQL5ROOT + '"'
$testSources = Get-ChildItem -Path $testsRoot -Filter "*.mq5" | Sort-Object Name
if ($testSources.Count -lt 7) { throw "Expected at least seven native MT5 test sources; found $($testSources.Count)." }

# Compile every test/script source, including the read-only runtime preflight.
foreach ($testSource in $testSources) {
  $log = [System.IO.Path]::ChangeExtension($testSource.FullName, ".log")
  $compileArg = '/compile:"' + $testSource.FullName + '"'
  $proc = Start-Process -FilePath $env:METAEDITOR -ArgumentList @($compileArg, $includeArg, "/log") -Wait -PassThru
  if (-not (Test-Path $log)) { throw "MetaEditor log missing for $($testSource.Name); process exit $($proc.ExitCode)." }

  $content = Get-Content $log -Raw -Encoding Unicode
  $match = [regex]::Match($content, "Result:\s*(\d+)\s+errors?,\s*(\d+)\s+warnings?")
  if (-not $match.Success) { throw "Cannot parse MetaEditor result for $($testSource.Name): $content" }
  $errors = [int]$match.Groups[1].Value
  $warnings = [int]$match.Groups[2].Value
  Write-Host "$($testSource.Name): $errors errors, $warnings warnings"
  # Preserve the compiler log even when the zero-warning gate fails.
  Copy-Item $log ("artifacts/" + $testSource.BaseName + ".MetaEditor.log") -Force
  if ($errors -ne 0 -or $warnings -ne 0) {
    throw "Native test source $($testSource.Name) must compile with zero errors and zero warnings."
  }
}

$runtimeTests = @(
  "AccountRiskProfilePolicy",
  "ConfigSyncContract",
  "DecisionEngineGeometry",
  "DynamicStopEngine",
  "FreshSweepAdditiveRouter",
  "OpposingPositionPolicy",
  "PositionManagementPolicy",
  "PipCalculatorGeometry",
  "BrokerQuoteValidator"
)
$terminal = Join-Path (Split-Path $env:METAEDITOR) "terminal64.exe"
if (-not (Test-Path $terminal)) { throw "terminal64.exe was not found beside MetaEditor." }

foreach ($name in $runtimeTests) {
  $resultFile = Join-Path $filesRoot ($name + "-tests.txt")
  if (Test-Path $resultFile) { Remove-Item $resultFile -Force }

  $config = Join-Path $env:RUNNER_TEMP ($name + "-test.ini")
  $ini = @"
[StartUp]
Script=development\EA\tests\$name
Symbol=EURUSD
Period=M1
ShutdownTerminal=Yes
"@
  Set-Content -LiteralPath $config -Value $ini -Encoding Unicode

  $proc = Start-Process -FilePath $terminal -ArgumentList @("/portable", "/config:$config") -PassThru
  if (-not $proc.WaitForExit(180000)) {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    throw "$name MT5 runtime test exceeded 180 seconds."
  }
  $proc.Refresh()

  if (-not (Test-Path $resultFile)) {
    throw "$name did not write its result file; the script may not have started or may have failed before assertions."
  }
  $result = Get-Content -LiteralPath $resultFile -Raw
  if ($result -notmatch "failures=0") { throw "$name runtime assertions failed: $result" }
  if ($proc.ExitCode -ne 0) { throw "$name terminal process returned exit code $($proc.ExitCode)." }

  Write-Host "$name runtime assertions: PASS ($($result.Trim()))"
  Copy-Item $resultFile ("artifacts/" + $name + "-tests.txt") -Force
}

"Native MT5 policy suites passed: $($runtimeTests -join ', ')" |
  Out-File "artifacts/native-policy-test-summary.txt" -Encoding utf8
