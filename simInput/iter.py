# %%
# Load Packages - KEEP MINIMAL FOR FISHTANK COMPATIBILITY
import pandas as pd
import numpy as np
import os

# %%
# set locations for working files
parameters_dir = '/mnt/analysis/e17023/Adam/simInput/parameters.csv'
output_dir = '/mnt/analysis/e17023/Adam/simOutput/'
indicator_directory = '/mnt/analysis/e17023/Adam/'

attpcroot_param = '/mnt/analysis/e17023/Adam/ATTPCROOTv2/parameters/GADGET.sim.par'
default_name = 'output.h5'

attpcroot_mg20_cxx = '/mnt/analysis/e17023/Adam/ATTPCROOTv2/AtGenerators/AtTPC20MgDecay.cxx'
attpcroot_mg20_h = '/mnt/analysis/e17023/Adam/ATTPCROOTv2/AtGenerators/AtTPC20MgDecay.h'

alpha_gen = '/mnt/analysis/e17023/Adam/simInput/generators/GeneratorA.txt'
proton_gen = '/mnt/analysis/e17023/Adam/simInput/generators/GeneratorP.txt'
pa_gen = '/mnt/analysis/e17023/Adam/simInput/generators/GeneratorPA.txt'
next_gen = '/mnt/analysis/e17023/Adam/simInput/generators/nextGenerator.txt'

attpcroot_mg20_testsim = '/mnt/analysis/e17023/Adam/simInput/generators/Mg20_test_sim.txt'
attpcroot_mg20_testsim_template = '/mnt/analysis/e17023/Adam/simInput/generators/Mg20_test_sim_template.txt'
attpcroot_rundigi = '/mnt/analysis/e17023/Adam/ATTPCROOTv2/macro/Simulation/GADGET/rundigi_sim.C'
attpcroot_r2h = '/mnt/analysis/e17023/Adam/ATTPCROOTv2/compiled/ROOT2HDF/R2HMain.cc'

# %%
def indicator_file(file_type, indicator_directory=indicator_directory):
    df = pd.DataFrame([0])
    df.to_csv(indicator_directory + file_type + '.csv', index=False)
    print(file_type + ' FILE CREATED')

# %%
def energy_to_momentum(energy, particle):
    # input energy in KeV, convert to MeV
    energy = energy/1000

    # Mass values from NIST
    if particle == 'a':
        mass = 3727.3794066 # MeV/c^2
    elif particle == 'p':
        mass = 938.27208816 # MeV/c^2
    else:
        indicator_file('STOP')
        raise Exception('Error: particle must be "a" or "p"')
    momentum = np.sqrt(2*mass*energy)/1000 # GeV/c
    return momentum

# %%
parameters = pd.read_csv(parameters_dir)

# %%
# check for and complete any active simulations

# 0 = inactive
# 1 = active
# 2 = complete

previous_N = 0
previous_Particles = (0,0,0,0)

if not parameters['Sim'].is_unique:
    indicator_file('STOP')
    raise Exception('Simulation names are not unique')

active_sims = parameters[parameters['Status'] == 1]
if len(active_sims) > 0:
    
    if len(active_sims) > 1:
        indicator_file('STOP')
        raise Exception('More than one active simulation')
    
    # Search for output.h5 and rename
    Complete = False
    for filename in os.listdir(output_dir):
        f = os.path.join(output_dir, filename)
        # checking if it is a file
        if os.path.isfile(f):
            if filename == default_name:
                os.rename(f, output_dir+active_sims.loc[active_sims.index[0],'Sim']+'.h5')
                Complete = True
    # Set Status in parameters
    if Complete:
        previous_N  = parameters.loc[active_sims.index[0], 'N']
        previous_Particles = (parameters.loc[active_sims.index[0], 'P0'], parameters.loc[active_sims.index[0], 'E0'], parameters.loc[active_sims.index[0], 'P1'], parameters.loc[active_sims.index[0], 'E1'])
        parameters.loc[active_sims.index[0], 'Status'] = 2
        print('Simulation', parameters.loc[active_sims.index[0], 'Sim'] + ' complete')
        
    else:
        indicator_file('STOP')
        raise Exception('Could not find output file')

# %%
# Determine next simulation to run and mark as active
inactive_sims = parameters[parameters['Status'] == 0]
if len(inactive_sims) == 0:
    indicator_file('STOP')
    parameters.to_csv(parameters_dir, index=False)
    raise Exception('Finished with all simulations')
else:
    active_sim = inactive_sims.index[0]
    parameters.loc[active_sim, 'Status'] = 1
    print("next simulation: ", parameters.loc[active_sim, 'Sim'])

# %%
# write new params to GADGET.sim.par
with open(attpcroot_param, 'r') as f:
    lines = f.readlines()

lines[38] = 'CoefL:Double_t      ' + str(parameters.loc[active_sim, 'CoefL']) +   ' # Longitudal coefficient of diffusion [cm2/us]\n'
lines[39] = 'CoefT:Double_t      ' + str(parameters.loc[active_sim, 'CoefT']) +   ' # Transverse coefficient of diffusion [cm2/us]\n'
lines[40] = 'Gain:Double_t       ' + str(parameters.loc[active_sim, 'Gain']) +    ' # Average gain of micromegas\n'
lines[41] = 'GETGain:Double_t    ' + str(parameters.loc[active_sim, 'GETGain']) + ' # Gain of the GET electronics in fC\n'
lines[42] = 'PeakingTime:Int_t   ' + str(parameters.loc[active_sim, 'PeakingTime']) +' # Electronic peaking time in ns\n'

print('New parameters:')
[print(line) for line in lines[38:43]]

with open(attpcroot_param, "w") as f:
    f.writelines(lines)

# %%
# IF N is different, change Mg20_test_sim.C and rundigi_sim.C
if parameters.loc[active_sim, 'N'] != previous_N:
    # modify Mg20_test_sim.C
    with open(attpcroot_mg20_testsim_template, 'r') as f:
        lines = f.readlines()
    lines[0] = 'void Mg20_test_sim(Int_t nEvents = ' + str(parameters.loc[active_sim,'N']) +', TString mcEngine = "TGeant4")'
    with open(attpcroot_mg20_testsim, "w") as f:
        f.writelines(lines)
    
    # modify rundigi_sim.C
    with open(attpcroot_rundigi, 'r+') as f:
        lines = f.readlines()
        lines[68] = 'fRun->Run(0, ' + str(parameters.loc[active_sim,'N']) +');}'
        f.seek(0)
        f.writelines(lines)

# %%
# If particle energies are different, change AtTPC20MgDecay.cxx
# particle notation:
# P0 = primary particle, P1 = secondary particle
# a = alpha, p = proton, 0 = none
# if only one particle, P1 = 0, E1 is ignored
# for proton-alpha events, P0 = p, P1 = a, not reversed
# E0/E1 = energy of primary/secondary particle, KeV

if (parameters.loc[active_sim, 'P0'], parameters.loc[active_sim, 'E0'], parameters.loc[active_sim, 'P1'], parameters.loc[active_sim, 'E1']) != previous_Particles:
    
    # check if particle types and energies are valid
    if parameters.loc[active_sim, 'P0'] not in ['a', 'p']:
        indicator_file('STOP')
        raise Exception('Primary particle not specified')
    elif parameters.loc[active_sim, 'E0'] <= 0:
        indicator_file('STOP')
        raise Exception('Primary particle energy not specified or invalid')
    elif parameters.loc[active_sim, 'P1'] not in ['a', 'p', '0']:
        indicator_file('STOP')
        raise Exception('Secondary particle not specified')
    elif parameters.loc[active_sim, 'P1'] in ['a', 'p'] and parameters.loc[active_sim, 'E1'] <= 0:
        indicator_file('STOP')
        raise Exception('Secondary particle energy not specified or invalid')
    elif parameters.loc[active_sim, 'P0'] == 'a' and parameters.loc[active_sim, 'P1'] == 'a':
        indicator_file('STOP')
        raise Exception('Alpha-alpha events not supported yet')
    elif parameters.loc[active_sim, 'P0'] == 'p' and parameters.loc[active_sim, 'P1'] == 'p':
        indicator_file('STOP')
        raise Exception('Proton-proton events not supported yet')
    elif parameters.loc[active_sim, 'P0'] == 'a' and parameters.loc[active_sim, 'P1'] == 'p':
        indicator_file('STOP')
        raise Exception('Proton-Alpha events need to be in order (P0 = p, P1 = a)')
    
    # determine type of decay specified
    if parameters.loc[active_sim, 'P0'] == 'p':
        # proton decay 
        with open(proton_gen, 'r') as f:
            lines = f.readlines()
        lines[36] = '   Double32_t pabsProton = ' + str(energy_to_momentum(parameters.loc[active_sim, 'E0'], 'p')) + '; // GeV/c\n'
        with open(attpcroot_mg20_cxx, "w") as f:
            f.writelines(lines)
    
    elif parameters.loc[active_sim, 'P0'] == 'a':
        # alpha decay
        with open(alpha_gen, 'r') as f:
            lines = f.readlines()
        lines[36] = '   Double32_t pabsAlpha = ' + str(energy_to_momentum(parameters.loc[active_sim, 'E0'], 'a')) + '; // GeV/c'
        with open(attpcroot_mg20_cxx, "w") as f:
            f.writelines(lines)
        
    elif parameters.loc[active_sim, 'P0'] == 'p' and parameters.loc[active_sim, 'P1'] == 'a':
        # proton-alpha decay
        with open(pa_gen, 'r') as f:
            lines = f.readlines()
        lines[78] = '   Double32_t pabsProton = ' + str(energy_to_momentum(parameters.loc[active_sim, 'E0', 'p'])) + '; // GeV/c'
        lines[89] = '   Double32_t pabsAlpha = ' + str(energy_to_momentum(parameters.loc[active_sim, 'E1', 'a'])) + '; // GeV/c'
        with open(attpcroot_mg20_cxx, "w") as f:
            f.writelines(lines)
    
    
    # modify Mg20_test_sim.C for two-particle decay
    with open(attpcroot_mg20_testsim_template, 'r') as f:
        lines = f.readlines()
    # set primary particle
    lines[54] = '   decay->SetDecayChainPoint('+ str(energy_to_momentum(parameters.loc[active_sim, 'E0'], parameters.loc[active_sim, 'P0'])) + ', 1);        // p0'
    
    # set secondary particle
    if parameters.loc[active_sim, 'P1'] == 'a':
        lines[55] = '   decay->SetDecayChainPoint('+ str(energy_to_momentum(parameters.loc[active_sim, 'E1'], parameters.loc[active_sim, 'P1'])) + ', 2);        // p1'
    else: # comment out 2nd particle
        lines[55] = '//   decay->SetDecayChainPoint('+ str(0) + ', 1);        // p1'
    
    lines[0] = 'void Mg20_test_sim(Int_t nEvents = ' + str(parameters.loc[active_sim,'N']) +', TString mcEngine = "TGeant4")'
    
    with open(attpcroot_mg20_testsim, "w") as f:
        f.writelines(lines)

    indicator_file('BUILD')

# %%
# Update parameters.csv
parameters.to_csv(parameters_dir, index=False)


