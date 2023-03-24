#!/bin/bash
set -x
set -e

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <abs remote path of bitstream> <serverid, e.g. '1 2 3 4'>" >&2
  exit 1
fi

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DRIVER_REMOTE_PATH=/mnt/scratch/runshi/coyote_drv.ko

# Args
FPGA_BIT_PATH=$1
echo Bitsteam path: $FPGA_BIT_PATH
# server IDs of u55c.
SERVID=$2

USER=''
if [ -z "$3" ] 
then
	USER='honghe'
    echo "No user specified (default: 'honghe')"
else
	USER=$3
fi

# generate host name list
for servid in ${SERVID[@]}; do 
	hostlist+="$USER@alveo-u55c-$(printf "%02d" $servid) "
done

FPGAMAC0=(000A350B22D8 000A350B22E8 000A350B2340 000A350B24D8 000A350B23B8 000A350B2448 000A350B2520 000A350B2608 000A350B2498 000A350B2528)
FPGAMAC1=(000A350B22DC 000A350B22EC 000A350B2344 000A350B24DC 000A350B23BC 000A350B244C 000A350B2524 000A350B260C 000A350B249C 000A350B252C)
FPGAIP0=(0afd4a44 0afd4a48 0afd4a4c 0afd4a50 0afd4a54 0afd4a58 0afd4a5c 0afd4a60 0afd4a64 0afd4a68)
FPGAIP1=(0afd4a45 0afd4a49 0afd4a4d 0afd4a51 0afd4a55 0afd4a59 0afd4a5d 0afd4a61 0afd4a65 0afd4a69)

# STEP1: Program FPGA
# activate servers (login with passwd/public key to enable the nfs home mounting)
echo "Activating server..."
pssh -H "$hostlist" -O PreferredAuthentications=publickey "echo Login success!"
echo "Targeting hosts: $hostlist"
echo "Programming FPGA..."
pssh -H "$hostlist" -x '-tt' "/mnt/scratch/runshi/tools/sguitl_vivado -b $FPGA_BIT_PATH"
echo "Removing the driver if exist..."
pssh -H "$hostlist" -x '-tt' "if lsmod | grep -wq coyote_drv; then sudo rmmod coyote_drv; fi"
echo "PCIe hot reseting..."
pssh -H "$hostlist" -x '-tt' "/opt/cli/sgutil program rescan"

# STEP2: Hot reset
# put -x '-tt' (pseudo terminal) here for sudo command
echo "Loading driver..."
for servid in ${SERVID[@]}; do
	boardidx=$(expr $servid)
	pssh -H "$USER@alveo-u55c-$(printf "%02d" $servid)" -x '-tt' "sudo insmod $DRIVER_REMOTE_PATH ip_addr_q0=${FPGAIP0[boardidx]} ip_addr_q1=${FPGAIP1[boardidx]} mac_addr_q0=${FPGAMAC0[boardidx]} mac_addr_q1=${FPGAMAC1[boardidx]}"
done
pssh -H "$hostlist" -x '-tt' "sudo /opt/cli/program/fpga_chmod 0"
echo "Driver loaded."

exit 0