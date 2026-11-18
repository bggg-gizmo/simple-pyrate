package com.bggg.simplepyrate;

import android.content.Context;
import android.graphics.*;
import android.os.SystemClock;
import android.view.View;
import java.io.InputStream;
import java.util.ArrayDeque;

final class Voyage extends View {
    private static final String[] PORTS={"EMBER QUAY","BONEWATCH","LANTERN REACH","GHOSTWATER"};
    private static final String[] HEAD={"Ready to set sail","Setting sail","Under way","Plundering in progress","Returning to harbor"};
    private static final String[] RAID={"Cannon volley","Fires on the waterfront","Dinghies away","Cargo to the boats","Hauling cargo aboard","Crew back aboard","Dinghies hoisted"};
    private static final int[] MILESTONES={30,50,75,80,95,98};
    private static final int[][] ROOF_X={{826,879,933,991,1051,1116,1166},{825,885,951,1009,1061,1108,1170},{825,874,925,974,1020,1081,1154},{822,882,936,989,1046,1123,1182}};
    private static final int[][] ROOF_Y={{232,216,177,231,154,211,178},{238,185,131,216,168,197,144},{225,147,236,213,229,196,213},{210,218,173,226,171,151,213}};
    private final Paint g=new Paint(Paint.ANTI_ALIAS_FLAG|Paint.FILTER_BITMAP_FLAG);
    private final RectF dest=new RectF();
    private final Path path=new Path();
    private final Bitmap sky,harbor,ship,fog;
    private final Bitmap[] port=new Bitmap[4];
    private final AudioDeck sound;
    private final ArrayDeque<Battle> route=new ArrayDeque<>();
    private static final class Battle {
        int number,progress; boolean done, success, batch; String cargo;
        Battle(int n,String m,boolean batch){number=n;cargo=m;this.batch=batch;}
    }
    private Battle current,received;
    private int shot,stage,leaving,leavingStage;
    private long cut=now(), beat=cut, waitUntil, cannon;
    private boolean motion=true,inbound,returnSuccess,active,artOnly;
    private String cargo="",message="";
    private final Rect viewport=new Rect();
    private boolean useViewport;
    private Shader backdrop;
    private static final Typeface SCENE_FONT=Typeface.create("serif",Typeface.BOLD);
    void viewport(Rect value){
        if(useViewport&&viewport.equals(value))return;
        useViewport=true;viewport.set(value);invalidate();
    }
    Voyage(Context c,AudioDeck audio){
        super(c); sound=audio;
        sky=picture("sea-and-sky"); harbor=picture("lagoon"); ship=picture("pyrate-ship"); fog=picture("fog");
        for(int i=0;i<4;i++)port[i]=picture("port-"+i);
        setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
    }
    void artworkOnly(){artOnly=true;invalidate();}
    private Bitmap picture(String name){try(InputStream in=getContext().getAssets().open("voyage/"+name+".png")){
        Bitmap b=BitmapFactory.decodeStream(in);if(b==null)throw new IllegalStateException(name);return b;
    }catch(Exception e){throw new IllegalStateException("Missing scene asset "+name,e);}}
    void motion(boolean b){motion=b;invalidate();}
    void start(){
        long t=now();active=true;inbound=false;message="";waitUntil=0;
        if(shot==0||shot==4){cut=t;shot=1;stage=0;leaving=0;current=null;}
        invalidate();
    }
    void mode(String name){cargo=name;invalidate();}
    void port(int n,String name,boolean batch){
        int next=n<=0?1:n;received=new Battle(next,name,batch);route.addLast(received);waitUntil=0;invalidate();
    }
    void transfer(int p){if(received!=null&&!received.done)received.progress=Math.max(received.progress,p);invalidate();}
    void waitFor(double seconds){waitUntil=now()+(long)(1000*Math.max(0,seconds));invalidate();}
    void done(boolean ok){if(received!=null){received.done=true;received.success=ok;if(ok)received.progress=100;}invalidate();}
    void finish(boolean ok){inbound=true;returnSuccess=ok;waitUntil=0;invalidate();}
    void reset(){
        route.clear(); current=null;received=null;shot=0;stage=0;active=false;inbound=false;waitUntil=0;
        invalidate();
    }
    private static long now(){return SystemClock.uptimeMillis();}
    private static float clamp(float x){return Math.max(0,Math.min(1,x));}
    private static float ease(float x){x=clamp(x);return x*x*(3-2*x);}
    private static float lerp(float a,float b,float t){return a+(b-a)*t;}
    private static float s(double z){return (float)Math.sin(z);}
    private static float c(double z){return (float)Math.cos(z);}
    private void update(long t){
        if(artOnly)return;
        long age=t-cut;
        if(shot==1&&age>=2100){shot=2;cut=t;}
        else if(shot==2&&age>=(leaving>0?1680:550)&&!route.isEmpty()){
            current=route.removeFirst();shot=3;cut=beat=t;stage=0;cannon=t+290;
        }else if(shot==3&&current!=null){
            if(stage<2&&t>=cannon){
                if(sound!=null)sound.raid(0);
                cannon=t+2700;
            }
            if(stage<6&&current.progress>=MILESTONES[stage]&&t-beat>=(stage==0?700:500)){
                stage++;beat=t;if(sound!=null)sound.raid(stage);
            }
            if(current.done&&t-beat>=600&&age>=850&&(!current.success||stage>=6)){
                if(!route.isEmpty()||!inbound){
                    leaving=current.number; leavingStage=stage;current=null;shot=2;cut=t;
                }else{
                    current=null;goHome(t);
                }
            }
        }else if((shot==2||shot==1)&&inbound&&route.isEmpty()&&age>=(shot==1?2100:leaving>0?1680:660)){
            goHome(t);
        }else if(shot==4&&age>=1900){shot=0;cut=t;active=false;cargo="";leaving=0;}
    }
    private void goHome(long t){shot=4;cut=t;inbound=false;leaving=0;message=returnSuccess?"Cargo secured":"Back at anchor";}
    @Override protected void onSizeChanged(int w,int h,int ow,int oh){
        backdrop=new LinearGradient(0,0,0,Math.max(1,h),0xff091722,0xff0a2129,Shader.TileMode.CLAMP);
    }
    @Override protected void onDraw(Canvas canvas){
        super.onDraw(canvas);
        int w=getWidth(),h=getHeight();
        if(w<=1||h<=1)return;
        long t=now();update(t);
        float sec=motion?(t%720000)/1000f:0;float dt=(t-cut)/1000f;
        canvas.drawColor(0xff06121b);
        g.setShader(backdrop);g.setAlpha(255);canvas.drawRect(0,0,w,h,g);g.setShader(null);
        int left=useViewport?viewport.left:0,top=useViewport?viewport.top:0;
        int width=useViewport?viewport.width():w,height=useViewport?viewport.height():h;
        float dp=getResources().getDisplayMetrics().density;
        float band=artOnly?0:Math.min(80*dp,height*.30f);
        float windowH=height-band;
        if(width>1&&windowH>1){
            // Keep the ship, port and their effects inside the visible deck, above the text band.
            float worldWidth=artOnly||shot==1||shot==4?1200:shot==3||leaving>0?1000:940;
            float worldLeft=worldWidth==1200?0:worldWidth==1000?200:205;
            float scale=Math.min(width/worldWidth,windowH/390f);
            float x=(width-worldWidth*scale)*.5f-worldLeft*scale;
            float y=(windowH-390*scale)*.5f;
            canvas.save();canvas.clipRect(left,top,left+width,top+windowH);
            canvas.translate(left+x,top+y);canvas.scale(scale,scale);
            scenery(canvas,sec,dt,t);
            canvas.restore();
            if(!artOnly&&band>=44*dp){
                canvas.save();canvas.translate(left,top+windowH);canvas.clipRect(0,0,width,band);
                caption(canvas,width,band,t,dt);
                canvas.restore();
            }
        }
        if(!artOnly&&(motion||active||inbound||!route.isEmpty()))postInvalidateDelayed(motion?32:120);
    }
    private void scenery(Canvas k,float t,float age,long now){
        float p=ease(age/(shot==1?2.1f:shot==4?1.9f:1.68f)),x,y,z;
        boolean reverse=shot==4;
        image(k,sky,0,0,1200,390,255);
        if(shot==0||shot==1||shot==4)image(k,harbor,0,0,1200,390,255);
        if(shot==1){x=lerp(504,1210,p);y=lerp(125,147,p);z=lerp(.78f,.55f,p);}
        else if(shot==4){x=lerp(1210,504,p);y=lerp(150,125,p);z=lerp(.55f,.78f,p);}
        else if(shot==0){x=504;y=125;z=.78f;}else{x=420;y=147;z=.67f;}
        if(shot==3&&current!=null){
            int variant=(current.number-1)%4;
            float shift=motion?lerp(350,0,ease(age/.82f)):0;
            k.save(); k.translate(shift,0);
            image(k,port[variant],0,0,1200,390,255);damage(k,variant,stage,t);
            k.restore();
        }else if(shot==2&&leaving>0&&p<1&&motion){
            int variant=(leaving-1)%4;k.save();k.translate(-720*p,0);
            image(k,port[variant],0,0,1200,390,255);damage(k,variant,leavingStage,t);k.restore();
        }
        for(int i=0;i<56;i++){
            float q=(i*53%133)/133f;float depth=q*q;
            float wx=(i*793.31f-t*(12+depth*36))%1300;
            if(wx<0)wx+=1300;wx-=50;
            oval(k,wx,255+depth*133+s(t*.7+i)*.8f,3+depth*(7+i%37),.5f+depth*.74f,Math.abs(wx-841)<19+depth*123?0xffb6d4c5:0xff68a99f,(int)(21+depth*32));
        }
        float drift=s(t*.39)*47;
        image(k,fog,drift,-5,1200,390,200);
        float center=x+207*z,deck=y+221*z,bob=s(t*1.44)*2.6f;
        for(int i=0;i<10;i++){
            float q=(i*.071f+t*.48f)%1f;
            oval(k,center+(reverse?1:-1)*(55+q*123),deck+2+i*2.15f,(11+i*4)*(shot==0?.46f:1),1+q*.42f,0xffb3d3bc,(int)((1-q)*90));
        }
        k.save();k.rotate(s(t*1.13)*1.7f,center,deck-16);if(reverse)k.scale(-1,1,center,0);
        image(k,ship,x,y+bob,415*z,221*z,255);k.restore();
        if(shot==3&&current!=null){
            int variant=(current.number-1)%4;
            float shift=motion?lerp(350,0,ease(age/.82f)):0;
            float volley=(age-.29f)%2.7f;
            if(motion&&age>=.29f&&stage<2&&volley<1.55f)volley(k,volley,x+342*z,y+bob+187*z,variant,shift);
            crew(k,variant,x+288*z,y+bob+187*z+4,stage,motion?(now-beat)/1000f:1,t,shift);
        }
        image(k,fog,-drift*.66f,9,1200,390,135);
    }
    private void caption(Canvas k,int w,float band,long now,float dt){
        float dp=getResources().getDisplayMetrics().density;
        float x=16*dp, y=band*.65f, f=Math.min(Math.min(29*dp,w/13f),band*.38f);
        String region=shot==3&&current!=null?"PORT "+current.number+"  /  "+PORTS[(current.number-1)%4]:shot==2?"OPEN WATER":shot==4?"INBOUND":shot==1?"LEAVING HARBOR":"AT ANCHOR";
        String detail=shot==3?RAID[stage]+(cargo.isEmpty()?"":"  ·  "+cargo):waitUntil>now?"Source pause  ·  "+((waitUntil-now+999)/1000)+" s":shot==0?message:"";
        float a=motion?.67f+.33f*ease(dt/.62f):1;
        if(motion&&dt<1.1f){
            float q=clamp(dt/1.1f);
            for(int i=0;i<6;i++)oval(k,x+(18+i*22+q*55)*dp,y-(8+12*q+s(i)*5)*dp,(19+21*q)*dp,(5+7*q)*dp,0xffb6dfd4,(int)(35*s(q*Math.PI)));
        }
        float glide=motion?10*dp*(1-ease(dt/.63f)):0;
        label(k,region,x,y-f-dp,10*dp,0xffe8bd82,Typeface.MONOSPACE,w-x-12*dp);
        label(k,HEAD[shot],x+glide+dp,y+dp,f,0xf906121b,SCENE_FONT,w-x-18*dp);
        label(k,HEAD[shot],x+glide,y,f,((int)(a*255)<<24)|0xeceada,SCENE_FONT,w-x-18*dp);
        label(k,detail,x,y+16*dp,11*dp,0xffafd0be,Typeface.DEFAULT,w-x-12*dp);
    }
    private void label(Canvas k,String value,float x,float y,float sz,int color,Typeface font,float max){
        if(value.isEmpty()||max<=0)return;g.setTypeface(font);g.setTextSize(sz);g.setColor(color);
        if(g.measureText(value)>max)g.setTextSize(sz*max/g.measureText(value));
        k.drawText(value,x,y,g);
    }
    private void damage(Canvas k,int portIndex,int stage,float time){
        if(stage<1)return;
        int count=stage>=6?7:Math.min(6,stage+1);
        for(int i=0;i<count;i++){
            int j=(i*3+portIndex)%7;float x=ROOF_X[portIndex][j],y=ROOF_Y[portIndex][j];
            float q=time*2.3f+i*1.72f;
            if(stage==6&&j!=1){
                rect(k,x-21,y-4,x+21,274,0xff101a1c);
                poly(k,0xff253133,x-21,267,x-16,y+23,x-7,y+40,x-4,y+29,x+3,y+43,x+17,y+33,x+21,268);
                y+=38;x+=4;
            }else y+=14;
            oval(k,x,y+10,23,24,0xffff903c,45);
            poly(k,0xffec975a,x-7,y+13,x-5,y+2,x-2,y-5+3*s(q),x+1,y+4,x+5,y-9+4*c(q),x+9,y+12);
            oval(k,x+2,y+9,3.1f,6,0xffffdba0,174);
            for(int l=0;l<4;l++){
                float u=(l*.25f+time*.23f)%1;
                oval(k,x+u*25-7,y-5-u*79,7+18*u,5+11*u,0xff748783,(int)((1-u)*(71+stage*7)));
                oval(k,x+5*s(q+l)+u*20,y-5-u*37,1.1f,1.1f,0xffffad64,(int)((1-u)*190));
            }
        }
    }
    private void volley(Canvas k,float t,float x,float y,int portIndex,float shift){
        float tx=975+portIndex*28+shift,ty=254-portIndex*6;
        if(t<.38f){float q=1-t/.38f;oval(k,x+7,y,29,15,0xffffb462,(int)(170*q));oval(k,x+10,y,16*q+2,5*q+1,0xffffe4a2,(int)(245*q));}
        for(int i=0;i<9;i++){
            float q=clamp((t-i*.022f)/1.35f);
            if(t<i*.022f||q>=1)continue;
            oval(k,x+9+4*i+q*(26+20*s(i*1.83)),y-q*(18+21*Math.abs(c(i*1.83))),8+26*q,4+12*q,0xff9cab9e,(int)(105*(1-q)));
        }
        if(t<.47f){float q=t/.47f;oval(k,lerp(x+8,tx,q),lerp(y,ty,q)-52*s(q*Math.PI),10,2,0xffffbd75,226);}
        else if(t<1.1f){float q=(t-.47f)/.63f;oval(k,tx,ty-q*26,10+21*q,6+15*q,0xffe9955f,(int)((1-q)*124));}
    }
    private void crew(Canvas k,int variant,float hullX,float hullY,int stage,float age,float time,float shift){
        if(stage<2)return;
        float p=ease(age/.49f),deck=hullY-21,pace=s(time*9);
        for(int i=0;i<3;i++){
            float dock=856+variant*12+24*i+shift, from=hullX+8*i;
            float bx=stage==2?lerp(from,dock,p):stage==3?dock:stage==4?lerp(dock,from,p):from;
            float by=309+10*i+s(time*4+i)*1.4f;if(stage==6)by=lerp(by,deck+4,p);
            oval(k,bx,by+3,20,2,0xffb3d3bc,120);
            poly(k,0xff886748,bx-13,by-4,bx+13,by-4,bx+8,by+2,bx-8,by+2);
            line(k,bx-13,by-4,bx+13,by-4,0xffe8bd82,.8f);
            if(stage==2||stage==4)line(k,bx-5,by-5,bx+3+pace*4,by+5,0xffbba280,1.1f);
            if(stage==2&&p<.85f)person(k,bx,by-2,pace,false);
            if(stage==2||stage==3){float walk=stage==2?p:1-p;person(k,dock+lerp(-7,55,walk),lerp(303,270,walk),pace,stage==3);if(stage==3)crate(k,bx-4,by,6);}
            if(stage>=4){float lift=stage==4?ease((age-.12f)/.42f):1, cx=lerp(bx,from,lift),cy=lerp(by-2,deck-2-i*2,lift);line(k,from,deck-12,cx,cy-6,0xffc0a880,.9f);crate(k,cx,cy,8);}
            if(stage>=5){line(k,from-3,deck-7,from-3,by,0xffc0a880,.9f);person(k,from-3,lerp(by-1,deck+1,stage==5?p:1),pace,false);}
        }
    }
    private void person(Canvas k,float x,float y,float step,boolean carry){
        oval(k,x,y-10,2,2.3f,0xffe3bc80,255);line(k,x-3,y-11.7f,x+3,y-11.7f,0xff101b20,1.4f);
        rect(k,x-2.4f,y-8,x+2.4f,y-2,0xff35575b);
        line(k,x-1.5f,y-3,x-2.5f+step,y,0xff1b2a2b,1.5f);
        line(k,x+1.5f,y-3,x+2.5f-step,y,0xff1b2a2b,1.5f);
        if(carry)crate(k,x-6,y-2,5.5f);
    }
    private void crate(Canvas k,float x,float y,float sz){rect(k,x-sz/2,y-sz,x+sz/2,y,0xff886748);line(k,x-sz/2,y,x+sz/2,y-sz,0xffe8bd82,.85f);}
    private void image(Canvas k,Bitmap b,float x,float y,float w,float h,int a){dest.set(x,y,x+w,y+h);g.setAlpha(a);k.drawBitmap(b,null,dest,g);g.setAlpha(255);}
    private void oval(Canvas k,float x,float y,float rx,float ry,int color,int a){g.setColor(color);g.setAlpha(Math.min(255,Math.max(0,a)));k.drawOval(x-rx,y-ry,x+rx,y+ry,g);}
    private void rect(Canvas k,float a,float b,float c,float d,int color){g.setColor(color);k.drawRect(a,b,c,d,g);}
    private void line(Canvas k,float a,float b,float c,float d,int color,float sw){g.setColor(color);g.setStrokeWidth(sw);k.drawLine(a,b,c,d,g);}
    private void poly(Canvas k,int color,float... xy){path.reset();path.moveTo(xy[0],xy[1]);for(int i=2;i<xy.length;i+=2)path.lineTo(xy[i],xy[i+1]);path.close();g.setColor(color);k.drawPath(path,g);}
}
