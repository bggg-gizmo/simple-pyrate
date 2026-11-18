package com.bggg.simplepyrate;

import android.content.Context;
import android.content.SharedPreferences;
import android.content.res.AssetFileDescriptor;
import android.media.AudioAttributes;
import android.media.MediaPlayer;
import android.media.SoundPool;
import android.os.Handler;
import android.os.Looper;
import java.util.ArrayDeque;

final class AudioDeck {
    static final String[] LISTS={"Music off","Lantern watch","Corsair run","All scores"};
    static final String[] TITLES={"Lagoon Watch","Lantern Reach","Storm Corsairs","The Black Tide"};
    private static final String[] SONGS={"lagoon-watch","lantern-reach","storm-corsairs","the-black-tide"};
    private static final String[] FX={"cannon","embers","boats","cargo","hoist","aboard","ruins"};
    private static final int[][] TRACKS={{},{0,1},{2,3},{0,1,2,3}};
    private final Context context;
    private final SharedPreferences prefs;
    private final Handler h=new Handler(Looper.getMainLooper());
    private final SoundPool pool;
    private final int[] samples=new int[7];
    private final ArrayDeque<String> pending=new ArrayDeque<>();
    private MediaPlayer sea,music,bell;
    private boolean foreground=true,audible=true;
    private int track;
    AudioDeck(Context c,SharedPreferences p){
        context=c;prefs=p;
        pool=new SoundPool.Builder().setMaxStreams(5).setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()).build();
        for(int i=0;i<FX.length;i++){
            try(AssetFileDescriptor fd=c.getAssets().openFd("audio/"+FX[i]+".wav")){samples[i]=pool.load(fd,1);}
            catch(Exception e){android.util.Log.e("SimplePyrate","Packaged sound unavailable: "+FX[i],e);}
        }
    }
    int playlist(){return Math.max(0,Math.min(3,prefs.getInt("music",0)));}
    String trackTitle(){int p=playlist();return p==0?"Music off":TITLES[TRACKS[p][track%TRACKS[p].length]];}
    boolean fx(){return prefs.getBoolean("effects",true);}
    boolean sea(){return prefs.getBoolean("sea",false);}
    int effectsVolume(){return prefs.getInt("fxVolume",72);}
    int musicVolume(){return prefs.getInt("musicVolume",36);}
    void foreground(boolean b){foreground=b;sync();}
    void preferences(){sync();}
    void select(int p){prefs.edit().putInt("music",p).apply();track=0;release(music);music=null;sync();}
    void next(){track++;release(music);music=null;sync();}
    void raid(int stage){
        if(!fx()||!audible||stage<0||stage>=samples.length||effectsVolume()==0)return;
        float gain=effectsVolume()/100f;pool.play(samples[stage],gain,gain,1,0,1f);
    }
    void bell(String cue){
        if(!fx()||effectsVolume()==0)return;
        pending.addLast(cue);nextBell();
    }
    private void nextBell(){
        if(bell!=null||pending.isEmpty()||!fx())return;
        String cue=pending.removeFirst();
        bell=play("audio/ship-bell-"+cue+".wav",effectsVolume()/100f,false);
        if(bell!=null)bell.setOnCompletionListener(p->{release(p);if(bell==p)bell=null;h.post(this::nextBell);});
        else h.post(this::nextBell);
    }
    private void sync(){
        int list=playlist();
        audible=foreground;
        if(!audible)pool.autoPause();else pool.autoResume();
        if(sea!=null&&(!sea()||!foreground)){release(sea);sea=null;}
        if(sea==null&&sea()&&foreground)sea=play("Night-Sea.wav",.42f,true);
        if(music!=null&&(list==0||!foreground)){release(music);music=null;}
        if(music!=null)music.setVolume(musicVolume()/100f,musicVolume()/100f);
        if(music==null&&list>0&&foreground){
            music=play("audio/"+SONGS[TRACKS[list][track%TRACKS[list].length]]+".mp3",musicVolume()/100f,false);
            if(music!=null)music.setOnCompletionListener(p->{if(music==p)next();});
        }
        if(!fx()||effectsVolume()==0){release(bell);bell=null;pending.clear();pool.autoPause();}
        else {if(audible)pool.autoResume();if(bell!=null)bell.setVolume(effectsVolume()/100f,effectsVolume()/100f);}
    }
    private MediaPlayer play(String asset,float gain,boolean loop){
        MediaPlayer p=new MediaPlayer();
        try(AssetFileDescriptor file=context.getAssets().openFd(asset)){
            p.setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).setContentType(loop?AudioAttributes.CONTENT_TYPE_MUSIC:AudioAttributes.CONTENT_TYPE_SONIFICATION).build());
            p.setDataSource(file.getFileDescriptor(),file.getStartOffset(),file.getLength());
            p.setOnErrorListener((player,what,extra)->{android.util.Log.e("SimplePyrate","Sound decode error "+asset+": "+what+"/"+extra);return false;});
            p.prepare();p.setLooping(loop);p.setVolume(gain,gain);p.start();return p;
        }catch(Exception e){release(p);android.util.Log.e("SimplePyrate","Unable to play "+asset,e);return null;}
    }
    private static void release(MediaPlayer p){if(p!=null)p.release();}
}
