# GADGET2
Simulation and Analysis Automation for GADGET 2

## Simulation Instructions and Requirements
1. Install ATTPCROOTv2 (https://github.com/ATTPC/ATTPCROOTv2) commit b7dd09ae in parent directory
2. run the command ./run_sim.sh
3. follow prompts for desired simulation type, will automatically run and output h5 files to simOutput/hdf5/

## Analysis
- done with jupyter notebooks, although could be made into python scripts if needed
- traces.ipynb produces images for visual analysis
- numerical.ipynb analyzes h5 files for numerical trends

## Manual Parameter file generation
### Essential Values:
- Sim : simulation Name, output h5 will be named this
- Status : status of the simulation, set to 0 to queue. will automatically change to 1 for in progress, 2 for completed.
- P0 : main particle type (use name or abbreviation of particle, or pdgid number)
- E0 : energy (in keV) of main particle
- P1 : secondary particle type (add '-' before to specify 180° relative angle with P0)
- E1 : secondary particle energy
Set P1,E1 to a,0 for no secondary particle

### Optional Parameters
- N : number of events to simulate per h5, default int 100
- Threshold : pad theshold, default int 20
- Seed : random seed for simulation, default 0. Set 0 for random, other integer for specified seed
- Xb : x bounds for origin of event, default 2
    - Set to 99 to artificially raise detector efficiency by placing event origins on opposite side of detector from their direction of travel.
- Yb: y bounds for origin of event, default 2
- Zb1 : lower z bound for origin of event, default 10
- Zb2 : upper z bound for origin of event, default 40
- CD : Charge Dispersion adjacent pads, default int 2 (rundigi_sim_CD instance)
- CDH : Charge Dispersion adjacent pads (header version), defaults to CD if that is specified, or 2 if not
- ANY PARAMETER LOCATED IN GADGET.sim.par, see simInput/templates for default values