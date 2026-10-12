// Evidence coverage only. No pixel editing, fitting, scale correction or art approval.
export const METRICS = Object.freeze({faceWidth:'臉部大小',eyeSeparation:'兩眼下緣間距',eyeToFoot:'眼線至腳底'});
const point = value => Array.isArray(value) && value.length===2 && value.every(Number.isFinite);
const points = value => Array.isArray(value) && value.length===2 && value.every(point);
const positive = value => Number.isFinite(value) && value>0;
function consistentLandmark(source,key){
  if(key==='eyeToFoot')return measuredFootPoints(source)!==null;
  const line=source[key==='faceWidth'?'faceCaliperPoints':'eyeLowerRimPoints'];if(!points(line))return false;
  const distance=Math.hypot(line[1][0]-line[0][0],line[1][1]-line[0][1]);
  // Facial widths come from 0.25 px samples on a tilted unit line; each
  // displayed endpoint is rounded to a source pixel (combined error <= sqrt(2)).
  // Lower-rim points are exact half-pixel coordinates, so their distance is exact.
  const tolerance=key==='faceWidth'?Math.SQRT2+1e-6:1e-6*Math.max(1,distance);
  return distance>0&&Math.abs(distance-source[key])<=tolerance;
}
export function measuredFootPoints(source){
  if(!positive(source?.eyeToFoot))return null;
  if(source.eyeToFootPoints!==undefined){
    const value=source.eyeToFootPoints;
    return points(value)&&Math.abs(value[1][0]-value[0][0])<1e-6&&Math.abs(value[1][1]-value[0][1]-source.eyeToFoot)<1e-5?value:null;
  }
  // Legacy reports explicitly define this scalar as trueFootY - eyeMidpointY.
  return point(source.eyeMidpoint)?[source.eyeMidpoint,[source.eyeMidpoint[0],source.eyeMidpoint[1]+source.eyeToFoot]]:null;
}
function unknownReason(frame,key,sourceRecord){
  const source=frame?.source;
  const explicit=source?.[`${key}UnavailableReason`]||(key==='eyeToFoot'&&source?.footUnavailableReason)||source?.unavailableReason||source?.unavailable;
  if(typeof explicit==='string'&&explicit.trim())return explicit;
  // The original audit stores the cushion/hidden-feet reason once per source.
  // Accept it only after binding that source record to this PNG and contour.
  if(key==='eyeToFoot'&&typeof sourceRecord?.footBaselineUnavailableReason==='string'&&sourceRecord.footBaselineUnavailableReason.trim())return sourceRecord.footBaselineUnavailableReason;
  const flag=frame?.flags?.find(flag=>typeof flag==='object'&&typeof flag.message==='string'&&flag.message.trim()&&(!flag.metrics||flag.metrics.includes(key)));
  return flag?.message||null;
}
export function summarizeEvidence(clip,entry,sourceFrameCount,report=null){
  const errors=[],warnings=[],sequence=clip.frameIndices||Array.from({length:clip.frameCount},(_,i)=>i);
  const result={clipID:clip.id,catalog:clip.catalogKind||'catalog',artApproval:false,reviewRequired:true,evidenceComplete:false,
    errors,warnings,reportedIssues:entry?.flags||[],sourceFrameCount,playbackFrameCount:sequence.length,uniqueUsedFrames:new Set(sequence).size,recordedFrames:0,measuredFrames:0,metrics:{}};
  const fail=(code,message)=>errors.push({code,message});
  if(!entry){fail('missing-audit','缺少對應圖稿的量測紀錄。');return result;}
  if(entry.id!==clip.id||entry.catalog!==result.catalog||entry.sourceSha256!==clip.sha256||entry.regionsSha256!==clip.frameRegions?.sha256){
    fail('stale-identity','圖片或輪廓版本不符，量測不可沿用。');return result;
  }
  const sourceRecord=report?.sources?.find(source=>source.sourcePath===clip.atlas&&source.sourceSha256===clip.sha256&&source.regionsSha256===clip.frameRegions?.sha256);
  if(!Number.isInteger(sourceFrameCount)||sourceFrameCount<1){fail('source-frame-count','來源格數無效。');return result;}
  if(!Array.isArray(sequence)||sequence.length!==clip.frameCount||sequence.some(i=>!Number.isInteger(i)||i<0||i>=sourceFrameCount))fail('playback-sequence','播放格序與來源格數不符。');
  if(entry.sourceFrameCount!==sourceFrameCount)fail('audit-frame-count','報告的原始格數與輪廓不符。');
  const frames=new Map();
  for(const frame of Array.isArray(entry.frames)?entry.frames:[]){
    if(!Number.isInteger(frame.sourceFrame)||frame.sourceFrame<0||frame.sourceFrame>=sourceFrameCount){fail('invalid-source-index','報告含無效來源格。');continue;}
    if(frames.has(frame.sourceFrame)){fail('duplicate-frame',`來源第 ${frame.sourceFrame+1} 格重複。`);continue;}
    frames.set(frame.sourceFrame,frame);
  }
  result.recordedFrames=frames.size;
  for(let i=0;i<sourceFrameCount;i++)if(!frames.has(i))fail('missing-frame',`來源第 ${i+1} 格缺少量測或明示未知的紀錄。`);
  const measuredFrames=new Set();
  for(const [key,label]of Object.entries(METRICS)){
    const values=new Map(),unknown=[];
    for(const [index,frame]of frames){
      const value=frame.source?.[key];
      if(value===null||value===undefined){
        const reason=unknownReason(frame,key,sourceRecord);unknown.push({sourceFrame:index,reason});
        if(!reason)fail('unexplained-unknown',`來源第 ${index+1} 格的${label}未知，但沒有原因。`);
      }else if(!positive(value))fail('invalid-measurement',`來源第 ${index+1} 格的${label}不是有效正數。`);
      else if(!consistentLandmark(frame.source,key))
        fail('missing-landmark',`來源第 ${index+1} 格的${label}缺少相符尺線，不能只引用外框。`);
      else{values.set(index,value);measuredFrames.add(index);}
    }
    const first=values.get(sequence[0])??null,last=values.get(sequence.at(-1))??null,all=[...values.values()];
    const deltaPercent=first!==null&&last!==null?(last/first-1)*100:null;
    const spreadPercent=all.length>1?(Math.max(...all)/Math.min(...all)-1)*100:null;
    result.metrics[key]={measured:values.size,unknown:unknown.length,missing:sourceFrameCount-frames.size,first,last,deltaPercent,spreadPercent,unknownFrames:unknown};
    if(deltaPercent!==null&&Math.abs(deltaPercent)>8)warnings.push({code:'endpoint-difference',metric:key,message:`${label}首末相差 ${Math.abs(deltaPercent).toFixed(1)}%，需看姿勢與比例。`});
    if(spreadPercent!==null&&spreadPercent>8)warnings.push({code:'within-clip-variation',metric:key,message:`${label}全段可量格的最大／最小差 ${spreadPercent.toFixed(1)}%，需逐格確認。`});
  }
  result.measuredFrames=measuredFrames.size;
  if(measuredFrames.size<sourceFrameCount)warnings.push({code:'unknown-anatomy',message:`${sourceFrameCount-measuredFrames.size} 格沒有可靠人體尺規，須人工看原圖。`});
  result.evidenceComplete=errors.length===0;
  return result;
}
