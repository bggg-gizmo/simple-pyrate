package com.bggg.simplepyrate;

import android.app.Instrumentation;
import android.content.Context;
import android.os.Bundle;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

public final class Smoke extends Instrumentation {
    private Bundle arguments;
    private final StringBuilder output=new StringBuilder();
    @Override public void onCreate(Bundle a){super.onCreate(a);arguments=a;start();}
    private void check(boolean value,String name){if(!value)throw new AssertionError(name);output.append("PASS ").append(name).append('\n');}
    @Override public void onStart(){
        Bundle report=new Bundle();
        File test=null;
        try {
            Context c=getTargetContext();
            test=new File(c.getCacheDir(),"pyrate-instrumentation");
            RuntimeTools.erase(test);RuntimeTools.mkdir(test);
            RuntimeTools runtime=new RuntimeTools(c);
            if(arguments.getBoolean("layout",false)||"true".equals(arguments.getString("layout"))) layoutCheck(c);
            String versions=runtime.versions();
            output.append(versions).append('\n');
            check(versions.contains("yt-dlp 20"),"packaged Python and yt-dlp execute");
            check(versions.contains("ffmpeg version")&&versions.contains("ffprobe version"),"packaged FFmpeg and FFprobe execute");
            check(versions.contains("QuickJS available"),"packaged QuickJS executes");
            Access auth=new Access("web.gvs+TEST_ACCESS_457",null);
            File cfg=auth.config(test,"https://www.youtube.com/watch?v=test");
            check(cfg!=null&&cfg.isFile(),"YouTube token produces a private config");
            String options=new String(java.nio.file.Files.readAllBytes(cfg.toPath()),StandardCharsets.UTF_8);
            check(options.contains("youtube:po_token=web.gvs+TEST_ACCESS_457;player_client=default,web"),
                "private yt-dlp config includes the token and matching client");
            check(auth.config(test,"https://example.org/asset")==null,"YouTube token ignored on unrelated hosts");
            check(auth.redact("TEST_ACCESS_457",test).equals("[PO token]"),"token is redacted from log strings");
            check(CargoRunner.validateLanguages("en,pt-BR").contains("pt-br"),"transcript language parser");
            check(CargoRunner.toText("1\n00:00:00,000 --> 00:00:01,000\nThe port &amp; ship\n").trim().equals("The port & ship"),"SRT to plaintext");
            String source=arguments.getString("fixture");
            if(source!=null){
                List<CargoRunner.Saved> saved=new ArrayList<>();
                CargoRunner.Events sink=new CargoRunner.Events(){
                    public void mode(String name){output.append("MODE ").append(name).append('\n');}
                    public void port(String m,String title,int n,int t){output.append("PORT ").append(m).append(' ').append(title).append('\n');}
                    public void transfer(int p,String d){}
                    public void waiting(double s){}
                    public void processing(String text){output.append("PROCESS ").append(text).append('\n');}
                    public void portDone(boolean ok){output.append("PORT DONE ").append(ok).append('\n');}
                    public void saved(CargoRunner.Saved f){saved.add(f);output.append("FILE ").append(f.name).append('\n');}
                    public void log(String line){output.append(line).append('\n');}
                };
                try{
                    CargoRunner.Settings r=new CargoRunner.Settings(source,Arrays.asList("MP4","MP3","Transcript"),false,480,"192K","en",true,true,true,null);
                    CargoRunner.Result result=new CargoRunner(c,runtime,r,new Access("",null),sink).run();
                    check(result.errors==0&&result.saved==4,"local HTTP fixture produced MP4, MP3, SRT and TXT");
                    for(String ext:new String[]{".mp4",".mp3",".srt",".txt"}){
                        boolean readable=false;
                        for(CargoRunner.Saved f:saved)if(f.name.endsWith(ext))try(InputStream in=c.getContentResolver().openInputStream(f.uri)){readable=in!=null&&in.read()!=-1;}
                        check(readable,"MediaStore export "+ext+" is readable");
                    }
                }finally{for(CargoRunner.Saved f:saved)c.getContentResolver().delete(f.uri,null,null);}
            }
            report.putString("stream","\n"+output);finish(0,report);
        }catch(Throwable ex){
            StringWriter writer=new StringWriter();ex.printStackTrace(new PrintWriter(writer));
            report.putString("stream","\n"+output+writer);report.putString("failure",ex.toString());finish(1,report);
        }finally{if(test!=null)RuntimeTools.erase(test);}
    }
    private void layoutCheck(Context c){
        android.content.SharedPreferences prefs=c.getSharedPreferences("simple-pyrate",Context.MODE_PRIVATE);
        boolean hadSetup=prefs.contains("setup"), setup=prefs.getBoolean("setup",false);
        prefs.edit().putBoolean("setup",true).commit();
        MainActivity activity=null;
        try {
            android.content.Intent intent=new android.content.Intent(c,MainActivity.class)
                .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK);
            activity=(MainActivity)startActivitySync(intent);waitForIdleSync();
            android.view.View root=activity.getWindow().getDecorView();
            android.graphics.Rect scene=new android.graphics.Rect(), dock=new android.graphics.Rect();
            android.view.View action=root.findViewWithTag("pyrate-download");
            check(root.findViewWithTag("pyrate-scene").getGlobalVisibleRect(scene)&&!scene.isEmpty(),
                "voyage has a visible viewport");
            check(action.getGlobalVisibleRect(dock)&&dock.height()==action.getHeight()&&dock.width()==action.getWidth(),
                "Download action is visible without scrolling");
            check(!android.graphics.Rect.intersects(scene,dock),"primary controls do not cover the voyage viewport");
            check(root.findViewWithTag("pyrate-token").getGlobalVisibleRect(dock),"source access is visible on deck");
        } finally {
            if(activity!=null){MainActivity current=activity;runOnMainSync(current::finish);}
            android.content.SharedPreferences.Editor settings=prefs.edit();
            if(hadSetup)settings.putBoolean("setup",setup);else settings.remove("setup");
            settings.commit();
        }
    }

}
