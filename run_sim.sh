#!/bin/bash

# set paths for ATTPCROOT and Automation scripts
automation_dir=$(dirname "$(readlink -f "$0")") # get parent directory of script
automation_dir=$(readlink -f "$automation_dir" | sed 's:\([^/]\)$:\1/:') # add trailing slash if not present

# test for ATTPCROOT in same directory as automation scripts
attpcroot_dir="$automation_dir/../ATTPCROOTv2" # set ATTPCROOT path relative to script location
attpcroot_dir=$(readlink -f "$attpcroot_dir")
attpcroot_dir="${attpcroot_dir%/GADGET2/..}"

# check if ATTPCROOT directory exists and contains env_fishtank.sh
if [ ! -d "$attpcroot_dir" ] || [ ! -f "$attpcroot_dir/env_fishtank.sh" ]; then
    read -p "Enter full ATTPCROOT directory: " attpcroot_dir
    attpcroot_dir=$(readlink -f "$attpcroot_dir" | sed 's:\([^/]\)$:\1/:') # add trailing slash if not present
    if [ ! -d "$attpcroot_dir" ] || [ ! -f "$attpcroot_dir/env_fishtank.sh" ]; then
        echo "specified ATTPCROOT directory is invalid"
        exit 1
    fi
else
    attpcroot_dir=$(readlink -f "$attpcroot_dir" | sed 's:\([^/]\)$:\1/:') # add trailing slash if not present
    echo "ATTPCROOT directory found automatically at $attpcroot_dir"
fi

# ask for type of simulation loop to run
read -p "Type of simulation loop (0:generated, 1:tuning): " sim_type
if [ $sim_type -eq "0" ]; then

    # convert ipynb to py
    python3 $automation_dir"simInput/nb2py.py" $automation_dir"simInput/iter-params.ipynb"
    python3 $automation_dir"simInput/nb2py.py" $automation_dir"simInput/create-params.ipynb"

    # prompt user for parameters file (generate or use existing)
    read -p "Generate new parameters? (y/n): " new_params
    if [ $new_params == "y" ]; then
        python3 $automation_dir"simInput/create-params.py" $automation_dir
    else 
        echo "Using existing parameters.csv"
    fi

    # test for parameters.csv
    if [ ! -f $automation_dir"simInput/parameters.csv" ]; then
        echo "parameters.csv not found"
        exit 1
    fi


    # load prerequisites for ATTPCROOT
    source $attpcroot_dir"env_fishtank.sh"
    module load fairroot/18.6.3

    # send updated R2HMain.cc and R2HMain.hh to ATTPCROOT (have fix for trace and event data not present in stock version)
    cp -f $automation_dir"simInput/templates/R2HMain.cc" $attpcroot_dir"compiled/ROOT2HDF/R2HMain.cc"
    cp -f $automation_dir"simInput/templates/R2HMain.hh" $attpcroot_dir"compiled/ROOT2HDF/R2HMain.hh"

    # start timer
    start=`date +%s`
    iterations=0


    # run simulation loop
    while true; do
    	# modify parameters and rename old h5
        echo "Modifying parameters"
    	python3 $automation_dir"simInput/iter-params.py" $automation_dir $attpcroot_dir

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

            # build ATTPCROOT
            make -C $attpcroot_dir"build/" -j8

            # build ROOT2HDF
            make -C $attpcroot_dir"compiled/ROOT2HDF/build/"
            #fi


            # run simulation        
            echo "Mg20_test_sim.C"
            nohup root -b -l $attpcroot_dir"macro/Simulation/GADGET/Mg20_test_sim.C" &
            pid1=$!
            wait $pid1

            echo "rundigi_sim.C"
            nohup root -b -l $attpcroot_dir"macro/Simulation/GADGET/rundigi_sim.C" &
            pid2=$!
            wait $pid2

            # convert root files to h5
            echo "Converting root files to h5"

            # bad fix to solve location of output_digi.root
            mv $automation_dir"output_digi.root" $attpcroot_dir"macro/Simulation/GADGET/output_digi.root"

            $attpcroot_dir"compiled/ROOT2HDF/build/R2HExe" $attpcroot_dir"macro/Simulation/GADGET/output_digi.root"

            mv $automation_dir"output.h5" $automation_dir"simOutput/output.h5"
            ((iterations++))
        fi
    
    done
    end=`date +%s`
    runtime=$((end-start))
    echo "Runtime: $runtime"
    echo "Number of Simulations: $iterations"

    # clean up files
    rm -f $automation_dir"simInput/iter-params.py"
    rm -f $automation_dir"simInput/create-params.py"
    rm -f $automation_dir"nohup.out"

    # copy parameters.csv to simOutput
    cp -f $automation_dir"simInput/parameters.csv" $automation_dir"simOutput/parameters.csv"

    # zip simOutput, named with date and time
    #zip -r $automation_dir"simOutput/$(date +%Y-%m-%d_%H-%M-%S).zip" $automation_dir"simOutput/"

elif [ $sim_type -eq "1" ]; then
    echo "Tuning not yet implemented"
    
else
    echo "Invalid simulation type"
fi