#!/bin/bash
set -e

cd /yocto

# Configure Git globally
echo "Configuring Git..."
git config --global user.email "yocto.builder@example.com"
git config --global user.name "Yocto Builder"

# Initialize repo if not already done
if [ ! -d .repo ]; then
    echo "Initializing repo..."
    git config --global color.ui false
    repo init -u https://github.com/nxp-imx/imx-manifest.git -b imx-linux-scarthgap -m imx-6.6.23-2.0.0.xml
    repo sync
fi

# Clone meta-mender layer if not present
if [ ! -d sources/meta-mender ]; then
    echo "Cloning meta-librescoot layer..."
    git clone -b scarthgap https://github.com/mendersoftware/meta-mender sources/meta-mender
else
    cd sources/meta-mender
    git checkout scarthgap
    git pull
    cd /yocto
fi

# Clone meta-librescoot layer if not present
if [ ! -d sources/meta-librescoot ]; then
    echo "Cloning meta-librescoot layer..."
    git clone -b scarthgap https://github.com/librescoot/meta-librescoot sources/meta-librescoot
else
    cd sources/meta-librescoot
    git checkout scarthgap
    git pull
    cd /yocto
fi

echo "Setting up build environment..."
DISTRO=librescoot-mdb source ./imx-setup-release.sh -b build

if ! grep -q "meta-mender-core" /yocto/build/conf/bblayers.conf && \
   ! grep -q "meta-mender-demo" /yocto/build/conf/bblayers.conf && \
   ! grep -q "meta-librescoot" /yocto/build/conf/bblayers.conf; then
    echo "Adding additional layers to bblayers.conf..."
    cat >> /yocto/build/conf/bblayers.conf << 'EOL'

BBLAYERS += " \
  ${BSPDIR}/sources/meta-mender/meta-mender-core \
  ${BSPDIR}/sources/meta-mender/meta-mender-demo \
  ${BSPDIR}/sources/meta-librescoot \
"
EOL
fi

cat > /yocto/build/conf/bblayers.conf << 'EOL'
LCONF_VERSION = "7"

BBPATH = "${TOPDIR}"
BSPDIR := "${@os.path.abspath(os.path.dirname(d.getVar('FILE', True)) + '/../..')}"

BBFILES ?= ""
BBLAYERS = " \
  ${BSPDIR}/sources/poky/meta \
  ${BSPDIR}/sources/poky/meta-poky \
  ${BSPDIR}/sources/meta-openembedded/meta-oe \
  ${BSPDIR}/sources/meta-openembedded/meta-multimedia \
  ${BSPDIR}/sources/meta-openembedded/meta-python \
  ${BSPDIR}/sources/meta-freescale \
  ${BSPDIR}/sources/meta-freescale-3rdparty \
  ${BSPDIR}/sources/meta-freescale-distro \
  ${BSPDIR}/sources/meta-mender/meta-mender-core \
  ${BSPDIR}/sources/meta-mender/meta-mender-demo \
  ${BSPDIR}/sources/meta-librescoot \
  "
EOL

echo "Creating local.conf..."
cat > /yocto/build/conf/local.conf << 'EOL'
MACHINE ??= 'librescoot-mdb'
DISTRO ?= 'librescoot-mdb'
MENDER_ARTIFACT_NAME = "release-1"
INHERIT += "mender-full"
ARTIFACTIMG_FSTYPE = "ext4"
INIT_MANAGER = "systemd"
DISTRO_VERSION = "0.0.1"
OLDEST_KERNEL = "5.4.24"
PREFERRED_PROVIDER_u-boot = "u-boot-imx"
PREFERRED_PROVIDER_virtual/bootloader = "u-boot-imx"
PREFERRED_PROVIDER_virtual/kernel="linux-imx"
PREFERRED_VERSION_linux_imx = "5.4.24"
PREFERRED_VERSION_u-boot-imx = "2017.03"
EXTRA_IMAGE_FEATURES ?= "debug-tweaks"
USER_CLASSES ?= "buildstats"
PATCHRESOLVE = "noop"
BB_DISKMON_DIRS ??= "\
    STOPTASKS,${TMPDIR},1G,100K \
    STOPTASKS,${DL_DIR},1G,100K \
    STOPTASKS,${SSTATE_DIR},1G,100K \
    STOPTASKS,/tmp,100M,100K \
    HALT,${TMPDIR},100M,1K \
    HALT,${DL_DIR},100M,1K \
    HALT,${SSTATE_DIR},100M,1K \
    HALT,/tmp,10M,1K"
PACKAGECONFIG:append:pn-qemu-system-native = " sdl"
CONF_VERSION = "2"
DL_DIR ?= "${BSPDIR}/downloads/"
ACCEPT_FSL_EULA = "1"
HOSTTOOLS += "x86_64-linux-gnu-gcc git-lfs python"
EXTRA_IMAGE_FEATURES = "debug-tweaks"
EOL

echo "Starting build process..."

bitbake librescoot-mdb-image --continue

