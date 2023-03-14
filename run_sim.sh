#!/bin/bash

# set paths for ATTPCROOT and Automation scripts
attpcroot_dir=/mnt/analysis/e17023/Adam/ATTPCROOTv2/
automation_dir=/mnt/analysis/e17023/Adam/GADGET2/

# start timer
start=`date +%s`
iterations=0

# mark if debug
debug=1

# load prerequisites
source $attpcroot_dir"env_fishtank.sh"
module load fairroot/18.6.3

while true; do
	# modify parameters and rename old h5
    echo "Modifying parameters"
	python3 $automation_dir"simInput/iter.py"

    if [ -f $automation_dir"STOP.csv" ]; then
        # Delete STOP.csv and break loop
        echo "STOP.csv found, stopping Loop"
        rm $automation_dir"STOP.csv"
        break
    else
        if [ -f $automation_dir"BUILD.csv" ]; then
            # Delete BUILD.csv
            echo "BUILD.csv found, rebuilding ATTPCROOT"
            rm $automation_dir"BUILD.csv"

            # build ATTPCROOT
            make -C $automation_dir"build/" -j8

            # build ROOT2HDF
            make -C $attpcroot_dir"compiled/ROOT2HDF/build/"
        fi

        # copy simulation files
        rm $attpcroot_dir"macro/Simulation/GADGET/Mg20_test_sim.C"
        cp $automation_dir"simInput/Mg20_test_sim.txt" $attpcroot_dir"macro/Simulation/GADGET/Mg20_test_sim.C"
        
        
        # run simulation        
        if [ $debug -eq 1 ]; then

            echo "Mg20_test_sim.C"
            root -b -l $attpcroot_dir"macro/Simulation/GADGET/Mg20_test_sim.C"
            echo "rundigi_sim.C"
            root -b -l $attpcroot_dir"macro/Simulation/GADGET/rundigi_sim.C"
        else
            echo "Mg20_test_sim.C"
            nohup root -b -l $attpcroot_dir"macro/Simulation/GADGET/Mg20_test_sim.C" &
            pid1=$!
            wait $pid1
            
            echo "rundigi_sim.C"
            nohup root -b -l $attpcroot_dir"macro/Simulation/GADGET/rundigi_sim.C" &
            pid2=$!
            wait $pid2
        fi

        # convert root files to h5
        echo "Converting root files to h5"
        ./$attpcroot_dir"compiled/ROOT2HDF/build/R2HExe" output_digi.root

        mv $attpcroot_dir"compiled/ROOT2HDF/build/output.h5" $automation_dir"simOutput/output.h5"
        ((iterations++))
    fi

end=`date +%s`
runtime=$((end-start))
echo "Runtime: $runtime"
echo "Number of Simulations: $iterations"
done