SUMMARY = "Library to manage multi-chip sync on FMCOMMS5 platforms with multiple AD9361 devices"
SECTION = "libs"
LICENSE = "LGPLv2.1+"
LIC_FILES_CHKSUM = "file://LICENSE;md5=40d2542b8c43a3ec2b7f5da31a697b88"
BRANCH = "2022_R2"

# If we are in an offline build we cannot use AUTOREV since it would require internet!
SRCREV = "${@ "2bf936d6afcb3e6385642b6a769fd74f8ab9b62d" if bb.utils.to_boolean(d.getVar('BB_NO_NETWORK')) else d.getVar('AUTOREV')}"
PV:append = "+git${SRCPV}"

SRC_URI = "git://github.com/analogdevicesinc/libad9361-iio.git;protocol=https;branch=${BRANCH}"

S = "${WORKDIR}/git"

DEPENDS = "libiio"

inherit cmake pkgconfig
