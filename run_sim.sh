#!/bin/bash

# set paths for ATTPCROOT and Automation scripts
attpcroot_dir=/mnt/analysis/e17023/Adam/ATTPCROOTv2/
automation_dir=/mnt/analysis/e17023/Adam/GADGET2/

# start timer
start=`date +%s`
iterations=0

# load prerequisites
cd $attpcroot_dir
source env_fishtank.sh
module load fairroot/18.6.3

while true; do
	# modify parameters and rename old h5
	cd $automation_dir"simInput/"
    echo "Modifying parameters"
	python3 iter.py

    if [ -f $automation_dir"STOP.csv" ]; then
        # Delete STOP.csv and break loop
        echo "STOP.csv found, stopping Loop"
        rm $automation_dir"STOP.csv"
        
        # zip output
        #zip -r $automation_dir"output.zip" $automation_dir"simOutput/" $automation_dir"simInput/parameters.csv"
        break
    else
        if [ -f $automation_dir"BUILD.csv" ]; then
            # Delete BUILD.csv
            echo "BUILD.csv found, rebuilding ATTPCROOT"
            rm $automation_dir"BUILD.csv"

            # build ATTPCROOT
            cd $attpcroot_dir"build/"
            make -j8

            # build ROOT2HDF
            cd $attpcroot_dir"compiled/ROOT2HDF/build/"
            make
        fi

        # copy simulation files
        rm $attpcroot_dir"macro/Simulation/GADGET/Mg20_test_sim.C"
        cp $automation_dir"simInput/Mg20_test_sim.txt" $attpcroot_dir"macro/Simulation/GADGET/Mg20_test_sim.C"
        
        # run simulation
        cd $attpcroot_dir"macro/Simulation/GADGET/"
        
        echo "Mg20_test_sim.C"
        nohup root -b -l Mg20_test_sim.C &
        pid1=$!
        wait $pid1
        
        echo "rundigi_sim.C"
        nohup root -b -l rundigi_sim.C &
        pid2=$!
        wait $pid2

        # convert root files to h5
        cd $attpcroot_dir"compiled/ROOT2HDF/build/"
        echo "Converting root files to h5"
        ./R2HExe output_digi.root

        mv output.h5 $automation_dir"simOutput/output.h5"
        ((iterations++))
    fi

end=`date +%s`
runtime=$((end-start))
echo "Runtime: $runtime"
echo "Number of Simulations: $iterations"
done