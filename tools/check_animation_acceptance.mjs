#!/usr/bin/env node
// Read-only evidence gate. A zero exit never approves art or edits a catalog.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {summarizeEvidence} from '../size-review/acceptance-core.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const args=process.argv.slice(2),options={audits:[],ids:[],catalog:'animation/candidates.json'};
for(let i=0;i<args.length;i++){
  const key=args[i],value=args[++i];
  if(!value)throw new Error(`Missing value for ${key}`);
  if(key==='--audit')options.audits.push(value);
  else if(key==='--clip-ids')options.ids=value.split(',').map(x=>x.trim()).filter(Boolean);
  else if(key==='--catalog')options.catalog=value;
  else if(key==='--output')options.output=value;
  else throw new Error(`Unknown argument ${key}`);
}
if(!options.audits.length||!options.ids.length)throw new Error('Provide --audit report.json (repeatable) and --clip-ids id1,id2. Art approval is separate.');
const digest=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
function read(relative,expected){
  const location=path.resolve(root,relative),real=fs.realpathSync(location),base=fs.realpathSync(root)+path.sep;
  if(!real.startsWith(base))throw new Error(`Path outside repository: ${relative}`);
  const bytes=fs.readFileSync(real);if(expected&&digest(bytes)!==expected)throw new Error(`SHA mismatch: ${relative}`);return bytes;
}
const json=relative=>JSON.parse(read(relative).toString('utf8').replace(/^\uFEFF/,''));
const catalog=json(options.catalog),kind=options.catalog==='animation/catalog.json'?'catalog':'candidates';
const reports=options.audits.map(relative=>({path:relative,data:json(relative)}));
const result={schemaVersion:1,checkedAt:new Date().toISOString(),artApproval:false,reviewRequired:true,
  meaning:'Evidence integrity and explicit unknowns only; not anatomical equality or visual approval.',catalog:options.catalog,
  scope:{selection:'Explicit IDs only; not a pass for all candidates',clipIDs:options.ids,catalogClipCount:catalog.clips.length,otherCatalogClipsNotChecked:catalog.clips.filter(clip=>!options.ids.includes(clip.id)).length},clips:[],errors:[]};
for(const report of reports){
  try{
    if(report.data.schemaVersion!==1||report.data.artApproval!==false)throw new Error('Audit must declare schemaVersion 1 and artApproval false');
    for(const dependency of report.data.sourceReports||[])read(dependency.path,dependency.sha256);
    if(report.data.landmarksPath)read(report.data.landmarksPath,report.data.landmarksSha256);
  }catch(error){result.errors.push({report:report.path,message:error.message});}
}
for(const id of options.ids){
  try{
    const clip=catalog.clips.find(clip=>clip.id===id);if(!clip?.atlas||!clip.frameRegions)throw new Error('Clip or contour source missing');
    read(clip.atlas,clip.sha256);const regions=JSON.parse(read(clip.frameRegions.path,clip.frameRegions.sha256));
    if(regions.source?.sha256!==clip.sha256)throw new Error('Contour source identity does not match PNG');
    const match=reports.flatMap(report=>(report.data.clips||[]).map(entry=>({entry,report}))).find(({entry})=>entry.id===id&&entry.catalog===kind&&entry.sourceSha256===clip.sha256&&entry.regionsSha256===clip.frameRegions.sha256);
    const summary=summarizeEvidence({...clip,catalogKind:kind},match?.entry,regions.frames.length,match?.report.data);
    result.clips.push({...summary,auditPath:match?.report.path||null,sourceSha256:clip.sha256,regionsSha256:clip.frameRegions.sha256,scale:clip.scale});
  }catch(error){result.errors.push({clipID:id,message:error.message});}
}
result.evidenceComplete=result.errors.length===0&&result.clips.length===options.ids.length&&result.clips.every(clip=>clip.evidenceComplete);
const serialized=JSON.stringify(result,null,2)+'\n';
if(options.output){const destination=path.resolve(root,options.output);if(!destination.startsWith(path.join(root,'output')+path.sep))throw new Error('--output must be inside repository output/');fs.mkdirSync(path.dirname(destination),{recursive:true});fs.writeFileSync(destination,serialized);}
console.log(serialized);process.exitCode=result.evidenceComplete?0:2;
