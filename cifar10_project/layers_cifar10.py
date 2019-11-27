import numpy as np
# These layer functions are implemented in very very naive ways.

def conv(x, w, b, conv_param):
    # print(x.shape)
    # Input
    N, C, W, H = x.shape
    
    # Filter
    F, C, WW, HH = w.shape
    # Parameter
    stride = conv_param['stride']
    pad = conv_param['pad']

    # Calculate for output size
    H_out = 1 + int((H+2*pad-HH)/stride)
    W_out = 1 + int((W+2*pad-WW)/stride)
    # Padding using numpy.pad function
    x_pad = np.pad(x, pad_width=((0, 0), (0, 0), (pad, pad), (pad, pad)), mode='constant', constant_values=0)
    out = np.zeros((N, F, H_out, W_out))
    
    # just loop-method
    for i in range(N):
        for j in range(F):
            for k in range(H_out):
                for l in range(W_out):
                    out[i, j, k, l] = np.sum(x_pad[i, :, k*stride:k*stride+HH, l*stride:l*stride+WW] * w[j,:,:,:])+b[j]
    return out

def maxpool(x, pool_param):
    # Input
    N, C, W, H = x.shape
    # Pooling parameter
    ph = pool_param['pool_height']
    pw = pool_param['pool_width']
    stride = pool_param['stride']
    # Calculate for output size
    H_out = int((H - ph)/stride + 1)
    W_out = int((W - pw)/stride + 1)
    out = np.zeros((N, C, H_out, W_out))
    
    # just loop-method
    for i in range(N):
        for j in range(H_out):
            for k in range(W_out):
                h_i = j*stride
                h_f = j*stride + ph
                w_i = k*stride
                w_f = k*stride + pw
                temp = x[i, :, h_i:h_f, w_i:w_f]                
                out[i, :, j, k] = np.max(np.reshape(temp, (C, ph*pw)), axis=1)
    return out

def relu(x):
    out = np.maximum(0, x)
    return out

def fully_connected(x, w, b):
    out = np.dot(x, w.T) + b
    return out
