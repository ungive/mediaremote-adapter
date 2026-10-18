import json, os, subprocess
from pathlib import Path
binary=Path(__file__).resolve().parents[1]/'build/test-get-bundle'
def read(bundle, sessions, **flags):
 env=dict(os.environ, SESSIONS=json.dumps(sessions), MEDIAREMOTEADAPTER_OPTION_bundle_id=bundle)
 env.update({'MEDIAREMOTEADAPTER_OPTION_'+k:v for k,v in flags.items()})
 return subprocess.run([str(binary)],env=env,text=True,capture_output=True)
def session(bundle,parent=None,state=1,info=None):
 return dict(bundle=bundle,parent=parent,state=state,pid=123,info=info or {'kMRMediaRemoteNowPlayingInfoTitle':'Song'})
a=session('shared.helper','browser.a');b=session('shared.helper','browser.b',state=2)
r=read('shared.helper',[a,b]); data=json.loads(r.stdout)
assert len(data)==2 and data[0]['playing'] is True and data[1]['playing'] is False, r
assert data[0]['bundleIdentifier']=='shared.helper'
assert len(json.loads(read('browser.a',[a,b]).stdout))==1
assert json.loads(read('missing',[a,b]).stdout)==[]
assert json.loads(read('com.vandenbe.MediaRemoteAdapter.TestClient',[session('com.vandenbe.MediaRemoteAdapter.TestClient')]).stdout)==[]
r=read('',[a]);assert r.returncode!=0 and 'Missing value' in r.stderr
untitled=session('app',info={'kMRMediaRemoteNowPlayingInfoDuration':100})
assert json.loads(read('app',[untitled]).stdout)==[]
assert len(json.loads(read('app',[untitled],allow_missing_title='1').stdout))==1
print('PASS: multiple clients, parent matching, true/false state without playback rate, missing client, test exclusion, empty option, missing-title opt-in')
