.nh
.TH EMTEE 1 "Version 1.0.5: Apr 2020"
.SH NAME
.PP
emtee \- a faster\-startup emerge \-DuU \-\-with\-bdeps=y \-\-keep\-going @world (et al.)

.SH SYNOPSIS
.PP
\fB\fCemtee\fR [\fB\fC\-a\fR] [\fB\fC\-A\fR] [\fB\fC\-b\fR] [\fB\fC\-c\fR] [\fB\fC\-C\fR] [\fB\fC\-d\fR] [\fB\fC\-e\fR args] [\fB\fC\-E\fR args] [\fB\fC\-f\fR NUM]
[\fB\fC\-h\fR] [\fB\fC\-p\fR] [\fB\fC\-N\fR] [\fB\fC\-s\fR set] [\fB\fC\-S\fR] [\fB\fC\-v\fR] [\fB\fC\-V\fR] [\fB\fC\-z\fR]

.SH DESCRIPTION
.PP
\fB\fCemtee\fR is a simple script to speed up \fI@world\fP updates on Gentoo
Linux systems, by significantly decreasing the time taken for the
\fB\fCemerge\fR(1)'s initial dependency resolution stage (often the dominant
component for SBCs and other resource\-challenged systems, if a binhost
is deployed).

.PP
It may be used (with appropriate options) in place of:

.RS
.IP \(bu 2
\fB\fCemerge \-\-with\-bdeps=y \-\-deep \-\-update \-\-changed\-use \-\-keep\-going @world\fR,
.IP \(bu 2
\fB\fCemerge \-\-with\-bdeps=y \-\-deep \-\-update \-\-newuse \-\-ask \-\-verbose \-\-keep\-going @world\fR;

.RE

.PP
and similar invocations.

.PP
For example, you could achieve the same effect as the above commands
with:

.RS
.IP \(bu 2
\fB\fCemtee\fR, and
.IP \(bu 2
\fB\fCemtee \-\-newuse \-\-ask \-\-verbose\fR (or, equivalently, \fB\fCemtee \-\-Nav\fR)

.RE

.PP
respectively.

.PP
Generally speaking, \fB\fCemtee\fR will take materially less time
to get the first actual build underway than its counterpart \fB\fCemerge
\-\-update\fR, while still targeting an identical build list, permitting
job parallelism, and triggering any required slot\-driven rebuilds, and
block\-driven unmerges.

.SH OPTIONS
.PP
\fB\fC\-a\fR, \fB\fC\-\-ask\fR
  Turns on interactive mode for the real \fB\fCemerge\fR step (i.e.
  during phase 4, as described in \fIALGORITHM\fP, below).

.PP
\fB\fC\-A\fR, \fB\fC\-\-alert\fR
  Uses terminal bell notification for all interactive prompts in
  the real \fB\fCemerge\fR step. Selecting this turns on \fB\fC\-a\fR by default.

.PP
\fB\fC\-b\fR, \fB\fC\-\-with\-bdeps=y|n\fR
  Specifies whether or not to pull\-in build time dependencies. NB,
  defaults to \fB\fCy\fR if unspecified, in contrast to \fB\fCemerge\fR\&'s default
  behaviour.

.PP
\fB\fC\-c\fR, \fB\fC\-\-crosscheck\fR
  Checks the final build list against the result obtained by running a
  conventional \fB\fC\-\-deep\fR \fB\fCemerge\fR, and prints a \fB\fCdiff\fR(1) of the package
  list; also provides a comparitive timing, for benchmarking purposes.
  NB: does not check the \fIordering\fP of the packages in the two lists.

.PP
\fB\fC\-C\fR, \fB\fC\-\-strict\-crosscheck\fR
  As for \fB\fC\-c\fR, but exits with an error if the \fB\fCemtee\fR and conventional
  \fB\fC\-\-deep \-\-update\fR \fB\fCemerge\fR lists do not match.

.PP
\fB\fC\-d\fR, \fB\fC\-\-debug\fR
  Prints some additional debugging information during the process.

.PP
\fB\fC\-e\fR, \fB\fC\-\-emptytree\-emerge\-args=\fR\fIADDITIONAL\_ARGS\fP
  Passes the specified arguments to the initial (\fB\fC\-\-pretend
  \-\-emptytree\fR) \fB\fCemerge\fR step used to caclulate the (unfiltered) build
  list. Note that these arguments are \fInot\fP passed to the real
  \fB\fCemerge\fR step; you need to use \fB\fC\-E\fR for that.

.PP
\fB\fC\-E\fR, \fB\fC\-\-emerge\-args=\fR\fIADDITIONAL\_ARGS\fP
  Passes the specified arguments to the real \fB\fCemerge\fR step. Note that
  these arguments are \fInot\fP passed to the preliminary \fB\fCemerge\fR step; you
  need to use \fB\fC\-e\fR for that.
.br

.br
  Note also that you can achieve the effect of the \fB\fC\-a\fR \fB\fC\-A\fR, \fB\fC\-p\fR and \fB\fC\-v\fR
  options by setting them directly via \fB\fC\-E\fR, if you prefer. They are
  provided as syntactic sugar, for convenience.

.PP
\fB\fC\-f\fR, \fB\fC\-\-full\-build\-fallback\-threshold=\fR\fINUM\fP
  If the number of packages passed to the real emerge step
  is >= \fINUM\fP, then a dry\-run will first be performed, to check that
  the proposed set can be emerged consistently, and iff that
  fails, then a full \fB\fCemerge \-\-emptytree @world\fR
  run will be initiated, followed by (if successful)
  \fB\fCemerge \-\-depclean\fR\&.
.br

.br
  This functionality is provided as a fallback, to ensure that
  fundamental changes that trigger many dependencies can be built
  consistently. The default is \fBnot\fP to do this dry\-run test.

.PP
\fB\fC\-h\fR, \fB\fC\-\-help\fR
  Prints a short help message, and exits.

.PP
\fB\fC\-p\fR, \fB\fC\-\-pretend\fR
  Passes the \fB\fC\-\-pretend\fR option to the real \fB\fCemerge\fR step, resulting in
  a 'dry run' (nothing will actually be updated).

.PP
\fB\fC\-N\fR, \fB\fC\-\-newuse\fR
  Rebuild packages which have had any USE flag changes, even if those
  changes don't affect flags the user has enabled (the more
  conservative \fB\fC\-\-changed\-use\fR behaviour is the default).

.PP
\fB\fC\-s\fR, \fB\fC\-\-set\fR=\fISET\fP
  Uses the specified set (e.g. \fI@system\fP) in preference to the default
  \fI@world\fP\&. You can pass regular package names here as well, but note
  that using a regular \fB\fCemerge\fR is likely to be faster for such targets.

.PP
\fB\fC\-S\fR, \fB\fC\-\-force\-slot\-rebuilds\fR
  Checks for any slot\-change\-driven rebuilds, and adds these (reverse)
  dependencies to the build list; this option should not generally be
  required, as the real \fB\fCemerge\fR step will trigger such rebuilds
  automatically anyway.

.PP
\fB\fC\-v\fR, \fB\fC\-\-verbose\fR
  Passes the \fB\fC\-\-verbose\fR option to the real \fB\fCemerge\fR step

.PP
\fB\fC\-V\-\fR, \fB\fC\-\-version\fR
  Prints \fB\fCemtee\fR\&'s version number, and exits.

.PP
\fB\fC\-z\fR, \fB\fC\-\-keep\-going=y|n\fR
  Specifies whether or not to try to build as much as possible during
  the main \fB\fCemerge\fR phase, restarting should errors occur. NB,
  defaults to \fB\fCy\fR if unspecified, in contrast to \fB\fCemerge\fR\&'s default
  behaviour.

.SH ALGORITHM
.PP
The \fB\fCemtee\fR process runs as follows:

.RS
.IP "  1." 5
Derive a full, versioned build list for the \fI@world\fP set and its
entire deep dependency tree, via \fB\fCemerge \-\-with\-bdeps=y \-\-pretend
\-\-emptytree \-\-verbose [opts]\fR \fI@world\fP, which Portage can do
relatively quickly. The resulting list, as it is derived as if \fIno\fP
packages were installed to begin with, will automatically contain
all necessary packages at their 'best' versions (which may entail
upgrades, downgrades, new slots etc.  wrt the currently installed
set).
.IP "  2." 5
Filter this list, by marking each fully\-qualified atom
(\fIFQA\fP=\fI$CATEGORY/$PF\fP) within it for building (or not). Begin
with all \fIFQAs\fP unmarked.
.br

.br

.RS
.IP \(bu 2
Then (pass 1), mark anything which isn't a block, uninstall or reinstall for build;
.IP \(bu 2
Then (pass 2), check each reinstall, to see if its \fIactive\fP
USE flag set is changing (default behaviour), or if \fIany\fP of
its USE flags are changing (\fB\fC\-N\fR/\fB\fC\-\-newuse\fR behaviour), and if
so, mark that package for build (fortunately, the \fB\fC\-\-verbose\fR
output from step 1 contains the necessary USE flag delta
information to allow us to easily work this out).
.IP \(bu 2
Then (pass 3), if \fB\fC\-S\fR/\fB\fC\-\-force\-slot\-rebuilds\fR is in use, for
each marked package on the list whose slot or subslot is
changing (also inferable from the phase 1 output), search
\fI/var/db/pkg/FQA/RDEPENDS\fP (and \fIDEPENDS\fP, if
\fB\fC\-\-with\-bdeps=y\fR, the default, is active) for any matching slot
dependencies.  Mark each such located (reverse) dependency that
is \fIalso\fP on the original \fB\fC\-\-emptytree\fR list (and not a block
or uninstall) for build.
.br

.br
Note that pass 3 is skipped by default, since the phase 4 emerge
(aka the real \fB\fCemerge\fR) will automatically trigger any
necessary slot rebuilds anyway, so it is redundant except for in a
few esoteric situations.

.RE

.IP "  3." 5
Iff \fB\fC\-c\fR/\fB\fC\-\-crosscheck\fR (or \fB\fC\-C\fR/\fB\fC\-\-strict\-crosscheck\fR) passed,
compare the \fIFQA\fP build list produced by invoking \fB\fCemerge \-\-bdeps=y
\-\-pretend \-\-deep \-\-update [\-\-changed\-use|\-\-newuse] [opts]\fR \fI@world\fP
(adapted for specified options appropriately), with that produced
by invoking \fB\fCemerge \-\-oneshot \-\-pretend [opts]\fR
\fIfiltered\-FQA\-build\-list\-from\-phase\-2\fP\&. If any differences are
found, report them (and, additionally, stop the build in such a
case, if \fB\fC\-S\fR/\fB\fC\-\-strict\-crosscheck\fR specified). Also report
a series of comparative (total elapsed wall\-clock) timings for both
alternatives, for benchmarking purposes.
.br

.br
Note: crosschecking should \fIonly\fP be used for reassurance or
benchmarking, as it will, of necessity, be slower than the baseline
in total time cost (since the check involves running both that
\fIand\fP the newer, \fB\fC\-\-emptytree\fR\-based approach)! So, if your goal is
to improve emerge times, do \fInot\fP pass \fB\fC\-s\fR/\fB\fC\-S\fR\&.
.IP "  4." 5
Invoke the real \fB\fCemerge\fR, as: \fB\fCemerge \-\-oneshot [opts]\fR
\fIfiltered\-FQA\-build\-list\-from\-phase\-2\fP\&.
.br

.br
Note that additional arguments may be passed to this invocation, both
explicitly (via \fB\fC\-E\fR/\fB\fC\-\-emerge\-args\fR) and implicitly, via one of
the impacting options (\fB\fC\-v\fR/\fB\fC\-\-verbose\fR, \fB\fC\-a\fR/\fB\fC\-\-ask\fR,
\fB\fC\-A\fR/\fB\fC\-\-alert\fR, \fB\fC\-p\fR/\fB\fC\-\-pretend\fR or \fB\fC\-z\fR/\fB\fC\-\-keep\-going\fR).

.br
Note also that if \fB\fC\-f\fR/\fB\fC\-\-full\-build\-fallback\-threshold\fR is used, and
the number of packages passed to this phase is >= \fINUM\fP, then
a dry\-run  will first be performed, to check that the proposed
set can be emerged consistently, and iff that  fails,
then  a  full \fB\fCemerge \-\-emptytree @world\fR run will be initiated,
followed by (if successful)  \fB\fCemerge  \-\-depclean\fR\&.  The
default is not to do any such dry run.

.RE

.SH BASIS
.PP
Why is this approach faster? Well, the main claims behind \fB\fCemtee\fR are:

.RS
.IP "  1." 5
An \fB\fC\-\-emptytree\fR \fB\fCemerge\fR of \fI@world\fP yields the same versioned package list
that a \fB\fC\-\-deep \-\-update\fR \fB\fCemerge\fR would arrive at.
.br

.br
That is, for \fB\fCemtee\fR to work, it must be true that for a consistent,
depcleaned Gentoo system with a recently updated set of ebuild
repositories, if \fB\fCemerge \-\-with\-bdeps=y \-\-emptytree\fR \fI@world\fP is
invoked and runs successfully to conclusion, then an immediately
following \fB\fCemerge \-\-with\-bdeps=y \-\-deep \-\-changed\-use \-\-update\fR
\fI@world\fP will always be a no\-op.
.br

.br
Or, to put it another way, we claim that the list of
fully\-qualified atoms (\fIFQAs\fP, where an \fIFQA\fP is \fI$CATEGORY/$PF\fP)
produced by running \fB\fCemerge \-\-with\-bdeps=y \-\-pretend \-\-emptytree
\-\-verbose\fR \fI@world\fP will always describe the same end state reached
by running \fB\fCemerge \-\-with\-bdeps=y \-\-deep \-\-update
[\-\-changed\-use|\-\-newuse]\fR \fI@world\fP from same starting conditions,
as regards packages and versions, anyhow.
.IP "  2." 5
It also contains sufficient information to simulate \fB\fC\-\-changed\-use\fR
and \fB\fC\-\-newuse\fR\&.
.br

.br
Of course, the issue is that in addition to new versions (\fI[N]\fP),
package upgrades (\fI[U]\fP), downgrades (\fI[UD]\fP), new slots (\fI[NS]\fP)
blocks and uninstalls, such a list will generally also contain a
huge number of reinstalls (\fI[R]\fP). Some of these will genuinely
need doing (in light of changed USE flags etc.), but many,
usually the vast majority, will be redundant.
.br

.br
Fortunately, for common rebuild selections (such as \fB\fC\-\-changed\-use\fR
and \fB\fC\-\-newuse\fR), we can easily identify which is which, using only
the information provided by the \fB\fC\-\-pretend \-\-emptytree\fR \fB\fCemerge\fR
itself \- since in its output, changes to the USE flag active set
for a given package are shown with an \fI*\fP suffix, and changes to
the remaining set with a \fI%\fP suffix, when \fB\fC\-\-verbose\fR is used.
.IP "  3." 5
Producing such a list, and then shallow emerging it, reduces the net
dependency calculation time.
.br

.br
Finally, we also claim that for a Gentoo system with many installed
packages, the time taken to 1) generate an \fB\fC\-\-emptytree\fR \fI@world\fP
\fIFQA\fP list for all packages, 2) filter this to leave only those
elements that actually \fIneed\fP an install or reinstall (given the
current package set and \fB\fC\-\-changed\-use\fR/\fB\fC\-\-newuse\fR
etc. preference); and 3) invoke a \fB\fC\-\-oneshot\fR \fB\fCemerge\fR on the
resulting list (of \fI=$CATEGORY/$PF\fP \fIFQAs\fP), to the point the first
build actually starts, can be up to an \fIorder of magnitude\fP less
than the equivalent time to first build commencement for a \fB\fC\-\-deep
\-\-update\fR based \fI@world\fP \fB\fCemerge\fR (for a system with many installed
packages and where the number of required updates is (relatively)
small).  Yet, if the other claims above are correct, the resulting
merge lists for both approaches will be identical. Furthermore,
this real \fB\fC\-\-oneshot\fR \fB\fCemerge\fR will still deal with triggered slot
change rebuilds and soft block uninstalls for us, and (subject to
\fIEMERGE\_DEFAULT\_OPTS\fP) allow the scheduled builds to be fully
parallelized.

.RE

.SH ADVANTAGES
.PP
The speedup for the dependency phase just mentioned, can
translate to hours saved on slow SBCs with binhost backing (where the
build phase itself is relatively low cost). The efficiency gains fall
if a large number of packages require updating, however.

.PP
Another advantage of this approach is that for some complex updates,
with many blockers, \fB\fCemerge \-\-with\-bdeps=y \-\-pretend \-\-emptytree
\-\-verbose\fR \fI@world\fP can sometimes derive a valid list of \fIFQAs\fP, in
cases where \fB\fCemerge \-\-with\-bdeps=y \-\-pretend \-\-deep \-\-update\fR \fI@world\fP
fails so to do, even with heavy backtracking (although this is a
comparatively rare situation).

.PP
Note: in the context of this script, an \fIFQA\fP, or fully qualified
atom, is taken to be \fI$CATEGORY/$PF\fP, so for example:
\fIsys\-apps/package\-a\-1.0.4\_rc4\_p3\-r2\fP\&.

.SH BUGS
.PP
A number of nice \fB\fCemerge\fR features don't work with \fB\fCemtee\fR, such as
\fB\fC\-\-changed\-deps\fR etc. The focus has been on \fB\fC\-\-changed\-use\fR and
\fB\fC\-\-newuse\fR, which are the most common.

.PP
To operate correctly, \fB\fCemtee\fR needs to be able to parse the output
from \fB\fCemerge\fR\&. So, if the latter's format changes in the future,
expect breakage ><

.PP
The script's efficiency gains degrade rapidly as the number of
packages requiring upgrade increases.

.SH COPYRIGHT
.PP
Copyright © 2018\-2020 sakaki

.PP
License GPLv3+ (GNU GPL version 3 or later)
.br
http://gnu.org/licenses/gpl.html
\[la]http://gnu.org/licenses/gpl.html\[ra]

.PP
This is free software, you are free to change and redistribute it.
.br
There is NO WARRANTY, to the extent permitted by law.

.SH AUTHOR
.PP
sakaki — send bug reports or comments to sakaki@deciban.com
\[la]mailto:sakaki@deciban.com\[ra]

.SH SEE ALSO
.PP
\fB\fCdiff\fR(1), \fB\fCemerge\fR(1), \fB\fCportage\fR(5)
