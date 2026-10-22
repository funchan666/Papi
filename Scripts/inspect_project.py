"""Static resource/configuration inspection only. Does not build, test or launch Papi."""
from pathlib import Path
from PIL import Image
import json,plistlib,re,subprocess
root=Path(__file__).resolve().parents[1]
errors=[]
assets=root/'Papi/Resources/Assets.xcassets'
names={p.stem for p in assets.glob('*.imageset')}
for p in assets.rglob('Contents.json'):
 try:
  value=json.loads(p.read_text())
  for image in value.get('images',[]):
   if 'filename' in image and not (p.parent/image['filename']).is_file():errors.append(f'Missing asset: {p.parent/image["filename"]}')
 except Exception as exc:errors.append(f'{p}: {exc}')
source_files=list((root/'Papi').rglob('*.swift'))
for p in source_files:
 source=p.read_text()
 for name in re.findall(r'(?:Image\(|PapiImage\(name:|PapiBackground\(asset:)"([^"\\]+)"',source):
  if name not in names:errors.append(f'{p.name}: unknown image {name}')
 if 'Image(systemName:' in source or 'UIScreen.main' in source:errors.append(f'{p.name}: forbidden image or global-screen pattern')
 for number,line in enumerate(source.splitlines(),1):
  if line.rstrip()!=line:errors.append(f'{p.name}:{number}: trailing whitespace')
# Every seeded bundled video must have its real poster and file.
for index in range(21):
 for ext in ['mp4','jpg']:
  p=root/f'Papi/Resources/Media/coffeeVideo{index:02d}.{ext}'
  if not p.is_file() or p.stat().st_size==0:errors.append(f'Missing video resource: {p.name}')
for p in [root/'Config/Info.plist',root/'Papi/Resources/PrivacyInfo.xcprivacy']:
 with p.open('rb') as f:plistlib.load(f)
project=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(root/'Papi.xcodeproj/project.pbxproj')]))
objects=project['objects'];phases={}
for value in objects.values():
 if value.get('isa') in ['PBXSourcesBuildPhase','PBXResourcesBuildPhase']:
  phases[value['isa']]=[objects[objects[b]['fileRef']].get('path') or objects[objects[b]['fileRef']].get('name') for b in value.get('files',[]) if 'fileRef' in objects[b]]
expected={p.name for p in source_files};included=set(phases.get('PBXSourcesBuildPhase',[]))
if expected!=included:errors.append(f'Source phase mismatch: {expected ^ included}')
resources=set(phases.get('PBXResourcesBuildPhase',[]))
resource_names={Path(p).name for p in resources}
for required in ['Assets.xcassets','Media','PrivacyInfo.xcprivacy','Localization','InfoPlist.strings']:
 if required not in resource_names:errors.append(f'Missing resource-phase entry: {required}')
if any('ProjectMaterials' in str(v) for v in objects.values()):errors.append('Raw project materials were added to the Xcode project')
with Image.open(assets/'AppIcon.appiconset/AppIcon.png') as icon:
 if icon.size != (1024,1024) or icon.mode != 'RGB':errors.append('App icon packaging is not 1024px opaque RGB')
size=sum(p.stat().st_size for p in (root/'Papi/Resources').rglob('*') if p.is_file())
translations=json.loads((root/'Papi/Resources/Localization/PapiTranslations.json').read_text())
languages={'es','th','ar','vi','ko'}
for key,values in translations.items():
 if set(values)!=languages:errors.append(f'Incomplete languages: {key}')
 expected=set(re.findall(r'\{\d+\}',key))
 for language,text in values.items():
  if not text or set(re.findall(r'\{\d+\}',text))!=expected:errors.append(f'Translation placeholder mismatch: {language}: {key}')
for code in languages|{'en'}:
 path=root/f'Papi/Resources/InfoPlistLocalizations/{code}.lproj/InfoPlist.strings'
 if not path.exists():errors.append(f'Missing privacy permission copy: {code}')
 else:
  result=subprocess.run(['plutil','-lint',str(path)],capture_output=True,text=True)
  if result.returncode:errors.append(result.stdout+result.stderr)
report={'sourceFiles':len(source_files),'imageSets':len(names),'bundledVideos':21,'resourceBytes':size,'resourcePhase':sorted(resources),'translationEntries':len(translations),'uiLanguages':['en']+sorted(languages),'findings':errors,'buildExecuted':False,'testsExecuted':False,'appLaunched':False}
(root/'docs/STATIC_INSPECTION.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False,indent=2))
raise SystemExit(1 if errors else 0)
