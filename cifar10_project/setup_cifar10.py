import pickle
import numpy as np
import os
import struct
import urllib.request
import shutil
import tarfile
import gzip
import csv
from matplotlib import pyplot as plt

def isfloat(value):
    try:
        float(value)
        return True
    except ValueError:
        return False

def download_dataset():
    if not os.path.exists("./dataset_cifar10/"):
        os.makedirs("./dataset_cifar10/")
    print("Download the CIFAR-10 dataset from https://www.cs.toronto.edu/~kriz/cifar.html")
    if not os.path.exists("./dataset_cifar10/cifar-10-python.tar.gz"):
        print("\thttps://www.cs.toronto.edu/~kriz/cifar-10-python.tar.gz")
        urllib.request.urlretrieve("https://www.cs.toronto.edu/~kriz/cifar-10-python.tar.gz", \
                                   "./dataset_cifar10/cifar-10-python.tar.gz")
    print("Finish download the CIFAR-10 dataset.")
    return None

def unzip_cifar10(path):
    if not os.path.exists(path):
        print("File %s doesn't exists!" %(path))
    if path.endswith("tar.gz"):
        tar = tarfile.open(path, "r:gz")
        tar.extractall()
        tar.close()

def gen_image(arr):
    R = arr[0]
    G = arr[1]
    B = arr[2]
    pixels = np.dstack((R,G,B))
    plt.imshow(pixels, interpolation='bicubic')
    return plt

# Using Python style data loading...
def load_CIFAR10_batch(file_name):
    path = "./cifar-10-batches-py/"
    with open(path + file_name, 'rb') as fo:
        data_dict = pickle.load(fo, encoding='latin1')
        X = data_dict['data']
        Y = data_dict['labels']
        X = X.reshape(10000, 3, 32, 32)
        X = X/255
        Y = np.array(Y)
        return X, Y

def load_CIFAR10_test():
    X_test, Y_test = load_CIFAR10_batch("test_batch")
    return X_test, Y_test
