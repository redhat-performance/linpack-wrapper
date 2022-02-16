#! /bin/sh
threads=1
interleave=all
while getopts "t:n:" opt; do
        case ${opt} in
		t)
			threads=${OPTARG};
		;;
		n)
			interleave=${OPTARG}
		;;
	esac
done

export OMP_NUM_THREADS=$threads

uname -v | grep Ubuntu > /dev/null
if [ $? -eq 0 ]; then
	./xlinpack_xeon64 < ./linpack.dat
else
	numactl --interleave=${interleave} ./xlinpack_xeon64 < ./linpack.dat
fi

