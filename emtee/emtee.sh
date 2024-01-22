#!/bin/bash
#
# SUMMARY
# -------
#
# A faster-startup "emerge -DuU --with-bdeps=y @world" (et al.)
#
# emtee is a simple script to speed up @world updates on Gentoo
# Linux systems, by significantly decreasing the time taken for the
# initial dependency resolution stage (often the dominant component for
# SBCs and other resource-challenged systems, if a binhost is deployed).
#
# It may be used (with appropriate options) in place of:
#    emerge --with-bdeps=y --deep --update --changed-use @world,
#    emerge --with-bdeps=y --deep --update --newuse --ask --verbose @world;
# and similar invocations.
#
# For example, you could achieve the same effect as the above commands
# with:
#   emtee
# and
#   emtee --newuse --ask --verbose     (or, equivalently, emtee --Nav)
# respectively. Generally speaking, emtee will take materially less time
# to get the first actual build underway than its counterpart emerge
# --update, while still targeting an identical build list, permitting
# job parallelism, and triggering any slot-driven rebuilds.
#
# BASIS
# -----
#
# The main claims behind emtee are:
#
# *) An --emptytree emerge of @world yields the same versioned package
#    list that a --deep --update would arrive at.
#
#    For emtee to work, it must be true that for a consistent, depcleaned
#    Gentoo system with a recently updated set of ebuild repositories,
#    if emerge --with-bdeps=y --emptytree @world is invoked and runs
#    successfully to conclusion, then an immediately following emerge
#    --with-bdeps=y --deep --changed-use --update @world will always
#    be a no-op.
#
#    Or, to put it another way, we claim that the list of
#    fully-qualified atoms (FQAs, where an FQA is $CATEGORY/$PF)
#    produced by running emerge --with-bdeps=y --pretend --emptytree
#    --verbose @world will always describe the same end state reached
#    by running emerge --with-bdeps=y --deep --update
#    [--changed-use|--newuse] @world from same starting conditions, as
#    regards packages and versions, anyhow.
#
# *) It also contains sufficient information to simulate --changed-use
#    and --newuse.
#
#    Of course, the issue is that in addition to new versions ([N]),
#    package upgrades ([U]), downgrades ([UD]), new slots ([NS])
#    blocks and uninstalls, such a list will generally also contain a
#    huge number of reinstalls ([R]). Some of these will genuinely
#    need doing (in light of changed USE flags etc.), but many,
#    usually the vast majority, will be redundant.
#
#    Fortunately, for common rebuild selections (such as --changed-use
#    and --newuse), we can easily identify which is which, using only
#    the information provided by the --pretend --emptytree emerge
#    itself - since in its output, changes to the USE flag active set
#    for a given package are shown with an * suffix, and changes to
#    the remaining set with a % suffix, when --verbose is used.
#
# *) Producing such a list, and then shallow emerging it, reduces the net
#    dependency calculation time.
#
#    Finally, we also claim that for a Gentoo system with many
#    installed packages, the time taken to 1) generate an --emptytree
#    @world FQA list for all packages, 2) filter this to leave only
#    those elements that actually *need* an install or reinstall
#    (given the current package set and --changed-use/--newuse
#    etc. preference); and 3) invoke a --oneshot emerge on the
#    resulting list (of =$CATEGORY/$PF FQAs), to the point the first
#    build actually starts, can be up to an *order of magnitude* less
#    than the equivalent time to first build commencement for a --deep
#    --update based @world emerge (for a system with many installed
#    packages and where the number of required updates is (relatively)
#    small).  Yet, if the other claims above are correct, the
#    resulting merge lists for both approaches will be
#    identical. Furthermore, this 'real' --oneshot emerge will still
#    deal with triggered slot change rebuilds and soft block
#    uninstalls for us, and (subject to EMERGE_DEFAULT_OPTS) allow the
#    scheduled builds to be fully parallelized.
#
# ALGORITHM
# ---------
#
# The emtee process runs as follows:
#
# 1. Derive a full, versioned build list for the @world set and its
#    entire deep dependency tree, via
#      emerge --with-bdeps=y --pretend --emptytree --verbose [opts] @world
#    which Portage can do relatively quickly. The resulting list, as
#    it is derived as if *no* packages were installed to begin with,
#    will automatically contain all necessary packages at their 'best'
#    versions (which may entail upgrades, downgrades, new slots etc.
#    wrt the currently installed set).
#
# 2. Filter this list, by marking each fully-qualified atom (FQA)
#    within it for building (or not). Begin with all FQAs unmarked.
#    Then (pass 1):
#      * mark anything which isn't a block, uninstall or reinstall
#        for build;
#    Then (pass 2):
#      * check each reinstall, to see if its *active* USE flag set is
#        changing (default behaviour), or if *any* of its USE flags
#        are changing (-N/--newuse behaviour), and if so, mark that
#        package for build (fortunately, the --verbose output from
#        step 1 contains the necessary USE flag delta information
#        to allow us to easily work this out).
#    Then (pass 3), if -S/--force-slot-rebuilds is in use:
#      * for each marked package on the list whose slot or subslot
#        is changing (also inferable from the phase 1 output), search
#        /var/db/pkg/<FQA>/RDEPENDS (and DEPENDS, if --with-bdeps=y,
#        the default, is active) for any matching slot dependencies.
#        Mark each such located (reverse) dependency that is *also*
#        on the original --emptytree list (and not a block or
#        uninstall) for build.
#    Note that pass 3 is skipped by default, since the phase 4 emerge
#    (aka the "real" emerge, see below) will automatically trigger any
#    necessary slot rebuilds anyway, so it is redundant except for in
#    a few esoteric situations.
#
# 3. Iff -c/--crosscheck (or -C/--strict-crosscheck) passed, compare
#    the build list produced by invoking:
#      emerge --bdeps=y --pretend --deep --update [--changed-use|--newuse] [opts] @world
#    (adapted for specified options appropriately), with that produced
#    by invoking:
#      emerge --oneshot --pretend [opts] <filtered-build-list-from-phase-2>
#    If any differences are found, report them (and stop the build,
#    if -S/--strict-crosscheck specified). Report a series of
#    comparative (total elapsed wall-clock) timings for both
#    alternatives, for benchmarking purposes.
#    (Note: crosschecking should *only* be used for reassurance or
#    benchmarking, as it will, of necessity, be slower than the baseline
#    in total time cost (since the check involves running both that
#    *and* the new approach)! So, if your goal is to improve emerge
#    times, do *not* pass -s/-S.)
#
# 4. Invoke the 'real' emerge, as:
#      emerge --oneshot [opts] <filtered-FQA-build-list-from-phase-2>
#    (Note that additional opts may be passed to this invocation,
#    both explicitly (via -E/--emerge-args) and implicitly, via one of
#    the impacting options (-v/--verbose, -a/--ask, -A/--alert, or
#    -p/--pretend).)
#
# ADVANTAGES
# ----------
#
# The speedup for the dependency phase can be up to an *order of
# magnitude* for systems with a large number of installed packages,
# and where the required number of updates is relatively small.  This
# can translate to hours saved on slow SBCs with binhost backing
# (where the build phase itself is relatively low cost). The
# efficiency gains fall if a large number of packages require
# updating.
#
# Another advantage of this approach is that for some complex updates,
# with many blockers,
#   emerge --with-bdeps=y --pretend --emptytree --verbose @world
# can sometimes derive a valid list of FQAs, in cases where
#   emerge --with-bdeps=y --pretend --deep --update @world
# fails so to do, even with heavy backtracking (although this is
# a comparatively rare situation).
#
# Note: in the context of this script, an FQA, or fully qualified
# atom, is taken to be $CATEGORY/$PF, so for example:
#   sys-apps/package-a-1.0.4_rc4_p3-r2
#
# MANPAGE
# -------
#
# This script has an accompanying manpage.
#
# BUGS
# ----
#
# A number of nice emerge features don't work with emtee, such as
# --changed-deps etc. The focus has been on --changed-use and
# --newuse, which are the most common.
#
# To operate correctly, emtee needs to be able to parse the output
# from emerge. So, if the latter's format changes in the future,
# expect breakage ><
#
# The script's efficiency gains degrade rapidly as the number of
# packages requiring upgrade increases.
#
# AUTHOR
# ------
#
# Copyright (c) 2018-2020 sakaki <sakaki@deciban.com>
#
# License (GPL v3.0)
# ------------------
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#

set -e
set -u
shopt -s nullglob
set -o pipefail

# Scroll to the bottom of this script to follow the main program flow.

# ********************** variables ********************* 

PROGNAME="$(basename "${0}")"
VERSION="1.0.5"

RED_TEXT="" GREEN_TEXT="" YELLOW_TEXT="" RESET_ATTS="" ALERT_TEXT=""
if [[ -v TERM && -n "${TERM}" && "${TERM}" != "dumb" ]]; then
    RED_TEXT="$(tput setaf 1)$(tput bold)"
    GREEN_TEXT="$(tput setaf 2)$(tput bold)"
    YELLOW_TEXT="$(tput setaf 3)$(tput bold)"
    RESET_ATTS="$(tput sgr0)"
    ALERT_TEXT="$(tput bel)"
fi

declare -i VERBOSITY=1

# below arrays are used to hold the results of parsing emerge --verbose --pretend --emptytree @world
# output, a typical line of which might read:
# [ebuild     U  ] sys-apps/package-a-1.0.4_rc4_p3-r2:3/5::test-repo [1.0.3_rc7_beta_p2-r1:3/4::old-repo] USE="afoo -abar -ayak" 0 KiB

declare -a ALL_EMTYPE        # emerge type: "ebuild", "binary" etc.
declare -a ALL_EMFLAGS       # emerge flags, without spaces "UD" "NS" "R" etc.
                             # NB: --emptytree doesn't do "r", we need to
                             # manually compute rebuilds for --changed-use etc.
declare -a ALL_CATEGORY      # category: "sys-apps" etc.
declare -a ALL_PN            # package name: "package-a" etc.
declare -a ALL_PF            # full package name $PN-$PVR: "package-a-1.0.4_rc4_p3-r2" etc.
declare -a ALL_PVR           # package version and revision (if any): "1.0.4_rc4_p3-r2" etc.
declare -a ALL_PV            # package version, excluding revision: "1.0.4_rc4_p3" etc.
declare -a ALL_PR            # package revision: "r2" etc. (NB "" if none, NOT "r0")
declare -a ALL_FQA           # fully qualified atom $CATEGORY/$PF: "sys-apps/package-a-1.0.4_rc4_p3-r2" etc.
declare -a ALL_SLOT          # full supslot/subslot: "3/5", "0/0" etc.
declare -a ALL_SUPSLOT       # (super) slot: "3" etc.
declare -a ALL_SUBSLOT       # subslot (=supslot if no subslot): "5" etc.
declare -a ALL_REPO          # repository: "test-repo" etc.
# following are used to store the current package version data, iff
# the operation recommended is an upgrade of some form; all fields "" where
# not applicable (in cases of pure reinstall, new install etc.)
declare -a ALL_CURR_PF       # current $PN-$PVR: "package-a-1.0.3_rc7_p2-r1" etc.
declare -a ALL_CURR_PVR      # current $PVR: "1.0.3_rc7_p2-r1"
declare -a ALL_CURR_PV       # current $PV: "1.0.3_rc7_p2" etc.
declare -a ALL_CURR_PR       # current $PR: "-r1" etc. ("" if none)
declare -a ALL_CURR_FQA      # current $FQA: "sys-apps/package-a-1.0.3_rc7_p2-r1" etc.
declare -a ALL_CURR_SLOT     # current $SLOT: "3/4", "0" etc.
declare -a ALL_CURR_SUPSLOT  # current $SUPSLOT: "3" etc.
declare -a ALL_CURR_SUBSLOT  # current $SUBSLOT: "4" etc.
declare -a ALL_CURR_REPO     # current $REPO: "old-repo" etc.
declare -a ALL_TAIL          # the rest of the line, including USE flags etc.
                             # e.g. 'USE="afoo -abar -ayak" 0 KiB'
# build marking
declare -a ALL_BUILD         # whether (1) or not (0) to really build the atom
                             # filtering affects this array
declare -a ALL_MASK          # whether (1) or not (0) to prohibit the atom from
                             # being built (used for uninstalls, blocks etc.)
declare -i NUM_ATOMS=0       # number of atoms held in the above arrays
declare -i NUM_TO_BUILD=0    # number of packages to actually emerge
declare -A FQA_TO_IX         # associative array mapping FQA to index in above array
BUILD_FQAS=""                # final list of fully-qualified atoms to build, each
                             # prefixed by "=" (so can be passed directly to emerge)

PREFIXSTRING="* "
SHOWPREFIX="${GREEN_TEXT}${PREFIXSTRING}${RESET_ATTS}"
SHOWSUFFIX=""

# number of phase 4 builds at or above which an emerge failure will
# trigger a full, ground-up rebuild; 0 means never do this
declare -i FALLBACK_THRESHOLD=0
FALLBACK_SENTINEL="/tmp/.full-emptytree-emerge-performed"

# program arguments (booleans in this case)
declare -i ARG_ASK=0 ARG_ALERT=0 ARG_HELP=0 ARG_VERSION=0
declare -i ARG_VERBOSE=0 ARG_NEWUSE=0 ARG_PRETEND=0
declare -i ARG_DEBUG=0 ARG_CROSSCHECK=0 ARG_STRICT_CROSSCHECK=0
declare -i ARG_WITH_BDEPS=1 # defaults ON
declare -i ARG_KEEP_GOING=1 # defaults ON
declare -i ARG_FORCE_SLOT_REBUILDS=0

BDEPS_FLAG=y
KEEP_GOING_FLAG=y

# force TERM if none found (e.g. when running from cron)
if ! tty -s; then
    export TERM="dumb"
fi

# store copy of original args, and canonical path to script itself
ORIGINAL_ARGS="${@}"
SCRIPTPATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# various flags to be passed to (differing) emerge
# invocations
ASKFLAG=""
ALERTFLAG=""
VERBOSITYFLAG=""
PRETENDFLAG=""
ETEMERGEARGS=""              # extra user arguments for the --emptytree emerge
EMERGEARGS=""                # and for the real emerge
TARGETSET="@world"
USEOPT="--changed-use"
SHORTUSEOPT="U"

# for internal timing, use bash special variable
declare -i START_SECS="${SECONDS}" EMPTYTREE_DONE_SECS=0
declare -i FILTRATION_DONE_SECS=0 EMERGE_DONE_SECS=0
declare -i CROSSCHECK_DEEP_DONE_SECS=0
declare -i CROSSCHECK_LIST_DONE_SECS=0
declare -i CROSSCHECK_DONE_SECS=0 ALL_DONE_SECS=0
declare -i EMPTYTREE_ELAPSED_SECS=0
declare -i FILTRATION_ELAPSED_SECS=0
declare -i CROSSCHECK_DEEP_ELAPSED_SECS=0
declare -i CROSSCHECK_LIST_ELAPSED_SECS=0
declare -i CROSSCHECK_ELAPSED_SECS=0
declare -i EMERGE_ELAPSED_SECS=0
# cost of all phases to get to a final
# actionable (pretend) emerge, when
# crosschecking
# = emptytree + filter + list-emerge (elapsed times)
declare -i MT_EQUIVALENT_ELAPSED_SECS=0

# output from emerge runs
EMPTYTREE_OUTPUT=""
CROSSCHECK_OUTPUT=""
ONESHOT_OUTPUT=""

# location of the installed package database
PKGDB="/var/db/pkg"

# ***************** various functions ****************** 
cleanup_and_exit_with_code() {
    # add any cleanup code here
    trap - EXIT
    exit $1
}
show() {
    local MESSAGE=${1:-""}
    local VERBLEVEL=${2:-${VERBOSITY}}
    if (( VERBLEVEL >=1 )); then
        echo -e "${SHOWPREFIX}${MESSAGE}${SHOWSUFFIX}"
    fi
}
alertshow() {
    local MESSAGE=${1:-""}
    local VERBLEVEL=${2:-${VERBOSITY}}
    if ((ARG_ALERT==0)); then
        show "${@}"
    elif (( VERBLEVEL >=1 )); then
        echo -e "${SHOWPREFIX}${MESSAGE}${SHOWSUFFIX}${ALERT_TEXT}"
    fi
}
warning() {
    echo -e "${YELLOW_TEXT}${PREFIXSTRING}${RESET_ATTS}${PROGNAME}: Warning: ${1}" >&2
}
die() {
    echo
    echo -e "${RED_TEXT}${PREFIXSTRING}${RESET_ATTS}${PROGNAME}: Error: ${1} - exiting" >&2
    cleanup_and_exit_with_code 1
}
trap_cleanup() {
    trap - SIGHUP SIGQUIT SIGINT SIGTERM SIGKILL EXIT
    die "Caught signal"
}
trap trap_cleanup SIGHUP SIGQUIT SIGINT SIGTERM SIGKILL EXIT
test_yn() {
    echo -n -e "${SHOWPREFIX}${1} (y/n)? ${SHOWSUFFIX}${ALERT_TEXT}"
    read -r -n 1
    echo
    if [[ ${REPLY} =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}
continue_yn() {
    if ! test_yn "${1}"; then
        echo -e "${RED_TEXT}${PREFIXSTRING}${RESET_ATTS}Quitting" >&2
        cleanup_and_exit_with_code 1
    fi
}
suppress_colours() {
    RED_TEXT=""
    GREEN_TEXT=""
    YELLOW_TEXT=""
    RESET_ATTS=""
    SHOWPREFIX="${PREFIXSTRING}"
}
suppress_alert() {
    ALERT_TEXT=""
}
suppress_colour_and_alert_if_output_not_to_a_terminal() {
    if [ ! -t 1 -o ! -t 2 ]; then
        # we are going to a non-terminal
        suppress_colours
        suppress_alert
    fi
}
display_greeting() {
    show "${PROGNAME}: a faster-startup @world updater for Gentoo Linux, v${VERSION}"
}
display_final_status() {
    ALL_DONE_SECS="${SECONDS}"
    local -i DURATION=$((ALL_DONE_SECS - START_SECS))
    local CROSSCHECK_TIMING="${CROSSCHECK_ELAPSED_SECS}s (crosscheck) + "
    if ((ARG_CROSSCHECK==0)); then
        CROSSCHECK_TIMING=""
    fi
    show "Run completed in $((DURATION))s = ${EMPTYTREE_ELAPSED_SECS}s (emptytree) + ${FILTRATION_ELAPSED_SECS}s (filter) + ${CROSSCHECK_TIMING}${EMERGE_ELAPSED_SECS}s (emerge)"
    show "All done!"
}
print_usage() {
    cat << EOF
Usage: ${PROGNAME} [options]

Options:
  -a, --ask             turns on interactive mode for the 'real' emerge
  -A, --alert           sound terminal bell when interaction required
                        (selecting this also automatically selects --ask)
  -b, --with-bdeps=y|n  whether or not to pull in build-time dependencies;
                        NB defaults to y if unspecified, in contrast to
                        emerge's default behaviour
  -c, --crosscheck      checks the final build list against the result
                        obtained by running a conventional --deep emerge,
                        and prints a diff of the package list; also provides
                        a comparative timing, for benchmarking purposes;
                        NB: does not check the ordering of the packages
  -C, --strict-crosscheck
                        as for -c, but exits with an error if the
                        emtee and conventional --deep --update emerge
                        lists do not match
  -d, --debug           print some additional debugging output
  -e, --emptytree-emerge-args=ARGS
                        pass provided additional ARGS to the initial
                        (--emptytree) emerge stage
  -f, --full-build-fallback-threshold=NUM
                        if there are >=NUM packages to be rebuilt at the
                        final phase, then dry-run the oneshot emerge of
                        these first; if this fails, run a _full_
                        --emptytree @world emerge, followed (if successful)
                        by emerge --depclean (the default is not to
                        do any of these steps)
  -E, --emerge-args=ARGS
                        pass provided additional ARGS to the 'real' emerge
                        e.g., use --emerge-args='--autounmask-write' to
                        automatically make necessary changes to config files
  -h, --help            show this help message and exit
  -p, --pretend         don't actually perform the update, just show what it
                        would do (dry run)
  -N, --newuse          rebuild packages which have had any USE flag changes,
                        even if those do not affect flags the user has enabled
                        (the more conservative "--changed-use" behaviour
                        is the default)
                        NB the --newuse feature is experimental
  -s, --set=SET         target the given SET, instead of the default @world;
                        (you can pass regular package names here too, but
                        using a regular emerge is likely to be faster for
                        such targets)
  -S, --force-slot-rebuilds
                        checks for any slot-driven rebuilds, and adds these
                        (reverse) dependencies to the build list; this
                        option should not generally be required, as the
                        real emerge stage will trigger such rebuilds
                        automatically anyway
  -v, --verbose         ask called programs to display more information
  -V, --version         display the version number of ${PROGNAME} and exit
  -z, --keep-going=y|n  whether or not to continue the 'real' emerge phase as
                        much as possible after an error; NB defaults to y
                        if unspecified, in contrast to emerge's default
                        behaviour
EOF
}
print_help() {
    cat << EOF
${PROGNAME} - a faster @world updater
EOF
    print_usage
}
print_version() {
    printf "%s\n" "${VERSION}"
}
display_usage_message_and_bail_out() {
    if [ ! -z "${1+x}" ]; then
        printf "%s: %s\n" "${PROGNAME}" "${1}" >&2
    fi
    print_usage >&2
    cleanup_and_exit_with_code 1
}
internal_consistency_option_checks() {
    # following not exhaustive, just some more obvious snafus
    if ((ARG_FORCE_SLOT_REBUILDS==1)); then
        warning "Forced slot rebuilding is activated."
        warning "This is generally redundant, as the final"
        warning "emerge stage will do it anyway."
    fi
}
process_command_line_options() {
    local TEMP
    declare -i RC
    set +e
        # error trapping temporarily off while we parse
        # so we can handle issues ourselves
        TEMP="$(getopt -o aAb:cCde:E:f:hpNs:SvVz: --long ask,alert,with-bdeps:,crosscheck,strict-crosscheck,debug,emptytree-emerge-args:,emerge-args:,full-build-fallback-threshold:,pretend,newuse,set:,force-slot-rebuilds,verbose,version,keep-going: -n "${PROGNAME}" -- "${@}")"
        RC="${?}"
    set -e
    if ((RC!=0)); then
        display_usage_message_and_bail_out
    fi
    eval set -- "${TEMP}"

    # extract options and their arguments into variables.
    while true ; do
        case "${1}" in
            -a|--ask) ARG_ASK=1 ; shift ;;
            -A|--alert) ARG_ALERT=1 ; ARG_ASK=1 ; shift ;;
            -b|--with-bdeps)
                case "${2}" in
                    "") ARG_WITH_BDEPS=1; shift 2 ;;
                    *) [[ "${2,,}" =~ n ]] && ARG_WITH_BDEPS=0 || ARG_WITH_BDEPS=1 ; shift 2 ;;
                esac ;;
            -c|--crosscheck) ARG_CROSSCHECK=1 ; shift ;;
            -C|--strict-crosscheck) ARG_STRICT_CROSSCHECK=1 ; ARG_CROSSCHECK=1 ; shift ;;
            -d|--debug) ARG_DEBUG=1 ; shift ;;
            -e|--emptytree-emerge-args)
                case "${2}" in
                    "") shift 2 ;;
                    *) ETEMERGEARGS="${2}" ; shift 2 ;;
                esac ;;
            -E|--emerge-args)
                case "${2}" in
                    "") shift 2 ;;
                    *) EMERGEARGS="${2}" ; shift 2 ;;
                esac ;;
            -f|--full-build-fallback-threshold)
                case "${2}" in
                    "") shift 2 ;;
                    *) FALLBACK_THRESHOLD="${2}" ; shift 2 ;;
                esac ;;
            -h|--help) ARG_HELP=1 ; shift ;;
            -p|--pretend) ARG_PRETEND=1 ; shift ;;
            -N|--newuse) ARG_NEWUSE=1 ; USEOPT="--newuse" ; SHORTUSEOPT="N" ; shift ;;
            -s|--set)
                case "${2}" in
                    "") shift 2 ;;
                    *) TARGETSET="${2}" ; shift 2 ;;
                esac ;;
            -S|--force-slot-rebuilds) ARG_FORCE_SLOT_REBUILDS=1 ; shift ;;
            -v|--verbose) ARG_VERBOSE=1 ; shift ;;
            -V|--version) ARG_VERSION=1 ; shift ;;
            -z|--keep-going)
                case "${2}" in
                    "") ARG_KEEP_GOING=1; shift 2 ;;
                    *) [[ "${2,,}" =~ n ]] && ARG_KEEP_GOING=0 || ARG_KEEP_GOING=1 ; shift 2 ;;
                esac ;;
            --) shift ; break ;;
            *) die "Internal error!" ;;
        esac
    done
    if ((ARG_WITH_BDEPS==0)); then
        BDEPS_FLAG="n"
    fi
    if ((ARG_KEEP_GOING==0)); then
        KEEP_GOING_FLAG="n"
    fi
    # process 'perform-then-exit' options
    if ((ARG_HELP==1)); then
        print_help
        cleanup_and_exit_with_code 0
    elif ((ARG_VERSION==1)); then
        print_version
        cleanup_and_exit_with_code 0
    fi
    # set verbosity
    if ((ARG_VERBOSE==1)); then
        VERBOSITY+=1
    fi
    if ((VERBOSITY>1)); then
        VERBOSITYFLAG="--verbose"
    fi
    # pretending?
    if ((ARG_PRETEND==1)); then
        PRETENDFLAG="--pretend"
    fi
    # set interactive mode
    if ((ARG_ASK==1)); then
        ASKFLAG="--ask"
    fi
    if ((ARG_ALERT==1)); then
        ALERTFLAG="--alert"
    else
        suppress_alert
    fi
    internal_consistency_option_checks
}
compute_emptytree_package_list() {
    # phase 1 of the process: get an --emptytree FQA list, and parse the
    # constituent parts of the relevant lines of its output into arrays
    # for subsequent processing
    local NEXTLINE NEXTTAIL
    show "Computing full ordered package list, via:"
    show "  emerge --with-bdeps=${BDEPS_FLAG} --pretend --emptytree --verbose ${ETEMERGEARGS}${ETEMERGEARGS:+ }${TARGETSET}"
    show "Please wait..."
    # cache output in a variable...
    EMPTYTREE_OUTPUT="$(emerge --with-bdeps=${BDEPS_FLAG} --pretend --emptytree --verbose ${ETEMERGEARGS} ${TARGETSET})"
    # ...and parse each line from it, using a regex
    while read -r NEXTLINE; do
        # following regex isn't meant to enforce syntax - assume
        # Portage's naming rules have been followed
        if [[ "${NEXTLINE}" =~ ^\[([^[:blank:]]+)([^\]#\*~]+)[#\*~]*\][[:blank:]]+([^/]+)/(([0-9A-Za-z_+\-]+)-((([0-9.]+[0-9A-Za-z]?)(((_alpha|_beta|_pre|_rc|_p)[0-9]*)*))(-r[^:]+)?)):?([^:/]+)?/?([^:]+)?::([^[:blank:]]+)[[:blank:]]+(.*)$ ]]; then
            ALL_EMTYPE[${NUM_ATOMS}]="${BASH_REMATCH[1]}"
            ALL_EMFLAGS[${NUM_ATOMS}]="${BASH_REMATCH[2]//[[:blank:]]/}" # drop all spaces
            ALL_CATEGORY[${NUM_ATOMS}]="${BASH_REMATCH[3]}"
            ALL_PN[${NUM_ATOMS}]="${BASH_REMATCH[5]}"
            ALL_PF[${NUM_ATOMS}]="${BASH_REMATCH[4]}"
            ALL_PVR[${NUM_ATOMS}]="${BASH_REMATCH[6]}"
            ALL_PV[${NUM_ATOMS}]="${BASH_REMATCH[7]}"
            ALL_PR[${NUM_ATOMS}]="${BASH_REMATCH[12]#-}"
            ALL_FQA[${NUM_ATOMS}]="${ALL_CATEGORY[${NUM_ATOMS}]}/${ALL_PF[${NUM_ATOMS}]}"
            ALL_SUPSLOT[${NUM_ATOMS}]="${BASH_REMATCH[13]:-0}"
            ALL_SUBSLOT[${NUM_ATOMS}]="${BASH_REMATCH[14]:-${ALL_SUPSLOT[${NUM_ATOMS}]}}"
            ALL_SLOT[${NUM_ATOMS}]="${ALL_SUPSLOT[${NUM_ATOMS}]}/${ALL_SUBSLOT[${NUM_ATOMS}]}"
            ALL_REPO[${NUM_ATOMS}]="${BASH_REMATCH[15]}"
            NEXTTAIL="${BASH_REMATCH[16]}"
            if [[ "${ALL_EMFLAGS[${NUM_ATOMS}]}" =~ U|NS ]]; then
                # upgrade of some sort, parse the tail
                if [[ "${NEXTTAIL}" =~ ^\[((([0-9.]+[0-9A-Za-z]?)(((_alpha|_beta|_pre|_rc|_p)[0-9]*)*))(-r[^:]+)?):?([^:/]+)?/?([^:]+)?::([^\]]+)\][[:blank:]]+(.*)$ ]]; then
                    ALL_CURR_PVR[${NUM_ATOMS}]="${BASH_REMATCH[1]}"
		    ALL_CURR_PF[${NUM_ATOMS}]="${ALL_PN[${NUM_ATOMS}]}-${ALL_CURR_PVR[${NUM_ATOMS}]}"
                    ALL_CURR_PV[${NUM_ATOMS}]="${BASH_REMATCH[2]}"
                    ALL_CURR_PR[${NUM_ATOMS}]="${BASH_REMATCH[7]#-}"
                    ALL_CURR_FQA[${NUM_ATOMS}]="${ALL_CATEGORY[${NUM_ATOMS}]}/${ALL_CURR_PF[${NUM_ATOMS}]}"
                    ALL_CURR_SUPSLOT[${NUM_ATOMS}]="${BASH_REMATCH[8]:-0}"
                    ALL_CURR_SUBSLOT[${NUM_ATOMS}]="${BASH_REMATCH[9]:-${ALL_CURR_SUPSLOT[${NUM_ATOMS}]}}"
                    ALL_CURR_SLOT[${NUM_ATOMS}]="${ALL_CURR_SUPSLOT[${NUM_ATOMS}]}/${ALL_CURR_SUBSLOT[${NUM_ATOMS}]}"
                    ALL_CURR_REPO[${NUM_ATOMS}]="${BASH_REMATCH[10]}"
                    ALL_TAIL[${NUM_ATOMS}]="${BASH_REMATCH[11]}"
		else
		    die "Failed to parse tail: '${NEXTTAIL}'!"
		fi
            else
                # no upgrade
                ALL_CURR_PVR[${NUM_ATOMS}]=""
                ALL_CURR_PF[${NUM_ATOMS}]=""
                ALL_CURR_PV[${NUM_ATOMS}]=""
                ALL_CURR_PR[${NUM_ATOMS}]=""
                ALL_CURR_FQA[${NUM_ATOMS}]=""
                ALL_CURR_SUPSLOT[${NUM_ATOMS}]=""
                ALL_CURR_SUBSLOT[${NUM_ATOMS}]=""
                ALL_CURR_SLOT[${NUM_ATOMS}]=""
                ALL_CURR_REPO[${NUM_ATOMS}]=""
                ALL_TAIL[${NUM_ATOMS}]=="${NEXTTAIL}"
            fi
            # store a cross-reference by FQA to index
            FQA_TO_IX["${ALL_FQA[${NUM_ATOMS}]}"]=${NUM_ATOMS}
            NUM_ATOMS=$((NUM_ATOMS+1))
        fi
    done <<<"${EMPTYTREE_OUTPUT}"
    EMPTYTREE_DONE_SECS="${SECONDS}"
    EMPTYTREE_ELAPSED_SECS=$((EMPTYTREE_DONE_SECS - START_SECS))
    if ((NUM_ATOMS==0)); then
        die "The initial (--pretend) emerge step failed"
    fi
    if ((ARG_DEBUG==1)); then
        show "The unfiltered list of packages is as follows:"
        local -i I
        for ((I=0;I<NUM_ATOMS;I++)); do
            echo "  [${ALL_EMTYPE[${I}]} ${ALL_EMFLAGS[${I}]}] ${ALL_FQA[${I}]}:${ALL_SLOT[${I}]}::${ALL_REPO[${I}]} ${ALL_CURR_FQA[${I}]}${ALL_CURR_SLOT[${I}]:+:}${ALL_CURR_SLOT[${I}]}${ALL_CURR_REPO[${I}]:+::}${ALL_CURR_REPO[${I}]}"
        done
    fi
    show "There are $((NUM_ATOMS)) packages specified by the ${TARGETSET} --emptytree emerge"
    show "Phase completed in $((EMPTYTREE_ELAPSED_SECS))s"
    show
}
filter_package_list() {
    # phase 2 of the process: filter the full package list produced
    # from the --pretend --emptytree emerge step, down to a set of
    # fully qualified package atoms that we *do* care about
    #
    # see the top-of-file "ALGORITHM" text for more details
    # of the process followed
    show "Filtering package list..."
    show "Pass 1: removing uninstalls, blocks and rebuilds..."
    local -i I
    for ((I=0;I<NUM_ATOMS;I++)); do
        # pass 1, begin by assuming we don't want to build it or mask
        # it NB 'masking' here refers to an internal flag that
        # prevents a package having its build flag set; it is not
        # related to Portage masks per se
        ALL_BUILD[${I}]=0
        ALL_MASK[${I}]=0
        if [[ "uninstall" == "${ALL_EMTYPE[${I}]}" || "blocks" == "${ALL_EMTYPE[${I}]}" ]]; then
            # blocks and uninstalls will be dealt with by final emerge step
            # we mask these, so they can never be flagged as
            # candidate FQAs
            ALL_MASK[${I}]=1
            continue
        fi
        if [[ "${ALL_EMFLAGS[${I}]}" =~ R ]]; then
            # begin by assuming we don't need pure rebuilds
            # we'll revisit this decision in the next pass
           continue
        fi
        # turn on the build flag for all others (U, UD, N, NS etc.)
        ALL_BUILD[${I}]=1
        NUM_TO_BUILD=$((NUM_TO_BUILD+1))
    done
    show "After first pass, ${NUM_TO_BUILD} of ${NUM_ATOMS} packages marked for build"
    if ((ARG_DEBUG==1)); then
        show "The filtered list of packages, after the first pass, is as follows:"
        for ((I=0;I<NUM_ATOMS;I++)); do
            if ((ALL_BUILD[${I}]==1)); then
                echo "  [${ALL_EMTYPE[${I}]} ${ALL_EMFLAGS[${I}]}] ${ALL_FQA[${I}]}:${ALL_SLOT[${I}]}::${ALL_REPO[${I}]} ${ALL_CURR_FQA[${I}]}${ALL_CURR_SLOT[${I}]:+:}${ALL_CURR_SLOT[${I}]}${ALL_CURR_REPO[${I}]:+::}${ALL_CURR_REPO[${I}]}"
            fi
        done
    fi

    # pass 2, deal with changed / new use
    # revisit rebuilds, and look at the USE flag delta information
    # contained at the end ('tail') of each line's output from
    # the emerge --emptytree --verbose @world run, to do this
    show "Pass 2: dealing with ${USEOPT}..."
    local -i FORCE_REBUILD=0
    local NEXTTAIL
    for ((I=0;I<NUM_ATOMS;I++)); do
        if ((ALL_MASK[I]==1)); then
            continue
        fi
        FORCE_REBUILD=0
        # ignore, as Portage does, any changes to the test flag
        # where constrained by a FEATURES setting
        # (denoted by {...})
        NEXTTAIL="${ALL_TAIL[${I}]//\{test\*\}/}"
        NEXTTAIL="${NEXTTAIL//\{-test\*\}/}"
        NEXTTAIL="${NEXTTAIL//\{test\%\}/}"
        NEXTTAIL="${NEXTTAIL//\{-test\%\}/}"
        if ((ARG_NEWUSE==0)); then
            # changes to the active USE flag set are marked with
            # an asterisk
            if [[ "${NEXTTAIL}" =~ \* ]]; then
                FORCE_REBUILD=1
            fi
        else
            # other changes to the USE flag set are marked with
            # a percent sign
            if [[ "${NEXTTAIL}" =~ [*%] ]]; then
                FORCE_REBUILD=1
            fi
        fi
        if ((FORCE_REBUILD==1 && ALL_BUILD[I]==0)); then
            # this rebuild needs to happen, resurrect it
            show "Forcing rebuild for: ${ALL_FQA[${I}]}"
            ALL_BUILD[${I}]=1
            NUM_TO_BUILD=$((NUM_TO_BUILD+1))
        fi
    done
    show "After second pass, ${NUM_TO_BUILD} of ${NUM_ATOMS} packages marked for build"
    if ((ARG_DEBUG==1)); then
        show "The filtered list of packages, after the second pass, is as follows:"
        for ((I=0;I<NUM_ATOMS;I++)); do
            if ((ALL_BUILD[${I}]==1)); then
                echo "  [${ALL_EMTYPE[${I}]} ${ALL_EMFLAGS[${I}]}] ${ALL_FQA[${I}]}:${ALL_SLOT[${I}]}::${ALL_REPO[${I}]} ${ALL_CURR_FQA[${I}]}${ALL_CURR_SLOT[${I}]:+:}${ALL_CURR_SLOT[${I}]}${ALL_CURR_REPO[${I}]:+::}${ALL_CURR_REPO[${I}]}"
            fi
        done
    fi

    # pass 3, compute rebuilds caused by slot changes
    # this pass is optional (default off), since the final
    # 'real' emerge should automatically trigger any such
    # rebuilds anyhow
    if ((ARG_FORCE_SLOT_REBUILDS==0)); then
        show "Pass 3: skipping slot change revdep marking"
        show "(necessary rebuilds should be triggered automatically during"
        show " final emerge, so this is generally safe to do)"
    else
        show "Pass 3: marking revdeps of slot changes for rebuild..."
        local -i SUPSLOT_CHANGED=0 SUBSLOT_CHANGED=0 SLOT_CHANGED=0
        for ((I=0;I<NUM_ATOMS;I++)); do
            SLOT_CHANGED=0
            if [[ "${ALL_EMFLAGS[${I}]}" =~ U|NS ]]; then
                # possible slot change
                if [[ "${ALL_SUPSLOT[${I}]}" == "${ALL_CURR_SUPSLOT[${I}]}" ]]; then
                    SUPSLOT_CHANGED=0
                    if [[ "${ALL_SUBSLOT[${I}]}" == "${ALL_CURR_SUBSLOT[${I}]}" ]]; then
                        SUBSLOT_CHANGED=0
                    else
                        SUBSLOT_CHANGED=1
                    fi
                else
                    SUPSLOT_CHANGED=1
                    SUBSLOT_CHANGED=1
                fi
                SLOT_CHANGED=$((SUPSLOT_CHANGED | SUBSLOT_CHANGED))
            fi
            if ((SLOT_CHANGED==0)); then
                continue # not of interest
            fi
            # OK we have a slot and/or subslot change; look for revdeps
            # of interest in the package database (/var/db/pkg)
            # we always look in RDEPEND, but only in DEPEND
            # if --with-bdeps=y specified (default)
            # PDEPEND ignored for now, not sure what a
            # rebuild-triggering slot dep here would even mean ><
            local DEPSPEC
            if ((ARG_WITH_BDEPS==0)); then
                DEPSPEC="-name RDEPEND"
            else
                DEPSPEC="-name DEPEND -o -name RDEPEND"
            fi
            # force a rebuild for anything whose deps record it as having a
            # :<SUP>/<SUB>= slot dependency (on the _current_ target
            # package's slot, that is)
            local FQAS_WITH_DEPS
            local NEXTLINE NEXTFQA NEXTRDEP
            local -i NEXTIX
            local NEXTCATEGORY NEXTPN
            local NEXTSUPSLOT NEXTSUBSLOT
            local NEXTPKG="${ALL_CATEGORY[${I}]}/${ALL_PN[${I}]}"
            show "Looking for ${NEXTPKG} in ${DEPSPEC}"
            if FQAS_WITH_DEPS="$(find "${PKGDB}" -type f \( ${DEPSPEC} \) -exec grep -o "${NEXTPKG}[^><=~!:[:blank:]]*:\(${ALL_CURR_SUPSLOT[${I}]}\)/\(\1\|${ALL_CURR_SUBSLOT[${I}]}\)=" {} +)"; then
                echo "${FQAS_WITH_DEPS}"
                while read -r NEXTLINE; do
                    # extract FQA from path
                    NEXTFQA="${NEXTLINE#${PKGDB}/}"
                    NEXTFQA="${NEXTFQA%%/RDEPEND:*}"
                    NEXTRDEP="${NEXTLINE#*:}"
                    # parse out the reverse dependency, so we can check it
                    if [[ "${NEXTRDEP}" =~ ^([^/]+)/(([0-9A-Za-z_+\-]+)(-((([0-9.]+[0-9A-Za-z]?)(((_alpha|_beta|_pre|_rc|_p)[0-9]*)*))(-r[^:]+)?))?):([^:/]+)/([^:\[]+)=(.*)$ ]]; then
                        NEXTCATEGORY="${BASH_REMATCH[1]}"
                        NEXTPN="${BASH_REMATCH[3]}"
                        NEXTSUPSLOT="${BASH_REMATCH[12]}"
                        NEXTSUBSLOT="${BASH_REMATCH[13]}"
                        # now check we haven't accidentally got a partial prefix
                        # match on the name etc.
                        if [[ "${NEXTCATEGORY}/${NEXTPN}" != "${NEXTPKG}" ]]; then
                            continue # false positive (sys-apps/foo matching sys-apps/fo etc)
                        fi
                        # rebuild needed
                        # so, if this FQA is in our full list, mark it for rebuild
                        # if absent, no problem (maybe it is getting deleted)
                        if [[ ${FQA_TO_IX["${NEXTFQA}"]+_} ]]; then
                            NEXTIX=${FQA_TO_IX["${NEXTFQA}"]}
                            if ((ALL_BUILD[NEXTIX]==0 && ALL_MASK[NEXTIX]==0)); then
                                show "Forcing rebuild for: ${ALL_FQA[${NEXTIX}]}"
                                ALL_BUILD[NEXTIX]=1
                                NUM_TO_BUILD=$((NUM_TO_BUILD+1))
                            fi
                        fi

                    else
                        warning "Failed to parse '${NEXTRDEP}'"
                    fi
                done <<<"${FQAS_WITH_DEPS}"
            else
                show "No rdeps found"
            fi
        done
        show "After third pass, ${NUM_TO_BUILD} of ${NUM_ATOMS} packages marked for build"
    fi

    # make the final list of FQAs that can be passed to the 'real' emerge
    for ((I=0;I<NUM_ATOMS;I++)); do
        if ((ALL_BUILD[I]==1)); then
            if [[ -z "${BUILD_FQAS}" ]]; then
                BUILD_FQAS="=${ALL_FQA[${I}]}"
            else
                BUILD_FQAS+=" =${ALL_FQA[${I}]}"
            fi
        fi
    done

    FILTRATION_DONE_SECS="${SECONDS}"
    FILTRATION_ELAPSED_SECS=$((FILTRATION_DONE_SECS - EMPTYTREE_DONE_SECS))

    if ((ARG_DEBUG==1 && NUM_TO_BUILD>0)); then
        show "Retained packages are (in order, mask flag omitted):"
        for ((I=0;I<NUM_ATOMS;I++)); do
            if ((ALL_BUILD[I]==1)); then
                echo "  ${ALL_EMTYPE[${I}]}, ${ALL_EMFLAGS[${I}]}, ${ALL_FQA[${I}]}, ${ALL_TAIL[${I}]}"
            fi
        done
    fi
    if ((NUM_TO_BUILD>0)); then
        if ((NUM_TO_BUILD==1)); then
            show "After filtration, 1 package is retained"
        else
            show "After filtration, $((NUM_TO_BUILD)) packages are retained"
        fi
    else
        show "No retained packages!"
    fi
    show "Phase completed in $((FILTRATION_ELAPSED_SECS))s"
    show
}
optionally_crosscheck_package_list() {
    # phase 3 of the process: perform an old-school baseline emerge
    # and compare it with the result of a non-deep emerge of the
    # FQA list from phase 2; report any errors and calculate
    # comparative timings, for benchmarking purposes
    #
    # see the top-of-file "ALGORITHM" text for more details
    # of the process followed
    if ((ARG_CROSSCHECK==0)); then
        CROSSCHECK_DONE_SECS=$((FILTRATION_DONE_SECS))
        return
    fi
    show "Computing, as a cross-check, desired package list from:"
    show "  emerge --with-bdeps=${BDEPS_FLAG} --pretend --deep --update ${USEOPT} ${EMERGEARGS}${EMERGEARGS:+ }${TARGETSET}"
    show "Please wait..."
    # assume same 'real' emerge args as us, but don't pass on
    # --verbose, and force --pretend
    CROSSCHECK_OUTPUT="$(emerge --with-bdeps=${BDEPS_FLAG} --pretend --deep --update ${USEOPT} ${EMERGEARGS} ${TARGETSET} 2>/dev/null | grep -oP "^\[[^\]]+\][[:blank:]]+[^[:blank:]]+")"
    CROSSCHECK_DEEP_DONE_SECS="${SECONDS}"
    CROSSCHECK_DEEP_ELAPSED_SECS=$((CROSSCHECK_DEEP_DONE_SECS - FILTRATION_DONE_SECS))
    show "Subphase completed in $((CROSSCHECK_DEEP_ELAPSED_SECS))s"

    show "Computing final desired package list from:"
    show "  emerge --oneshot --pretend  ${EMERGEARGS}${EMERGEARGS:+ }<filtered-package-list>"
    show "Please wait..."
    ONESHOT_OUTPUT="$(emerge --oneshot --pretend ${EMERGEARGS} ${BUILD_FQAS} 2>/dev/null | grep -oP "^\[[^\]]+\][[:blank:]]+[^[:blank:]]+")"
    CROSSCHECK_LIST_DONE_SECS="${SECONDS}"
    CROSSCHECK_LIST_ELAPSED_SECS=$((CROSSCHECK_LIST_DONE_SECS - CROSSCHECK_DEEP_DONE_SECS))
    show "Subphase completed in $((CROSSCHECK_LIST_ELAPSED_SECS))s"

    # now filter the crosscheck output, so it is just fully-qualified
    # atoms
    CROSSCHECK_OUTPUT="$(sed -e 's/^\[.*\][[:blank:]]*//g' <<<${CROSSCHECK_OUTPUT})"
    ONESHOT_OUTPUT="$(sed -e 's/^\[.*\][[:blank:]]*//g' <<<${ONESHOT_OUTPUT})"

    local -i DURATION=$((CROSSCHECK_DONE_SECS - EMERGE_DONE_SECS))
    if ((ARG_DEBUG==1)); then
        local NEXTLINE
        show "Crosscheck output from --pretend --deep ${USEOPT} ${TARGETSET} emerge is:"
        while read -r NEXTLINE; do
            echo "  ${NEXTLINE}"
        done <<<"${CROSSCHECK_OUTPUT}"
        show "While output from --pretend ${USEOPT} <filtered-pkg-list> emerge is:"
        while read -r NEXTLINE; do
            echo "  ${NEXTLINE}"
        done <<<"${ONESHOT_OUTPUT}"
    fi
    # we sort the output as non-dependent nodes of the graph can end
    # up in a random order wrt each other
    # essentially, we're trusting that the --emptytree emerge has got
    # overall ordering down correctly here

    show "Diff between --deep ${TARGETSET} and <filtered-pkg-list> sorted emerge lists:"
    if diff <(echo "${CROSSCHECK_OUTPUT}" | sort) <(echo "${ONESHOT_OUTPUT}" | sort); then
        show "  empty: lists are identical!"
        show "Crosscheck PASSED."
    else
        if ((ARG_STRICT_CROSSCHECK==1)); then
            die "Lists do not match!"
        else
            warning "Lists do not match!"
            warning "Crosscheck FAILED."
        fi
    fi
    CROSSCHECK_DONE_SECS="${SECONDS}"
    CROSSCHECK_ELAPSED_SECS=$((CROSSCHECK_DONE_SECS - FILTRATION_DONE_SECS))
    MT_EQUIVALENT_ELAPSED_SECS=$((EMPTYTREE_ELAPSED_SECS + FILTRATION_ELAPSED_SECS + CROSSCHECK_LIST_ELAPSED_SECS))
    show "Comparative net emerge --pretend time costs:"
    show "  baseline: ${CROSSCHECK_DEEP_ELAPSED_SECS}s (traditional emerge --with-bdeps=${BDEPS_FLAG} -Du${SHORTUSEOPT}p ${TARGETSET})"
    show "  ${PROGNAME}:  ${MT_EQUIVALENT_ELAPSED_SECS}s = ${EMPTYTREE_ELAPSED_SECS}s (emptytree) + ${FILTRATION_ELAPSED_SECS}s (filter) + ${CROSSCHECK_LIST_ELAPSED_SECS}s (list emerge)"
    show "Phase completed in $((CROSSCHECK_ELAPSED_SECS))s"
    show
}
perform_itemized_emerge() {
    # phase 4 of the process: now we can actually emerge the filtered
    # FQA list; yes, this *will* involve another dependency check, but:
    # * it'll be a lot faster since the list is, hopefully,
    # * (relatively) short and fully versioned; and
    # * doing things this way (and not via e.g. emerge --nodeps) has
    #   some significant advantages, in that it will:
    #   1. deal with blocks / uninstalls correctly
    #   2. add in slot-change rebuilds automatically, and
    #   3. permit job parallelism (where enabled via EMERGE_DEFAULT_OPTS)
    #
    # if --full-build-fallback-threshold=N / -f N is set, and >=N FQAs are carried
    # forward into this phase 4, then the emerge will first be
    # dry-run, and if that _fails_ (indicating usually a stubborn
    # blocker caused by e.g. a slot change in a low-level library with
    # lots of deps) then a _full_ emptytree @world emerge will be
    # triggered instead; this provides a failsafe for most
    # cases
    #
    # also, if --extreme / -x is set, then emerge --depclean will be
    # run at the (successful) conclusion of the emerge, to leave
    # the system in a consistent state

    declare -i TRY_STANDARD_EMERGE=1

    if ((NUM_TO_BUILD>0)); then
        if ((FALLBACK_THRESHOLD>0 && NUM_TO_BUILD>=FALLBACK_THRESHOLD)); then
            show "Fallback threshold met, validating phase 4 build list..."
            show "(this may take some time)"
            if emerge --oneshot --pretend ${EMERGEARGS} ${BUILD_FQAS} &>/dev/null; then
                show "Build list validated!"
            else
                warning "NOT valid; initiating full --emptytree @world emerge"
                # fallback
                TRY_STANDARD_EMERGE=0
                emerge ${ASKFLAG} ${ALERTFLAG} ${VERBOSITYFLAG} ${PRETENDFLAG} \
                       --emptytree @world
                show "Full emerge successful!"
                show "Removing packages not required by @world set..."
                emerge ${ASKFLAG} ${ALERTFLAG} ${VERBOSITYFLAG} ${PRETENDFLAG} --depclean
                # write a sentinel to show other programs (e.g. genup) that we got here
                touch "${FALLBACK_SENTINEL}"
            fi
        fi
        if ((TRY_STANDARD_EMERGE==1)); then
            if ((ARG_DEBUG==1)); then
                show "Issuing:"
                echo "  emerge --oneshot ${ASKFLAG} ${ALERTFLAG} ${VERBOSITYFLAG} ${PRETENDFLAG} --keep-going=${KEEP_GOING_FLAG} ${EMERGEARGS} ${BUILD_FQAS}"
            fi
            emerge --oneshot ${ASKFLAG} ${ALERTFLAG} ${VERBOSITYFLAG} ${PRETENDFLAG} \
                   --keep-going=${KEEP_GOING_FLAG} ${EMERGEARGS} ${BUILD_FQAS}
        fi
    else
        show "Nothing to emerge!"
    fi
    EMERGE_DONE_SECS="${SECONDS}"
    EMERGE_ELAPSED_SECS=$((EMERGE_DONE_SECS - CROSSCHECK_DONE_SECS))
    show "Phase completed in $((EMERGE_ELAPSED_SECS))s"
    show
}
remove_fallback_sentinel() {
    # remove marker that successful full emerge has taken place
    rm -f "${FALLBACK_SENTINEL}"
}

# *************** start of script proper ***************
remove_fallback_sentinel
suppress_colour_and_alert_if_output_not_to_a_terminal
process_command_line_options "${@}"
display_greeting
compute_emptytree_package_list
filter_package_list
optionally_crosscheck_package_list
perform_itemized_emerge
display_final_status
cleanup_and_exit_with_code 0
# **************** end of script proper ****************
