#!/bin/bash

# start timer
start=`date +%s`
iterations=0

# load prerequisites
cd /mnt/analysis/e17023/Adam/ATTPCROOTv2/
source env_fishtank.sh
module load fairroot/18.6.3

while true; do
	# modify parameters and rename old h5
	cd /mnt/analysis/e17023/Adam/simInput/
    echo "Modifying parameters"
	python3 iter.py

    if [ -f /mnt/analysis/e17023/Adam/STOP.csv ]; then
        # Delete STOP.csv and break loop
        echo "STOP.csv found, stopping Loop"
        rm /mnt/analysis/e17023/Adam/STOP.csv
        
        # zip output
        zip -r /mnt/analysis/e17023/Adam/output.zip /mnt/analysis/e17023/Adam/simOutput/ /mnt/analysis/e17023/Adam/simInput/parameters.csv
        break
    else
        if [ -f /mnt/analysis/e17023/Adam/BUILD.csv ]; then
            # Delete BUILD.csv
            echo "BUILD.csv found, rebuilding ATTPCROOT"
            rm /mnt/analysis/e17023/Adam/BUILD.csv

            # build ATTPCROOT
            cd /mnt/analysis/e17023/Adam/ATTPCROOTv2/build/
            make -j8

            # build ROOT2HDF
            cd /mnt/analysis/e17023/Adam/ATTPCROOTv2/compiled/ROOT2HDF/build/
            make
        fi

        # copy simulation files
        rm /mnt/analysis/e17023/Adam/ATTPCROOTv2/macro/Simulation/GADGET/Mg20_test_sim.C
        cp /mnt/analysis/e17023/Adam/simInput/generators/Mg20_test_sim.txt /mnt/analysis/e17023/Adam/ATTPCROOTv2/macro/Simulation/GADGET/Mg20_test_sim.C
        
        # run simulation
        cd /mnt/analysis/e17023/Adam/ATTPCROOTv2/macro/Simulation/GADGET/
        
        echo "Mg20_test_sim.C"
        nohup root -b -l Mg20_test_sim.C &
        pid1=$!
        wait $pid1
        
        echo "rundigi_sim.C"
        nohup root -b -l rundigi_sim.C &
        pid2=$!
        wait $pid2

        # convert root files to h5
        cd /mnt/analysis/e17023/Adam/ATTPCROOTv2/compiled/ROOT2HDF/build/
        echo "Converting root files to h5"
        ./R2HExe output_digi.root

        mv output.h5 /mnt/analysis/e17023/Adam/simOutput/output.h5
        ((iterations++))
    fi

end=`date +%s`
runtime=$((end-start))
echo "Runtime: $runtime"
echo "Number of Simulations: $iterations"
done