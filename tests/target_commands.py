import subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[1]
framework=root/'build/MediaRemoteAdapter.framework'
for command,value in [('send','2'),('seek','0'),('shuffle','1'),('repeat','1'),('speed','1')]:
 for args in [[command,value,'--bundle-id=not.registered'],[command,'--bundle-id=not.registered',value]]:
  r=subprocess.run(['/usr/bin/perl',str(root/'bin/mediaremote-adapter.pl'),str(framework)]+args,text=True,capture_output=True)
  assert r.returncode==1 and 'Targeted commands are unsupported' in r.stderr, r
 r=subprocess.run(['/usr/bin/perl',str(root/'bin/mediaremote-adapter.pl'),str(framework),command,value,'--bundle-id='],text=True,capture_output=True)
 assert r.returncode==1 and 'Missing value' in r.stderr, r
print('PASS: all five commands reject targets in either option position; empty targets fail')
