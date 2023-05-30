#!/bin/bash

function MakeDirectory {
  for dirname in "$@"
  do
    if [ ! -d "$dirname" ]
    then
      mkdir -p "$dirname"
    fi
  done  
}

SOURCE="${BASH_SOURCE[0]}"

while [ -h "$SOURCE" ]; do
  # resolve $SOURCE until the file is no longer a symlink
  ScriptRoot="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
  [[ $SOURCE != /* ]] && SOURCE="$ScriptRoot/$SOURCE"
done

ScriptRoot="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

ScriptName=$(basename -s '.sh' "$SOURCE")

help=false
architecture=''

while [[ $# -gt 0 ]]; do
  lower="$(echo "$1" | awk '{print tolower($0)}')"
  case $lower in
    --help)
      help=true
      shift 1
      ;;
    --architecture)
      architecture=$2
      shift 2
      ;;
    *)
  esac
done

function Help {
  echo "  --architecture <value>    Specifies the architecture for the package (e.g. x64)"
  echo "  --help                    Print help and exit"
}

if $help; then
  Help
  exit 0
fi

if [[ -z "$architecture" ]]; then
  echo "$ScriptName: architecture missing."
  Help
  exit 1
fi

RepoRoot="$ScriptRoot/.."

SourceRoot="$RepoRoot/sources"

ArtifactsRoot="$RepoRoot/artifacts"
BuildRoot="$ArtifactsRoot/build"
InstallRoot="$ArtifactsRoot/install"
PackageRoot="$ArtifactsRoot/pkg"

MakeDirectory "$ArtifactsRoot" "$BuildRoot" "$InstallRoot" "$PackageRoot"

Runtime="linux-$architecture"

echo "$ScriptName: Installing dotnet ..."
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_MULTILEVEL_LOOKUP=0
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1

DotNetInstallScript="$ArtifactsRoot/dotnet-install.sh"
wget -O "$DotNetInstallScript" "https://dot.net/v1/dotnet-install.sh"

DotNetInstallDirectory="$ArtifactsRoot/dotnet"
MakeDirectory "$DotNetInstallDirectory"

bash "$DotNetInstallScript" --channel 6.0 --version latest --install-dir "$DotNetInstallDirectory"
LAST_EXITCODE=$?
if [ $LAST_EXITCODE != 0 ]; then
  echo "$ScriptName: Failed to install dotnet 6.0."
  exit "$LAST_EXITCODE"
fi

PATH="$DotNetInstallDirectory:$PATH:"

echo "$ScriptName: Restoring dotnet tools ..."
dotnet tool restore
LAST_EXITCODE=$?
if [ $LAST_EXITCODE != 0 ]; then
  echo "$ScriptName: Failed to restore dotnet tools."
  exit "$LAST_EXITCODE"
fi

echo "$ScriptName: Calculating SDL2_ttf package version..."
PackageVersion=$(dotnet gitversion /output json /showvariable NuGetVersion)
LAST_EXITCODE=$?
if [ $LAST_EXITCODE != 0 ]; then
  echo "$ScriptName: Failed to calculate SDL2_ttf package version."
  exit "$LAST_EXITCODE"
fi

echo "$ScriptName: Updating package list..."
sudo apt-get update
LAST_EXITCODE=$?
if [ $LAST_EXITCODE != 0 ]; then
  echo "$ScriptName: Failed to update package list."
  exit "$LAST_EXITCODE"
fi

echo "$ScriptName: Installing packages needed to build SDL2_ttf..."
sudo apt-get -y install \
  autoconf \
  automake \
  cmake \
  file \
  fonts-dejavu-core \
  libtool \
  ninja-build \
  pkg-config \
  mono-devel
LAST_EXITCODE=$?
if [ $LAST_EXITCODE != 0 ]; then
  echo "$ScriptName: Failed to install packages needed to build SDL2_ttf."
  exit "$LAST_EXITCODE"
fi

if [ ! command -v nuget &> /dev/null ]; then
  NuGetUrl='https://dist.nuget.org/win-x86-commandline/latest/nuget.exe'
  NuGetInstallPath="$ArtifactsRoot/nuget.exe"
  echo "$ScriptName: Downloading latest stable 'nuget.exe' from $NuGetUrl to $NuGetInstallPath..."
  sudo curl -o $NuGetInstallPath $NuGetUrl
  LAST_EXITCODE=$?
  if [ $LAST_EXITCODE != 0 ]; then
    echo "$ScriptName: Failed to download 'nuget.exe' from $NuGetUrl to $NuGetInstallPath."
    exit "$LAST_EXITCODE"
  fi

  echo "$ScriptName: Creating alias for 'nuget' installed in $NuGetInstallPath..."
  shopt -s expand_aliases
  alias nuget="mono $NuGetInstallPath"
fi

SDL2PackageSource="https://pkgs.dev.azure.com/ronaldvanmanen/SDL2Sharp/_packaging/SDL2Sharp/nuget/v3/index.json"

if [ -n "${NUGET_AUTH_TOKEN}" ]; then
  echo "$ScriptName: Settings API key for package source $SDL2PackageSource..."
  nuget setapikey "${NUGET_AUTH_TOKEN}" -Source "$SDL2PackageSource"
  if [ $LAST_EXITCODE != 0 ]; then
    echo "$ScriptName: Failed to set API key for package source $SDL2PackageSource."
    exit "$LAST_EXITCODE"
  fi
fi

SDL2PackageName="SDL2.devel.$Runtime"

echo "$ScriptName: Installing SDL2 development package in $InstallRoot..."
nuget install "$SDL2PackageName" \
  -DirectDownload \
  -ExcludeVersion \
  -NoCache \
  -OutputDirectory "$InstallRoot" \
  -PreRelease \
  -Source "$SDL2PackageSource"
if [ $LAST_EXITCODE != 0 ]; then
  echo "$ScriptName: Failed to install SDL2 development package $InstallRoot."
  exit "$LAST_EXITCODE"
fi

export SDL2_DIR="$InstallRoot/$SDL2PackageName"

echo "$ScriptName: Calculating SDL2_ttf package version..."
PackageVersion=$(dotnet gitversion /output json /showvariable NuGetVersion)
if [ $LAST_EXITCODE != 0 ]; then
  echo "$ScriptName: Failed calculate SDL2_ttf package version."
  exit "$LAST_EXITCODE"
fi

SourceDir="$SourceRoot/SDL_ttf"
BuildDir="$BuildRoot/SDL2_ttf/$Runtime"
InstallDir="$InstallRoot/SDL2_ttf/$Runtime"

echo "$ScriptName: Setting up build for SDL2_ttf in $BuildDir..."
cmake -S "$SourceDir" -B "$BuildDir" -G Ninja \
  -DBUILD_SHARED_LIBS=ON \
  -DSDL2TTF_HARFBUZZ=ON \
  -DSDL2TTF_SAMPLES=OFF \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DSDL2TTF_VENDORED=ON \
  -DCMAKE_BUILD_TYPE=Release
LAST_EXITCODE=$?
if [ $LAST_EXITCODE != 0 ]; then
  echo "$ScriptName: Failed to setup build for SDL2_ttf in $BuildDir."
  exit "$LAST_EXITCODE"
fi

echo "$ScriptName: Building SDL2_ttf in $BuildDir..."
cmake --build "$BuildDir" --config Release
LAST_EXITCODE=$?
if [ $LAST_EXITCODE != 0 ]; then
  echo "$ScriptName: Failed to build SDL2_ttf in $BuildDir."
  exit "$LAST_EXITCODE"
fi

echo "$ScriptName: Installing SDL2_ttf to $InstallDir..."
cmake --install "$BuildDir" --prefix "$InstallDir"
LAST_EXITCODE=$?
if [ $LAST_EXITCODE != 0 ]; then
  echo "$ScriptName: Failed to install SDL2_ttf version in $InstallDir."
  exit "$LAST_EXITCODE"
fi

NuGetVersion=$(nuget ? | grep -oP 'NuGet Version: \K.+')

RuntimePackageName="SDL2_ttf.runtime.$Runtime"
RuntimePackageBuildDir="$BuildRoot/$RuntimePackageName.nupkg"
DevelPackageName="SDL2_ttf.devel.$Runtime"
DevelPackageBuildDir="$BuildRoot/$DevelPackageName.nupkg"

echo "$ScriptName: Producing SDL2_ttf runtime package folder structure in $RuntimePackageBuildDir..."
MakeDirectory "$RuntimePackageBuildDir"
cp -dR "$RepoRoot/packages/$RuntimePackageName/." "$RuntimePackageBuildDir"
cp -d "$SourceDir/LICENSE.txt" "$RuntimePackageBuildDir"
cp -d "$SourceDir/README.txt" "$RuntimePackageBuildDir"
mkdir -p "$RuntimePackageBuildDir/runtimes/$Runtime/native" && cp -d "$InstallDir/lib/libSDL2"*"so"* $_

echo "$ScriptName: Building SDL2_ttf runtime package (using NuGet $NuGetVersion)..."
nuget pack "$RuntimePackageBuildDir/$RuntimePackageName.nuspec" -Properties "version=$PackageVersion" -OutputDirectory $PackageRoot
LAST_EXITCODE=$?
if [ $LAST_EXITCODE != 0 ]; then
  echo "$ScriptName: Failed to build SDL2_ttf runtime package."
  exit "$LAST_EXITCODE"
fi

echo "$ScriptName: Producing SDL2_ttf development package folder structure in $DevelPackageBuildDir..."
MakeDirectory "$DevelPackageBuildDir"
cp -dR "$RepoRoot/packages/$DevelPackageName/." "$DevelPackageBuildDir"
cp -dR "$InstallDir/." "$DevelPackageBuildDir"

echo "$ScriptName: Building SDL2_ttf development package (using NuGet $NuGetVersion)..."
nuget pack "$DevelPackageBuildDir/$DevelPackageName.nuspec" -Properties "version=$PackageVersion" -Properties NoWarn=NU5103,NU5128 -OutputDirectory $PackageRoot
LAST_EXITCODE=$?
if [ $LAST_EXITCODE != 0 ]; then
  echo "$ScriptName: Failed to build SDL2_ttf development package."
  exit "$LAST_EXITCODE"
fi
