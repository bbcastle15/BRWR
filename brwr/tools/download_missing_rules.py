import pathlib, urllib.request, concurrent.futures, json, hashlib
out=pathlib.Path('../materials/official_missing'); out.mkdir(exist_ok=True)
jobs={'BRW_Core_ENG':'https://ludusmagnusstudio.com/download/116233/','BRW_Inferno_ENG':'https://ludusmagnusstudio.com/download/117569/','BRW_Crono_ENG':'https://ludusmagnusstudio.com/download/117968/','BRW_Hidden_Thorns_ENG':'https://ludusmagnusstudio.com/download/117975/'}
for name,ident in [('Duel_Lex','1XAZFsQqqLBLSVP_25N645Npq305XZTcT'),('Duel_Void','1ac5cJkqjmGA69AwF9JgBMQm6g6xseKTr'),('Duel_Kami','1TRmcp81Y_VOUCvkERejFNkVj8anEH8od')]: jobs[name+'_ENG']='https://drive.google.com/uc?export=download&id='+ident
jobs['BRW_Sator_ENG']='https://ludusmagnusstudio.com/download/117608/'
def get(item):
 name,url=item; p=out/(name+'.pdf')
 try:
  if name=='BRW_Sator_ENG': data=pathlib.Path('docs/handoff-2026-10-18/evidence/sator-rules.pdf').read_bytes()
  else: data=urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'Mozilla/5.0'}),timeout=90).read()
  if not data.startswith(b'%PDF'): raise ValueError('Response is not a PDF')
  p.write_bytes(data)
  r={'file':p.name,'url':url,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'status':'downloaded'}
 except Exception as e: r={'file':p.name,'url':url,'status':str(e)}
 print(name,r['status'],flush=True); return r
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool: results=list(pool.map(get,jobs.items()))
(out/'sources.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
