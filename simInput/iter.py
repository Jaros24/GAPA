# %%
# Load Packages - KEEP MINIMAL FOR FISHTANK COMPATIBILITY
import pandas as pd
import numpy as np
import os

# %%
# set locations for working files
# ATTPCROOTv2 directory
attpcroot_dir = '/mnt/analysis/e17023/Adam/ATTPCROOTv2/'

# Automation directory
automation_dir = '/mnt/analysis/e17023/Adam/GADGET2/'

# %%
def indicator_file(file_type, indicator_directory=automation_dir):
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
parameters = pd.read_csv(automation_dir + 'simInput/parameters.csv')

# %%
# check for and complete any active simulations

# 0 = inactive
# 1 = active
# 2 = complete

# todo: check for changes that require a rebuild

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
    for filename in os.listdir(automation_dir + 'simOutput/'):
        f = os.path.join(automation_dir + 'simOutput/', filename)
        # checking if it is a file
        if os.path.isfile(f):
            if filename == 'output.h5':
                os.rename(f, automation_dir + 'simOutput/' + active_sims.loc[active_sims.index[0],'Sim']+'.h5')
                Complete = True
    
    # Set Status in parameters
    if Complete:
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
    parameters.to_csv(automation_dir + 'simInput/parameters.csv', index=False)
    raise Exception('Finished with all simulations')
else:
    active_sim = inactive_sims.index[0]
    parameters.loc[active_sim, 'Status'] = 1
    print("next simulation: ", parameters.loc[active_sim, 'Sim'])

# %%
# run check on parameters to confirm they are valid
# TODO

# %%
# Modify GADGET.sim.par
with open(automation_dir + 'simInput/templates/GADGET.sim.par', 'r') as file :
    filedata = file.readlines()
    
# replace target parameters
for param in parameters.columns:
    for i, line in enumerate(filedata):
        if param == line.split(':')[0]:
            # Line composition:     param:ptype_t   paramval   # units / comments
            
            ptype = line.split(':')[1].split('_')[0]
            paramval = parameters.loc[active_sim, param]
            filedata[i] = param + ': ' + ptype + '_t     ' + str(paramval) + '     #' + line.split('#')[1]
 
# write file
with open(automation_dir + 'simInput/queue/GADGET.sim.par', 'w') as file:
    file.writelines(filedata)


# %%
# Modify AtTPC20MgDecay.cxx (Generators)
P0 = parameters.loc[active_sim, 'P0']; E0 = parameters.loc[active_sim, 'E0']
P1 = parameters.loc[active_sim, 'P1']; E1 = parameters.loc[active_sim, 'E1']

ParticleString = str(P0)
if E1 != 0:
    ParticleString = ParticleString + str(P1)

ParticleString = ParticleString.upper()

# TEST FOR EXISTING GENERATOR FILE AND EDIT WITH PARTICLE ENERGIES
if os.path.isfile(automation_dir + 'simInput/templates/Generator' + ParticleString + '.txt'):
    with open(automation_dir + 'simInput/templates/Generator' + ParticleString + '.txt', 'r') as file :
        filedata = file.readlines()
    
    # locate and replace particle energies (Comment lines in generators with P0 E0 or P1 E1 to specify which line to replace)
    for i, line in enumerate(filedata):
        if 'P0 E0' in line.split('//')[-1]:
            filedata[i] = line.split('=')[0] + '= ' + str(energy_to_momentum(E0, P0)) + '; // P0 E0\n'

        if 'P1 E1' in line.split('//')[-1]:
            filedata[i] = line.split('=')[0] + '= ' + str(energy_to_momentum(E1, P1)) + '; // P1 E1\n'

    
    # write file
    with open(automation_dir + 'simInput/queue/AtTPC20MgDecay.cxx', 'w') as file:
        file.writelines(filedata)

else: # STOP SIMULATIONS, GENERATOR FILE DOES NOT EXIST
    indicator_file('STOP')
    print('Generator file', ParticleString ,'does not exist')
    raise Exception('Generator file does not exist')

# %%
# MODIFY Mg20_test_sim.C
active_sim = 0

P0 = parameters.loc[active_sim, 'P0']; E0 = parameters.loc[active_sim, 'E0']
P1 = parameters.loc[active_sim, 'P1']; E1 = parameters.loc[active_sim, 'E1']

with open(automation_dir + 'simInput/templates/Mg20_test_sim.txt', 'r') as file:
    filedata = file.readlines()

# Modify particle momentum
for i, line in enumerate(filedata):
    if 'P0 E0' in line.split('//')[-1]:
        filedata[i] = line.split('(')[0] + '(' + str(energy_to_momentum(E0, P0)) + ', 1); // P0 E0\n'

    if 'P1 E1' in line.split('//')[-1]:
        if E1 == 0:
            filedata[i] = '// ' + line
        else:
            filedata[i] = line.split('(')[0] + '(' + str(energy_to_momentum(E1, P1)) + ', 1); // P1 E1\n'

# modify particle origin
for i, line in enumerate(filedata):
    if 'bounds' in line.split('//')[-1]:
        Xb = parameters.loc[active_sim, 'Xb']
        Yb = parameters.loc[active_sim, 'Yb']
        Zb1 = parameters.loc[active_sim, 'Zb1']
        Zb2 = parameters.loc[active_sim, 'Zb2']

        filedata[i] = line.split('(')[0] + '(' + str(-Xb) + ', ' + str(-Yb) + ', ' + str(Zb1) + ', ' + str(Xb) + ', ' + str(Yb) + ', ' + str(Zb2) + '); // bounds\n'

# modify number of particles
filedata[0] = filedata[0].split('=')[0] + '= ' + str(int(parameters.loc[active_sim, 'N'])) + ',' + filedata[0].split(',')[-1]

# write file
with open(automation_dir + 'simInput/queue/Mg20_test_sim.C', 'w') as file:
    file.writelines(filedata)

# %%
# Modify rundigi_sim.C
with open(automation_dir + 'simInput/templates/rundigi_sim.C', 'r') as file:
    filedata = file.readlines()

# modify number of particles
for i, line in enumerate(filedata):
    if ' N\n' == line.split('//')[-1]:
        filedata[i] = line.split(',')[0] + ', ' + str(int(parameters.loc[active_sim, 'N'])) + '); // N\n'

# modify Threshold
for i, line in enumerate(filedata):
    if 'Threshold' in line.split('//')[-1]:
        threshold = parameters.loc[active_sim, 'Threshold']

        filedata[i] = line.split('(')[0] + '(' + str(threshold) + '); // Threshold\n'

# write file
with open(automation_dir + 'simInput/queue/rundigi_sim.C', 'w') as file:
    file.writelines(filedata)

# %%
# POSSIBLE FUTURE FILE MODIFICATIONS (NOT CURRENTLY IMPLEMENTED)
# Modify R2HMain.cc
# TODO
# Modify media.geo
# TODO
# Modify GADGET_II.C
# TODO
# Modify GADGET_II_lp.C
# TODO

# %%
# Update parameters.csv
parameters.to_csv(automation_dir + 'simInput/parameters.csv', index=False)


