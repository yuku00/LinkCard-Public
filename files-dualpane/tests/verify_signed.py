"""Verify each Mach-O slice's embedded CodeDirectory page hashes (ad-hoc signature integrity)."""
from pathlib import Path
import sys, struct, hashlib
b=Path(sys.argv[1]).read_bytes()
u32=lambda data,off: struct.unpack_from('>I',data,off)[0]
assert u32(b,0)==0xcafebabe
count=u32(b,4); assert count==2
for i in range(count):
    cpu,sub,offset,size,align=struct.unpack_from('>IIIII',b,8+i*20)
    data=b[offset:offset+size]; assert data[:4]==bytes.fromhex('cffaedfe')
    pos=32; signature=None
    for _ in range(struct.unpack_from('<I',data,16)[0]):
        cmd,length=struct.unpack_from('<II',data,pos)
        assert length>=8 and pos+length<=len(data)
        if cmd==29:
            start,n=struct.unpack_from('<II',data,pos+8); signature=data[start:start+n]
        pos+=length
    assert signature and u32(signature,0)==0xfade0cc0
    checked=0
    for j in range(u32(signature,8)):
        slot,off=struct.unpack_from('>II',signature,12+j*8)
        if u32(signature,off)!=0xfade0c02: continue
        cd=signature[off:off+u32(signature,off+4)]
        hashOffset,nSlots,limit=u32(cd,16),u32(cd,28),u32(cd,32)
        hashSize,hashType,platform,pageShift=cd[36:40]
        algorithm={1:'sha1',2:'sha256',3:'sha256',4:'sha384'}[hashType]
        page=1<<pageShift if pageShift else limit
        assert limit<=len(data) and nSlots==(limit+page-1)//page
        for k in range(nSlots):
            digest=hashlib.new(algorithm,data[k*page:min((k+1)*page,limit)]).digest()[:hashSize]
            assert digest==cd[hashOffset+k*hashSize:hashOffset+(k+1)*hashSize], 'invalid code page signature'
        checked+=1
    assert checked
    print('PASS signature code pages',hex(cpu),hex(sub),'CodeDirectories',checked)
