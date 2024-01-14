#!/usr/bin/env python3
# ruff: noqa: T201

from hashlib import scrypt

passw = bytes(input("password: "), "ascii")
salt = b"tamborg"
np = 20
n = 2**np
r = 8
p = 1
maxmem = 2**(np+10) + 2**20
dklen = 16

h = scrypt(passw, salt=salt, n=n, r=r, p=p, maxmem=maxmem, dklen=dklen)
print(h.hex())
