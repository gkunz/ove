#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# MIT License
#
# Copyright (c) 2021 Ericsson
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is furnished
# to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice (including the next
# paragraph) shall be included in all copies or substantial portions of the
# Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
# FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS
# OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF
# OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


function _echo {
	if [[ ${OVE_DISTROCHECK_STEPS} == *verbose* ]]; then
		ove-echo stderr "$*"
	fi

	return 0
}

function init {
	local s

	if ! command -v lxc > /dev/null; then
		echo "error: lxc missing"
		exit 1
	elif [ $# -ne 2 ]; then
		echo "usage: $(basename "$0") file|project|unittest distro"
		exit 1
	fi

	if [ "$1" = "unittest" ]; then
		unittest=1
	else
		unittest=0
		distcheck="$1"
	fi

	if [ -t 1 ]; then
		bash_opt="-i"
		lxc_opt="-t"
	fi

	distro="$2"

	if [ ! -v OVE_DISTROCHECK_STEPS ]; then
		OVE_DISTROCHECK_STEPS="sleep"
	fi

	if [[ ${OVE_DISTROCHECK_STEPS} == *verbose* ]]; then
		for s in ${OVE_DISTROCHECK_STEPS//:/ };do
			echo $s
		done
	fi

	trap cleanup EXIT
}

function run {
	_echo "[${distro}]$ $*"
	if ! eval "$@"; then
		_echo "error: '$*' failed for distro '${distro}'"
		exit 1
	fi
}

function run_no_exit {
	_echo "[${distro}]$ $*"
	if ! eval "$@"; then
		_echo "warning: '$*' failed for distro ${distro}"
	fi
}

function lxc_command {
	if ! lxc exec "${lxc_name}" -- sh -c "command -v $1" &> /dev/null; then
		return 1
	else
		return 0
	fi
}

function lxc_exec {
	local e
	local lxc_exec_options

	lxc_exec_options="${lxc_opt} --env DEBIAN_FRONTEND=noninteractive"
	for e in ftp_proxy http_proxy https_proxy; do
		if [ "x${!e}" = "x" ]; then
			continue
		fi
		lxc_exec_options+=" --env ${e}=${!e}"
	done

	if [ "x$LXC_EXEC_EXTRA" != "x" ]; then
		lxc_exec_options+=" $LXC_EXEC_EXTRA"
	fi

	run "lxc exec ${lxc_exec_options} ${lxc_name} -- $*"
}

function package_manager_noconfirm {
	lxc_exec "bash -c ${bash_opt} '${prefix}; ove add-config \$HOME/.oveconfig OVE_INSTALL_PKG 1'"

	if [[ ${package_manager} == apt-get* ]];  then
		lxc_exec "bash -c ${bash_opt} '${prefix}; ove add-config \$HOME/.oveconfig OVE_OS_PACKAGE_MANAGER_ARGS -y -qq -o=Dpkg::Progress=0 -o=Dpkg::Progress-Fancy=false install'"
	elif [[ ${package_manager} == pacman* ]]; then
		lxc_exec "bash -c ${bash_opt} '${prefix}; ove add-config \$HOME/.oveconfig OVE_OS_PACKAGE_MANAGER_ARGS -S --noconfirm --noprogressbar'"
	elif [[ ${package_manager} == xbps-install* ]]; then
		lxc_exec "bash -c ${bash_opt} '${prefix}; ove add-config \$HOME/.oveconfig OVE_OS_PACKAGE_MANAGER xbps-install -y'"
	elif [[ ${package_manager} == zypper* ]]; then
		lxc_exec "bash -c ${bash_opt} '${prefix}; ove add-config \$HOME/.oveconfig OVE_OS_PACKAGE_MANAGER_ARGS install -y'"
	elif [[ ${package_manager} == dnf* ]]; then
		lxc_exec "bash -c ${bash_opt} '${prefix}; ove add-config \$HOME/.oveconfig OVE_OS_PACKAGE_MANAGER_ARGS install -y'"
	elif [[ ${package_manager} == apk* ]]; then
		lxc_exec "bash -c ${bash_opt} '${prefix}; ove add-config \$HOME/.oveconfig OVE_OS_PACKAGE_MANAGER_ARGS add --no-progress -q'"
	fi
	lxc_exec "bash -c ${bash_opt} '${prefix}; ove config'"
}

lxc_name=""
function cleanup {
	if [[ ${OVE_DISTROCHECK_STEPS} == *running* ]]; then
		return
	fi
	run_no_exit "lxc stop ${lxc_name} --force"
	if [[ ${OVE_DISTROCHECK_STEPS} == *stopped* ]]; then
		return
	fi
	run_no_exit "lxc delete ${lxc_name} --force"
}

function main {
	local _home="/root"
	local ove_packs
	local package_manager
	local prefix="true"
	local tag
	local _uid=0

	init "$@"

	if [ "x${OVE_LAST_COMMAND}" != "x" ]; then
		# re-use date+time (ignore micro/nano) from OVE_LAST_COMMAND
		tag="${OVE_LAST_COMMAND##*/}"
		tag="${tag:0:18}"
	else
		tag="$(date '+%Y%m%d-%H%M%S%N')"
	fi

	lxc_name="${OVE_USER}-${tag}-${distro}"

	# replace slashes and dots
	lxc_name="${lxc_name//\//-}"
	lxc_name="${lxc_name//./-}"

	if [ ${#lxc_name} -gt 63 ]; then
		_echo "info: lxc name '${lxc_name}' tuncated"
		lxc_name=${lxc_name:0:63}
	fi

	if [[ ${distro} == *archlinux* ]] || [[ ${distro} == *fedora* ]]; then
		run "lxc launch images:${distro} -c security.nesting=true ${lxc_name} ${OVE_LXC_LAUNCH_EXTRA_ARGS//\#/ } > /dev/null"
	else
		run "lxc launch images:${distro} ${lxc_name} ${OVE_LXC_LAUNCH_EXTRA_ARGS//\#/ } > /dev/null"
	fi
	run "sleep 1"

	if [[ ${OVE_DISTROCHECK_STEPS} == *user* ]] && [ ${EUID} -ne 0 ]; then
		lxc_exec "useradd --shell /bin/bash -m -d ${HOME:?} ${OVE_USER:?}"
		_uid=$(lxc_exec "id -u ${OVE_USER}")
		_uid=${_uid/$'\r'/}
		_home=$HOME

		_echo "idmap"
		printf "uid %s $_uid\ngid %s $_uid" "$(id -u)" "$(id -g)" | \
			lxc config set "${lxc_name}" raw.idmap -

		_echo "user and sudo"
		echo "${OVE_USER} ALL=(ALL) NOPASSWD:ALL" > "$OVE_TMP/91-ove"
		run "lxc file push --uid 0 --gid 0 $OVE_TMP/91-ove ${lxc_name}/etc/sudoers.d/91-ove"

		run "lxc restart ${lxc_name}"
	fi

	if [[ ${OVE_DISTROCHECK_STEPS} == *sleep* ]]; then
		run "sleep 10"
	fi

	if [[ ${OVE_DISTROCHECK_STEPS} == *ove* ]]; then
		ove_packs="bash bzip2 git curl file binutils util-linux coreutils"
		if lxc_command "apk"; then
			package_manager="apk add --no-progress -q"
		elif lxc_command "pacman"; then
			package_manager="pacman -S --noconfirm -q --noprogressbar"
		elif lxc_command "apt-get"; then
			ove_packs+=" bsdmainutils procps"
			package_manager="apt-get -y -qq -o=Dpkg::Progress=0 -o=Dpkg::Progress-Fancy=false install"
			if [ -s "/etc/apt/apt.conf" ]; then
				run "lxc file push --uid 0 --gid 0 /etc/apt/apt.conf ${lxc_name}/etc/apt/apt.conf"
			fi
			lxc_exec "apt-get update"
		elif lxc_command "xbps-install"; then
			package_manager="xbps-install -y"
		elif lxc_command "dnf"; then
			package_manager="dnf install -y"
		elif lxc_command "zypper"; then
			package_manager="zypper install -y"
		else
			echo "error: unknown package manager for '${distro}'"
			exit 1
		fi

		# install OVE packages
		lxc_exec "${package_manager} ${ove_packs}"
	fi

	if [[ ${OVE_DISTROCHECK_STEPS} == *user* ]] && [ ${EUID} -ne 0 ]; then
		# from now on, run all lxc exec commands as user
		export LXC_EXEC_EXTRA="--user $_uid --env HOME=$HOME"
	fi

	# gitconfig
	if [ -s "${HOME}"/.gitconfig ]; then
		run "lxc file push --uid $_uid ${HOME}/.gitconfig ${lxc_name}${_home}/.gitconfig"
	fi

	if [[ ${OVE_DISTROCHECK_STEPS} == *ove* ]]; then
		if [[ ${OVE_DISTROCHECK_STEPS} == *user* ]]; then
			# expose OVE workspace to the container
			run "lxc config device add ${lxc_name} home disk source=${OVE_BASE_DIR} path=${OVE_BASE_DIR}"
			ws_name="${OVE_BASE_DIR}"
			prefix="cd ${ws_name}; source ove hush"
		else
			# search for a SETUP file
			if [ "${OVE_OWEL_DIR}" != "x" ] && [ -s "${OVE_OWEL_DIR}/SETUP" ]; then
				lxc_exec "bash -c '$(cat "${OVE_OWEL_DIR}"/SETUP)'"
				ws_name=$(lxc_exec "bash -c 'find -mindepth 2 -maxdepth 2 -name .owel' | cut -d/ -f2")
				if [ "x${ws_name}" = "x" ]; then
					echo "error: workspace name not found"
					exit 1
				fi
			else
				# fallback to ove-tutorial
				ws_name="distrocheck"
				lxc_exec "bash -c 'curl -sSL https://raw.githubusercontent.com/Ericsson/ove/master/setup | bash -s ${ws_name} https://github.com/Ericsson/ove-tutorial'"
			fi
			prefix="cd ${ws_name}; source ove hush"
		fi
	fi

	if [[ ${OVE_DISTROCHECK_STEPS} == *ove* ]]; then
		if [ ${unittest} -eq 1 ]; then
			lxc_exec "bash -c ${bash_opt} 'cd ${ws_name}; source ove'"
			lxc_exec "bash -c ${bash_opt} '${prefix}; ove env'"
			lxc_exec "bash -c ${bash_opt} '${prefix}; ove list-externals'"
			lxc_exec "bash -c ${bash_opt} '${prefix}; ove status'"
		fi

		package_manager_noconfirm
		if [[ ${distro} == *archlinux* ]]; then
			lxc_exec "sed -i 's|#en_US.UTF-8 UTF-8|en_US.UTF-8 UTF-8|g' /etc/locale.gen"
			lxc_exec "locale-gen"
		fi

		if [[ ${distro} == *opensuse* ]]; then
			lxc_exec "sudo zypper install -y -t pattern devel_basis"
		fi
	fi

	if [ ${unittest} -eq 1 ]; then
		lxc_exec "${package_manager} python3"
		if [[ ${distro} == *alpine* ]]; then
			lxc_exec "${package_manager} py3-yaml"
		elif [[ ${distro} == *archlinux* ]]; then
			lxc_exec "${package_manager} python-yaml"
		elif [[ ${distro} == *opensuse* ]]; then
			lxc_exec "${package_manager} python3-PyYAML"
		else
			lxc_exec "${package_manager} python3-yaml"
		fi

		if [[ ${distro} == *alpine* ]]; then
			lxc_exec "${package_manager} alpine-sdk cabal ghc libffi-dev"
		elif [[ ${distro} == *voidlinux* ]]; then
			lxc_exec "${package_manager} cabal-install ghc"
		else
			lxc_exec "${package_manager} cabal-install ghc happy"
		fi
		lxc_exec "cabal update --verbose=0"
		if [[ ${distro} == *archlinux* ]]; then
			lxc_exec "cabal install --verbose=0 --ghc-options=-dynamic shelltestrunner-1.9"
		else
			lxc_exec "cabal install --verbose=0 shelltestrunner-1.9"
		fi
		lxc_exec "bash -c ${bash_opt} '${prefix}; ove unittest'"
	fi

	if [ "x${distcheck}" != "x" ]; then
		if [[ ${OVE_DISTROCHECK_STEPS} == *ove* ]]; then
			packs=$(lxc_exec "bash -c ${bash_opt} '${prefix}; DEBIAN_FRONTEND=noninteractive ove list-needs $distcheck'")
			packs=${packs//$'\r'/ }
			packs=${packs//$'\n'/}
			if [ "$packs" != "" ]; then
				LXC_EXEC_EXTRA="--user 0" lxc_exec "${package_manager} ${packs}"
			fi
			lxc_exec "bash -c ${bash_opt} '${prefix}; OVE_AUTO_CLONE=1 ove distcheck $distcheck'"
		else
			if [ -s "${distcheck}" ]; then
				cp -a "${distcheck}" "${OVE_TMP}/${tag}.cmd"
			else
				echo "$distcheck" > "${OVE_TMP}/${tag}.cmd"
			fi
			chmod +x "${OVE_TMP}/${tag}.cmd"
			run "lxc file push --uid 0 --gid 0 ${OVE_TMP}/${tag}.cmd ${lxc_name}/tmp/${tag}.cmd"
			lxc_exec "/tmp/${tag}.cmd"
		fi
	fi
}

main "$@"
