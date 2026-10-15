"""Sequential block extractor for NSIS 1.x installers (len-prefixed raw deflate blocks)."""
import sys, zlib, os

data = open(sys.argv[1], 'rb').read()
out = sys.argv[2]
os.makedirs(out, exist_ok=True)
i = 0x881c
n = 0
while i + 4 <= len(data):
    ln = int.from_bytes(data[i:i + 4], 'little')
    comp = bool(ln & 0x80000000)
    ln &= 0x7FFFFFFF
    i += 4
    if ln == 0 or i + ln > len(data):
        print('stop at', hex(i), ln)
        break
    chunk = data[i:i + ln]
    i += ln
    try:
        res = zlib.decompress(chunk, -15) if comp else chunk
    except zlib.error as e:
        print('fail', n, e)
        res = chunk
    kind = 'pe' if res[:2] == b'MZ' else 'bin'
    fn = f'{out}/{n:03d}_{kind}.dat'
    open(fn, 'wb').write(res)
    print(fn, len(res))
    n += 1
print('blocks', n)
