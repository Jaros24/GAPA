#!/bin/bash

debug_log=0 # -l option
tuning=0 # -t option
iter_limit=0 # -i option
var_params=0 # -v option
reset_params=0 # -d option

# set paths for ATTPCROOT and Automation scripts
automation_dir=$(dirname "$(readlink -f "$0")") # get parent directory of script
automation_dir=$(readlink -f "$automation_dir" | sed 's:\([^/]\)$:\1/:') # add trailing slash if not present
rm -f $automation_dir"log.log" # remove old log file if present

# test for ATTPCROOT in same directory as automation script
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
fi

# parse command line arguments for options
while getopts "htvildc" option; do
    case ${option} in
        h ) # display help
            echo "Usage: run_sim.sh [-h][-t][-v][-i][-l][-d]"
            echo "  -t  run simulation in tuning mode"
            echo "  -v  generate parameters with variation script"
            echo "  -i  limit number of iterations for testing"
            echo "  -l  display full logs in terminal"
            echo "  -d  reset parameter file for debugging"
            echo "  -c  clean output before running"
            echo "  -h  display help message"
            echo "See documentation on GitHub for more information"
            echo "https://github.com/Jaros24/GADGET2"
            exit 0
            ;;
        t ) # run simulation in tuning mode
            echo "tuning mode enabled"
            tuning="y"
            ;;
        v ) # generate parameters with variation script
            echo "parameters will be generated with variation script"
            var_params="y"
            ;;
        i ) # limit number of iterations to 1
            echo "limiting number of iterations to 1"
            iter_limit="y"
            ;;
        l ) # display logs instead of supressing to log file
            echo "build and simulation logs will be displayed"
            echo "you will need to input '.q' to exit ROOT after each simulation"
            debug_log="y"
            ;;
        d ) # parameter debug mode
            echo "parameters.csv will be reset at end of loop"
            reset_params="y"
            ;;
        c ) # clean output before running
            echo "cleaning output"
            rm -rf $automation_dir"simOutput/"
            mkdir -p $automation_dir"simOutput/"
            mkdir -p $automation_dir"simOutput/hdf5/"
            mkdir -p $automation_dir"simOutput/images/"
            mkdir -p $automation_dir"simOutput/gifs/"
            mkdir -p $automation_dir"simOutput/gifs/events/"
            mkdir -p $automation_dir"simOutput/aug_images/"
            ;;
        \? ) # invalid option
            echo "Invalid option: -$OPTARG" 1>&2
            exit 1
            ;;

    esac
done

source $attpcroot_dir"env_fishtank.sh"
# check for if ATTPCROOT is already built, if not build it
if [ ! -f $attpcroot_dir"build/Makefile" ]; then
    echo "ATTPCROOT not setup, building"
    source $attpcroot_dir"env_fishtank.sh"
    mkdir -p $attpcroot_dir"build"
    cd $attpcroot_dir"build"
    # directories for fairroot and fairsoft are hardcoded, change if needed
    if debug_log == "y"; then
        cmake -DCMAKE_PREFIX_PATH=/mnt/simulations/attpcroot/fair_install_18.6.3/ -DCMAKE_INSTALL_PATH=/mnt/misc/sw/x86_64/all/gnu/gcc/9.3.0/bin/gcc-9.3/ ../
        make install -j8
    else
        cmake -DCMAKE_PREFIX_PATH=/mnt/simulations/attpcroot/fair_install_18.6.3/ -DCMAKE_INSTALL_PATH=/mnt/misc/sw/x86_64/all/gnu/gcc/9.3.0/bin/gcc-9.3/ ../ >> $automation_dir"log.log"
        make install -j8 >> $automation_dir"log.log"
    fi
    cd $automation_dir
    mkdir -p $attpcroot_dir"macro/Simulation/Charge_Dispersion/data"
fi

# convert ipynb to py
python3 $automation_dir"simInput/nb2py.py" $automation_dir"simInput/queue-sim.ipynb"
python3 $automation_dir"simInput/nb2py.py" $automation_dir"simInput/process-sim.ipynb"
python3 $automation_dir"simInput/nb2py.py" $automation_dir"simInput/create-params.ipynb"
python3 $automation_dir"simInput/nb2py.py" $automation_dir"simInput/tuning.ipynb"


if [ $var_params == "y" ]; then # run create-params.py if needed
    echo "Parameter variation script"
    python3 $automation_dir"simInput/create-params.py" $automation_dir
fi

if [ ! -f $automation_dir"simInput/parameters.csv" ]; then # test for parameters.csv
    echo "parameters.csv not found in simInput"
    exit 1
fi

if [ $reset_params == "y" ]; then # backup parameters.csv for debugging
    cp $automation_dir"simInput/parameters.csv" $automation_dir"simInput/queue/parameters.csv"
fi

# load prerequisites for ATTPCROOT
source $attpcroot_dir"env_fishtank.sh"
module load fairroot/18.6.3

# start timer
start=`date +%s`
iterations=0

# SIMULATION LOOP 
while true; do
    # tuning if needed
    if [ $tuning == "y" ]; then # tuning mode
        python3 $automation_dir"simInput/tuning.py" $automation_dir $attpcroot_dir $iterations # 2> $automation_dir"log.log"
    fi
    
	# queue new simulation parameters or break loop
	python3 $automation_dir"simInput/queue-sim.py" $automation_dir $attpcroot_dir
    
    if [ -f $automation_dir"STOP.csv" ]; then
        # Delete STOP.csv and break loop
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
        
        # check if ATTPCROOT needs to be rebuilt
        if [ -f $automation_dir"BUILD.csv" ]; then
            if [ $debug_log == "y" ]; then
                echo "Rebuilding ATTPCROOT"
                rm $automation_dir"BUILD.csv"
                make -C $attpcroot_dir"build/" -j8
            else
                echo -ne "\r\e[0KRebuilding ATTPCROOT"
                rm $automation_dir"BUILD.csv"
                make -C $attpcroot_dir"build/" -j8 &>> $automation_dir"log.log"
            fi
        fi

        # run simulation and digitization
        if [ $debug_log == "y" ]; then # display output in terminal for debugging
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

        # run processing script
        echo -ne '\r\e[0Kprocessing simulation'
        python3 $automation_dir"simInput/process-sim.py" $automation_dir $attpcroot_dir

        echo -ne '\r\e[0K' # clear line in terminal for next iteration
        ((iterations++))

        # break loop if iteration limit is reached
        if [ $iter_limit == "y" ]; then
            break
        fi
    fi
done

end=`date +%s`
runtime=$((end-start))
echo "$iterations simulations completed in $runtime seconds"

# clean up files
rm -f $automation_dir"simInput/create-params.py"
rm -f $automation_dir"simInput/queue-sim.py"
rm -f $automation_dir"simInput/process-sim.py"
rm -f $automation_dir"simInput/tuning.py"
rm -f $automation_dir"nohup.out"

# copy parameters.csv to simOutput
cp -f $automation_dir"simInput/parameters.csv" $automation_dir"simOutput/parameters.csv"

# move queued parameters.csv to simInput if it exists (for -d option)
if [ -f $automation_dir"simInput/queue/parameters.csv" ]; then
    mv -f $automation_dir"simInput/queue/parameters.csv" $automation_dir"simInput/parameters.csv"
fi

# zip simOutput folder
cd $automation_dir"simOutput/"
zip -r output.zip * >> $automation_dir"log.log"
cd $automation_dir