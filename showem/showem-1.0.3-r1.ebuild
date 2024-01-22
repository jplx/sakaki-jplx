# ebuild for showem (a simple emerge progress viewer)
# Copyright (c) 2015 sakaki <sakaki@deciban.com>
# License: GPL v2
# NO WARRANTY

EAPI=8

DESCRIPTION="View output of a parallel emerge from a separate terminal"
# BASE_SERVER_URI="https://github.com/sakaki-"
HOMEPAGE="http://localhost/tarballs"
# HOMEPAGE="https://github.com/sakaki-/${PN}"
SRC_URI="http://localhost/tarballs/${P}.tar.gz"
# SRC_URI="${BASE_SERVER_URI}/${PN}/releases/download/${PV}/${P}.tar.gz"
LICENSE="GPL-3+"
SLOT="0"
KEYWORDS="amd64 ~arm ~ppc ~x86"

RESTRICT="mirror"

RDEPEND="${DEPEND}
	>=sys-libs/ncurses-5.9-r2"

src_install() {
	dobin "${PN}"
	doman "${PN}.1"
}
