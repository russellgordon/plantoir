// node serve.mjs <site folder> <port> [delay ms] [nopaged|-] [regex of files to delay]
// Serves a built site with no-store, optionally holding pictures (or the files the
// regex names) for <delay> ms and answering paged.min.js with a 404 (nopaged).
// Used by safari_print.sh (#576); a measurement harness, not a gate.
import http from "node:http"; import fs from "node:fs"; import path from "node:path";
const root = process.argv[2]; const port = +process.argv[3]; const delay = +(process.argv[4]||0);
const types = {".html":"text/html",".css":"text/css",".js":"text/javascript",".png":"image/png",".json":"application/json",".woff2":"font/woff2",".svg":"image/svg+xml",".wasm":"application/wasm"};
http.createServer((req,res)=>{ let p = decodeURIComponent(new URL(req.url,"http://x").pathname); let f = path.join(root,p);
 const tries=[f, f+".html", path.join(f,"index.html")]; let hit=null; for(const t of tries){ try{ if(fs.statSync(t).isFile()){hit=t;break} }catch{} }
 if(process.argv[5]==="nopaged" && p.endsWith("paged.min.js")) hit=null; if(!hit){res.writeHead(404,{"content-type":"text/html"}); res.end(fs.readFileSync(path.join(root,"404.html"))); return}
 const send=()=>{res.writeHead(200,{"content-type":types[path.extname(hit)]||"application/octet-stream","cache-control":"no-store"}); fs.createReadStream(hit).pipe(res)};
 if(delay && new RegExp(process.argv[6]||"\\.(png|jpe?g|webp)$","i").test(hit)) setTimeout(send, delay); else send();
}).listen(port,"127.0.0.1");
