#!/bin/bash

### GADGET2 ATTPCROOT Automation Script ###
automation_dir=$(dirname "$(readlink -f "$0")") # get parent directory of script
automation_dir=$(readlink -f "$automation_dir" | sed 's:\([^/]\)$:\1/:') # add trailing slash if not present

#####################################
#### READ COMMAND LINE ARGUMENTS ####
num_simulators=4
tuning=0
reset_params=0
var_params=0

while getopts "htvildcam:" option; do
    case ${option} in
        h ) # display help
            echo "    GADGET2 ATTPCROOT Automation Script"
            echo "Developed by Adam Jaros as part of the FRIB's E21072 under Dr. Chris Wrede"
            echo "See documentation on the project's GitHub page for more information"
            echo "https://github.com/Jaros24/GADGET2"
            echo ""
            echo "Usage: run_sim.sh [-flags]"
            echo "  -t   run tuning mode"
            echo "  -v   generate parameters with variation script"
            echo "  -m#  specify number of simulators (1 - 10)"       
            echo "  -c   clean Output before running"
            echo "  -a   force reset of Simulators"
            echo "  -d   reset parameter file for testing"
            echo "  -h   display this help message"
            exit 0
            ;;
        t ) # run simulation in tuning mode
            echo "tuning mode enabled"
            tuning="y"
            ;;
        v ) # generate parameters with variation script
            var_params="y"
            ;;
        d ) # parameter debug mode
            echo "parameters.csv will be reset at end of loop"
            reset_params="y"
            ;;
        c ) # clean output before running
            echo "Cleaning Output Directory..."
            rm -rf $automation_dir"Output/"
            ;;
        a ) # force reset of ATTPCROOT
            echo "Resetting Simulators..."
            rm -rf $automation_dir".sims/"
            ;;
        m ) # specify number of simulators
            num_simulators="${OPTARG}"
            echo "Running with $num_simulators simulators"
            ;;
        \? ) # invalid option
            echo "Invalid option: -$OPTARG" 1>&2
            exit 1
            ;;
    esac
done

#####################################
### CHECK FOR CONFLICTING OPTIONS ###

if [ $tuning == "y" ] && [ $reset_params == "y" ]; then
    echo "tuning and resetting parameters options conflict"
    exit 1
fi
if [ $tuning == "y" ] && [ $var_params == "y" ]; then
    echo "tuning mode and parameter variation options conflict"
    exit 1
fi
if [ $reset_params == "y" ] && [ $var_params == "y" ]; then
    echo "resetting parameters and parameter variation options conflict"
    exit 1
fi

#####################################
### SET UP SIMULATION ENVIRONMENT ###

if [ $var_params == "y" ]; then # run create-params.py if needed"
    python3 $automation_dir".input/nb2py.py" $automation_dir".input/create-params.ipynb"
    python3 $automation_dir".input/create-params.py" $automation_dir
    rm -f $automation_dir".input/create-params.py"
fi

if [ ! -f $automation_dir"parameters.csv" ]; then # test for parameters.csv
    echo "parameters.csv not found"
    exit 1
fi

if [ $reset_params == "y" ]; then # backup parameters.csv for debugging
    cp $automation_dir"parameters.csv" $automation_dir".input/parameters.bak"
fi

if [ ! -d $automation_dir".sims/" ]; then # create Sims directory if needed
    mkdir -p $automation_dir".sims/"
fi

if [ ! -d $automation_dir"Output/" ]; then # create Output directory if needed
    mkdir -p $automation_dir"Output/"
    mkdir -p $automation_dir"Output/hdf5/"
    mkdir -p $automation_dir"Output/images/"
    mkdir -p $automation_dir"Output/gifs/"
    mkdir -p $automation_dir"Output/gifs/events/"
    mkdir -p $automation_dir"Output/aug_images/"
fi

#####################################
######### RUN SIMULATIONS ###########

start=`date +%s`
echo "Starting simulations at `date`"

# run simulations managed by python scripts
python3 $automation_dir".input/nb2py.py" $automation_dir".input/simManager.ipynb"
python3 $automation_dir".input/simManager.py" $automation_dir $num_simulators


#####################################
######### CLEAN UP SIMULATIONS ######

rm -f $automation_dir".input/simManager.py"
rm -f $automation_dir".input/status.csv"
cp -f $automation_dir"parameters.csv" $automation_dir"Output/parameters.csv"

if [ $reset_params == "y" ]; then # restore parameters.csv
    mv $automation_dir".input/parameters.bak" $automation_dir"parameters.csv"
fi

# zip simOutput folder
cd $automation_dir"Output/"
zip -r output.zip * >> /dev/null 
cd $automation_dir

end=`date +%s`
runtime=$((end-start))
echo "Finished simulations at `date`"
echo "Total runtime: $runtime seconds"