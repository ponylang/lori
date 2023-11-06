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

$ponyArgs = "--path $rootDir"

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

switch ($Command.ToLower())
{
  "test"
  {
    $testFile = (BuildTest)[-1]
    Write-Host "$testFile --sequential"
    & "$testFile"
    if ($LastExitCode -ne 0) { throw "Error" }
    break
  }
}
