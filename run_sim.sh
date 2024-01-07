#!/bin/bash

debug_log=0 # -l option
tuning=0 # -t option
iter_limit=0 # -i option
var_params=0 # -v option
reset_params=0 # -d option
multi=0 # -m option

# set paths for ATTPCROOT and Automation scripts
automation_dir=$(dirname "$(readlink -f "$0")") # get parent directory of script
automation_dir=$(readlink -f "$automation_dir" | sed 's:\([^/]\)$:\1/:') # add trailing slash if not present
rm -f $automation_dir"log.log" # remove old log file if present

# parse command line arguments for options
while getopts "htvildcam:" option; do
    case ${option} in
        h ) # display help
            echo "    GADGET2 ATTPCROOT Automation Script"
            echo "Developed by Adam Jaros as part of the FRIB's E21072 under Dr. Chris Wrede"
            echo "See documentation on the project's GitHub page for more information"
            echo "https://github.com/Jaros24/GADGET2"
            echo ""
            echo "Usage: run_sim.sh [-flags]"
            echo "  -t  run simulation in tuning mode"
            echo "  -v  generate parameters with variation script"
            echo "  -m4  run simulation multi-threaded, specify number of simulators with integer"           
            echo "  -c  clean simOutput before running"
            echo "  -l  display full logs in terminal"
            echo "  -a  force reset of ATTPCROOT"
            echo "  -d  reset parameter file for testing"
            echo "  -i  limit number of iterations for testing"
            echo "  -h  display help message"
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
        a ) # force reset of ATTPCROOT
            echo "ATTPCROOT will be rebuilt"
            rm -rf $automation_dir"Sims/"
            mkdir -p $automation_dir"Sims/"
            mkdir -p $automation_dir"Sims/0/" # sim0 directory for ATTPCROOT
            ;;
        m ) # run simulation multi-threaded
            multi="y"
            num_simulators="${OPTARG}"
            echo "running multi-threaded with $num_simulators simulators"
            ;;
        \? ) # invalid option
            echo "Invalid option: -$OPTARG" 1>&2
            exit 1
            ;;
    esac
done

# check if multi mode is conflicting with other options
if [ $multi == "y" ]; then
    if [ $debug_log == "y" ]; then
        echo "multi-threaded mode is not compatible with debug mode"
        # cannot display output in terminal if multi-threaded
        exit 1
    fi
    if [ $tuning == "y" ]; then
        echo "multi-threaded mode is not currently compatible with tuning mode"
        # todo - fix this
        exit 1
    fi
    if [ $iter_limit == "y" ]; then
        echo "multi-threaded mode is not compatible with iteration limit"
        # not worth implementing
        exit 1
    fi
fi

python3 $automation_dir"simInput/nb2py.py" $automation_dir"simInput/create-params.ipynb"
if [ $var_params == "y" ]; then # run create-params.py if needed
    echo "Parameter variation script"
    python3 $automation_dir"simInput/create-params.py" $automation_dir
fi
rm -f $automation_dir"simInput/create-params.py"

if [ ! -f $automation_dir"simInput/parameters.csv" ]; then # test for parameters.csv
    echo "parameters.csv not found in simInput"
    exit 1
fi

if [ $reset_params == "y" ]; then # backup parameters.csv for debugging
    cp $automation_dir"simInput/parameters.csv" $automation_dir"simInput/parameters.bak"
fi

start=`date +%s`
echo "Starting simulations at `date`"

if [ $multi == "y" ]; then
    # run multi-threaded simulation script
    python3 $automation_dir"simInput/nb2py.py" $automation_dir"simInput/multi-sim.ipynb"
    python3 $automation_dir"simInput/multi-sim.py" $automation_dir $num_simulators

    # clean up files
    rm -f $automation_dir"simInput/multi-sim.py"
    rm -f $automation_dir"simInput/status.csv"
    cp -f $automation_dir"simInput/parameters.csv" $automation_dir"simOutput/parameters.csv"
    if [ $reset_params == "y" ]; then # restore parameters.csv
        mv $automation_dir"simInput/parameters.bak" $automation_dir"simInput/parameters.csv"
    fi
    
    # zip simOutput folder
    cd $automation_dir"simOutput/"
    zip -r output.zip * >> $automation_dir"log.log"
    cd $automation_dir

    end=`date +%s`
    runtime=$((end-start))
    echo "multi-threaded simulation completed in $runtime seconds at `date`"
    exit 0
fi

# check for ATTPCROOT installed in Sims directory, download if not
if [ ! -f $automation_dir"Sims/0/ATTPCROOTv2/env_fishtank.sh" ]; then
    mkdir -p $automation_dir"Sims/0/"
    cd $automation_dir"Sims/0/"
    echo "Downloading ATTPCROOT"
    if [ $debug_log == "y" ]; then
        git clone https://github.com/ATTPC/ATTPCROOTv2
        cd ATTPCROOTv2
        git checkout 40699a2 # use specific version that has been tested
        rm -rf .git # remove git files to prevent conflicts
    else
        git clone https://github.com/ATTPC/ATTPCROOTv2 &>> $automation_dir"log.log"
        cd ATTPCROOTv2
        git checkout 40699a2 &>> $automation_dir"log.log"
        rm -rf .git &>> $automation_dir"log.log"
    fi
    cd $automation_dir
    attpcroot_dir=$automation_dir"Sims/0/ATTPCROOTv2/"
else # ATTPCROOT already installed
    attpcroot_dir=$automation_dir"Sims/0/ATTPCROOTv2/"
fi

source $attpcroot_dir"env_fishtank.sh"

# build ATTPCROOT if needed
if [ ! -f $attpcroot_dir"build/Makefile" ]; then
    echo "ATTPCROOT not setup, building"
    # steps pulled from ATTPCROOTv2 installation wiki page
    cd $attpcroot_dir
    source env_fishtank.sh
    mkdir build
    cd build
    if [ $debug_log == "y" ]; then
        cmake -DCMAKE_PREFIX_PATH=/mnt/simulations/attpcroot/fair_install_18.6/ ../
        make install -j 4
        source config.sh

        cd $attpcroot_dir"geometry/"
        root -l GADGET_II.C
    else
        echo -ne "\r\e[0KCMake"
        cmake -DCMAKE_PREFIX_PATH=/mnt/simulations/attpcroot/fair_install_18.6/ ../ &>> $automation_dir"log.log"
        echo -ne "\r\e[0KMake"
        make install -j 4 &>> $automation_dir"log.log"
        echo -ne "\r\e[0K"
        source config.sh &>> $automation_dir"log.log"

        cd $attpcroot_dir"geometry/"
        echo -ne "\r\e[0Kbuilding geometry"
        nohup root -b -l GADGET_II.C &>> $automation_dir"log.log"
        pid1=$!
        wait $pid1
    fi
    cd $automation_dir
    mkdir -p $attpcroot_dir"macro/Simulation/Charge_Dispersion/data"
    echo "ATTPCROOT built"
fi

# convert ipynb to py
python3 $automation_dir"simInput/nb2py.py" $automation_dir"simInput/queue-sim.ipynb"
python3 $automation_dir"simInput/nb2py.py" $automation_dir"simInput/process-sim.ipynb"
python3 $automation_dir"simInput/nb2py.py" $automation_dir"simInput/tuning.ipynb"

mkdir -p $automation_dir"Sims/0/queue/" # make file queue directory if needed

# load prerequisites for ATTPCROOT
source $attpcroot_dir"env_fishtank.sh"
module load fairroot/18.6.3

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
        cp -f $automation_dir"Sims/0/queue/Mg20_test_sim_pag.C" $attpcroot_dir"macro/Simulation/Charge_Dispersion/Mg20_test_sim_pag.C"
        cp -f $automation_dir"Sims/0/queue/rundigi_sim_CD.C" $attpcroot_dir"macro/Simulation/Charge_Dispersion/rundigi_sim_CD.C"
        cp -f $automation_dir"Sims/0/queue/GADGET.sim.par" $attpcroot_dir"parameters/GADGET.sim.par"
        cp -f $automation_dir"Sims/0/queue/AtTPC20MgDecay_pag.cxx" $attpcroot_dir"AtGenerators/AtTPC20MgDecay_pag.cxx"
        cp -f $automation_dir"Sims/0/queue/AtPulseGADGET.h" $attpcroot_dir"AtDigitization/AtPulseGADGET.h"
        
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
echo "Simulation loop completed at `date`"
echo "$iterations simulations completed in $runtime seconds"


# clean up files
rm -f $automation_dir"simInput/queue-sim.py"
rm -f $automation_dir"simInput/process-sim.py"
rm -f $automation_dir"simInput/tuning.py"
rm -f $automation_dir"nohup.out"

# copy parameters.csv to simOutput
cp -f $automation_dir"simInput/parameters.csv" $automation_dir"simOutput/parameters.csv"

# move queued parameters.csv to simInput if it exists (for -d option)
if [ -f $automation_dir"simInput/parameters.bak" ]; then
    mv -f $automation_dir"simInput/parameters.bak" $automation_dir"simInput/parameters.csv"
fi

# zip simOutput folder
cd $automation_dir"simOutput/"
zip -r output.zip * >> $automation_dir"log.log"
cd $automation_dir