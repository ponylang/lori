param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("nightlies", "releases")]
    [string]$RepoType
)

$baseUrl = "https://dl.cloudsmith.io/public/ponylang/$RepoType/raw/versions/latest"

# Download and extract ponyc
Invoke-WebRequest "$baseUrl/ponyc-x86-64-pc-windows-msvc.zip" -OutFile C:\ponyc.zip
Expand-Archive -Force -Path C:\ponyc.zip -DestinationPath C:\ponyc

# Download and extract corral
Invoke-WebRequest "$baseUrl/corral-x86-64-pc-windows-msvc.zip" -OutFile C:\corral.zip
Expand-Archive -Force -Path C:\corral.zip -DestinationPath C:\ponyc
