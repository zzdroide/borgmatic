# First ensure that this actually prevents history from being saved to disk: (~/.python_history)
import readline
readline.set_auto_history(False)


from hashlib import scrypt
scrypt(b'pass', salt=b'', n=2**20, r=8, p=1, maxmem=2**30+2**20, dklen=16).hex()
# TODO: salt=b'borg'
# TODO: make this executable and automatic
