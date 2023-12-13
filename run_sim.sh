#!/bin/bash

debug=0 #"n" # set to y to enable debug mode

# set paths for ATTPCROOT and Automation scripts
automation_dir=$(dirname "$(readlink -f "$0")") # get parent directory of script
automation_dir=$(readlink -f "$automation_dir" | sed 's:\([^/]\)$:\1/:') # add trailing slash if not present
rm -f $automation_dir"log.log" # remove old log file if present

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
    #echo "ATTPCROOT directory found automatically at $attpcroot_dir"n
fi

source $attpcroot_dir"env_fishtank.sh"

# check for if ATTPCROOT is already built
if [ ! -f $attpcroot_dir"build/Makefile" ]; then
    echo "ATTPCROOT not setup, building"
    source $attpcroot_dir"env_fishtank.sh"
    mkdir -p $attpcroot_dir"build"
    cd $attpcroot_dir"build"
    # directories for fairroot and fairsoft are hardcoded, change if needed
    cmake -DCMAKE_PREFIX_PATH=/mnt/simulations/attpcroot/fair_install_18.6.3/ -DCMAKE_INSTALL_PATH=/mnt/misc/sw/x86_64/all/gnu/gcc/9.3.0/bin/gcc-9.3/ ../ >> $automation_dir"log.log"
    make install -j8 >> $automation_dir"log.log"
    cd $automation_dir

    mkdir -p $attpcroot_dir"macro/Simulation/Charge_Dispersion/data"
fi

# check for if R2HMain is already built
#if [ ! -f $attpcroot_dir"compiled/ROOT2HDF/R2HMain/build" ]; then
#    mkdir -p $attpcroot_dir"compiled/ROOT2HDF/build"
#    cd $attpcroot_dir"compiled/ROOT2HDF/build"
#    cmake ../ >> $automation_dir"log.log"
#    make -j8 >> $automation_dir"log.log"
#    cd $automation_dir
#fi

# ask for type of simulation loop to run
read -p "Is this a tuning simulation? (y/n): " tuning

# convert ipynb to py
python3 $automation_dir"simInput/nb2py.py" $automation_dir"simInput/iter-params.ipynb"
python3 $automation_dir"simInput/nb2py.py" $automation_dir"simInput/create-params.ipynb"
python3 $automation_dir"simInput/nb2py.py" $automation_dir"simInput/tuning-params.ipynb"
python3 $automation_dir"simInput/nb2py.py" $automation_dir"simInput/tuning-view.ipynb"
python3 $automation_dir"simInput/nb2py.py" $automation_dir"simInput/h5-to-img.ipynb"

if [ $tuning == "y" ]; then
    echo "Tuning simulation"
else
    # echo "Standard simulation"
    # prompt user for parameters file (generate or use existing)
    read -p "Generate new parameters? (y/n): " new_params

    if [ $new_params == "y" ]; then
        python3 $automation_dir"simInput/create-params.py" $automation_dir
    else 
        #echo "Using existing parameters.csv"
        if [ $debug == "y" ]; then
            echo "using debug parameters"
            cp $automation_dir"simInput/debug-parameters.csv" $automation_dir"simInput/parameters.csv"
        fi
    fi

    # test for parameters.csv
    if [ ! -f $automation_dir"simInput/parameters.csv" ]; then
        echo "parameters.csv not found"
        exit 1
    fi
fi


# load prerequisites for ATTPCROOT
#echo "Loading prerequisites"
source $attpcroot_dir"env_fishtank.sh"
module load fairroot/18.6.3

# send updated R2HMain.cc and R2HMain.hh to ATTPCROOT (have fix for trace and event data not present in stock version)
#cp -f $automation_dir"simInput/templates/R2HMain.cc" $attpcroot_dir"compiled/ROOT2HDF/R2HMain.cc"
#cp -f $automation_dir"simInput/templates/R2HMain.hh" $attpcroot_dir"compiled/ROOT2HDF/R2HMain.hh"

# start timer
#echo "Starting simulation loop"
start=`date +%s`
iterations=0

# run simulation loop
while true; do
    # tuning if needed
    if [ $tuning == "y" ]; then
        # run tuning simulation
        #echo "Tuning simulation"
        python3 $automation_dir"simInput/tuning-params.py" $automation_dir $attpcroot_dir $iterations
        python3 $automation_dir"simInput/tuning-view.py"
    fi

	# modify parameters and rename old h5
    #echo "Modifying parameters"
	python3 $automation_dir"simInput/iter-params.py" $automation_dir $attpcroot_dir 2> $automation_dir"log.log"
    if [ -f $automation_dir"STOP.csv" ]; then
        # Delete STOP.csv and break loop
        #echo "STOP.csv found, stopping Loop"
        rm $automation_dir"STOP.csv"
        break

    else
        echo -n "Running simulation"
        # MOVE QUEUED FILES TO SIMULATION FOLDER
        mv -f $automation_dir"simInput/queue/Mg20_test_sim_pag.C" $attpcroot_dir"macro/Simulation/Charge_Dispersion/Mg20_test_sim_pag.C"
        mv -f $automation_dir"simInput/queue/rundigi_sim_CD.C" $attpcroot_dir"macro/Simulation/Charge_Dispersion/rundigi_sim_CD.C"
        mv -f $automation_dir"simInput/queue/GADGET.sim.par" $attpcroot_dir"parameters/GADGET.sim.par"
        mv -f $automation_dir"simInput/queue/AtTPC20MgDecay_pag.cxx" $attpcroot_dir"AtGenerators/AtTPC20MgDecay_pag.cxx"
        mv -f $automation_dir"simInput/queue/AtPulseGADGET.h" $attpcroot_dir"AtDigitization/AtPulseGADGET.h"
        # Add more files as implimented in same format
        
        # check if ATTPCROOT needs to be rebuilt
        if [ -f $automation_dir"BUILD.csv" ]; then
            echo -ne "\r\e[0KRebuilding ATTPCROOT"
            rm $automation_dir"BUILD.csv"
            make -C $attpcroot_dir"build/" -j8 &>> $automation_dir"log.log"
            # make -C $attpcroot_dir"compiled/ROOT2HDF/build/" >> $automation_dir"log.log"
        fi

        # run simulation and digitization
        if [ $debug == "y" ]; then # debug mode, display output in terminal
            cd $attpcroot_dir"macro/Simulation/Charge_Dispersion/"
            echo 'Mg20_test_sim.C'
            root -l Mg20_test_sim_pag.C 
            echo 'rundigi_sim.C'
            root -l rundigi_sim_CD.C
            cd $automation_dir
        else # normal mode, hide output
            cd $attpcroot_dir"macro/Simulation/Charge_Dispersion/"
            echo -ne '\r\e[0KMg20_test_sim_pag.C'
            nohup root -b -l Mg20_test_sim_pag.C &>> $automation_dir"log.log"
            pid1=$!
            wait $pid1
            echo -ne '\r\e[0Krundigi_sim_CD.C'
            nohup root -b -l rundigi_sim_CD.C &>> $automation_dir"log.log"
            pid2=$!
            wait $pid2
            cd $automation_dir
        fi
        
        mv $attpcroot_dir"macro/Simulation/Charge_Dispersion/data/output.h5" $automation_dir"simOutput/output.h5"
        echo -ne '\r\e[0K'
        ((iterations++))
    fi
done

end=`date +%s`
runtime=$((end-start))
echo "$iterations simulations completed in $runtime seconds"

# clean up files
rm -f $automation_dir"simInput/iter-params.py"
rm -f $automation_dir"simInput/create-params.py"
rm -f $automation_dir"simInput/tuning-params.py"
rm -f $automation_dir"simInput/tuning-view.py"
rm -f $automation_dir"nohup.out"

# copy parameters.csv to simOutput
cp -f $automation_dir"simInput/parameters.csv" $automation_dir"simOutput/parameters.csv"

# convert h5 files into images
# echo "Producing images from h5 files"
python3 $automation_dir"simInput/h5-to-img.py" $automation_dir
rm -f $automation_dir"simInput/h5-to-img.py"

# zip simOutput, named with date and time
cd $automation_dir"simOutput/"
zip -r output.zip * >> $automation_dir"log.log"
cd $automation_dir