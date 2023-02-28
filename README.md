# GADGET2
Simulation and Analysis for GADGET 2

## Simulation Instructions and Requirements
1. Requires Python 
2. Install ATTPCROOTv2 (https://github.com/ATTPC/ATTPCROOTv2)
3. modify the paths in `run.sh` to point to the ATTPCROOTv2 directory the GADGET2 directory
4. modify the paths in `Parameters-Iteration.ipynb` to point to the ATTPCROOTv2 directory the GADGET2 directory
5. export `Parameters-Iteration.ipynb` to a python script `iter.py` in the simInput directory
6. modify `parameters.csv` in the simInput directory to contain the parameters you want to iterate over
7. run `run_sim.sh`
8. completed h5 files will be in the simOutput directory

Format of parameters.csv file:
| Sim | CoefL | CoefT | Gain | GETGain | PeakingTime | N | P0 | E0 | P1 | E1 | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Name of Simulation | 0.000114 | 0.00037 | 10000 | 1000 | 720 | 100 | a or p | Main Particle Energy | a or p or 0 | Secondary Particle Energy | 0 |
| 800KeV_proton | 0.000114 | 0.00037 | 10000 | 1000 | 720 | 100 | p | 800 | 0 | 0 | 0 |
| Mg20_pa | 0.000114 | 0.00037 | 10000 | 1000 | 720 | 100 | p | 1200 | a | 500 | 0 |


## Analysis Instructions
To be added