#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# MuseScore-CLA-applies
#
# MuseScore
# Music Composition & Notation
#
# Copyright (C) 2023 MuseScore BVBA and others
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

# For maximum AppImage compatibility, build on the oldest Linux distribution
# that still receives security updates from its manufacturer.

echo "Setup Linux build environment"
trap 'echo Setup failed; exit 1' ERR

df -h .

BUILD_TOOLS=$HOME/build_tools
ENV_FILE=$BUILD_TOOLS/environment.sh

mkdir -p $BUILD_TOOLS

# Let's remove the file with environment variables to recreate it
rm -f $ENV_FILE

echo "echo 'Setup MuseScore build environment'" >> $ENV_FILE

##########################################################################
# GET DEPENDENCIES
##########################################################################

# DISTRIBUTION PACKAGES

apt_packages=(
  cimg-dev
  curl
  desktop-file-utils
  file
  fuse
  git
  gpg
  libboost-dev
  libboost-filesystem-dev
  libboost-regex-dev
  libcairo2-dev
  libfuse-dev
  libtool
  libssl-dev
  patchelf
  pkg-config
  software-properties-common # installs `add-apt-repository`
  unzip
  wget
  xxd
  p7zip-full
  libasound2-dev 
  libfontconfig1-dev
  libfreetype6-dev
  libfreetype6
  libgl1-mesa-dev
  libjack-dev
  libnss3-dev
  libportmidi-dev
  libpulse-dev
  libsndfile1-dev
  zlib1g-dev
  make
  desktop-file-utils # installs `desktop-file-validate` for appimagetool
  zsync # installs `zsyncmake` for appimagetool
  )

# MuseScore compiles without these but won't run without them
apt_packages_runtime=(
  libcups2
  libdbus-1-3
  libegl1-mesa-dev
  libgles2-mesa-dev
  libodbc1
  libpq-dev
  libxcomposite-dev
  libxcursor-dev
  libxi-dev
  libxkbcommon-x11-0
  libxrandr2
  libxtst-dev
  libdrm-dev
  libxcb-icccm4
  libxcb-image0
  libxcb-keysyms1
  libxcb-randr0
  libxcb-render-util0
  libxcb-xinerama0
  )

apt_packages_ffmpeg=(
  ffmpeg
  libavcodec-dev 
  libavformat-dev 
  libswscale-dev
  )

apt-get update # no package lists in Docker image
DEBIAN_FRONTEND="noninteractive" TZ="Europe/London" apt-get install -y --no-install-recommends \
  "${apt_packages[@]}" \
  "${apt_packages_runtime[@]}" \
  "${apt_packages_ffmpeg[@]}"

# Add additional ppa (Qt 5.15.2 and CMake)
wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | gpg --dearmor - | tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null
echo 'deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ bionic main' | tee /etc/apt/sources.list.d/kitware.list >/dev/null
add-apt-repository --yes ppa:theofficialgman/opt-qt-5.15.2-bionic-arm
apt-get update

# add an exception for the "detected dubious ownership in repository" (only seen inside a Docker image)
git config --global --add safe.directory /MuseScore

##########################################################################
# GET TOOLS
##########################################################################

# COMPILER
apt_packages_compiler=(
  automake
  gcc
  g++
  )

apt-get install -y --no-install-recommends \
  "${apt_packages_compiler[@]}"

# CMAKE
# Get newer CMake (only used cached version if it is the same)
apt-get install -y --no-install-recommends cmake
cmake --version

# Ninja
apt-get install -y --no-install-recommends ninja-build
echo "ninja version"
ninja --version

##########################################################################
# GET QT
##########################################################################

# Get newer Qt (only used cached version if it is the same)

apt_packages_qt=(
  qt515base
  qt515declarative
  qt515quickcontrols
  qt515quickcontrols2
  qt515graphicaleffects
  qt515imageformats
  qt515networkauth-no-lgpl
  qt515remoteobjects
  qt515svg
  qt515tools
  qt515translations
  qt515x11extras
  qt515xmlpatterns
  )

apt-get install -y \
  "${apt_packages_qt[@]}"

qt_version="5152"
qt_dir="/opt/qt515"

##########################################################################
# Compile and install nlohmann-json
##########################################################################
export CFLAGS="-Wno-psabi"
export CXXFLAGS="-Wno-psabi"
CURRDIR=${PWD}
cd /

git clone https://github.com/nlohmann/json
cd /json/
git checkout --recurse-submodules v3.10.4
git submodule update --init --recursive
mkdir -p build
cd build
cmake -DJSON_BuildTests=OFF ..
cmake --build . -j $(nproc)
cmake --build . --target install
cd /

##########################################################################
# Compile and install linuxdeploy
##########################################################################

git clone https://github.com/linuxdeploy/linuxdeploy
cd /linuxdeploy/
git checkout --recurse-submodules 49f4f237762395c6a37
git submodule update --init --recursive
mkdir -p build
cd build
cmake -DBUILD_TESTING=OFF -DUSE_SYSTEM_BOOST=ON ..
cmake --build . -j $(nproc)
mkdir -p $BUILD_TOOLS/linuxdeploy
mv /linuxdeploy/build/bin/* $BUILD_TOOLS/linuxdeploy/
$BUILD_TOOLS/linuxdeploy/linuxdeploy --version
cd /

##########################################################################
# Compile and install linuxdeploy-plugin-qt
##########################################################################

git clone https://github.com/linuxdeploy/linuxdeploy-plugin-qt
cd /linuxdeploy-plugin-qt/
git checkout --recurse-submodules 59b6c1f90e21ba14
git submodule update --init --recursive
mkdir -p build
cd build
cmake -DBUILD_TESTING=OFF -DUSE_SYSTEM_BOOST=ON ..
cmake --build . -j $(nproc)
mv /linuxdeploy-plugin-qt/build/bin/linuxdeploy-plugin-qt $BUILD_TOOLS/linuxdeploy/linuxdeploy-plugin-qt
$BUILD_TOOLS/linuxdeploy/linuxdeploy --list-plugins
cd /

##########################################################################
# Compile and install linuxdeploy-plugin-appimage
##########################################################################

git clone https://github.com/linuxdeploy/linuxdeploy-plugin-appimage
cd /linuxdeploy-plugin-appimage/
git checkout --recurse-submodules 779bd58443e8cc
git submodule update --init --recursive
mkdir -p build
cd build
cmake -DBUILD_TESTING=OFF ..
cmake --build . -j $(nproc)
mv /linuxdeploy-plugin-appimage/build/src/linuxdeploy-plugin-appimage $BUILD_TOOLS/linuxdeploy/linuxdeploy-plugin-appimage
cd /
$BUILD_TOOLS/linuxdeploy/linuxdeploy --list-plugins

##########################################################################
# Compile and install AppImageKit
##########################################################################

git clone https://github.com/AppImage/AppImageKit
cd /AppImageKit/
git checkout --recurse-submodules 13
git submodule update --init --recursive
mkdir -p build
cd build
cmake -DBUILD_TESTING=OFF ..
cmake --build . -j $(nproc)
cmake --build . --target install
mkdir -p $BUILD_TOOLS/appimagetool
cd /
appimagetool --version

cd ${CURRDIR}

##########################################################################
# appimageupdatetool empty (TODO)
##########################################################################
mkdir -p $BUILD_TOOLS/appimageupdatetool


# delete build folders
rm -rf /linuxdeploy*
rm -rf /AppImageKit

echo export PATH="${qt_dir}/bin:\${PATH}" >> ${ENV_FILE}
echo export LD_LIBRARY_PATH="${qt_dir}/lib:\${LD_LIBRARY_PATH}" >> ${ENV_FILE}
echo export QT_PATH="${qt_dir}" >> ${ENV_FILE}
echo export QT_PLUGIN_PATH="${qt_dir}/plugins" >> ${ENV_FILE}
echo export QML2_IMPORT_PATH="${qt_dir}/qml" >> ${ENV_FILE}
echo export CFLAGS="-Wno-psabi" >> ${ENV_FILE}
echo export CXXFLAGS="-Wno-psabi" >> ${ENV_FILE}

##########################################################################
# POST INSTALL
##########################################################################

chmod +x "$ENV_FILE"

# # tidy up (reduce size of Docker image)
# apt-get clean autoclean
# apt-get autoremove --purge -y
# rm -rf /tmp/* /var/{cache,log,backups}/* /var/lib/apt/*

df -h .
echo "Setup script done"