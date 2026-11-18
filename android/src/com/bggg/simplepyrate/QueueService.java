package com.bggg.simplepyrate;

import android.app.*;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;

public final class QueueService extends Service {
    private final String channel="active_hauls";
    private final int id=260;
    private DeckState deck;
    private long last;
    @Override public void onCreate(){
        super.onCreate();deck=DeckState.get(this);
        getSystemService(NotificationManager.class).createNotificationChannel(new NotificationChannel(channel,"Download queue",NotificationManager.IMPORTANCE_LOW));
    }
    @Override public int onStartCommand(Intent intent,int flags,int sequence){
        if(intent!=null&&"com.bggg.simplepyrate.STOP".equals(intent.getAction()))deck.stop();
        deck.service=this;
        try{startForeground(id,notification(),ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC);}
        catch(RuntimeException ex){deck.log("Android did not allow the foreground service for this haul.");stopSelf();return START_NOT_STICKY;}
        if(!deck.busy())finish();
        return START_NOT_STICKY;
    }
    @Override public IBinder onBind(Intent intent){return null;}
    @Override public void onDestroy(){if(deck!=null&&deck.service==this)deck.service=null;super.onDestroy();}
    @Override public void onTimeout(int startId,int fgsType){
        if(deck!=null)deck.stop();finish();
    }
    void finish(){stopForeground(STOP_FOREGROUND_REMOVE);stopSelf();}
    void update(){
        if(!deck.busy()||android.os.SystemClock.uptimeMillis()-last<720)return;
        last=android.os.SystemClock.uptimeMillis();
        getSystemService(NotificationManager.class).notify(id,notification());
    }
    private Notification notification(){
        PendingIntent open=PendingIntent.getActivity(this,0,new Intent(this,MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT);
        PendingIntent stop=PendingIntent.getService(this,1,new Intent(this,QueueService.class).setAction("com.bggg.simplepyrate.STOP"),PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT);
        return new Notification.Builder(this,channel).setSmallIcon(R.drawable.anchor).setContentTitle("Simple Pyrate · "+deck.state)
            .setContentText(deck.detail).setContentIntent(open).setOnlyAlertOnce(true).setOngoing(true)
            .setProgress(100,Math.max(0,deck.percent),deck.percent<0)
            .addAction(new Notification.Action.Builder(null,"Stop active",stop).build()).build();
    }
}
