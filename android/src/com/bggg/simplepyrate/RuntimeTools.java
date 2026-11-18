package com.bggg.simplepyrate;

import android.content.Context;
import android.os.Build;
import android.system.Os;
import org.json.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.zip.*;

final class RuntimeTools {
    static final String YT_REPO="https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest";
    private final Context app;
    private final File root, nativeDir;
    private final File yt, python, ffmpeg, probe, quickjs;
    private File data;
    private boolean ready;
    RuntimeTools(Context c) {
        app=c.getApplicationContext();
        root=new File(app.getNoBackupFilesDir(),"runtime");
        nativeDir=new File(app.getApplicationInfo().nativeLibraryDir);
        yt=new File(root,"yt-dlp");
        python=new File(nativeDir,"libpython.so");
        ffmpeg=new File(nativeDir,"libffmpeg.so");
        probe=new File(nativeDir,"libffprobe.so");
        quickjs=new File(nativeDir,"libqjs.so");
    }
    synchronized void prepare() throws Exception {
        if(ready)return;
        for(File nativeFile:new File[]{python,ffmpeg,probe,quickjs}) if(!nativeFile.canExecute())
            throw new IOException("Missing executable for "+Build.SUPPORTED_ABIS[0]+": "+nativeFile.getName());
        mkdir(root);
        File py=new File(nativeDir,"libpython.zip.so"), ff=new File(nativeDir,"libffmpeg.zip.so");
        String revision="v2-2-"+py.length()+"-"+ff.length();
        data=new File(root,revision);
        if(!new File(data,"ready").isFile()) {
            File temp=new File(root,revision+".stage");
            erase(temp); mkdir(temp);
            try {
                JSONObject map;
                try(InputStream in=app.getAssets().open("runtime/native-links.json")){
                    ByteArrayOutputStream out=new ByteArrayOutputStream();copy(in,out,128*1024);
                    JSONObject all=new JSONObject(out.toString("UTF-8"));
                    String abi=nativeDir.getName().contains("64")&&nativeDir.getName().startsWith("x86")?"x86_64":nativeDir.getName().contains("arm")?"arm64-v8a":Build.SUPPORTED_ABIS[0];
                    map=all.getJSONObject(abi);
                }
                unzip(py,new File(temp,"python"),map.getJSONObject(py.getName()));
                unzip(ff,new File(temp,"ffmpeg"),map.getJSONObject(ff.getName()));
                if(!new File(temp,"python/usr/etc/tls/cert.pem").isFile()) throw new IOException("Missing Python CA bundle");
                new File(temp,"ready").createNewFile();
                erase(data);
                Files.move(temp.toPath(),data.toPath());
            } finally { erase(temp); }
        }
        if(!yt.isFile()) {
            File tmp=new File(root,"yt-dlp.init");
            try(InputStream a=app.getAssets().open("runtime/yt-dlp");
                OutputStream b=new FileOutputStream(tmp)) { copy(a,b,20L*1024*1024); }
            commit(tmp,yt);
        }
        ready=true;
        File[] previous=root.listFiles();
        if(previous!=null)for(File old:previous)if(old.isDirectory()&&old.getName().startsWith("v2-")&&!old.equals(data))erase(old);
    }
    File extractorCache(){return new File(root,"extractor-cache");}
    File ffmpeg(){return ffmpeg;}
    File ffprobe(){return probe;}
    File quickjs(){return quickjs;}
    Process startYt(List<String> args,File working) throws Exception {
        prepare();
        return startYtFile(yt,args,working);
    }
    Process startHaul(File plan,File working) throws Exception {
        prepare();
        // The runner is supplied by this signed APK. Overwrite the small script
        // each process start so upgrades never run the old session protocol.
        File script=new File(root,"haul.py");
        File staged=new File(root,"haul.py.stage");
        try(InputStream in=app.getAssets().open("runtime/haul.py");OutputStream out=new FileOutputStream(staged)){
            copy(in,out,64*1024);
        }
        commit(staged,script);
        return process(Arrays.asList(python.getAbsolutePath(),"-u",script.getAbsolutePath(),
            yt.getAbsolutePath(),plan.getAbsolutePath()),working).start();
    }
    private Process startYtFile(File script,List<String> args,File working) throws IOException {
        ArrayList<String> a=new ArrayList<>(); a.add(python.getAbsolutePath());a.add(script.getAbsolutePath());a.addAll(args);
        return process(a,working).start();
    }
    synchronized Process startTool(File tool,List<String> args,File working) throws Exception {
        prepare();
        ArrayList<String> a=new ArrayList<>(); a.add(tool.getAbsolutePath()); a.addAll(args);
        return process(a,working).start();
    }
    private ProcessBuilder process(List<String> a,File working) {
        ProcessBuilder b=new ProcessBuilder(a).directory(working).redirectErrorStream(true);
        Map<String,String> e=b.environment();
        String py=new File(data,"python/usr").getAbsolutePath();
        e.put("LD_LIBRARY_PATH",py+"/lib:"+new File(data,"ffmpeg/usr/lib").getAbsolutePath());
        e.put("PYTHONHOME",py);
        e.put("PYTHONNOUSERSITE","1");
        e.put("PYTHONUTF8","1");
        e.put("PYTHONDONTWRITEBYTECODE","1");
        e.put("SSL_CERT_FILE",py+"/etc/tls/cert.pem");
        e.put("HOME",root.getAbsolutePath());
        e.put("TMPDIR",app.getCacheDir().getAbsolutePath());
        e.put("PATH",nativeDir.getAbsolutePath()+":/system/bin");
        return b;
    }
    String versions() throws Exception {
        prepare();
        return version(startTool(python,Arrays.asList("--version"),root))+"\n"+"yt-dlp "+version(startYt(Arrays.asList("--ignore-config","--version"),root))+"\n"
            +version(startTool(ffmpeg,Arrays.asList("-version"),root))+"\n"
            +version(startTool(probe,Arrays.asList("-version"),root))+"\n"
            +"QuickJS "+version(startTool(quickjs,Arrays.asList("-e","console.log(\"available\")"),root));
    }
    private static String version(Process proc) throws Exception {
        proc.getOutputStream().close();
        ByteArrayOutputStream raw=new ByteArrayOutputStream();
        try(InputStream src=proc.getInputStream()) { copy(src,raw,150000); }
        int status=proc.waitFor();
        String s=raw.toString("UTF-8").trim();
        if(status!=0||s.isEmpty())throw new IOException("Bundled tool version check failed ("+status+").");
        return s.split("\n",2)[0].trim();
    }
    synchronized String updateYt() throws Exception {
        // Controller serializes component updates with active downloads.
        prepare();
        HttpsURLConnectionShim meta=open(YT_REPO, false);
        JSONObject release;
        try(InputStream in=meta.body()) {
            ByteArrayOutputStream b=new ByteArrayOutputStream();copy(in,b,4L*1024*1024);
            release=new JSONObject(b.toString("UTF-8"));
        } finally {meta.close();}
        JSONArray assets=release.getJSONArray("assets");
        JSONObject match=null;
        for(int i=0;i<assets.length();i++) if("yt-dlp".equals(assets.getJSONObject(i).getString("name")))match=assets.getJSONObject(i);
        if(match==null)throw new IOException("The official release does not contain the yt-dlp zipapp.");
        String tag=release.getString("tag_name"), digest=match.optString("digest");
        String url=match.optString("browser_download_url");long size=match.optLong("size");
        if(!tag.matches("[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}(?:\\.[0-9]+)?")||
           !url.equals("https://github.com/yt-dlp/yt-dlp/releases/download/"+tag+"/yt-dlp")||
           !digest.matches("sha256:[a-fA-F0-9]{64}")||size<=0||size>20L*1024*1024)
            throw new IOException("The upstream asset metadata did not pass verification.");
        File stage=new File(root,"yt-dlp.download");
        HttpsURLConnectionShim fetch=open(url,true);
        try {
            try(InputStream in=fetch.body();OutputStream out=new FileOutputStream(stage)) {copy(in,out,size);}
            if(stage.length()!=size||!sha(stage).equalsIgnoreCase(digest.substring(7)))throw new IOException("The download did not match the published SHA-256 and size.");
            String actual=version(startYtFile(stage,Arrays.asList("--ignore-config","--version"),root));
            if(!tag.equals(actual))throw new IOException("The downloaded tool did not report the expected version.");
            commit(stage,yt);
            return actual;
        } finally {fetch.close();Files.deleteIfExists(stage.toPath());}
    }
    private static final class HttpsURLConnectionShim {
        final HttpURLConnection c;
        HttpsURLConnectionShim(HttpURLConnection a){c=a;}
        InputStream body() throws IOException {return c.getInputStream();}
        void close(){c.disconnect();}
    }
    private static HttpsURLConnectionShim open(String where,boolean binary)throws Exception{
        URL u=new URL(where);
        for(int tries=0;tries<5;tries++){
            String host=u.getHost().toLowerCase(Locale.ROOT);
            if(!"https".equals(u.getProtocol())||u.getUserInfo()!=null||
               !(host.equals("api.github.com")||host.equals("github.com")||
                 (binary&&(host.equals("release-assets.githubusercontent.com")||host.equals("objects.githubusercontent.com")))))
                throw new IOException("Unexpected update host.");
            HttpURLConnection h=(HttpURLConnection)u.openConnection();
            h.setConnectTimeout(20000);h.setReadTimeout(45000);h.setInstanceFollowRedirects(false);
            h.setRequestProperty("User-Agent","BGGG-Simple-Pyrate/2.6.3");
            if(!binary)h.setRequestProperty("Accept","application/vnd.github+json");
            int status=h.getResponseCode();
            if(status==200)return new HttpsURLConnectionShim(h);
            if(status/100==3){
                String next=h.getHeaderField("Location");h.disconnect();
                if(next==null)throw new IOException("Empty update redirect.");
                u=new URL(u,next);continue;
            }
            h.disconnect();throw new IOException("Update server returned HTTP "+status+".");
        }
        throw new IOException("Too many update redirects.");
    }
    static void mkdir(File dir)throws IOException {
        if(!dir.isDirectory()&&!dir.mkdirs())throw new IOException("Could not create "+dir.getName());
    }
    static void erase(File f){
        if(!f.exists())return;
        if(f.isDirectory()&&!Files.isSymbolicLink(f.toPath())){
            File[] a=f.listFiles();if(a!=null)for(File k:a)erase(k);
        }
        f.delete();
    }
    private static void unzip(File source,File into,JSONObject links)throws Exception{
        mkdir(into);
        String root=into.getCanonicalPath()+File.separator;
        long bytes=0;int count=0;
        try(ZipInputStream z=new ZipInputStream(new BufferedInputStream(new FileInputStream(source)))) {
            ZipEntry entry;
            while((entry=z.getNextEntry())!=null){
                if(++count>6000)throw new IOException("Invalid runtime archive count.");
                File out=new File(into,entry.getName());
                if(!out.getCanonicalPath().startsWith(root))throw new IOException("Unsafe runtime archive entry.");
                if(entry.isDirectory()){mkdir(out);continue;}
                if(links.has(entry.getName())){z.closeEntry();continue;}
                mkdir(out.getParentFile());
                try(OutputStream t=new BufferedOutputStream(new FileOutputStream(out))) {
                    bytes+=copy(z,t,430L*1024*1024-bytes);
                }
                z.closeEntry();
            }
        }
        java.nio.file.Path base=into.getCanonicalFile().toPath();
        for(Iterator<String> keys=links.keys();keys.hasNext();){
            String name=keys.next();
            java.nio.file.Path path=base.resolve(name).normalize(),target=new File(links.getString(name)).toPath();
            if(target.isAbsolute()||path.equals(base)||!path.startsWith(base)||
                    !path.getParent().resolve(target).normalize().startsWith(base))
                throw new IOException("Unsafe runtime library link: "+name);
            mkdir(path.getParent().toFile());Files.createSymbolicLink(path,target);
        }
    }
    static long copy(InputStream in,OutputStream out,long limit)throws IOException{
        byte[] buf=new byte[65536];long length=0;int n;
        while((n=in.read(buf))!=-1){length+=n;if(length>limit)throw new IOException("Input exceeded its size limit.");out.write(buf,0,n);}
        return length;
    }
    static String sha(File p)throws Exception{
        MessageDigest d=MessageDigest.getInstance("SHA-256");
        try(InputStream in=new FileInputStream(p)){byte[] b=new byte[65536];int n;while((n=in.read(b))!=-1)d.update(b,0,n);}
        StringBuilder t=new StringBuilder();for(byte x:d.digest())t.append(String.format(Locale.ROOT,"%02x",x&255));return t.toString();
    }
    static void commit(File a,File b)throws IOException{
        Files.move(a.toPath(),b.toPath(),StandardCopyOption.REPLACE_EXISTING,StandardCopyOption.ATOMIC_MOVE);
    }
}
