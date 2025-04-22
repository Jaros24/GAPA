# %%
import numpy as np
import os
import h5py
import subprocess
import tqdm

# %%
Hdf5_output_directory = "/mnt/analysis/e17023/Adam/GAPA/Output/hdf5/"
merged_simulation_file = "merged_h5.h5"

# %%
component_h5_list = [filename for filename in os.listdir(Hdf5_output_directory) if filename.endswith('.h5')]
if len(component_h5_list) == 0:
    raise FileNotFoundError("No .h5 files found in the specified directory.")
if merged_simulation_file in component_h5_list:
    print(f"Warning: {merged_simulation_file} already exists in the directory. It will be overwritten.")
    os.remove(f"{Hdf5_output_directory}{merged_simulation_file}")
    component_h5_list.remove(merged_simulation_file)
component_h5_list.sort()

# copy first file as template
template_h5 = component_h5_list.pop(0)
os.system(f"cp {Hdf5_output_directory}{template_h5} {Hdf5_output_directory}{merged_simulation_file}")

for component_h5 in tqdm.tqdm(component_h5_list):
    batch_h5 = h5py.File(f"{Hdf5_output_directory}{merged_simulation_file}", 'a')
    component_h5 = h5py.File(f"{Hdf5_output_directory}{component_h5}", 'r')
    
    # get the event number of the last event in the batch
    last_event_number = int(batch_h5["meta/meta"][2]) + 1
    
    # merge get data
    for key in component_h5['get'].keys():
        if 'data' in key:
            try:
                event_number = int(key.split('_')[0][3:])
                batch_h5.create_dataset(f"get/evt{event_number + last_event_number}_header", data=component_h5[f"get/{key}"], dtype='float64')
                batch_h5.create_dataset(f"get/evt{event_number + last_event_number}_data", data=component_h5[f"get/{key}"], dtype='int16')
                batch_h5[f'get/evt{event_number + last_event_number}_header'][0] = event_number + last_event_number # update the event number in the header
            except IndexError:
                print(f"Error in {component_h5} - {key}")
    meta_data = batch_h5["meta/meta"]
    
    # merge clouds data
    for key in component_h5['clouds'].keys():
        event_number = int(key.split('_')[0].split('t')[1]) # evt#_cloud
        batch_h5.create_dataset(f"clouds/evt{event_number + last_event_number}_cloud", data=component_h5[f"clouds/{key}"], dtype='float64')
        meta_data[2] = max(meta_data[2], event_number + last_event_number)
    
    # re-write the meta data
    batch_h5['meta'].pop('meta')
    batch_h5.create_dataset("meta/meta", data=meta_data, dtype='float64')
    
    # close the files
    component_h5.close()
    batch_h5.close()


