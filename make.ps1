Param(
  [Parameter(Position=0, HelpMessage="The action to take (build, test, install, package, clean).")]
  [string]
  $Command = 'build',

  [Parameter(HelpMessage="The build configuration (Release, Debug).")]
  [string]
  $Config = "Release"
)

$ErrorActionPreference = "Stop"

$target = "lori"
$testPath = "."
$rootDir = Split-Path $script:MyInvocation.MyCommand.Path
$srcDir = Join-Path -Path $rootDir -ChildPath $target

if ($Config -ieq "Release")
{
  $configFlag = ""
  $buildDir = Join-Path -Path $rootDir -ChildPath "build/release"
}
elseif ($Config -ieq "Debug")
{
  $configFlag = "--debug"
  $buildDir = Join-Path -Path $rootDir -ChildPath "build/debug"
}
else
{
  throw "Invalid -Config path '$Config'; must be one of (Debug, Release)."
}

$libsDir = Join-Path -Path $rootDir -ChildPath "build/libs"

$ponyArgs = "--define libressl  --path $rootDir"

function BuildTest
{
  $testTarget = "$target.exe"

  $testFile = Join-Path -Path $buildDir -ChildPath $testTarget
  $testTimestamp = [DateTime]::MinValue
  if (Test-Path $testFile)
  {
    $testTimestamp = (Get-ChildItem -Path $testFile).LastWriteTimeUtc
  }

  :testFiles foreach ($file in (Get-ChildItem -Path $srcDir -Include "*.pony" -Recurse))
  {
    if ($testTimestamp -lt $file.LastWriteTimeUtc)
    {
      Write-Host "corral fetch"
      $output = (corral fetch)
      $output | ForEach-Object { Write-Host $_ }
      if ($LastExitCode -ne 0) { throw "Error" }

      $testDir = Join-Path -Path $srcDir -ChildPath $testPath
      Write-Host "corral run -- ponyc $configFlag $ponyArgs --output `"$buildDir`" `"$testDir`""
      $output = (corral run -- ponyc $configFlag $ponyArgs --output "$buildDir" "$testDir")
      $output | ForEach-Object { Write-Host $_ }
      if ($LastExitCode -ne 0) { throw "Error" }
      break testFiles
    }
  }

  Write-Output "$testTarget.exe is built" # force function to return a list of outputs
  return $testFile
}

function BuildLibs
{
  # When upgrading, change $libreSsl, $libreSslLib, and the copied libs below
  $libreSsl = "libressl-3.9.1"

  if (-not ((Test-Path "$rootDir/crypto.lib") -and (Test-Path "$rootDir/ssl.lib")))
  {
    $libreSslSrc = Join-Path -Path $libsDir -ChildPath $libreSsl

    if (-not (Test-Path $libreSslSrc))
    {
      $libreSslTgz = "$libreSsl.tar.gz"
      $libreSslTgzTgt = Join-Path -Path $libsDir -ChildPath $libreSslTgz
      if (-not (Test-Path $libreSslTgzTgt)) { Invoke-WebRequest -TimeoutSec 300 -Uri "https://cdn.openbsd.org/pub/OpenBSD/LibreSSL/$libreSslTgz" -OutFile $libreSslTgzTgt }
      tar -xvzf "$libreSslTgzTgt" -C "$libsDir"
      if ($LastExitCode -ne 0) { throw "Error downloading and extracting $libreSslTgz" }
    }

    # Write-Output "Building $libreSsl"
    $libreSslLib = Join-Path -Path $libsDir -ChildPath "lib/ssl-53.lib"

    if (-not (Test-Path $libreSslLib))
    {
      Push-Location $libreSslSrc
      (Get-Content "$libreSslSrc\CMakeLists.txt").replace('add_definitions(-Dinline=__inline)', "add_definitions(-Dinline=__inline)`nadd_definitions(-DPATH_MAX=255)") | Set-Content "$libreSslSrc\CMakeLists.txt"
      cmake.exe $libreSslSrc -Thost=x64 -A x64 -DCMAKE_INSTALL_PREFIX="$libsDir" -DCMAKE_BUILD_TYPE="Release"
      if ($LastExitCode -ne 0) { Pop-Location; throw "Error configuring $libreSsl" }
      cmake.exe --build . --target install --config Release
      if ($LastExitCode -ne 0) { Pop-Location; throw "Error building $libreSsl" }
      Pop-Location
    }

    # copy to the root dir (i.e. PONYPATH) for linking
    Copy-Item -Force -Path "$libsDir/lib/ssl.lib" -Destination "$rootDir/ssl.lib"
    Copy-Item -Force -Path "$libsDir/lib/crypto.lib" -Destination "$rootDir/crypto.lib"
    Copy-Item -Force -Path "$libsDir/lib/tls.lib" -Destination "$rootDir/tls.lib"
  }
}

function BuildExamples
{
    $examplesDir = Join-Path -Path $rootDir -ChildPath "examples"

    # Get all subdirectories in examples folder
    $examples = Get-ChildItem -Path $examplesDir -Directory

    foreach ($example in $examples) {
        $exampleName = $example.Name
        $exampleTarget = "$exampleName.exe"
        $exampleFile = Join-Path -Path $buildDir -ChildPath $exampleTarget

        Write-Host "Building example: $exampleName"

        # Check if we need to rebuild
        $needsRebuild = $false
        if (-not (Test-Path $exampleFile)) {
            $needsRebuild = $true
        } else {
            $exampleTimestamp = (Get-ChildItem -Path $exampleFile).LastWriteTimeUtc

            # Check source files in both src and example directories
            Get-ChildItem -Path $srcDir -Include "*.pony" -Recurse | ForEach-Object {
                if ($exampleTimestamp -lt $_.LastWriteTimeUtc) {
                    $needsRebuild = $true
                }
            }

            Get-ChildItem -Path $example.FullName -Include "*.pony" -Recurse | ForEach-Object {
                if ($exampleTimestamp -lt $_.LastWriteTimeUtc) {
                    $needsRebuild = $true
                }
            }
        }

        if ($needsRebuild) {
            Write-Host "corral fetch"
            $output = (corral fetch)
            $output | ForEach-Object { Write-Host $_ }
            if ($LastExitCode -ne 0) { throw "Error during corral fetch" }

            Write-Host "corral run -- ponyc $configFlag $ponyArgs --output `"$buildDir`" `"$($example.FullName)`""
            $output = (corral run -- ponyc $configFlag $ponyArgs --output "$buildDir" "$($example.FullName)")
            $output | ForEach-Object { Write-Host $_ }
            if ($LastExitCode -ne 0) { throw "Error building example $exampleName" }
        } else {
            Write-Host "$exampleTarget is up to date"
        }
    }
}

function BuildStressTests
{
    $stressTestsDir = Join-Path -Path $rootDir -ChildPath "stress-tests"

    # Get all subdirectories in stress-tests folder
    $stressTests = Get-ChildItem -Path $stressTestsDir -Directory

    foreach ($test in $stressTests) {
        $testName = $test.Name
        $testTarget = "$testName.exe"
        $testFile = Join-Path -Path $buildDir -ChildPath $testTarget

        Write-Host "Building stress test: $testName"

        # Check if we need to rebuild
        $needsRebuild = $false
        if (-not (Test-Path $testFile)) {
            $needsRebuild = $true
        } else {
            $testTimestamp = (Get-ChildItem -Path $testFile).LastWriteTimeUtc

            # Check source files in both src and stress-test directories
            Get-ChildItem -Path $srcDir -Include "*.pony" -Recurse | ForEach-Object {
                if ($testTimestamp -lt $_.LastWriteTimeUtc) {
                    $needsRebuild = $true
                }
            }

            Get-ChildItem -Path $test.FullName -Include "*.pony" -Recurse | ForEach-Object {
                if ($testTimestamp -lt $_.LastWriteTimeUtc) {
                    $needsRebuild = $true
                }
            }
        }

        if ($needsRebuild) {
            Write-Host "corral fetch"
            $output = (corral fetch)
            $output | ForEach-Object { Write-Host $_ }
            if ($LastExitCode -ne 0) { throw "Error during corral fetch" }

            Write-Host "corral run -- ponyc $configFlag $ponyArgs --output `"$buildDir`" `"$($test.FullName)`""
            $output = (corral run -- ponyc $configFlag $ponyArgs --output "$buildDir" "$($test.FullName)")
            $output | ForEach-Object { Write-Host $_ }
            if ($LastExitCode -ne 0) { throw "Error building stress test $testName" }
        } else {
            Write-Host "$testTarget is up to date"
        }
    }
}

switch ($Command.ToLower())
{
  "libs"
  {
    if (-not (Test-Path $libsDir))
    {
      mkdir "$libsDir"
    }

    BuildLibs
  }

  "test"
  {
    $testFile = (BuildTest)[-1]
    Write-Host "$testFile --sequential"
    & "$testFile"
    if ($LastExitCode -ne 0) { throw "Error" }
    break
  }

  "examples"
  {
      if (-not (Test-Path $buildDir))
      {
          mkdir "$buildDir"
      }
      BuildExamples
      break
  }

  "stress-tests"
  {
      if (-not (Test-Path $buildDir))
      {
          mkdir "$buildDir"
      }
      BuildStressTests
      break
  }

  default
  {
      throw "Unknown command '$Command'; must be one of (libs, test, examples, stress-tests)."
  }
}
