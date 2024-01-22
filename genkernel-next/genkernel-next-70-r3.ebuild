# Copyright 1999-2019 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
# Edited by Iade Gesso, PhD in 14th July 2020
# Updated by jplx on Jan 29, 2024. Changes:
#   Updated to busybox-1.36.1 (current and stable)
#   Verify that libm.a an d librt.a (from glibc) and lincrypt.a (from libxcrypt) are available
#   They are necessary to link busybox before packaging it within busybox-1.36.1-x86_64.tar.bz2
#   in the cache (/var/cache/genkernel) directory.
#   Converted to EAPI8. Added sys-libs/libxcrypt dependency for libcrypt.a static lib.

EAPI=8

LIBM="" ; LIBRT=""
if [[ (-s "/usr/lib/libm.a") || (-s "/usr/lib64/libm.a") ]] ; then  LIBM="libm_ok"; fi
if [[ (-s "/usr/lib/librt.a") || (-s "/usr/lib64/librt.a") ]] ; then LIBRT="librt_ok" ; fi

# To use local files, run apache and: "ln -s <path_to_tarballs> tarballs" in /var/www/localhost/htdocs
SRC_URI="http://localhost/tarballs/${P}.tar.gz
	http://localhost/tarballs/busybox-1.36.1.tar.bz2"
# SRC_URI="https://github.com/Sabayon/genkernel-next/archive/v${PV}.tar.gz -> ${P}.tar.gz
#	https://www.busybox.net/downloads/busybox-1.32.0.tar.bz2"

KEYWORDS="~alpha amd64 ~arm ~hppa ~ia64 ~ppc ~ppc64 x86"
inherit bash-completion-r1

DESCRIPTION="Gentoo automatic kernel building scripts, reloaded"
HOMEPAGE="http://localhost/tarballs"
# HOMEPAGE="https://github.com/Sabayon/genkernel-next/"

LICENSE="GPL-2"
SLOT="0"

IUSE="cryptsetup dmraid gpg iscsi mdadm plymouth selinux"
DOCS=( AUTHORS )

DEPEND="app-text/asciidoc
	sys-fs/e2fsprogs
	selinux? ( sys-libs/libselinux )
	sys-libs/libxcrypt[static-libs]"
RDEPEND="${DEPEND}
	!sys-kernel/genkernel
	cryptsetup? ( sys-fs/cryptsetup )
	dmraid? ( >=sys-fs/dmraid-1.0.0_rc16 )
	gpg? ( app-crypt/gnupg )
	iscsi? ( sys-block/open-iscsi )
	mdadm? ( sys-fs/mdadm )
	plymouth? ( sys-boot/plymouth )
	app-portage/portage-utils
	app-arch/cpio
	>=app-misc/pax-utils-0.6
	sys-apps/util-linux
	sys-block/thin-provisioning-tools
	sys-fs/lvm2"

PATCHES=(
	"${FILESDIR}/genkernel-next-70_old_busybox.patch"
)

src_prepare() {
	default
	sed -i "/^GK_V=/ s:GK_V=.*:GK_V=${PV}:g" "${S}/genkernel" || \
		die "Could not setup release"

	# Get the real location of 'DISTDIR'
	actual_distdir=$(dirname `readlink "${DISTDIR}"/${P}.tar.gz`)

	# Replace the busybox path from the patch with the real 'DISTDIR' path
	# that is set in '/etc/portage/make.conf'
	sed -i 's:'"/usr/portage/distfiles"':'"${actual_distdir}"':g' "${S}/genkernel.conf" || \
		die "Failed to update busybox location"

		if [ $LIBM != "libm_ok" ] ; then
		echo "Warning: libm.a not found. Won't be able to compile busybox. May use cached tar file if available." ;
		fi
		if [ $LIBRT != "librt_ok" ] ; then
		echo "Warning: librt.a not found. Won't be able to compile busybox. May use cached tar file if available." ;
		fi
}

src_install() {
	default

	doman "${S}"/genkernel.8

	newbashcomp "${S}"/genkernel.bash genkernel
}
