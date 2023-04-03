# GADGET2
Simulation and Analysis Automation for GADGET 2

## Simulation Instructions and Requirements
1. Install ATTPCROOTv2 (https://github.com/ATTPC/ATTPCROOTv2)
2. modify the paths in `run.sh` to point to the ATTPCROOTv2 directory the directory of this repository
3. modify the paths in `Parameters-Iteration.ipynb` to point to the ATTPCROOTv2 directory the GADGET2 directory
4. export `Parameters-Iteration.ipynb` to a python script `iter.py` in the simInput directory
5. modify `parameters.csv` in the simInput directory to contain the parameters you want to iterate over
6. run `run_sim.sh`
7. completed h5 files will be in the simOutput directory

## Analysis Instructions
To be added
