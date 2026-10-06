import { normalizeClip, validateFrameRegions, destinationRect } from '../preview/player-core.js?v=20261006-layouts1';
import { transformRect } from '../preview/layout-core.js?v=20261006-layouts1';
export const hashHex = async bytes => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),n=>n.toString(16).padStart(2,'0')).join('');
export async function resource(path, repo, expectedHash) {
  const url = new URL(path,repo);
  if(url.origin!==repo.origin || !url.pathname.startsWith(repo.pathname))throw new Error('資料路徑超出專案');
  const response=await fetch(url,{cache:'no-store',signal:AbortSignal.timeout(15000)});
  if(!response.ok)throw new Error(`${path}：HTTP ${response.status}`);
  const bytes=await response.arrayBuffer();if(expectedHash&&await hashHex(bytes)!==expectedHash.toLowerCase())throw new Error(`${path}：SHA 校驗不符`);return bytes;
}
export const decodeJSON = bytes => JSON.parse(new TextDecoder().decode(bytes).replace(/^\uFEFF/,''));
export async function loadClip(raw,repo,cache) {
  const clip=normalizeClip(raw);if(!clip.available)return clip;
  if(!clip.frameRegions)throw new Error(`${clip.title}：目前尺寸審稿只接受已分離輪廓的素材`);
  const key=`${clip.sha256}:${clip.frameRegions.sha256}`;
  if(!cache.has(key))cache.set(key,(async()=>{
    const [png,regions]=await Promise.all([resource(clip.atlas,repo,clip.sha256),resource(clip.frameRegions.path,repo,clip.frameRegions.sha256)]);
    const metadata=validateFrameRegions(clip,decodeJSON(regions));const image=await createImageBitmap(new Blob([png],{type:'image/png'}));
    if(image.width!==clip.width||image.height!==clip.height)throw new Error('來源圖片尺寸不符');
    const frames=metadata.frames.map((frame,index)=>{
      const canvas=document.createElement('canvas');canvas.width=metadata.canvas.width;canvas.height=metadata.canvas.height;
      const context=canvas.getContext('2d');const [dx,dy]=frame.translation;context.imageSmoothingEnabled=false;context.save();context.beginPath();
      for(const [y,...runs]of frame.rows)for(let i=0;i<runs.length;i+=2)context.rect(runs[i]+dx,y+dy,runs[i+1]-runs[i],1);
      context.clip();context.drawImage(image,dx,dy);context.restore();canvas.dataset.sourceFrame=String(index);return canvas;
    });image.close();return{metadata,frames};
  })());
  const shared=await cache.get(key);validateFrameRegions(clip,shared.metadata);
  return{...clip,...shared,renderCanvas:shared.metadata.canvas};
}
export function strongBounds(canvas) {
  const pixels=canvas.getContext('2d').getImageData(0,0,canvas.width,canvas.height).data;
  let left=canvas.width,top=canvas.height,right=-1,bottom=-1;
  for(let y=0;y<canvas.height;y++)for(let x=0;x<canvas.width;x++)if(pixels[4*(y*canvas.width+x)+3]>=128){left=Math.min(left,x);top=Math.min(top,y);right=Math.max(right,x);bottom=Math.max(bottom,y);}
  return[left,top,right+1-left,bottom+1-top];
}
export function frameGeometry(clip,index,master,layout) {
  const sourceIndex=clip.frameIndices[index],source=clip.frames[sourceIndex],rect=transformRect(destinationRect(clip,master),layout);
  clip.bounds ||= new Map();if(!clip.bounds.has(sourceIndex))clip.bounds.set(sourceIndex,strongBounds(source));
  const b=clip.bounds.get(sourceIndex);const scale=rect[2]/source.width;
  return{source,sourceIndex,rect,pixelScale:scale,bounds:[rect[0]+b[0]*scale,rect[1]+b[1]*scale,b[2]*scale,b[3]*scale],
    anchor:[rect[0]+clip.renderCanvas.anchorPixels[0]*scale,rect[1]+clip.renderCanvas.anchorPixels[1]*scale]};
}
