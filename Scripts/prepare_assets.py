"""Restore missing explicit artwork mappings without undoing optimized bundled copies."""
from pathlib import Path
import json,shutil,subprocess
root=Path(__file__).resolve().parents[1]
assets=root/'Papi/Resources/Assets.xcassets';media=root/'Papi/Resources/Media'
manifest=json.loads((root/'docs/ASSET_MANIFEST.json').read_text())
restored=[]
for row in manifest:
 if row.get('bundled',True) is False:continue
 source=root/row['source'];name=row['asset']
 if not source.is_file():raise FileNotFoundError(source)
 if row.get('kind')=='film':
  media.mkdir(exist_ok=True)
  target=media/(name+'.mp4')
  if not target.exists():shutil.copy2(source,target);restored.append(name)
  poster=media/row['poster']
  if not poster.exists():subprocess.run(['ffmpeg','-nostdin','-v','error','-y','-i',str(target),'-frames:v','1','-vf','scale=600:-2',str(poster)],check=True)
 else:
  folder=assets/(name+'.imageset');contents=folder/'Contents.json'
  if contents.exists():
   data=json.loads(contents.read_text())
   if all((folder/item['filename']).exists() for item in data['images'] if 'filename' in item):continue
  folder.mkdir(exist_ok=True);filename=name+source.suffix.lower();shutil.copy2(source,folder/filename)
  contents.write_text(json.dumps({'images':[{'filename':filename,'idiom':'universal','scale':'2x'}],'info':{'author':'xcode','version':1}},indent=2)+'\n');restored.append(name)
print('Verified explicit source mappings. Restored:',restored)
