"""Build a local, searchable index of the supplied text extracts."""
from pathlib import Path
import hashlib
import json
import shutil

root = Path('/Users/michaeljones/Downloads/Oxford_Brookes_CLI_correct/data')
out = Path(__file__).resolve().parent / 'dist' / 'sources'
out.mkdir(parents=True, exist_ok=True)
items=[]
for p in sorted(root.rglob('*')):
    if not p.is_file() or p.suffix not in ('.txt','.md'): continue
    relative=str(p.relative_to(root))
    key=hashlib.sha256(relative.encode()).hexdigest()[:16]
    shutil.copyfile(p,out/(key+'.txt'))
    module=next((code for code in ['COMP4004','COMP4009','COMP4035','MATH4004'] if code in relative),'GENERAL')
    historical=('2016-17' in relative or '2017-18' in relative)
    items.append({'id':key,'name':p.name.removesuffix('.txt'),'path':relative,'module':module,'historical':historical,'url':'sources/'+key+'.txt','captured':'2026-09-15'})
(out.parent/'sources.json').write_text(json.dumps(items,ensure_ascii=False,indent=2))
print(f'Indexed {len(items)} source extracts.')
