using System;
using System.Windows;
using System.Windows.Media;

namespace Pyrate {
    public sealed partial class VoyageCanvas {
        private static readonly SolidColorBrush HullRuin=Solid(0x101a1c), Rubble=Solid(0x253133);
        private static readonly SolidColorBrush Coat=Solid(0x243f44), CrewGold=Solid(0xe3bc80);
        private static readonly SolidColorBrush Crate=Solid(0x886748), SailWhite=Solid(0xcbc9ac);
        private static readonly Pen Rope=new Pen(Solid(0xc0a880),.9), Char=new Pen(Solid(0x101b20),1.5);
        private static readonly Pen GoldEdge=new Pen(Solid(0xe8bd82),.85);
        private static readonly Pen Oar=new Pen(Solid(0xbba280),1.25);
        // Building extents in the four original port sprites.
        private static readonly int[,] RoofX={{826,879,933,991,1051,1116,1166},{825,885,951,1009,1061,1108,1170},
            {825,874,925,974,1020,1081,1154},{822,882,936,989,1046,1123,1182}};
        private static readonly int[,] RoofY={{232,216,177,231,154,211,178},{238,185,131,216,168,197,144},
            {225,147,236,213,229,196,213},{210,218,173,226,171,151,213}};

        private static void Shape(DrawingContext dc, Brush fill, Pen pen, params Point[] points) {
            var geo=new StreamGeometry();
            using (var g=geo.Open()) {
                g.BeginFigure(points[0],true,true);
                for(int i=1;i<points.Length;i++) g.LineTo(points[i],true,false);
            }
            dc.DrawGeometry(fill,pen,geo);
        }
        private static int FireCount(int stage) {
            return stage < 1 ? 0 : stage >= 6 ? 7 : Math.Min(6,stage+1);
        }
        private void DrawPortDamage(DrawingContext dc,int port,double now) {
            int stage=frame.RaidStage;
            if(stage<1) return;
            double blend=motion ? Ease(frame.RaidAge/Math.Max(.2,frame.RaidBeat)*2) : 1;
            double ruin=stage==6 ? blend : 0;
            int fireCount=FireCount(stage), oldCount=FireCount(stage-1);
            for(int i=0;i<fireCount;i++) {
                int index=(i*3+port)%7;
                double x=RoofX[port,index],y=RoofY[port,index];
                double q=motion ? now*2.3+i*1.72 : i*1.72;
                if(ruin>0 && index!=1) {
                    var wreck=new Rect(x-21,y-4,42,Math.Max(5,274-y));
                    dc.PushOpacity(ruin);
                    dc.PushClip(new RectangleGeometry(wreck));
                    dc.DrawRectangle(HullRuin,null,wreck);
                    Shape(dc,Rubble,Char,new Point(x-21,267),new Point(x-16,y+23),new Point(x-7,y+40),
                        new Point(x-4,y+29),new Point(x+3,y+43),new Point(x+17,y+33),new Point(x+21,268));
                    dc.DrawLine(Char,new Point(x-15,265),new Point(x+14,y+37));
                    dc.Pop();
                    dc.Pop();
                    x+=4*ruin;
                    y+=Lerp(14,38,ruin);
                } else y+=14;
                dc.PushOpacity(i < oldCount ? 1 : blend);
                double intensity=.65+.2*Math.Sin(q);
                Overlay(dc,gunGlow,x,y+10,26,27,intensity*.57);
                Shape(dc,spark,null,new Point(x-7,y+13),new Point(x-5,y+2),new Point(x-2,y-5+3*Math.Sin(q)),
                    new Point(x+1,y+4),new Point(x+5,y-9+4*Math.Cos(q)),new Point(x+9,y+12));
                Overlay(dc,flash,x+2,y+9,3.1,6,intensity);
                for(int k=0;k<4;k++) {
                    double rise=(k*.25+(motion ? now*.23 : .18))%1.0;
                    double thickness=.48+(stage-1+blend)*.045;
                    Overlay(dc,exhaust,x+rise*25-7,y-5-rise*79,7+18*rise,5+11*rise,(1-rise)*thickness);
                    if(motion) Overlay(dc,spark,x+5*Math.Sin(q+k)+rise*20,y-5-rise*37,1.1,1.1,(1-rise)*.82);
                }
                dc.Pop();
            }
        }
        private void CrateAt(DrawingContext dc,double x,double y,double size) {
            dc.DrawRectangle(Crate,GoldEdge,new Rect(x-size*.5,y-size,size,size));
            dc.DrawLine(Rope,new Point(x-size*.5,y-size*.12),new Point(x+size*.47,y-size*.89));
        }
        private void CrewAt(DrawingContext dc,double x,double y,double step,bool loaded) {
            dc.DrawEllipse(CrewGold,Char,new Point(x,y-10),2,2.3);
            dc.DrawLine(Char,new Point(x-3,y-11.7),new Point(x+3,y-11.7));
            dc.DrawRoundedRectangle(Coat,GoldEdge,new Rect(x-2.3,y-8,4.6,5.7),1,1);
            dc.DrawLine(Char,new Point(x-1.5,y-3),new Point(x-2.5+step,y));
            dc.DrawLine(Char,new Point(x+1.5,y-3),new Point(x+2.5-step,y));
            if(loaded) CrateAt(dc,x-5,y-3,5.5);
        }
        private void DrawRaidCrew(DrawingContext dc,double hullX,double hullY,int port,double now) {
            int stage=frame.RaidStage;
            if(stage<2) return;
            double progress=motion ? Clamp(frame.RaidAge/Math.Max(.2,frame.RaidBeat)) : 1;
            RaidMotion pose=RaidMotion.Sample(stage,progress);
            double dockX=856+port*12, deck=hullY-21;
            double rowing=motion ? Math.Sin(now*8) : 0;
            double pace=motion ? Math.Sin(now*9)*pose.WalkEffort : 0;
            dc.PushOpacity(pose.BoatPresence);
            for(int i=0;i<3;i++) {
                double quay=dockX+24*i, start=hullX+8*i;
                double boatX=Lerp(start,quay,pose.BoatTravel)-8*i*pose.BoatLift;
                double bob=motion ? Math.Sin(now*4+i)*1.4 : 0;
                double boatY=Lerp(309+10*i+bob,deck+5,pose.BoatLift);
                double crewX=Lerp(Lerp(boatX,quay+55,pose.CrewShore),start-3,pose.CrewAboard);
                double crewY=Lerp(Lerp(boatY-2,270,pose.CrewShore),deck+1,pose.CrewAboard);

                if(pose.BoatLift>0 && pose.BoatLift<1) {
                    dc.PushOpacity(Ease(pose.BoatLift*8)*Ease((1-pose.BoatLift)*8));
                    dc.DrawLine(Rope,new Point(start,deck-7),new Point(boatX,boatY-1));
                    dc.Pop();
                }
                Overlay(dc,foamLight,boatX,boatY+3,20,2,.51*(1-pose.BoatLift));
                Shape(dc,Crate,GoldEdge,new Point(boatX-13,boatY-4),new Point(boatX+13,boatY-4),
                    new Point(boatX+8,boatY+2),new Point(boatX-8,boatY+2));
                if(pose.OarEffort>0) {
                    dc.PushOpacity(pose.OarEffort);
                    dc.DrawLine(Oar,new Point(boatX-5,boatY-5),new Point(boatX+3+rowing*4,boatY+5));
                    dc.Pop();
                }
                if(pose.CrewAboard>0 && pose.CrewAboard<1) {
                    dc.PushOpacity(Ease(pose.CrewAboard*8)*Ease((1-pose.CrewAboard)*8));
                    dc.DrawLine(Rope,new Point(start-3,deck-7),new Point(start-3,boatY));
                    dc.Pop();
                }
                CrewAt(dc,crewX,crewY,pace,false);
                if(pose.CargoPresence>0) {
                    double cx=Lerp(Lerp(crewX-5,boatX-4,pose.CargoStowed),start,pose.CargoLift);
                    double cy=Lerp(Lerp(crewY-3,boatY-2,pose.CargoStowed),deck-2-i*2,pose.CargoLift);
                    dc.PushOpacity(pose.CargoPresence);
                    if(pose.CargoLift>0 && pose.CargoLift<1) {
                        dc.PushOpacity(Ease(pose.CargoLift*8)*Ease((1-pose.CargoLift)*8));
                        dc.DrawLine(Rope,new Point(start,deck-12),new Point(cx,cy-6));
                        dc.Pop();
                    }
                    CrateAt(dc,cx,cy,Lerp(6,8,pose.CargoLift));
                    dc.Pop();
                }
                Overlay(dc,SailWhite,boatX,boatY,4,1,.5*Ease((pose.BoatLift-.8)/.2));
            }
            dc.Pop();
        }
    }
}
