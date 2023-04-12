# %%
import numpy as np
import pandas as pd
import math
import random

automation_dir = '/mnt/analysis/e17023/Adam/GADGET2/'

# set the seed for reproducibility
seed = input("Random Number Seed: ")
if seed == '':
    seed = random.randint(0, 1000000)
try:
    seed = int(seed)
except:
    pass
random.seed(seed)

# particle specification, will be made more variable later
print("format to be used for particle specification: 'E0P0, E0P0 E1P1, ...'")
print("currently implimented particle types: p, a")
print("particle energies specified in keV")
particles = input("Types of particles to simulate: ")
if particles == '':
    particles = '800p, 500a, 1200p 500a'

# split the particles into a list
particles = particles.split(',')
particles = [particle.split() for particle in particles]

# split particles into their respective types and energies
for i in range(len(particles)):
    particle = particles[i]
    # specify E1P1 if only one particle type is specified (marks as zero energy alpha)
    if len(particle) == 1:
        particle.append('0a')
    
    # split the particle type and energy
    P0 = particle[0][-1]
    E0 = particle[0][:-1]
    P1 = particle[1][-1]
    E1 = particle[1][:-1]
    particles[i] = [P0, float(E0), P1, float(E1)]


# number of events per simulation
nEvents = input("Number of events per simulation: ")
if nEvents == '':
    nEvents = 100
nEvents = int(nEvents)

# number of simulations per particle type
nSims = input("Number of simulations: ")
if nSims == '':
    nSims = 10
nSims = int(nSims)


# determine if parameter file should be overwritten or appended
overwrite = input("Overwrite parameter file? (y/n): ")
if overwrite == 'y':
    overwrite = True
else:
    overwrite = False

# name of simulations
simName = input("Simulations label: ")

# print the hyperparameters
print("Random Seed: ", seed)
print("Particles: ", particles)
print("Number of Events: ", nEvents)
print("Number of Simulations: ", nSims)
print("Overwrite: ", overwrite)
print("Simulations Label: ", simName)

# %%
# read in the default parameters from GADGET.sim.par
# and store them in a dictionary
# key: parameter name

param_dict = {}

with open(automation_dir + 'simInput/templates/GADGET.sim.par') as f:
    lines = f.readlines()
for i in range(len(lines)):
    # if line is commented, skip
    if lines[i][0] == '#':
        continue

    seg0 = lines[i].split(':')[0]
    seg1 = lines[i].split(':')[-1]
    if 'Int_t' in seg1 or 'Double_t' in seg1:
        # extract the number from seg1
        for j in seg1.split('#')[0].split(' '):
            if j != '':
                try:
                    float(j)
                    if 'Int_t' in seg1:
                        param_dict[seg0] = [int(j), 0, 0]
                    else:
                        param_dict[seg0] = [float(j)]
                        # determine precision of parameter
                        if '.' in j:
                            param_dict[seg0].append(len(j.split('.')[1]))
                        else:
                            param_dict[seg0].append(1)
                        
                        param_dict[seg0].append(0)

                except:
                    pass

# Add additional parameters by hand
param_dict['Xb'] = [0, 0, 0]
param_dict['Yb'] = [0, 0, 0]
param_dict['Zb1'] = [10, 0, 0]
param_dict['Zb2'] = [40, 0, 0]

param_dict['Threshold'] = [20, 0, 0]

# %%
def param_variation(val0, var, var_type='uniform', fraction = False, decimal=0):
    # val0: the base value
    # var: the variation
    # var_type: the type of distribution to use
    # fraction: whether the variation is a fraction of the base value
    # decimal: the number of decimal places to round to

    if fraction == True:
        var *= val0 

    if var_type == 'uniform':
        val = np.random.uniform(val0-var, val0+var)
    elif var_type == 'normal':
        val = np.random.normal(val0, var)
    elif var_type == 'triangular':
        val = np.random.triangular(val0-var, val0, val0+var)
    else:
        raise ValueError('var_type not valid')
    
    val = np.round(val, decimal)
    if decimal == 0:
        val = val.astype(int)
    
    # basic error checking, if the value is opposite sign of the base value or zero, return the base value
    if val*val0 <= 0:
        val = val0

    return val

# %%
# ask for variation in parameters

# percent variation
percent = input("Is the variation to be specified a percentage of the base value? (y/n): ")
if percent == 'y' or percent == 'Y' or percent == '':
    percent = True
else:
    percent = False

# iterate over the parameters, asking for variation
# if only one number is specified, base is assumed to be default, and variation is the number
# if two numbers are specified, the first is the base, and the second is the variation

differing_params = []
print('Format for specifying variation:')
print('if base value is default, only specify variation')
print('if base value is not default, specify base value then variation separated by a space')

for param in param_dict.keys():
    var = input(str(param) + ": " + str(param_dict[param][0]) + " variation: ") 
    if var != '':
        var = var.split()
        differing_params.append(param)
        if len(var) == 1:
            var = float(var[0])
            param_dict[param][2] = var
        elif len(var) == 2:
            param_dict[param][0] = float(var[0])
            param_dict[param][2] = float(var[1])

# %%
if overwrite:
    param_df = pd.DataFrame(columns=['Sim', 'Status', 'N', 'P0', 'E0', 'P1', 'E1', 'Xb', 'Yb', 'Zb1', 'Zb2', 'Threshold'])
else:
    param_df = pd.read_csv(automation_dir + 'simInput/parameters.csv')

var_type = input("Variation type (uniform, normal, triangular): ")
if var_type == '':
    var_type = 'normal'

for i in range(nSims):
    sim_variation = []
    # determine the variation in the parameters
    for param in differing_params:
        if percent:
            var = param_dict[param][2]/100
        else:
            var = param_dict[param][2]
        
        val0 = param_dict[param][0]
        decimal = param_dict[param][1]

        sim_variation.append(param_variation(val0, var, var_type='normal', fraction=percent, decimal=decimal))

    for particle in particles:
        P0 = particle[0]
        E0 = particle[1]
        P1 = particle[2]
        E1 = particle[3]

        # determine name for simulation
        if E1 != 0:
            sim_name = simName + str(i) + '-' + str(int(round(E0,0))) + P0 + str(int(round(E1,0))) + P1
        else:
            sim_name = simName + str(i) + '-' + str(int(round(E0,0))) + P0
        
        # write the parameters to a file
        param_df = pd.concat([param_df, pd.DataFrame([[sim_name, 0, nEvents, P0, E0, P1, E1, *sim_variation]], columns=['Sim', 'Status', 'N', 'P0', 'E0', 'P1', 'E1', *differing_params])], ignore_index=True)
    #[print(differing_params[i], ': ', sim_variation[i]) for i in range(len(differing_params))]

# fill in NaN values with default values
for param in param_dict.keys():
    if param in param_df.columns:
        param_df[param] = param_df[param].fillna(param_dict[param][0])
    

# %%
param_df.to_csv(automation_dir + 'simInput/parameters.csv', index=False)

# %%



