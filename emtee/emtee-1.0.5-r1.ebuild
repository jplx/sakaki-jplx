# Copyright (c) 2019 sakaki <sakaki@deciban.com>
# License: GPL v3+
# NO WARRANTY

EAPI=8

KEYWORDS="~amd64 ~arm ~arm64 ~ppc"

DESCRIPTION="A faster-startup emerge -DuU --with-bdeps=y --keep-going @world"
BASE_SERVER_URI="http://localhost/tarballs"
# BASE_SERVER_URI="https://github.com/sakaki-"
HOMEPAGE="http://localhost/tarballs"
# HOMEPAGE="https://github.com/sakaki-"
SRC_URI="${BASE_SERVER_URI}/${PN}-v${PV}.tar.gz"
# SRC_URI="${BASE_SERVER_URI}/${PN}/releases/download/v${PV}/${PN}-v${PV}.tar.gz"

LICENSE="GPL-3+"
SLOT="0"

RESTRICT="mirror"

RDEPEND="${DEPEND}
	>=app-shells/bash-4.4"

src_install() {
	dobin "${PN}"
	doman "${PN}.1"
}
