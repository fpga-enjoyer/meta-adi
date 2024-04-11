#!/bin/bash

# Script used on Jenkins to build all the supported projects weekly
#
# SPDX-License-Identifier: MIT

set -xe

_docker() {
	docker run --rm -v ${WORKSPACE}:${WORKSPACE} -v /opt:/opt -v $PWD:$PWD \
			-v /shared/petalinux_dl_shared:/shared/petalinux_dl_shared \
			--workdir $PWD petalinux bash -c "$@"
}

get_hdl_artifact() {
	local base_path="https://artifactory.analog.com/artifactory/sdg-generic-development/hdl"
	local export_branch="releases/hdl_2022_r2"
	local hdl=""
	local l
	local folders=$(wget -q -O - "${base_path}/${export_branch}/hdl_output/" 2>/dev/null | grep -E '<a href=\"[0-9]+.*' | wc -l)

	# try to find the latest successful artifact
	for ((l=0; l<${folders}; l++)); do
		hdl=$(wget -q -O - "${base_path}/${export_branch}/hdl_output/" 2>/dev/null | grep -E '<a href=\"[0-9]+.*' | tail -$((l+1)) | head -1)
		hdl=${hdl##*'/">'}
		hdl=${hdl%%'/</a'*}
		# check if file exists
		[[ $(wget -S --spider "${base_path}/${export_branch}/hdl_output/${hdl}/${project}/system_top.xsa" 2>&1 | grep 'HTTP/1.1 200 OK') ]] && break
	done

	if [[ ${l} == ${folders} ]]; then
		echo "Could not find HDL artifact for: \"${project}\""
		exit 1
	fi

	echo "Get hdl artifacts from: ${base_path}/${export_branch}/hdl_output/${hdl}/${project}"
	wget --tries=10 ${base_path}/${export_branch}/hdl_output/${hdl}/${project}/system_top.xsa -O ${WORKSPACE}/system_top.xsa
}

project=$1
template=$2
dts=$3
PETALINUX="/opt/petalinux/2022.2"

# remove any possible leftover
rm -rf ${project}/
rm -f system_top.xsa

get_hdl_artifact

_docker "source ${PETALINUX}/settings.sh; petalinux-create -t project --template ${template} --name ${project}"
cd ${project}

echo "CONFIG_USER_LAYER_0=\"${WORKSPACE}/meta-adi/meta-adi-core\"" >> project-spec/configs/config
echo "CONFIG_USER_LAYER_1=\"${WORKSPACE}/meta-adi/meta-adi-xilinx\"" >> project-spec/configs/config
echo "KERNEL_DTB=\"${dts}\"" >> project-spec/meta-user/conf/petalinuxbsp.conf
echo "DL_DIR=\"/shared/petalinux_dl_shared/${PETALINUX##*/}\"" >> project-spec/meta-user/conf/petalinuxbsp.conf

# This is copied from
#	https://github.com/webOS-ports/jenkins-jobs/blob/75e65d15226f55fe8a72f81c4307d224efb75689/jenkins-job.sh#L230
# There were tries to make "*setscene" and sstate errors being treated as warnings in OE CORE but
# those patches were never merged. The reason for the errors is that bitbake thinks there's a sstate package but
# cannot fetch it (server temporary down) in which case it executes the real task. Long story short, as far as bitbake
# is concerned, this is a real error and the problem is likely on xilinx side in the handling of the sstate packages.
# As we cannot fix xilinx hosts, we need to workaround the problem (yes, it's ugly but it is what it is...).
_docker "source ${PETALINUX}/settings.sh; petalinux-config --get-hw-description=${WORKSPACE}/ --silentconfig; petalinux-build 2>&1" | tee bitbake.log
PETA_RETURN=${PIPESTATUS[0]}
if [ "${PETA_RETURN}" -ne 0 ] ; then
	if grep -E -q "Summary: There [was|were]+ .* ERROR message[s]?.*" bitbake.log; then
		ERRORS_FOUND=`grep -E "Summary: There [was|were]+ .* ERROR message[s]?.*" bitbake.log | sed 's/Summary: There .* \(.*\) ERROR .*/\1/g'`
		ERRORS_SETSCENE=`grep -c "^ERROR: .* do_.*_setscene: Fetcher failure: Unable to find file" bitbake.log || true`
		ERRORS_SETSCENE2=`grep -c "^ERROR: .* do_.*_setscene: No suitable staging package found" bitbake.log || true`
		ERRORS_SETSCENE3=`grep -c "^ERROR: .* do_.*_setscene: Error executing a python function in .*" bitbake.log || true`
		TOTAL_SETSCENE=`expr ${ERRORS_SETSCENE} + ${ERRORS_SETSCENE2} + ${ERRORS_SETSCENE3}`

		printf "There were a total of ${ERRORS_FOUND} ERROR messages... From which, these are setscene related:\n \
 * Fetcher failures: ${ERRORS_SETSCENE}\n \
 * No suitable package messages: ${ERRORS_SETSCENE2}\n \
 * Error executing a python function in exec_python_func() autogenerated: ${ERRORS_SETSCENE3}\n"

		if [ ${ERRORS_FOUND} -ne ${TOTAL_SETSCENE} ] ; then
			echo "There were some other kinds of ERROR messages will respect the return code from bitbake:"
			exit 1
		else
			echo "All reported errors were about setscene failing to fetch sstate, we're going to ignore bitbake return code"
		fi
	else
		# something else just error out
		exit 1
	fi
fi

if [ ${template} == "microblaze" ]; then
	mv images/linux/system.bit ${WORKSPACE}/
	mv images/linux/u-boot.elf ${WORKSPACE}/
	mv images/linux/image.elf  ${WORKSPACE}/
elif [ ${template} == "versal" ]; then
	_docker "source ${PETALINUX}/settings.sh; petalinux-package --boot --u-boot"
	mv images/linux/BOOT.BIN ${WORKSPACE}/
	mv images/linux/boot.scr ${WORKSPACE}/
else
	_docker "source ${PETALINUX}/settings.sh; petalinux-package --boot --fsbl --fpga --u-boot"
	mv images/linux/BOOT.BIN ${WORKSPACE}/
	mv images/linux/boot.scr ${WORKSPACE}/
fi

mv images/linux/image.ub ${WORKSPACE}/

cd -
rm -rf ${project}/
rm -rf meta-adi
rm -f system_top.xsa

