"""Download only Actions evidence from the authorized repository over verified HTTPS."""
import sys
from pathlib import Path
from github_native import request_bytes,REPO
path=sys.argv[1]; out=Path(sys.argv[2]); binary=len(sys.argv)>3
if not path.startswith('/repos/'+REPO+'/actions/'):
    raise ValueError('Actions evidence path required')
payload=request_bytes('GET',path)
out.parent.mkdir(parents=True,exist_ok=True)
if binary: out.write_bytes(payload)
else: out.write_text(payload.decode('utf-8'))
print(str(out),out.stat().st_size)
