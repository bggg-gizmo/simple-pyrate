package com.bggg.simplepyrate;

import android.content.*;
import android.database.Cursor;
import android.os.Environment;
import android.os.SystemClock;
import android.provider.DocumentsContract;
import android.provider.MediaStore;
import android.net.Uri;
import org.json.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.*;
import java.util.concurrent.TimeUnit;
import java.util.regex.*;

final class CargoRunner {
    static final String[] MODES={"MP4","MP3","Transcript"};
    private static final Pattern WAIT=Pattern.compile("(?i)sleeping\\s+([0-9]+(?:\\.[0-9]+)?)\\s+seconds");
    static final class Settings {
        final String url,languages,quality;final boolean collection,txt,srt,auto;
        final int height;final List<String> modes;final Uri destination;
        Settings(String u,List<String> m,boolean c,int h,String q,String l,boolean t,boolean ss,boolean a,Uri d){
            url=u;modes=Collections.unmodifiableList(new ArrayList<>(m));collection=c;height=h;quality=q;
            languages=validateLanguages(l);txt=t;srt=ss;auto=a;destination=d;
            Access.link(u);
            if(modes.isEmpty()||!Arrays.asList(MODES).containsAll(modes))throw new IllegalArgumentException("Choose a cargo format.");
            if(!(q.matches("(?:0|(?:128|192|256|320)K)")&&h>=0&&h<=4320))throw new IllegalArgumentException("Unknown quality setting.");
        }
    }
    static String validateLanguages(String x) {
        x=x.toLowerCase(Locale.ROOT).trim();
        if(x.equals("all"))return "all,-live_chat";
        LinkedHashSet<String> out=new LinkedHashSet<>();
        for(String y:x.split(",",-1)){
            y=y.trim();
            if(!y.matches("[a-z]{2,3}(?:-[a-z0-9]{1,8}){0,4}"))throw new IllegalArgumentException("Enter comma-separated caption languages, or all.");
            out.add(y.contains("-")?y:y+"(?:-[a-z0-9]+)*");
        }
        return String.join(",",out);
    }
    static final class Saved {
        final String name;final Uri uri;
        Saved(String n,Uri u){name=n;uri=u;}
    }
    static final class Result {
        int saved,errors,missing;boolean cancelled;
        String status(){return cancelled?"Cancelled":saved>0?(errors>0||missing>0?"Partial":"Complete"):errors>0?"Failed":missing>0?"No captions":"No files";}
    }
    interface Events {
        void mode(String name);
        default void resolving(String step){}
        void port(String mode,String title,int number,int total);
        void transfer(int percent,String detail);
        void waiting(double seconds);
        void processing(String detail);
        void portDone(boolean saved);
        void saved(Saved file);
        void log(String text);
    }
    private final Context context;
    private final RuntimeTools runtime;
    private final Settings req;
    private final Access access;
    private final Events event;
    private volatile Process process,helper;
    private volatile boolean cancelled;
    private final Result result=new Result();
    CargoRunner(Context c,RuntimeTools t,Settings s,Access a,Events e){context=c;runtime=t;req=s;access=a;event=e;}
    void cancel(){
        cancelled=true;Process p=process,h=helper;
        if(p!=null)p.destroy();
        if(h!=null)h.destroy();
    }
    private void check() throws InterruptedIOException {if(cancelled||Thread.currentThread().isInterrupted())throw new InterruptedIOException("Haul cancelled.");}
    Result run() {
        File job=new File(new File(context.getNoBackupFilesDir(),"jobs"),UUID.randomUUID().toString());
        File auth=new File(job,"credentials");
        try {
            RuntimeTools.mkdir(job);
            File cfg=access.config(auth,req.url);
            if(!req.collection&&req.modes.size()>1)runHaul(job,cfg,auth);
            else for(String mode:req.modes){
                check();event.mode(mode);
                File work=new File(job,mode);RuntimeTools.mkdir(work);
                runMode(mode,cfg,auth,work);
            }
        } catch(Exception x) {
            if(!cancelled){result.errors++;event.log(access.redact(x.getMessage(),auth));}
        } finally {
            Process old=process;if(old!=null)old.destroyForcibly();
            Process h=helper;if(h!=null)h.destroyForcibly();
            result.cancelled=cancelled;
            RuntimeTools.erase(job);
        }
        return result;
    }
    private List<String> args(String mode,File cfg){
        ArrayList<String> a=new ArrayList<>(Arrays.asList("--ignore-config","--no-plugin-dirs","--cache-dir",runtime.extractorCache().getAbsolutePath(),"--no-colors","--newline",
            "--progress","--progress-delta","0.25","--windows-filenames","--no-overwrites","--continue","--no-mtime",
            "--socket-timeout","25","--retries","3","--fragment-retries","3","--ignore-errors","--no-simulate","--no-quiet",
            "--ffmpeg-location",runtime.ffmpeg().getAbsolutePath(),"--js-runtimes","quickjs:"+runtime.quickjs().getAbsolutePath(),
            "-o","%(title).100B [%(extractor_key).22B-%(id).42B].%(ext)s",
            "--progress-template","download:PYRATE_PROGRESS %(progress._percent_str)j\t%(progress._speed_str)j\t%(progress._eta_str)j\t%(info.format_id)j",
            "--progress-template","postprocess:PYRATE_PROCESS %(progress.postprocessor)j",
            "--print","before_dl:PYRATE_FORMAT %(requested_formats.:.format_id,format_id)j",
            "--print","video:PYRATE_PORT %(id)j\t%(title)j\t%(playlist_index)j\t%(n_entries)j",
            "--print","after_video:PYRATE_ITEM %(id)j\t%(requested_downloads.0.filepath)j\t%(requested_downloads.0.requested_subtitles,requested_subtitles)j"));
        if(cfg!=null){a.add("--config-locations");a.add(cfg.getAbsolutePath());}
        if(req.collection)a.add("--yes-playlist");else Collections.addAll(a,"--no-playlist","--playlist-items","1");
        if(mode.equals("MP4")){
            String res=req.height>0?"[height<="+req.height+"]":"";
            Collections.addAll(a,"-f","bv*"+res+"+ba/b"+res+"/bv"+res,"-S","res,vcodec:h264,acodec:aac","--merge-output-format","mp4/mkv");
        }else if(mode.equals("MP3"))Collections.addAll(a,"-f","bestaudio/best","-x","--audio-format","mp3","--audio-quality",req.quality);
        else {
            Collections.addAll(a,"--skip-download","--ignore-no-formats-error","--write-subs","--sub-langs",req.languages,
                "--sub-format","srt/vtt/best","--convert-subs","srt");
            if(req.auto)a.add("--write-auto-subs");
        }
        Collections.addAll(a,"--",req.url);
        return a;
    }
    private static Object json(String s) {
        try {Object v=new JSONTokener(s).nextValue();return v==JSONObject.NULL?null:v;}catch(Exception x){return null;}
    }
    private static String str(String s) {Object p=json(s);return p==null?"":p.toString();}
    private static int num(String s) {Object p=json(s);return p instanceof Number?((Number)p).intValue():0;}
    private void runMode(String mode,File cfg,File auth,File work)throws Exception{
        check();
        long started=SystemClock.elapsedRealtime();
        Process p=runtime.startYt(args(mode,cfg),work);process=p;p.getOutputStream().close();
        try(BufferedReader in=reader(p)){
            readMode(mode,auth,work,in,p,null,started);
        }finally {endProcess(p);}
    }
    private void runHaul(File job,File cfg,File auth)throws Exception{
        check();
        long started=SystemClock.elapsedRealtime();
        String boundary="PYRATE_END_"+UUID.randomUUID()+" ";
        JSONArray modes=new JSONArray();
        HashMap<String,File> dirs=new HashMap<>();
        for(String mode:req.modes){
            File dir=new File(job,mode);RuntimeTools.mkdir(dir);dirs.put(mode,dir);
            modes.put(new JSONObject().put("directory",dir.getAbsolutePath()).put("args",new JSONArray(args(mode,cfg))));
        }
        JSONObject captions=new JSONObject();
        if(req.modes.contains("Transcript")){
            captions.put("writesubtitles",true);
            if(req.auto)captions.put("writeautomaticsub",true);
        }
        File plan=new File(job,"haul.json");
        String payload=new JSONObject().put("boundary",boundary).put("modes",modes).put("captions",captions).toString();
        Files.write(plan.toPath(),payload.getBytes(StandardCharsets.UTF_8));
        Process p=runtime.startHaul(plan,job);process=p;p.getOutputStream().close();
        try(BufferedReader in=reader(p)){
            for(String mode:req.modes){
                check();event.mode(mode);
                readMode(mode,auth,dirs.get(mode),in,p,boundary,started);
                started=SystemClock.elapsedRealtime();
            }
            int exit=p.waitFor();
            if(exit!=0&&!cancelled)throw new IOException("Download session exited with code "+exit+".");
        } finally {endProcess(p);}
    }
    private static BufferedReader reader(Process p){
        return new BufferedReader(new InputStreamReader(p.getInputStream(),StandardCharsets.UTF_8));
    }
    private void endProcess(Process p)throws InterruptedException{
        process=null;if(p.isAlive()){p.destroy();if(!p.waitFor(800,TimeUnit.MILLISECONDS))p.destroyForcibly();}
    }
    private void readMode(String mode,File auth,File work,BufferedReader in,Process p,String boundary,long started)throws Exception{
        boolean opened=false;String active="";
        Set<String> sent=new HashSet<>(), currentFormats=new HashSet<>();
        Map<String,Integer> formats=new HashMap<>();
        int modeStart=result.saved;
        int exit=Integer.MIN_VALUE;
        long resolve=-1,firstTransfer=-1,publishMillis=0;
        String line;
        while((line=in.readLine())!=null){
            check();
            if(boundary!=null&&line.startsWith(boundary)){
                try{exit=Integer.parseInt(line.substring(boundary.length()));}
                catch(NumberFormatException e){throw new IOException("Invalid download session response.");}
                break;
            }
            if(line.startsWith("PYRATE_PORT ")){
                String[] f=line.substring(12).split("\t",-1);
                if(f.length!=4)continue;
                String id=str(f[0]);
                if(opened&&active.equals(id))continue;
                if(opened)event.portDone(false);
                active=id;opened=true;formats.clear();currentFormats.clear();
                if(resolve<0)resolve=SystemClock.elapsedRealtime()-started;
                event.port(mode,access.redact(str(f[1]),auth),num(f[2]),num(f[3]));
            }else if(line.startsWith("PYRATE_FORMAT ")){
                Object ids=json(line.substring(14));currentFormats.clear();
                if(ids instanceof JSONArray){
                    JSONArray list=(JSONArray)ids;for(int i=0;i<list.length();i++)currentFormats.add(list.optString(i));
                } else if(ids!=null)currentFormats.add(ids.toString());
            }else if(line.startsWith("PYRATE_PROGRESS ")){
                if(firstTransfer<0)firstTransfer=SystemClock.elapsedRealtime()-started;
                String[] f=line.substring(16).split("\t",-1);
                if(f.length!=4)continue;
                String pct=str(f[0]).replace("%","").trim();
                try{
                    int pc=(int)Math.max(0,Math.min(100,Double.parseDouble(pct)));
                    String id=str(f[3]);
                    if(currentFormats.size()>1 && currentFormats.contains(id)){
                        formats.put(id,Math.max(formats.getOrDefault(id,0),pc));
                        int sum=0;for(String key:currentFormats)sum+=formats.getOrDefault(key,0);
                        pc=sum/currentFormats.size();
                    }
                    String info=str(f[1]);String eta=str(f[2]);event.transfer(pc,access.redact(info+(eta.isEmpty()?"":"  /  ETA "+eta),auth));
                }catch(NumberFormatException ignored){}
            }else if(line.startsWith("PYRATE_PROCESS ")){
                event.processing("Finalizing "+mode); // file completion is determined separately.
            }else if(line.startsWith("PYRATE_ITEM ")){
                String[] f=line.substring(12).split("\t",-1);
                String id=f.length>0?str(f[0]):active;
                if(!opened)event.port(mode,"Completed "+mode,0,0);
                int start=result.saved;
                long publishStart=SystemClock.elapsedRealtime();
                try{publishCandidates(mode,work,id,sent);}catch(Exception e){if(cancelled)throw e;result.errors++;event.log(access.redact(e.getMessage(),auth));}
                finally{publishMillis+=SystemClock.elapsedRealtime()-publishStart;}
                if(start==result.saved&&mode.equals("Transcript"))result.missing++;
                event.portDone(result.saved>start);opened=false;
            }else{
                if(!opened){
                    if(line.contains("Downloading webpage"))event.resolving("Getting source page");
                    else if(line.contains("player API JSON"))event.resolving("Getting stream details");
                    else if(line.contains("Downloading player"))event.resolving("Preparing player");
                    else if(line.contains("Downloading m3u8")||line.contains("Downloading MPD"))event.resolving("Checking stream manifest");
                    else if(line.contains("Solving JS challenges"))event.resolving("Checking media signatures");
                }
                Matcher wait=WAIT.matcher(line);
                if(wait.find())event.waiting(Math.min(3600,Double.parseDouble(wait.group(1))));
                line=access.redact(line,auth);
                if(line.startsWith("ERROR:"))result.errors++;
                if(!line.trim().isEmpty())event.log(line.length()>1600?line.substring(0,1600):line);
            }
        }
        check();
        if(boundary==null)exit=p.waitFor();
        else if(exit==Integer.MIN_VALUE)throw new IOException("Download session ended before completing "+mode+".");
        if(exit!=0&&!cancelled){result.errors++;event.log(mode+" exited with code "+exit+".");}
        check();
        int before=result.saved;
        long publishStart=SystemClock.elapsedRealtime();
        publishCandidates(mode,work,"",sent);
        publishMillis+=SystemClock.elapsedRealtime()-publishStart;
        if(opened)event.portDone(result.saved>before);
        if(result.saved==modeStart&&mode.equals("Transcript")&&result.missing==0)result.missing++;
        if(result.saved==modeStart&&!mode.equals("Transcript")&&exit==0){result.errors++;event.log("No finished "+mode+" file was reported.");}
        long elapsed=SystemClock.elapsedRealtime()-started;
        event.log(mode+" timing · "+elapsed+" ms total"
            +(resolve>=0?" · "+resolve+" ms to source metadata":"")
            +(firstTransfer>=0?" · "+firstTransfer+" ms to first transfer":"")
            +" · "+publishMillis+" ms finalizing/saving");
    }
    private void publishCandidates(String mode,File work,String id,Set<String> sent)throws Exception{
        File[] files=work.listFiles(File::isFile);if(files==null)return;
        Arrays.sort(files,Comparator.comparing(File::getName));
        for(File from:files){
            check();
            String key=from.getName(),n=key.toLowerCase(Locale.ROOT);
            if(from.length()==0||sent.contains(key)||n.endsWith(".part")||n.contains(".pyrate-stage")||n.matches(".*\\.f[0-9]+\\.[^.]+")||
              (!id.isEmpty()&&!key.contains("-"+id+"]")))continue;
            if(mode.equals("MP3")&&!n.endsWith(".mp3"))continue;
            if(mode.equals("Transcript")&&!n.endsWith(".srt"))continue;
            if(mode.equals("MP4")&&!n.matches(".*\\.(mp4|mkv|webm|mov|m4v|avi|flv|ts|mpeg|mpg|3gp)") )continue;
            File actual=from;
            if(mode.equals("MP4")&&!n.endsWith(".mp4"))actual=mp4(from,work);
            if(mode.equals("MP4")&&n.endsWith(".mp4")&&!probeOkay(from,work)) {continue;}
            if(mode.equals("Transcript")&&req.txt){
                actual=new File(work,key.substring(0,key.length()-4)+".txt");
                byte[] raw=Files.readAllBytes(from.toPath());
                String plain=toText(new String(raw,StandardCharsets.UTF_8));
                if(!plain.isEmpty()){
                    Files.write(actual.toPath(),plain.getBytes(StandardCharsets.UTF_8));
                    Saved text=exportFile(actual,mode);result.saved++;event.saved(text);
                }
                sent.add(key);sent.add(actual.getName());
                if(!req.srt)continue;
                actual=from;
            }
            check();
            Saved f=exportFile(actual,mode);
            sent.add(key);sent.add(actual.getName());result.saved++;event.saved(f);
        }
    }
    private boolean probeOkay(File f,File work)throws Exception{
        Process p=runtime.startTool(runtime.ffprobe(),Arrays.asList("-v","error","-show_entries","format=duration","-of","default=nw=1:nk=1",f.getAbsolutePath()),work);
        helper=p;p.getOutputStream().close();
        try(InputStream in=p.getInputStream()){
            ByteArrayOutputStream b=new ByteArrayOutputStream();
            RuntimeTools.copy(in,b,65536);
            return p.waitFor()==0;
        } finally {helper=null;if(p.isAlive())p.destroyForcibly();}
    }
    private File mp4(File f,File work)throws Exception{
        event.processing("Converting to MP4");
        String name=f.getName().substring(0,f.getName().lastIndexOf('.'))+".mp4";
        File finalFile=new File(work,name),stage=new File(work,".pyrate-stage-"+UUID.randomUUID()+".mp4");
        try {
            if(ff(f,stage,work,true)!=0&&ff(f,stage,work,false)!=0)throw new IOException("FFmpeg could not finalize the MP4.");
            check();
            if(!stage.isFile()||stage.length()==0)throw new IOException("FFmpeg produced an empty MP4.");
            RuntimeTools.commit(stage,finalFile);return finalFile;
        }finally {stage.delete();}
    }
    private int ff(File f,File dst,File dir,boolean remux)throws Exception{
        check();
        ArrayList<String> cmd=new ArrayList<>(Arrays.asList("-nostdin","-hide_banner","-loglevel","error","-y","-i",f.getAbsolutePath(),"-map","0:v:0","-map","0:a:0?"));
        if(remux)Collections.addAll(cmd,"-c","copy");else Collections.addAll(cmd,"-c:v","libx264","-preset","veryfast","-pix_fmt","yuv420p","-c:a","aac");
        Collections.addAll(cmd,"-movflags","+faststart","-progress","pipe:1",dst.getAbsolutePath());
        double duration=mediaDuration(f,dir);check();
        Process proc=runtime.startTool(runtime.ffmpeg(),cmd,dir);helper=proc;proc.getOutputStream().close();
        try(BufferedReader b=new BufferedReader(new InputStreamReader(proc.getInputStream(),StandardCharsets.UTF_8))){
            String line;while((line=b.readLine())!=null){check();if(duration>0&&line.startsWith("out_time_us="))try{
                event.transfer((int)Math.min(99,Long.parseLong(line.substring(12))*0.0001/duration),"Finalizing MP4");
            }catch(NumberFormatException ignored){}}
            return proc.waitFor();
        }finally{helper=null;if(proc.isAlive())proc.destroyForcibly();}
    }
    private double mediaDuration(File f,File dir){
        try{
            Process p=runtime.startTool(runtime.ffprobe(),Arrays.asList("-v","error","-show_entries","format=duration","-of","default=nw=1:nk=1",f.getAbsolutePath()),dir);
            helper=p;p.getOutputStream().close();
            try(InputStream in=p.getInputStream()){
                ByteArrayOutputStream out=new ByteArrayOutputStream();
                RuntimeTools.copy(in,out,65536);if(p.waitFor()!=0)return 0;
                return Double.parseDouble(out.toString("UTF-8").trim());
            }finally{helper=null;if(p.isAlive())p.destroyForcibly();}
        }catch(Exception e){return 0;}
    }
    static String toText(String s) {
        StringBuilder out=new StringBuilder();String[] prev=new String[0];
        for(String block:s.replace("\r","").replace("\ufeff","").split("\\n\\s*\\n")){
            String[] lines=block.split("\n");int first=-1;
            for(int i=0;i<lines.length;i++)if(lines[i].matches("\\s*(?:\\d+:)?\\d\\d:\\d\\d[,.]\\d{3}\\s+-->.*")){first=i+1;break;}
            if(first<0||first>=lines.length)continue;
            String body=String.join(" ",Arrays.copyOfRange(lines,first,lines.length)).replaceAll("<[^>]*>|\\{\\\\[^}]*\\}","").trim();
            body=body.replace("&lt;","<").replace("&gt;",">").replace("&quot;","\"").replace("&#39;","'").replace("&nbsp;"," ").replace("&amp;","&");
            if(body.isEmpty())continue;
            String[] n=body.split("\\s+");
            int best=0;
            for(int k=Math.min(prev.length,n.length);k>0;k--){
                boolean same=true;for(int j=0;j<k;j++)if(!prev[prev.length-k+j].equals(n[j])){same=false;break;}
                if(same){best=k;break;}
            }
            if(best==1&&n.length>1)best=0;
            if(best<n.length)out.append(String.join(" ",Arrays.copyOfRange(n,best,n.length))).append('\n');
            prev=n;
        }
        return out.toString();
    }
    private Saved exportFile(File from,String mode)throws Exception{
        String kind=mode.equals("MP4")?"Video":mode.equals("MP3")?"Audio":"Transcripts";
        String type=mode.equals("MP4")?"video/mp4":mode.equals("MP3")?"audio/mpeg":from.getName().endsWith(".txt")?"text/plain":"application/x-subrip";
        ContentResolver resolver=context.getContentResolver();
        Uri target,dir=null;
        String relative=Environment.DIRECTORY_DOWNLOADS+"/Simple Pyrate/"+kind+"/";
        String name=from.getName();
        if(req.destination==null){
            String exist=name;int suffix=2;
            Uri collection=MediaStore.Downloads.EXTERNAL_CONTENT_URI;
            while(hasMedia(resolver,collection,relative,exist)){check();exist=withSuffix(name,suffix++);}
            name=exist;ContentValues props=new ContentValues();props.put(MediaStore.MediaColumns.DISPLAY_NAME,name);
            props.put(MediaStore.MediaColumns.MIME_TYPE,type);props.put(MediaStore.MediaColumns.RELATIVE_PATH,relative);
            props.put(MediaStore.MediaColumns.IS_PENDING,1);target=resolver.insert(collection,props);
        }else {
            dir=DocumentsContract.buildDocumentUriUsingTree(req.destination,DocumentsContract.getTreeDocumentId(req.destination));
            dir=makeDir(resolver,req.destination,dir,"Simple Pyrate");
            dir=makeDir(resolver,req.destination,dir,kind);
            Set<String> existing=names(resolver,req.destination,dir).keySet();
            int suffix=2;while(existing.contains(name)){check();name=withSuffix(from.getName(),suffix++);}
            target=DocumentsContract.createDocument(resolver,dir,type,name);
        }
        if(target==null)throw new IOException("The save location did not accept the file.");
        try {
            try(InputStream in=new BufferedInputStream(new FileInputStream(from));OutputStream out=resolver.openOutputStream(target,"w")){
                if(out==null)throw new IOException("The save location could not open an output stream.");
                byte[] b=new byte[65536];int n;while((n=in.read(b))!=-1){check();out.write(b,0,n);}
            }
            if(req.destination==null){ContentValues v=new ContentValues();v.put(MediaStore.MediaColumns.IS_PENDING,0);if(resolver.update(target,v,null,null)!=1)throw new IOException("Android did not publish the saved file.");}
            return new Saved(name,target);
        }catch(Exception e){
            try{if(req.destination==null)resolver.delete(target,null,null);else DocumentsContract.deleteDocument(resolver,target);}catch(Exception ignored){}
            throw e;
        }
    }
    private static boolean hasMedia(ContentResolver r,Uri base,String path,String n) {
        try(Cursor c=r.query(base,new String[]{"_id"},"relative_path=? AND _display_name=?",new String[]{path,n},null)){
            return c!=null&&c.moveToFirst();
        }
    }
    private static String withSuffix(String name,int n){
        int dot=name.lastIndexOf('.');return dot<1?name+" ("+n+")":name.substring(0,dot)+" ("+n+")"+name.substring(dot);
    }
    private static Map<String,Uri> names(ContentResolver r,Uri tree,Uri dir){
        HashMap<String,Uri> values=new HashMap<>();
        Uri list=DocumentsContract.buildChildDocumentsUriUsingTree(tree,DocumentsContract.getDocumentId(dir));
        try(Cursor c=r.query(list,new String[]{DocumentsContract.Document.COLUMN_DOCUMENT_ID,DocumentsContract.Document.COLUMN_DISPLAY_NAME},null,null,null)){
            if(c!=null)while(c.moveToNext())values.put(c.getString(1),DocumentsContract.buildDocumentUriUsingTree(tree,c.getString(0)));
        }
        return values;
    }
    private static Uri makeDir(ContentResolver r,Uri tree,Uri base,String name)throws IOException{
        Uri dir=names(r,tree,base).get(name);
        if(dir==null)dir=DocumentsContract.createDocument(r,base,DocumentsContract.Document.MIME_TYPE_DIR,name);
        if(dir==null)throw new IOException("Could not create the export directory.");
        return dir;
    }
}
