package com.bggg.simplepyrate;

import android.system.Os;
import java.io.*;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.Locale;
import java.util.LinkedHashSet;

final class Access {
    final String po;
    final byte[] cookies;
    Access(String token,byte[] jar) {
        po=token==null?"":token.trim();
        if(!po.isEmpty()&&(po.length()>16384||!po.matches("[A-Za-z0-9_-]+\\.(?:gvs|player|subs)\\+[A-Za-z0-9_-]+={0,2}(?:,[A-Za-z0-9_-]+\\.(?:gvs|player|subs)\\+[A-Za-z0-9_-]+={0,2})*")))
            throw new IllegalArgumentException("Use yt-dlp’s client.context+token format, with commas between tokens.");
        if(jar!=null&&(jar.length>1024*1024||!new String(jar,StandardCharsets.UTF_8).matches("(?s)\\A(?:\\uFEFF)?# (?:Netscape HTTP Cookie File|HTTP Cookie File)\\b.*")))
            throw new IllegalArgumentException("Import a Netscape-format cookies.txt export.");
        cookies=jar==null?null:jar.clone();
    }
    boolean active(){return !po.isEmpty()||cookies!=null;}
    static URI link(String s) {
        if(s.length()>8192||s.matches("(?s).*[\\x00-\\x20\\x7F\\\\].*"))throw new IllegalArgumentException("Use one valid HTTP or HTTPS link per line.");
        try {
            URI uri=new URI(s);
            if(uri.getHost()!=null&&uri.getUserInfo()==null&&("https".equalsIgnoreCase(uri.getScheme())||"http".equalsIgnoreCase(uri.getScheme())))return uri;
        } catch(Exception ignored) {}
        throw new IllegalArgumentException("Use one valid HTTP or HTTPS link per line.");
    }
    static boolean youtube(String host) {
        host=host.toLowerCase(Locale.ROOT);
        return host.equals("youtu.be")||host.equals("youtube.com")||host.endsWith(".youtube.com");
    }
    File config(File into,String url)throws Exception{
        boolean usePo=!po.isEmpty()&&youtube(link(url).getHost());
        if(!usePo&&cookies==null)return null;
        RuntimeTools.mkdir(into);Os.chmod(into.getAbsolutePath(),0700);
        StringBuilder opts=new StringBuilder();
        if(usePo){
            LinkedHashSet<String> clients=new LinkedHashSet<>();
            clients.add("default");
            for(String value:po.split(","))clients.add(value.substring(0,value.indexOf('.')));
            opts.append("--extractor-args 'youtube:po_token=").append(po)
                .append(";player_client=").append(String.join(",",clients)).append("'\n");
        }
        if(cookies!=null){
            File jar=new File(into,"cookies.txt");Files.write(jar.toPath(),cookies);Os.chmod(jar.getAbsolutePath(),0600);
            opts.append("--cookies '").append(jar.getAbsolutePath().replace("'","'\\''")).append("'\n");
        }
        File config=new File(into,"yt-dlp.conf");
        Files.write(config.toPath(),opts.toString().getBytes(StandardCharsets.UTF_8));Os.chmod(config.getAbsolutePath(),0600);
        return config;
    }
    String redact(String line,File into) {
        if(line==null)return "";
        if(into!=null)line=line.replace(into.getAbsolutePath(),"[source credentials]");
        if(!po.isEmpty())for(String token:po.split(",")){
            line=line.replace(token,"[PO token]");
            line=line.replace(token.substring(token.indexOf('+')+1),"[PO token]");
        }
        if(cookies!=null&&(line.toLowerCase(Locale.ROOT).contains("cookie")||line.contains("Cookie"))) {
            for(String row:new String(cookies,StandardCharsets.UTF_8).split("\\r?\\n")) {
                String[] f=row.split("\\t",7);
                if(f.length==7&&f[6].length()>0)line=line.replace(f[6],"[cookie]");
            }
        }
        return line;
    }
}
