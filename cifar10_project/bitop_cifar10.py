import numpy as np 
"""
    Edited by WL from mms@gscst
    Project term : Fall 2019
"""
"""
    8-bit 2's complement fixed point representations:
    sign: 1-bit
    int: 1-bit
    frac: 6-bit
    
    representation: x x . x x x x x x
    E.g) 10.100001 
         = (-2)*1 + 1*0 + 0.5*1 + 0.25*0 + 0.125*0 + 0.0625*0 + 0.03125*0 + 0.015625*1
         = -1.484375
"""

def val_to_8bit_fixed(data):
    ret_val = data
    if ret_val > 1.984375:
        ret_val = 1.984375
    elif ret_val < -2:
        ret_val = -2
    
    ret_val = int(ret_val*64)/64

    return ret_val

def to_8bit_fixed(data):
    shape = data.shape
    data = data.flatten()
    for i in range(data.size):
        data[i] = val_to_8bit_fixed(data[i])
    data = data.reshape(shape)
    return data

def data_to_8bit_binary(data):
    ret_val = data
    if ret_val > 1.984375:
        ret_val = 1.984375
    elif ret_val < -2:
        ret_val = -2
    ret_val = int(ret_val * 64)
    
    if ret_val < 0:
        ret_val = 256 + ret_val
    return ret_val

def to_8bit_fixed_binary(data):
    shape = data.shape
    data = data.flatten()
    for i in range(data.size):
        data[i] = data_to_8bit_binary(data[i])
    data = data.reshape(shape)
    return data