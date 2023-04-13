#!/bin/bash

# set paths for ATTPCROOT and Automation scripts
attpcroot_dir=/mnt/analysis/e17023/Adam/ATTPCROOTv2/
automation_dir=/mnt/analysis/e17023/Adam/GADGET2/

# start timer
start=`date +%s`
iterations=0

# mark if debug mode
debug=0

# if debug, overwrite parameters with test parameters
if [ $debug -eq 1 ]; then
    echo "Debug mode, overwriting parameters file with test parameters"
    cp $automation_dir"simInput/test-parameters.csv" $automation_dir"simInput/parameters.csv"
fi

if [ $debug -eq 0 ]; then
    python3 $automation_dir"simInput/create-param.py"
fi

# load prerequisites
source $attpcroot_dir"env_fishtank.sh"
module load fairroot/18.6.3

cp -f $automation_dir"simInput/templates/R2HMain.cc" $attpcroot_dir"compiled/ROOT2HDF/R2HMain.cc"
cp -f $automation_dir"simInput/templates/R2HMain.hh" $attpcroot_dir"compiled/ROOT2HDF/R2HMain.hh"

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
        # MOVE QUEUED FILES TO SIMULATION FOLDER
        mv -f $automation_dir"simInput/queue/Mg20_test_sim.C" $attpcroot_dir"macro/Simulation/GADGET/Mg20_test_sim.C"
        mv -f $automation_dir"simInput/queue/rundigi_sim.C" $attpcroot_dir"macro/Simulation/GADGET/rundigi_sim.C"
        mv -f $automation_dir"simInput/queue/GADGET.sim.par" $attpcroot_dir"parameters/GADGET.sim.par"
        mv -f $automation_dir"simInput/queue/AtTPC20MgDecay.cxx" $attpcroot_dir"AtGenerators/AtTPC20MgDecay.cxx"
        # Add more files as implimented in same format

        # for testing, assume build is always needed
        #if [ -f $automation_dir"BUILD.csv" ]; then
            # Delete BUILD.csv
            #echo "BUILD.csv found, rebuilding ATTPCROOT"
            #rm $automation_dir"BUILD.csv"

        # build ATTPCROOT - commented for testing
        #make -C $attpcroot_dir"build/" -j8

        # build ROOT2HDF - commented for testing
        #make -C $attpcroot_dir"compiled/ROOT2HDF/build/"
        #fi
        
        
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

        # bad fix to solve location of output_digi.root
        mv $automation_dir"output_digi.root" $attpcroot_dir"macro/Simulation/GADGET/output_digi.root"
        
        $attpcroot_dir"compiled/ROOT2HDF/build/R2HExe" $attpcroot_dir"macro/Simulation/GADGET/output_digi.root"

        mv $automation_dir"output.h5" $automation_dir"simOutput/output.h5"
        ((iterations++))
    fi

end=`date +%s`
runtime=$((end-start))
echo "Runtime: $runtime"
echo "Number of Simulations: $iterations"
done