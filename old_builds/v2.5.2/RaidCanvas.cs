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
        private void DrawPortDamage(DrawingContext dc,int port,double now) {
            int stage=frame.RaidStage;
            if(stage<1) return;
            int fireCount=stage>=6 ? 7 : Math.Min(6,stage+1);
            for(int i=0;i<fireCount;i++) {
                int index=(i*3+port)%7;
                double x=RoofX[port,index],y=RoofY[port,index];
                double q=motion ? now*2.3+i*1.72 : i*1.72;
                if(stage==6 && index!=1) {
                    var wreck=new Rect(x-21,y-4,42,Math.Max(5,274-y));
                    dc.PushClip(new RectangleGeometry(wreck));
                    dc.DrawRectangle(HullRuin,null,wreck);
                    Shape(dc,Rubble,Char,new Point(x-21,267),new Point(x-16,y+23),new Point(x-7,y+40),
                        new Point(x-4,y+29),new Point(x+3,y+43),new Point(x+17,y+33),new Point(x+21,268));
                    dc.DrawLine(Char,new Point(x-15,265),new Point(x+14,y+37));
                    dc.Pop();
                    x+=4; y+=38;
                } else y+=14;
                double intensity=.65+.2*Math.Sin(q);
                Overlay(dc,gunGlow,x,y+10,26,27,intensity*.57);
                Shape(dc,spark,null,new Point(x-7,y+13),new Point(x-5,y+2),new Point(x-2,y-5+3*Math.Sin(q)),
                    new Point(x+1,y+4),new Point(x+5,y-9+4*Math.Cos(q)),new Point(x+9,y+12));
                Overlay(dc,flash,x+2,y+9,3.1,6,intensity);
                for(int k=0;k<4;k++) {
                    double rise=(k*.25+(motion ? now*.23 : .18))%1.0;
                    Overlay(dc,exhaust,x+rise*25-7,y-5-rise*79,7+18*rise,5+11*rise,(1-rise)*(.48+stage*.045));
                    if(motion) Overlay(dc,spark,x+5*Math.Sin(q+k)+rise*20,y-5-rise*37,1.1,1.1,(1-rise)*.82);
                }
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
            double age=motion ? frame.RaidAge/Math.Max(.2,frame.RaidBeat) : 1.2;
            double p=Ease(age/.64), dockX=856+port*12;
            double pace=motion ? Math.Sin(now*9) : 0;
            double deck=hullY-21;
            for(int i=0;i<3;i++) {
                double quay=dockX+24*i, boatY=309+10*i, start=hullX+8*i;
                double boatX=stage==2 ? Lerp(start,quay,p) : stage==3 ? quay :
                    stage==4 ? Lerp(quay,start,p) : stage==5 ? start : start-8*i;
                if(stage==6) boatY=Lerp(boatY,deck+5,p);
                double bob=motion ? Math.Sin(now*4+i)*1.4 : 0;
                boatY+=bob;
                if(stage==6) dc.DrawLine(Rope,new Point(start,deck-7),new Point(boatX,boatY-1));
                Overlay(dc,foamLight,boatX,boatY+3,20,2,.51);
                Shape(dc,Crate,GoldEdge,new Point(boatX-13,boatY-4),new Point(boatX+13,boatY-4),
                    new Point(boatX+8,boatY+2),new Point(boatX-8,boatY+2));
                if(stage==2 || stage==4) dc.DrawLine(Oar,new Point(boatX-5,boatY-5),new Point(boatX+3+pace*4,boatY+5));
                if(stage==2 && p<.85) CrewAt(dc,boatX,boatY-2,pace,false);
                if(stage==2 || stage==3) {
                    double track=stage==2 ? p : 1-p;
                    CrewAt(dc,quay+Lerp(-7,55,track),Lerp(303,270,track),pace,stage==3);
                    if(stage==3) CrateAt(dc,boatX-4,boatY-2,6);
                }
                if(stage>=4) {
                    double lift=stage==4 ? Ease((age-.25)/.68) : 1;
                    double cx=Lerp(boatX,start,lift), cy=Lerp(boatY-2,deck-2-i*2,lift);
                    dc.DrawLine(Rope,new Point(start,deck-12),new Point(cx,cy-6));
                    CrateAt(dc,cx,cy,8);
                }
                if(stage>=5) {
                    double aboard=stage==5 ? p : 1;
                    dc.DrawLine(Rope,new Point(start-3,deck-7),new Point(start-3,boatY));
                    CrewAt(dc,start-3,Lerp(boatY-1,deck+1,aboard),pace,false);
                }
                if(stage==6 && p>=.95) Overlay(dc,SailWhite,boatX,boatY,4,1,.5);
            }
        }
    }
}
