"""Static source/resource/configuration inspection only. Does not build, test or launch Papi."""
from pathlib import Path
from PIL import Image
from fontTools.ttLib import TTFont
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
   if 'filename' in image and Path(image['filename']).suffix.lower() not in {'.png','.jpg','.jpeg'}:errors.append(f'Unsupported bundled bitmap format: {image["filename"]}')
 except Exception as exc:errors.append(f'{p}: {exc}')
source_files=list((root/'Papi').rglob('*.swift'))
for p in source_files:
 source=p.read_text()
 for name in re.findall(r'(?:Image\(|PapiImage\(name:|PapiBackground\(asset:)"([^"\\]+)"',source):
  if name not in names:errors.append(f'{p.name}: unknown image {name}')
 if 'Image(systemName:' in source or 'UIScreen.main' in source:errors.append(f'{p.name}: forbidden image or global-screen pattern')
 for number,line in enumerate(source.splitlines(),1):
  if line.rstrip()!=line:errors.append(f'{p.name}:{number}: trailing whitespace')
  if re.search(r'(?<!\\)(?:\\\\)*\\u[0-9A-Fa-f]{4}',line):errors.append(f'{p.name}:{number}: JSON-style Unicode escape; use UTF-8 or Swift Unicode braces')
# Only coffee-focused films selected by the reviewed manifest are bundled.
manifest=json.loads((root/'docs/ASSET_MANIFEST.json').read_text())
films=[row for row in manifest if row.get('kind')=='film' and row.get('bundled',True)]
for row in films:
 for filename in [row['asset']+'.mp4',row['poster']]:
  p=root/'Papi/Resources/Media'/filename
  if not p.is_file() or p.stat().st_size==0:errors.append(f'Missing film resource: {filename}')
expected_films={row['asset']+'.mp4' for row in films}
actual_films={p.name for p in (root/'Papi/Resources/Media').glob('*.mp4')}
if actual_films!=expected_films:errors.append('Unexpected or missing bundled coffee film')
for p in [root/'Config/Info.plist',root/'Papi/Resources/PrivacyInfo.xcprivacy']:
 with p.open('rb') as f:plistlib.load(f)
info=plistlib.loads((root/'Config/Info.plist').read_bytes())
font_manifest=json.loads((root/'docs/TYPEFACES.json').read_text())
expected_fonts={'Fonts/'+row['filename'] for row in font_manifest}
if set(info.get('UIAppFonts',[]))!=expected_fonts:errors.append('UIAppFonts differs from the shipped typeface catalog')
font_bytes=0
for row in font_manifest:
 path=root/'Papi/Resources/Fonts'/row['filename']
 if not path.is_file():errors.append(f'Missing offline font: {path.name}');continue
 font=TTFont(path);names_in_font={n.toUnicode() for n in font['name'].names if n.nameID==6}
 if row['postScriptName'] not in names_in_font:errors.append(f'Font PostScript name mismatch: {path.name}')
 if font['OS/2'].usWeightClass!=row['weight']:errors.append(f'Font weight metadata mismatch: {path.name}')
 font_bytes+=path.stat().st_size
for license in ['fraunces-OFL.txt','nunito-OFL.txt']:
 if 'SIL OPEN FONT LICENSE' not in (root/'Papi/Resources/Fonts'/license).read_text():errors.append(f'Missing font license: {license}')
project=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(root/'Papi.xcodeproj/project.pbxproj')]))
objects=project['objects'];phases={}
for value in objects.values():
 if value.get('isa') in ['PBXSourcesBuildPhase','PBXResourcesBuildPhase']:
  phases[value['isa']]=[objects[objects[b]['fileRef']].get('path') or objects[objects[b]['fileRef']].get('name') for b in value.get('files',[]) if 'fileRef' in objects[b]]
expected={p.name for p in source_files};included=set(phases.get('PBXSourcesBuildPhase',[]))
if expected!=included:errors.append(f'Source phase mismatch: {expected ^ included}')
resources=set(phases.get('PBXResourcesBuildPhase',[]))
resource_names={Path(p).name for p in resources}
for required in ['Assets.xcassets','Media','Fonts','PrivacyInfo.xcprivacy','Localization','InfoPlist.strings']:
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
# Wallet catalog inspection: checks configuration and source references, not StoreKit execution.
commerce=(root/'Papi/Persistence/AppleCoinCounter.swift').read_text()
packs=re.findall(r'\.init\(id:"([a-z]+)",coins:(\d+),referenceUSD:"([0-9.]+)"\)',commerce)
fixed={'rkbybzkkqpeaxovi':'0.99','yiyfivvjmkdiuqus':'1.99','vguhlyrrsyfaswwv':'4.99',
       'qqopbybcdridrsjl':'9.99','kokiljjwycwbpasa':'19.99','nylrtdzhiqgywsrh':'49.99','lkcdocdwdjjjmdfr':'99.99'}
old_coins=[400,800,2450,5150,10800,29400,63700]
catalog={pid:(int(coins),price) for pid,coins,price in packs}
if len(packs)!=9 or len(catalog)!=9:errors.append('Wallet must contain nine unique packs')
if any(not re.fullmatch('[a-z]{16}',pid) for pid in catalog):errors.append('Coin product ID format changed')
for (pid,price),old in zip(fixed.items(),old_coins):
 if pid not in catalog or catalog[pid][1]!=price:errors.append(f'Protected Apple product or price changed: {pid}')
 elif catalog[pid][0]==old:errors.append(f'Coin quantity was not updated: {pid}')
reference=json.loads((root/'docs/COIN_PRODUCTS.json').read_text())['products']
if {p['productID']:(p['coins'],p['referencePrice']) for p in reference}!=catalog:errors.append('Coin configuration guide differs from native catalog')
if any(not 2<=len(p['displayName'])<=30 or not 1<=len(p['description'])<=45 for p in reference):errors.append('Coin product display copy exceeds App Store Connect limits')
if commerce.count('Product.products(for:')!=1 or 'Product.products(for:[pack.id])' not in commerce:errors.append('Unexpected product-fetch path')
wallet=(root/'Papi/CoffeeHouse/Counter/CoffeeCounter.swift').read_text()
if 'commerce.load' in wallet or 'purchasesConfigured' in commerce:errors.append('Obsolete purchase preload or disable switch')
if 'coinBalance -=' in (root/'Papi/Persistence/CommunityActions.swift').read_text():errors.append('Chat must not debit coins')
archive=(root/'Papi/CoffeeDomain/CoffeeArchive.swift').read_text()
for property,original in {'passport':'profile','coinBalance':'coins','coinMovements':'wallet','ownMoments':'localPosts','letterDrafts':'chatDrafts','tastingReplies':'comments','followedMembers':'follows','blockedMembers':'blocked'}.items():
 if f'case {property} = "{original}"' not in archive:errors.append(f'Legacy storage key changed: {property}')
if 'Papi.LocalGuest.v1' not in (root/'Papi/Persistence/CoffeeVault.swift').read_text():errors.append('Original Keychain service changed')
recipe_source=(root/'Papi/CoffeeDomain/BrewRecords.swift').read_text()
recipe_costs=[int(cost) for cost in re.findall(r'unlockCoins:(\d+)',recipe_source)]
if recipe_costs!=[0,0,120,180,240]:errors.append('Unexpected recipe pricing configuration')
report={'sourceFiles':len(source_files),'imageSets':len(names),'bundledVideos':len(films),'resourceBytes':size,'resourcePhase':sorted(resources),'translationEntries':len(translations),'uiLanguages':['en']+sorted(languages),'typefaceFamilies':len({row['family'] for row in font_manifest}),'fontStyles':len(font_manifest),'fontBytes':font_bytes,'coinPacks':len(packs),'protectedCoinProductIDs':len(fixed),'addedCoinPacks':len(catalog.keys()-fixed.keys()),'brewRecipes':len(recipe_costs),'freeBrewRecipes':recipe_costs.count(0),'paidRecipeCoins':[cost for cost in recipe_costs if cost>0],'findings':errors,'buildExecuted':False,'testsExecuted':False,'appLaunched':False,'storeKitExecuted':False,'binarySimilarityMeasured':False}
(root/'docs/STATIC_INSPECTION.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False,indent=2))
raise SystemExit(1 if errors else 0)
