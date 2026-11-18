package com.bggg.simplepyrate;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

final class DeckState {
    private static DeckState instance;
    static DeckState get(Context c){if(instance==null)instance=new DeckState(c.getApplicationContext());return instance;}
    interface Receiver { void refresh(); }
    interface Work { String run() throws Exception; }
    interface Report { void finish(String value,boolean ok); }
    static final class Job {
        final CargoRunner.Settings options;
        Access access;
        String state="Queued",detail="";
        Job(CargoRunner.Settings options,Access access){this.options=options;this.access=access;}
    }
    final SharedPreferences prefs;
    final AudioDeck audio;
    final Voyage voyage;
    final RuntimeTools runtime;
    final ArrayList<Job> rows=new ArrayList<>();
    final ArrayList<CargoRunner.Saved> files=new ArrayList<>();
    final ArrayDeque<String> logs=new ArrayDeque<>();
    private final ArrayDeque<Job> pending=new ArrayDeque<>();
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    private final Handler main=new Handler(Looper.getMainLooper());
    private final Context app;
    private CargoRunner runner;
    private boolean voyageActive;
    Job active;
    boolean checking;
    int percent=-1;
    String state="At anchor",title="Ready to set sail",detail="Add a link and choose your cargo.";
    Access access=new Access("",null);
    Receiver view;
    QueueService service;
    private DeckState(Context c){
        app=c;prefs=c.getSharedPreferences("simple-pyrate",Context.MODE_PRIVATE);
        audio=new AudioDeck(c,prefs);voyage=new Voyage(c,audio);runtime=new RuntimeTools(c);
        voyage.motion(prefs.getBoolean("motion",true));
        audio.foreground(false);
        worker.execute(()->{
            RuntimeTools.erase(new java.io.File(app.getNoBackupFilesDir(),"jobs"));
            try{runtime.prepare();}catch(Exception ignored){/* The actual haul or tool check can retry and report failure. */}
        });
    }
    boolean busy(){return active!=null||!pending.isEmpty();}
    int waiting(){return pending.size();}
    void queue(Activity ui,List<CargoRunner.Settings> requests){
        for(CargoRunner.Settings options:requests){Job j=new Job(options,access);pending.add(j);rows.add(j);}
        if(active==null)advance();
        try{ui.startForegroundService(new Intent(ui,QueueService.class));}catch(RuntimeException ex){log("Android could not start the background queue. Keep this screen open.");}
        notifyView();
    }
    void remove(Job job){if(job==active)return;pending.remove(job);rows.remove(job);job.access=null;notifyView();}
    void retry(Activity activity,Job job){if(job!=active&&!pending.contains(job))queue(activity,java.util.Collections.singletonList(job.options));}
    void clearFinished(){
        rows.removeIf(j->j!=active&&!pending.contains(j));
        notifyView();
    }
    void stop(){if(runner!=null){detail="Stopping this haul";runner.cancel();notifyView();}}
    private void advance(){
        if(active!=null)return;
        Job job=pending.poll();
        if(job==null){
            if(voyageActive){voyage.finish(lastOk);if(lastOk)audio.bell("finish");voyageActive=false;}
            if(service!=null)service.finish();
            notifyView();return;
        }
        active=job;percent=-1;
        state="Resolving source";title=job.options.url;detail="Contacting the source";
        job.state="Resolving";
        if(!voyageActive){voyageActive=true;voyage.start();audio.bell("start");}
        Access credentials=job.access==null?new Access("",null):job.access;
        runner=new CargoRunner(app,runtime,job.options,credentials,new CargoRunner.Events(){
            private void post(Runnable r){main.post(()->{if(active==job)r.run();});}
            @Override public void mode(String name){post(()->{voyage.mode(name);state="Resolving source";detail=name+"  ·  Preparing manifest";percent=-1;job.state="Resolving";notifyView();});}
            @Override public void resolving(String step){post(()->{
                if("Resolving source".equals(state)&&!step.equals(detail)){detail=step;notifyView();}
            });}
            @Override public void port(String name,String label,int n,int total){post(()->{
                title=label;percent=-1;state="Approaching port";job.state="Downloading";
                detail=name+(n>0?"  ·  Item "+n+(total>0?" of "+total:""):"");
                voyage.port(++voyagePort,name,job.options.collection||job.options.modes.size()>1||rowsPerVoyage>1);
                if(job.options.collection||job.options.modes.size()>1||rowsPerVoyage>1)audio.bell("port");
                notifyView();
            });}
            @Override public void transfer(int p,String progress){post(()->{
                state="Plundering"; percent=p; detail=progress;voyage.transfer(p);notifyView();
            });}
            @Override public void waiting(double seconds){post(()->{
                state="Source pause";detail="The source requested a brief wait";percent=-1;voyage.waitFor(seconds);notifyView();
            });}
            @Override public void processing(String text){post(()->{
                state="Finalizing";detail=text;job.state="Finalizing";notifyView();
            });}
            @Override public void portDone(boolean saved){post(()->voyage.done(saved));}
            @Override public void saved(CargoRunner.Saved file){post(()->{files.add(file);notifyView();});}
            @Override public void log(String line){post(()->DeckState.this.log(line));}
        });
        CargoRunner started=runner;
        worker.execute(()->{
            CargoRunner.Result result=started.run();
            main.post(()->{
                if(active!=job)return;
                job.state=result.status();
                job.detail=result.saved+" saved" +(result.errors>0?" · "+result.errors+" error(s)":"")+(result.missing>0?" · "+result.missing+" without captions":"");
                job.access=null;
                active=null;runner=null;
                state=job.state;detail=job.detail;
                percent=result.saved>0?100:-1;
                lastOk|=result.saved>0;
                advance();
            });
        });
        notifyView();
    }
    private boolean lastOk;
    private int voyagePort,rowsPerVoyage;
    void beginQueue(Activity a,List<CargoRunner.Settings> requests){
        if(!voyageActive){voyagePort=0;lastOk=false;rowsPerVoyage=requests.size();}
        else rowsPerVoyage+=requests.size();
        queue(a,requests);
    }
    void log(String value){
        if(value==null||value.trim().isEmpty())return;
        logs.addLast(value.substring(0,Math.min(value.length(),1600)));
        if(logs.size()>400)logs.removeFirst();
    }
    void tools(boolean update,Report report){
        if(checking||busy()){report.finish("Finish or stop the active haul before checking tools.",false);return;}
        checking=true;notifyView();
        worker.execute(()->{
            String message;
            boolean pass=true;
            try{message=update?"Updated yt-dlp to "+runtime.updateYt():runtime.versions();}
            catch(Exception e){pass=false;message=e.getMessage();if(message==null||message.isEmpty())message="Could not check the bundled toolchain.";}
            final String value=message;final boolean ok=pass;
            main.post(()->{checking=false;log(value);notifyView();report.finish(value,ok);});
        });
    }
    void notifyView(){if(view!=null)view.refresh();if(service!=null)service.update();}
}
