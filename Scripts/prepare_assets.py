"""Copy explicitly selected source artwork. Never add ProjectMaterials to the target."""
from pathlib import Path
import json, shutil, subprocess
from PIL import Image
root=Path(__file__).resolve().parents[1]
assets=root/'Papi/Resources/Assets.xcassets'
manifest_path=root/'docs/ASSET_MANIFEST.json'
previous={item['asset']:item for item in json.loads(manifest_path.read_text())} if manifest_path.exists() else {}
assets.mkdir(parents=True,exist_ok=True)
def save_json(path,value):path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')
save_json(assets/'Contents.json',{'info':{'author':'xcode','version':1}})
mapping={
'brandMark':'image_868@2x.png','welcomeBackground':'Group_1271@2x.png','onboardingPour':'Group_1272@2x.png','onboardingChill':'Group_1273@2x.png','onboardingRoast':'Group_1274@2x.png','pageBackground':'Group_1295@2x.png','roomListBackground':'Group_1285@2x.png',
'homeTitle':'Group_1275@2x.png','exploreBanner':'Group_1276@2x.png','beansBanner':'Group_1277@2x.png','chatTitle':'Group_1286@2x.png','profileTitle':'Group_1287@2x.png','walletBanner':'Group_1288@2x.png','levelBanner':'Group_1289@2x.png','checkinBackground':'Group_1292@2x.png','levelCard':'Group_1293@2x.png','walletCard':'Group_1294@2x.png',
'beanArabica':'Group_1278@2x.png','beanRobusta':'Group_1279@2x.png','beanGeisha':'Group_1280@2x.png','beanBourbon':'Group_1281@2x.png','beanPacamara':'Group_1282@2x.png','beanSL28':'Group_1283@2x.png',
'back':'Frame@2x(29).png','close':'Frame@2x(17).png','more':'Frame@2x(24).png','moreLight':'Frame@2x(16).png','plus':'Frame@2x(25).png','edit':'Frame@2x(2).png','star':'Frame@2x(23).png','photo':'Frame@2x(15).png','send':'Frame@2x(34).png','check':'Frame@2x(12).png','trash':'Frame@2x(30).png','chevron':'Frame@2x(10).png','blocked':'Frame@2x(4).png','bag':'Frame@2x(5).png','calendar':'Frame@2x(6).png','globe':'Frame@2x(7).png','settings':'Frame@2x(8).png','emptyCup':'Frame@2x.png','soundWave':'Frame@2x(26).png',
'like':'Group_1225@2x.png','comment':'Group_1226@2x.png','clean':'Group_1236@2x.png','systemNotice':'Group_1238@2x.png','interactionNotice':'Group_1239@2x.png','onboardNext':'Group_1109@2x.png','report':'Group_135@2x.png','block':'Group_136@2x.png','followButton':'Group_559@2x.png','chatButton':'Group_560@2x(1).png','followedButton':'Group_561@2x.png',
'homeOn':'Group_592@2x.png','homeOff':'Group_592@2x(1).png','voiceOn':'Group_593@2x.png','voiceOff':'Group_593@2x(1).png','messagesOn':'Group_594@2x.png','messagesOff':'Group_594@2x(1).png','meOn':'Group_595@2x.png','meOff':'Group_595@2x(1).png',
'gift':'Group_782@2x.png','mic':'Group_904@2x.png','chatPhoto':'Group_905@2x.png','speaker':'Group_906@2x.png','coffeeUpdates':'image_872@2x.png','uploadImage':'image_194@2x.png','hot':'image_878@2x.png','coin':'image_883@2x.png','dialogBackground':'image_885@2x.png',
'giftLove':'Group_673@2x.png','giftPeach':'Rectangle_1106@2x.png','giftCake':'Rectangle_1108@2x.png','giftUmbrella':'Rectangle_1107@2x.png','giftBird':'Rectangle_1113@2x.png','giftHeadphones':'Rectangle_1114@2x.png','giftCar':'Rectangle_1115@2x.png','giftCrown':'Rectangle_1116@2x.png'
}
manifest=[]
def add(name,source):
 dest=assets/(name+'.imageset');dest.mkdir(exist_ok=True)
 suffix=source.suffix.lower();filename=name+suffix
 shutil.copy2(source,dest/filename)
 save_json(dest/'Contents.json',{'images':[{'filename':filename,'idiom':'universal','scale':'2x'}],'info':{'author':'xcode','version':1}})
 manifest.append({'asset':name,'source':str(source.relative_to(root))})
for name,src in mapping.items():add(name,root/'ProjectMaterials/UIAssets'/src)
photos=sorted(p for p in (root/'ProjectMaterials/ContentImages').iterdir() if not p.name.startswith('.'))
for i in list(range(18))+[30]:
 name=f'coffee{i:02d}'
 add(name,root/previous[name]['source'] if name in previous else photos[i])
for j,i in enumerate([18,19,20,21,22,23,24,25]):
 name=f'person{j:02d}'
 add(name,root/previous[name]['source'] if name in previous else photos[i])
 manifest[-1]['owner']=previous.get(name,{}).get('owner','unassigned-not-bound-to-profile')
 for field in ['displayName','mappingApprovedByUser']:
  if field in previous.get(name,{}):manifest[-1][field]=previous[name][field]
# Preserve the original, resize only the app-icon packaging copy.
icon=assets/'AppIcon.appiconset';icon.mkdir(exist_ok=True)
subprocess.run(['sips','-z','1024','1024',str(root/'ProjectMaterials/UIAssets/咖啡社区logo@2x.png'),'--out',str(icon/'AppIcon.png')],check=True,stdout=subprocess.DEVNULL)
Image.open(icon/'AppIcon.png').convert('RGB').save(icon/'AppIcon.png')
save_json(icon/'Contents.json',{'images':[{'filename':'AppIcon.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}})
color=assets/'LaunchCream.colorset';color.mkdir(exist_ok=True)
save_json(color/'Contents.json',{'colors':[{'idiom':'universal','color':{'color-space':'srgb','components':{'red':'0.992','green':'0.969','blue':'0.941','alpha':'1.0'}}}],'info':{'author':'xcode','version':1}})
media=root/'Papi/Resources/Media';media.mkdir(exist_ok=True)
videos=sorted((root/'ProjectMaterials/ContentVideos').glob('*.mp4'))
video_entries=sorted((name,root/item['source']) for name,item in previous.items() if name.startswith('coffeeVideo'))
if not video_entries:video_entries=[(f'coffeeVideo{i:02d}',p) for i,p in enumerate(videos)]
for name,p in video_entries:
 shutil.copy2(p,media/(name+'.mp4'))
 # Extract an actual first-frame poster from each supplied video, not an unrelated image.
 poster=media/(name+'.jpg')
 subprocess.run(['ffmpeg','-nostdin','-loglevel','error','-y','-i',str(p),'-frames:v','1','-vf','scale=600:-2',str(poster)],check=True)
 manifest.append({'asset':name,'source':str(p.relative_to(root)),'poster':poster.name,'owner':'unassigned-editorial-preview'})
generated=root/'ProjectMaterials/UIAssets/Generated/roomBackground.png'
if generated.exists():add('roomBackground',generated)
save_json(root/'docs/ASSET_MANIFEST.json',manifest)
print('Prepared',len(manifest),'explicit source mappings;',len(videos),'videos')
