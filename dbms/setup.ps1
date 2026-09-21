$ErrorActionPreference = "Stop"

$mysql = Get-Command mysql.exe -ErrorAction SilentlyContinue
if (-not $mysql) {
    $defaultPath = "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe"
    if (Test-Path $defaultPath) {
        $mysqlPath = $defaultPath
    } else {
        throw "mysql.exe was not found. Install MySQL 8.0+ and add its bin folder to PATH."
    }
} else {
    $mysqlPath = $mysql.Source
}

$sqlDirectory = Join-Path $PSScriptRoot "sql"
$runner = Join-Path ([System.IO.Path]::GetTempPath()) "railflow-setup-$([guid]::NewGuid()).sql"
$tests = Join-Path ([System.IO.Path]::GetTempPath()) "railflow-tests-$([guid]::NewGuid()).sql"
$cleanup = Join-Path ([System.IO.Path]::GetTempPath()) "railflow-cleanup-$([guid]::NewGuid()).sql"

try {
    $sources = 1..11 | ForEach-Object {
        "SOURCE $((Join-Path $sqlDirectory ("{0:D2}_*.sql" -f $_)).Replace('\', '/'));"
    }
    # Resolve the wildcard paths before writing SOURCE statements.
    $sources = 1..11 | ForEach-Object {
        $file = Get-ChildItem $sqlDirectory -Filter ("{0:D2}_*.sql" -f $_) | Select-Object -First 1
        if (-not $file) { throw "Missing SQL script for step $($_)." }
        "SOURCE $($file.FullName.Replace('\', '/'));"
    }
    $testFile = Join-Path $sqlDirectory "12_test_cases.sql"
    $cleanupFile = Join-Path $sqlDirectory "13_cleanup.sql"
    Set-Content -Path $runner -Value $sources -Encoding UTF8
    Set-Content -Path $tests -Value "SOURCE $($testFile.Replace('\', '/'));" -Encoding UTF8
    Set-Content -Path $cleanup -Value "SOURCE $($cleanupFile.Replace('\', '/'));" -Encoding UTF8

    Write-Host "Running schema, routines, seed data, and demo transactions."
    & $mysqlPath -u root -p -e "source $runner"
    if ($LASTEXITCODE -ne 0) {
        throw "RailFlow schema setup failed. Review the output above."
    }
    Write-Host "Running positive and expected-failure tests."
    & $mysqlPath -u root -p --force -e "source $tests"
    if ($LASTEXITCODE -ne 0) {
        throw "RailFlow tests returned an unexpected client error."
    }
    Write-Host "Removing test-only rows."
    & $mysqlPath -u root -p -e "source $cleanup"
    if ($LASTEXITCODE -ne 0) {
        throw "RailFlow cleanup failed. Review the output above."
    }
    Write-Host "RailFlow database setup and tests completed."
} finally {
    foreach ($temporaryFile in @($runner, $tests, $cleanup)) {
        if (Test-Path $temporaryFile) {
            Remove-Item -LiteralPath $temporaryFile -Force
        }
    }
}
