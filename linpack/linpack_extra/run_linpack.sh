#!/bin/bash
#
# Copyright (C) 2022  David Valin dvalin@redhat.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

max_threads=0
threads_to_do=0
iterations=5
threads_list=""
numb_hyper_mappings=0
cpus_non_hyper=""
cpus_hyper=""
config="config_none"
max_threads_to_run=0
tuned_config="none"
one_and_only_one=0
socket_stepping=1
interleave="all"
cpus_in_sock=""
GOMP_CPU_AFFINITY=""
NUMB_SOCKETS=""
reduce_only=0

if [[ -d linpack_results ]]; then
	rm -rf linpack_results
fi
mkdir linpack_results
out_dir=`pwd`/linpack_results

exit_out()
{
	echo $1
	exit $2
}

execute_hyper()
{
	nh_threads=0
	echo hyper threads
	echo First run just non hyper threads
	sockets=1
	hyper_config="hyper_yes_1_socket_nh"
	for cpus in $nhypcpus_in_sock; do
		# calculate how many threads per non hyper grouping
		if [ $nh_threads -eq 0 ]; then
			nh_threads=`grep -o ',' <<<"$cpus" | grep -c .`
			let "nh_threads=$nh_threads + 1"
			echo non hyper threads: $nh_threads
			max_threads_to_run=$nh_threads
			threads_to_do=$nh_threads
		fi
		echo "$cpus"
		GOMP_CPU_AFFINITY=`echo $cpus | cut -d',' -f 1-${threads_to_do}`
		max_threads_to_run=$threads_to_do
		execute_linpack
		if [ $one_and_only_one -eq 1 ]; then
			break
		fi
	done
# Now hyperthread/non hyperthread pairing.
	total_threads=0
	socket_index=0

	rm /tmp/socket_mappings 2> /dev/null
	grep "^HYPSOCKET" /tmp/hyperthreads  | cut -d ':' -f1 > /tmp/socket_info
	hcpus=`cat /tmp/socket_info`
	for cpus in $hcpus; do
		nhycpus=`grep ${cpus} /tmp/nhyperthreads | cut -d' ' -f2`
		hycpus=`grep ${cpus} /tmp/hyperthreads | cut -d' ' -f2`
		echo ${hycpus}","${nhycpus} >> /tmp/socket_mappings
	done
	socket_mappings=`cat /tmp/socket_mappings`
	sockets=1
	hyper_config="hyper_yes_1_socket_hyp"
	for cpu_list in $socket_mappings; do
		nh_threads=`grep -o ',' <<<"$cpu_list" | grep -c .`
		let "nh_threads=$nh_threads+1"
		max_threads_to_run=$nh_threads
		threads_to_do=$nh_threads
		GOMP_CPU_AFFINITY=`echo $cpu_list | cut -d',' -f 1-${threads_to_do}`
		echo $GOMP_CPU_AFFINITY
		execute_linpack
	done
	sockets=0
	for cpu_list in $socket_mappings; do
		if [ $sockets -eq 0 ]; then
			worker=$cpu_list
			let "sockets=$sockets + 1"
		else
			let "sockets=$sockets + 1"
			let "threads_to_do=$threads_to_do_per_socket * $sockets"
			hyper_config="hyper_yes_${sockets}_socket_hyp"
			worker1=`echo $cpu_list | cut -d',' -f 1-${threads_to_do}`
			worker=${worker}","${worker1}
			GOMP_CPU_AFFINITY=`echo $worker | cut -d',' -f 1-${threads_to_do}`
			echo $GOMP_CPU_AFFINITY
			max_threads_to_run=$threads_to_do
			execute_linpack
		fi
	done
}

execute_non_hyper()
{
	# single socket execution
	hyper_config="hyper_no"
	echo No hyper threads configured
	echo All we do is run the whole cores. 
	max_threads_to_run=$threads_to_do
	sockets=1
	for cpus in $cpus_in_sock; do
		echo "$cpus"
		GOMP_CPU_AFFINITY=`echo $cpus | cut -d',' -f 1-${max_threads_to_run}`
		execute_linpack
		if [ $one_and_only_one -eq 1 ]; then
			break
		fi
	done
	# now do increasing sockets
	# socket groupings now.

	if  [ $NUMB_SOCKETS -gt 1 ]; then
		sockets=0
		for cpus in $cpus_in_sock; do
			if [ $sockets == 0 ]; then
				GOMP_CPU_AFFINITY=$cpus
				let "sockets=$sockets+1"
			else
				let "sockets=$sockets+1"
				let "max_threads_to_run=$threads_to_do*$sockets"
				GOMP_CPU_AFFINITY=${GOMP_CPU_AFFINITY},${cpus}
				if [ $socket_stepping -ne 1 ]; then
					if [ $next_sockets -lt $sockets ]; then
						if [ $sockets -lt $NUMB_SOCKETS ]; then
							continue
						fi
					fi
				fi
				export GOMP_CPU_AFFINITY
				echo $GOMP_CPU_AFFINITY
				execute_linpack
				let "next_sockets=$socket_stepping+$sockets"
			fi
		done
	fi
}

process_summary()
{
	pwd
	test_results="Failed"
	rdir=`ls -d results_linpack_* | grep -v tar | tail -1`
	pushd $rdir
	#
	# We will over write this
	#
	echo Failed > test_results_report
	ls | cut -d'.' -f1-5 | sort -u > /tmp/linpack_temp
	iters=0
	input="/tmp/linpack_temp"
	test_name="linpack"

	echo hyper_config:sockets:threads:unit:"MB/sec:cpu_affin" > results_${test_name}.csv

	while IFS= read -r lin_file
	do
		ls  ${lin_file}* > /tmp/linpack_files_iter
		input1="/tmp/linpack_files_iter"
		iters=0
		sum=0
#linpack.20k.out.test_m5.xlarge_threads_1_sockets_1_hyper_no.iter_1
		threads=`echo $lin_file | cut -d'_' -f 4`
		sockets=`echo $lin_file | cut -d'_' -f 6`
		hyper_setting=`echo $lin_file | cut -d'_' -f7-10 | cut -d'.' -f 1`
		have_cpus=0
		cpu_affin="None"
		avg=""
		while IFS= read -r res_file
		do
			input2=$res_file
			next_line=0
			while IFS= read -r data
			do
				if [[ $have_cpus == "0" ]]; then
					have_cpus=1
					cpu_affin=`echo $data | cut -d' ' -f3`
				fi
				if [[ $data == *"Size"* ]]; then
					unit=`echo $data | cut -d' ' -f 5`
					# We want the next line.
					next_line=1
					continue
				fi
				if [[ $next_line == "1" ]]; then
					temp=`echo $data | cut -d' ' -f5`
					value=`echo "${sum} + ${temp}" | bc`
					sum=$value
					let "iters=$iters+1"
					break;
				fi
			done < "$input2"
			if [ $iters -ne 0 ]; then
				avg=`echo $sum / $iters | bc`
			fi
		done < "$input1"
		if [[ $avg  != "" ]]; then
			test_results="Ran"
			echo $hyper_setting:$sockets:$threads:$unit:$avg:$cpu_affin >> results_${test_name}.csv
		fi
	done < "$input"
	echo results at >> /tmp/dvalin_linpack
	pwd >> /tmp/dvalin_linpack

	echo $test_results > test_results_report
	cp results_${test_name}.csv test_results_report $out_dir
	popd
}

execute_linpack()
{
	export OMP_NUM_THREADS=$(( ${max_threads_to_run}))
	echo CPU affinity $GOMP_CPU_AFFINITY
 	for iter in `seq 1 $iterations`
	do
		out_file=results_linpack_${tuned_config}_numa_interleave_${interleave}/linpack.out.${PREFIX}_${config}_threads_${OMP_NUM_THREADS}_sockets_${sockets}_${hyper_config}_${tuned_config}_numa_interleave_${interleave}.iter_${iter}
		echo CPU Affinity: $GOMP_CPU_AFFINITY > $out_file
		echo ./runN.sh -n $interleave -t ${OMP_NUM_THREADS} >> $out_file
		./runN.sh -n $interleave -t ${OMP_NUM_THREADS} >> $out_file
		if [ $? -ne 0 ]; then
			exit_out "linpack execution failed 1" 1
		fi
	done
}

usage()
{
	echo "Usage:"
	echo "  -C config: designate the congiruation"
	echo "  -c: show config"
	echo "  -f: full run"
	echo "  -h: home parent directory"
	echo "  -i: value: number of iterationsto run"
	echo "  -n: numactl interleave"
	echo "  -s: sanity run"
	echo "  -t: max threads: maximum number of threads"
	exit 1
}

show_config=0

while getopts "RC:ci:t:h:P:s:u:oS:n:" opt; do
	case ${opt} in
		C)
			config=${OPTARG}
		;;
		c)
			show_config=1
		;;
		h)
			home=${OPTARG}
		;;
		i)
			iterations=${OPTARG}
		;;
		n)
			interleave=${OPTARG}
		;;
		o)
			one_and_only_one=1
		;;
		P)
			tuned_config=${OPTARG}
		;;
		R)
			reduce_only=1
		;;
		t)
			threads_list=${OPTARG}
		;;
		S)
			socket_stepping=${OPTARG}
		;;
		s)
			sysname=${OPTARG}
		;;
		u)
			user=${OPTARG}
		;;
		*)
			echo "Invalid option: $OPTARG requires an argument" 1>&2
			usage
		;;
	esac
done
shift $((OPTIND -1))

if [ $reduce_only -eq 1 ]; then
	pushd /tmp
	process_summary
	popd
	exit 0
fi

PREFIX=test
./core_info > /tmp/core_info
NUMB_CPUS=`grep "numb_cpus:" /tmp/core_info | cut -d: -f 2`
CORES_PER_SOCKET=`grep "cores_per_socket" /tmp/core_info | cut -d: -f 2`
THREADS_PER_CORE=`grep "threads_per_core" /tmp/core_info | cut -d: -f 2`
export NUMB_SOCKETS=`grep "numb_sockets" /tmp/core_info | cut -d: -f 2`

echo THREADS_PER_CORE $THREADS_PER_CORE

# Hypertheads
grep "^HYPSOCKET" /tmp/core_info > /tmp/hyperthreads
# Non hyperthreads
grep "^NHYPSOCKET" /tmp/core_info > /tmp/nhyperthreads

#
# Set up the core pairings
#

# 
# Determine if hyperthreading is in use, and set appropriate
# values.
#

hypcnt=`wc -l /tmp/hyperthreads | cut -d' ' -f 1` 

index=0
if [ $hypcnt -eq 0 ]; then
	echo No hyper threads
	rm /tmp/cpus_in_sock 2> /dev/null

	grep "^SOCKET" /tmp/core_info | cut -d ' ' -f2 > /tmp/socket_info
	cpus_in_sock=`cat /tmp/socket_info`
	for cpus in $cpus_in_sock; do
		echo "$cpus"
	done
else
	echo Hyper threads
	grep "^HYPSOCKET" /tmp/hyperthreads  | cut -d ' ' -f2 > /tmp/socket_info
	hypcpus_in_sock=`cat /tmp/socket_info`
	for cpus in $hypcpus_in_sock; do
		echo "$cpus"
	done
	echo Non hyper threads
	grep "^NHYPSOCKET" /tmp/nhyperthreads  | cut -d ' ' -f2 > /tmp/socket_info
	nhypcpus_in_sock=`cat /tmp/socket_info`
	for cpus in $nhypcpus_in_sock; do
		echo "$cpus"
	done
fi

#
# If threads are not provided, then $CORES_PER_SOCKET * $THREADS_PER_CORE
#
if [ $threads_to_do -gt 0 ]; then
	threads_to_do=$max_thread
else
	let "threads_to_do=$CORES_PER_SOCKET * $THREADS_PER_CORE"
fi

#
# If we requested to show the system configuration, do so.
#
if [ $show_config -gt 0 ]; then
	echo number cpus: $NUMB_CPUS
	echo cores per socket: $CORES_PER_SOCKET
	echo number_sockets: $NUMB_SOCKETS
	echo threads per core: $THREADS_PER_CORE
	echo cpu socket assignment
	max_socket=$NUMB_SOCKETS
	((max_socket--))
	if [ -z "$hyper" ]; then
		echo No hyperthreading
		for socket in 0 `seq 1 1 $max_socket`
		do
			echo socket: $socket: ${cpus_in_sock[$socket]}
		done
	fi
	exit 0
fi


threads_to_do_per_socket=$threads_to_do
mkdir results_linpack_${tuned_config}_numa_interleave_${interleave}
if [ $hypcnt -eq 0 ]; then
	execute_non_hyper
else
	execute_hyper
fi

process_summary
exit 0
