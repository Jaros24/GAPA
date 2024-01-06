#!/bin/bash

# set paths for ATTPCROOT and Automation scripts
automation_dir=$(dirname "$(readlink -f "$0")") # get parent directory of script
automation_dir=$(readlink -f "$automation_dir" | sed 's:\([^/]\)$:\1/:') # add trailing slash if not present

touch $automation_dir"STARTING.tmp" # create STARTING.tmp file to indicate script is running

# check for ATTPCROOT installed in same directory, download if not
if [ ! -f $automation_dir"ATTPCROOTv2/env_fishtank.sh" ]; then
    git clone https://github.com/ATTPC/ATTPCROOTv2
    cd ATTPCROOTv2
    git checkout 40699a2
    rm -rf .git
    cd $automation_dir
    attpcroot_dir=$automation_dir"ATTPCROOTv2/"
else # ATTPCROOT already installed
    attpcroot_dir=$automation_dir"ATTPCROOTv2/"
fi

source $attpcroot_dir"env_fishtank.sh"

if [ ! -f $attpcroot_dir"build/Makefile" ]; then
    # steps pulled from ATTPCROOTv2 installation wiki page
    cd $attpcroot_dir
    source env_fishtank.sh
    mkdir build
    cd build
    cmake -DCMAKE_PREFIX_PATH=/mnt/simulations/attpcroot/fair_install_18.6/ ../
    make install -j4
    source config.sh
    cd $attpcroot_dir"geometry/"
    nohup root -b -l GADGET_II.C
    pid1=$!
    wait $pid1
    cd $automation_dir
    mkdir -p $attpcroot_dir"macro/Simulation/Charge_Dispersion/data"
fi

# load prerequisites for ATTPCROOT
source $attpcroot_dir"env_fishtank.sh"
module load fairroot/18.6.3

# create output directory if it doesn't exist
mkdir -p $automation_dir"out"
mkdir -p $automation_dir"out/hdf5"
mkdir -p $automation_dir"out/images"
mkdir -p $automation_dir"out/gifs"

# SIMULATION LOOP 
while true; do
	# queue new simulation parameters or break loop
	python3 $automation_dir"queue.py" $automation_dir $attpcroot_dir
    if [ -f $automation_dir"STOP.tmp" ]; then
        # Delete STOP.csv and break loop
        rm $automation_dir"STOP.tmp"
        exit 0
    fi
    # build ATTPCROOT and run simulation
    make -C $attpcroot_dir"build/" -j8
    cd $attpcroot_dir"macro/Simulation/Charge_Dispersion/"
    echo "Running simulation (Mg20_test_sim_pag.C)"
    nohup root -b -l Mg20_test_sim_pag.C
    pid1=$!
    wait $pid1
    echo "Running simulation (rundigi_sim_CD.C)"
    nohup root -b -l rundigi_sim_CD.C
    pid2=$!
    wait $pid2
    cd $automation_dir
    mv $attpcroot_dir"macro/Simulation/Charge_Dispersion/data/output.h5" $automation_dir"out/output.h5"
    echo "Processing simulation output"
    python3 $automation_dir"process.py" $automation_dir $attpcroot_dir
done