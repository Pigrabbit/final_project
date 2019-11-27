import os
import struct
import gzip
import shutil
import urllib.request
import numpy as np
from matplotlib import pyplot as plt

def download_dataset():
    if not os.path.exists("./dataset_mnist"):
        os.makedirs("./dataset_mnist")
    print("Download the MNIST dataset from http://yann.lecun.com/exdb/mnist/")
    if not os.path.exists("./dataset_mnist/train-images-idx3-ubyte.gz"):
        print("\thttp://yann.lecun.com/exdb/mnist/train-images-idx3-ubyte.gz")
        urllib.request.urlretrieve("http://yann.lecun.com/exdb/mnist/train-images-idx3-ubyte.gz", \
                                "./dataset_mnist/train-images-idx3-ubyte.gz")
    if not os.path.exists("./dataset_mnist/train-images-idx1-ubyte.gz"):
        print("\thttp://yann.lecun.com/exdb/mnist/train-labels-idx1-ubyte.gz")
        urllib.request.urlretrieve("http://yann.lecun.com/exdb/mnist/train-labels-idx1-ubyte.gz", \
                                "./dataset_mnist/train-images-idx1-ubyte.gz")

    if not os.path.exists("./dataset_mnist/t10k-images-idx3-ubyte.gz"):
        print("\thttp://yann.lecun.com/exdb/mnist/t10k-images-idx3-ubyte.gz")
        urllib.request.urlretrieve("http://yann.lecun.com/exdb/mnist/t10k-images-idx3-ubyte.gz", \
                                "./dataset_mnist/t10k-images-idx3-ubyte.gz")
    if not os.path.exists("./dataset_mnist/t10k-images-idx1-ubyte.gz"):
        print("\thttp://yann.lecun.com/exdb/mnist/t10k-labels-idx1-ubyte.gz")
        urllib.request.urlretrieve("http://yann.lecun.com/exdb/mnist/t10k-labels-idx1-ubyte.gz", \
                                "./dataset_mnist/t10k-images-idx1-ubyte.gz")
    print("Finish download the MNIST dataset.")
    return None

def unzip_mnist(path):
    if not os.path.exists(path):
        print("File %s doesn't exists!" %(path))
    else:
        with gzip.open(path, 'rb') as f_in:
            path_r = path.replace(".gz","")
            with open(path_r, "wb") as f_out:
                shutil.copyfileobj(f_in, f_out)

def load_mnist(image_path, label_path):
    with open(label_path, 'rb') as l:
        temp, n = struct.unpack('>II', l.read(8))
        label = np.fromfile(l, dtype=np.uint8)
    with open(image_path, 'rb') as i:
        temp, n, r, c = struct.unpack('>IIII', i.read(16))
        image = np.fromfile(i, dtype=np.uint8).reshape(len(label), 784)
    return image, label

def gen_image(arr):
    pixels = (np.reshape(arr, (28, 28)) * 255).astype(np.uint8)
    plt.imshow(pixels, cmap='gray')
    return plt
