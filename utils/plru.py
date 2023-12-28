#!/usr/bin/env python3
import math

NUM_WAYS = 8
NUM_LEVELS = math.ceil(math.log(NUM_WAYS, 2))

bits = [0 for i in range(NUM_WAYS)]
bits[0] = 'X'

# Marks a given way as in use
def update_mru(tree, way):
    # print("Updating way", way)
    idx = way + 2**NUM_LEVELS

    while idx > 0:
        parent = math.floor(idx / 2)
        # print(idx, parent)

        if (parent == 0): break

        if (idx % 2 == 0):
            # Even
            tree[parent] = 1
        else:
            # Odd
            tree[parent] = 0

        idx = parent

# Gets lru way
def get_lru(tree):
    idx = 1
    while idx < NUM_WAYS:
        if (tree[idx] == 1): idx = 2 * idx + 1
        else: idx = 2 * idx
    return idx - NUM_WAYS

def print_lru(tree):
    print("LRU is", get_lru(tree))

def test_plru(tree):
    update_mru(tree, get_lru(tree))
    print_lru(tree)

def test_plru_access(tree, way):
    update_mru(tree, way)
    print_lru(tree)

# Perform the same test as SV testbench:
def test(bits):
    print("Testing cold miss pattern")
    print_lru(bits)
    test_plru(bits)
    test_plru(bits)
    test_plru(bits)
    test_plru(bits)
    test_plru(bits)
    test_plru(bits)
    test_plru(bits)
    test_plru(bits)
    test_plru(bits)
    test_plru(bits)
    test_plru(bits)
    test_plru(bits)
    test_plru(bits)
    test_plru(bits)
    test_plru(bits)

    # Simulate accessing the same few pieces of data
    print("Test temporal locality access")
    test_plru_access(bits, 0)
    test_plru_access(bits, 0)
    test_plru_access(bits, 0)
    test_plru_access(bits, 0)
    test_plru_access(bits, 0)

    print("Testing various way accesses")
    test_plru_access(bits, 0)
    test_plru_access(bits, 4)
    test_plru_access(bits, 0)
    test_plru_access(bits, 4)
    test_plru_access(bits, 1)
    test_plru_access(bits, 3)
    test_plru_access(bits, 7)
    test_plru_access(bits, 6)

# Test!
test(bits)
