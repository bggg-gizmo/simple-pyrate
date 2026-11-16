using System;
using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Pyrate {
    public sealed partial class VoyageCanvas : FrameworkElement {
        private static readonly CultureInfo Culture=CultureInfo.InvariantCulture;
        private readonly BitmapSource sky, lagoon, ship, fog;
        private readonly BitmapSource[] ports = new BitmapSource[4];
        private readonly Typeface titleFace = new Typeface(new FontFamily("Georgia"),FontStyles.Normal,FontWeights.Bold,FontStretches.Normal);
        private readonly Typeface detailFace = new Typeface(new FontFamily("Segoe UI"),FontStyles.Normal,FontWeights.Normal,FontStretches.Normal);
        private readonly Typeface codeFace = new Typeface(new FontFamily("Consolas"),FontStyles.Normal,FontWeights.Bold,FontStretches.Normal);
        private readonly SolidColorBrush seaLight=Solid(0x68a99f), foamLight=Solid(0xb3d3bc), ink=Solid(0x06121b);
        private readonly SolidColorBrush paper=Solid(0xe9ecda), gold=Solid(0xeec38d), mistText=Solid(0xafd0be), green=Solid(0x77c0b1);
        private readonly SolidColorBrush flash=Solid(0xffdba0), spark=Solid(0xffad64);
        private readonly Brush edge, textShade, captionFog, exhaust, gunGlow, seaShade;
        private VoyageFrame frame;
        private double time, labelSince;
        private bool motion=true;
        private string lastLabel="";
        private Shot lastShot=(Shot)(-1);
        private int lastPort;
        private double dpi = 1.0;
        private static readonly string[] PortNames={"EMBER QUAY","BONEWATCH","LANTERN REACH","GHOSTWATER"};

        public VoyageCanvas(string root) {
            sky=Load(root,"sea-and-sky"); lagoon=Load(root,"lagoon"); ship=Load(root,"pyrate-ship"); fog=Load(root,"fog");
            for (int i=0;i<ports.Length;i++) ports[i]=Load(root,"port-"+i);
            edge=Linear(new uint[]{0xeb07161e,0xa5081821,0x250a151d,0x0408151c},new double[]{0,.25,.55,1},new Point(0,.54),new Point(1,.54));
            seaShade=Linear(new uint[]{0x0009151d,0xd507141c},new double[]{0,1},new Point(0,0),new Point(0,1));
            textShade=Radial(new uint[]{0x990d2832,0x4d123039,0x000c232b},new double[]{0,.56,1});
            captionFog=Radial(new uint[]{0x7cb6dfd4,0x38a5cdc2,0x0095b7b0},new double[]{0,.46,1});
            exhaust=Radial(new uint[]{0xd3afbbb2,0x7d859c96,0x007a8a88},new double[]{0,.35,1});
            gunGlow=Radial(new uint[]{0xfffff2b6,0xcae4955f,0x00dc794c},new double[]{0,.27,1});
            IsHitTestVisible=false; Focusable=false; ClipToBounds=true;
        }
        private static BitmapSource Load(string root,string name) {
            var image=new BitmapImage();
            image.BeginInit(); image.CacheOption=BitmapCacheOption.OnLoad;
            image.UriSource=new Uri(Path.Combine(root,name+".png"),UriKind.Absolute);
            image.EndInit(); image.Freeze();
            return image;
        }
        private static Color ColorOf(uint argb) {
            return Color.FromArgb((byte)(argb>>24),(byte)(argb>>16),(byte)(argb>>8),(byte)argb);
        }
        private static SolidColorBrush Solid(uint rgb) {
            var b = new SolidColorBrush(ColorOf(0xff000000|rgb)); b.Freeze(); return b;
        }
        private static Brush Linear(uint[] rgb,double[] points,Point start,Point end) {
            var b=new LinearGradientBrush(); b.StartPoint=start; b.EndPoint=end;
            for (int i=0;i<rgb.Length;i++) b.GradientStops.Add(new GradientStop(ColorOf(rgb[i]),points[i]));
            b.Freeze(); return b;
        }
        private static Brush Radial(uint[] rgb,double[] points) {
            var b=new RadialGradientBrush();
            for (int i=0;i<rgb.Length;i++) b.GradientStops.Add(new GradientStop(ColorOf(rgb[i]),points[i]));
            b.Freeze(); return b;
        }

        public void Present(VoyageFrame next,double now,bool animate) {
            if (next==null) return;
            bool changed = next.Headline!=lastLabel || lastShot!=next.Shot ||
                (next.Shot==Shot.Battle && lastPort!=next.Port);
            bool update = animate || changed || frame==null || motion!=animate || (frame!=null && (frame.Detail!=next.Detail || frame.RaidStage!=next.RaidStage));
            if (changed) { labelSince=now; lastLabel=next.Headline; lastShot=next.Shot; lastPort=next.Port; }
            frame=next; time=animate ? now : 0; motion=animate;
            if (update) InvalidateVisual();
        }
        private static double Clamp(double value) { return Math.Max(0,Math.Min(1,value)); }
        private static double Ease(double value) { value=Clamp(value); return value*value*(3-2*value); }
        private static double Lerp(double a,double b,double t) { return a+(b-a)*t; }
        private static void Image(DrawingContext dc,BitmapSource image,double x,double y,double w,double h,double opacity) {
            if (opacity<=0) return;
            if (opacity<1) dc.PushOpacity(Clamp(opacity));
            dc.DrawImage(image,new Rect(x,y,w,h));
            if (opacity<1) dc.Pop();
        }
        private void Overlay(DrawingContext dc,Brush brush,double x,double y,double rx,double ry,double opacity) {
            if (opacity<=0) return;
            dc.PushOpacity(Clamp(opacity));
            dc.DrawEllipse(brush,null,new Point(x,y),rx,ry);
            dc.Pop();
        }
        protected override void OnRender(DrawingContext dc) {
            base.OnRender(dc);
            double w=ActualWidth, h=ActualHeight;
            if (w<20 || h<20) return;
            dpi=VisualTreeHelper.GetDpi(this).PixelsPerDip;
            var viewport = new Rect(0,0,w,h);
            dc.PushClip(new RectangleGeometry(viewport));
            dc.DrawRectangle(ink,null,viewport);
            if (frame==null) { dc.Pop(); return; }
            // Slight overscan prevents exposed edges on camera moves. At narrow widths keep the art to the right.
            double scale=Math.Max(w/1200,h/390);
            double shift=(w-1200*scale)*.72;
            double top=(h-390*scale)*.52;
            dc.PushTransform(new MatrixTransform(scale,0,0,scale,shift,top));
            DrawWorld(dc);
            dc.Pop();

            dc.DrawRectangle(edge,null,viewport);
            dc.DrawRectangle(seaShade,null,new Rect(0,h*.71,w,h*.29));
            DrawHud(dc,w,h);
            if (motion && (frame.Shot==Shot.OpenSea || frame.Shot==Shot.Battle || frame.Shot==Shot.Return) && frame.Age<.28) {
                double opacity=.6*(1-Ease(frame.Age/.28));
                dc.PushOpacity(opacity); dc.DrawRectangle(ink,null,viewport); dc.Pop();
            }
            dc.Pop();
        }
        private void DrawWorld(DrawingContext dc) {
            double p=motion ? Ease(frame.Progress) : 1;
            double now=motion ? time : 0;
            double sway=motion ? Math.Sin(now*1.44)*2.6 : 0;
            if (motion && frame.Shot==Shot.OpenSea) sway*=1.6;
            double shipX, shipY, zoom;
            double coast=0, threat=0;
            bool reverse=false;
            switch(frame.Shot) {
                case Shot.Departure:
                    coast=1;
                    shipX=Lerp(504,1220,p); shipY=Lerp(123,150,p); zoom=Lerp(.78,.55,p);
                    break;
                case Shot.OpenSea:
                    shipX=510+(motion ? Math.Sin(now*.8)*25 : 0);
                    shipY=136; zoom=.72;
                    break;
                case Shot.Battle:
                    threat=1;
                    shipX=motion ? Lerp(382,516,Ease(frame.Age/.57)) : 516;
                    shipY=159; zoom=.78;
                    break;
                case Shot.Return:
                    coast=1; reverse=true;
                    shipX=Lerp(1210,504,p); shipY=Lerp(152,125,p); zoom=Lerp(.58,.78,p);
                    break;
                default:
                    coast=1;
                    shipX=504; shipY=125; zoom=.78;
                    break;
            }
            Image(dc,sky,0,0,1200,390,1);
            Image(dc,lagoon,0,0,1200,390,coast);
            int variant=(Math.Max(1,frame.Port)-1)%ports.Length;
            Image(dc,ports[variant],0,0,1200,390,threat);
            if (frame.Shot==Shot.Battle) DrawPortDamage(dc,variant,now);
            DrawWater(dc,now,frame.Shot==Shot.OpenSea ? 1.35 : 1);
            double drift=now==0 ? 0 : Math.Sin(now*.39)*47;
            Image(dc,fog,drift,-5,1200,390,.82);
            double deck=shipY+221*zoom;
            double center=shipX+208*zoom;
            double hullY=shipY+sway+187*zoom;
            // Under-ship wake trails away from the bow and grows at open-sea speed.
            double heading=reverse ? 1 : -1;
            double speed=frame.Shot==Shot.Harbor ? .46 : 1;
            for (int i=0;i<10;i++) {
                double phase=(i*.071+now*.48)%1;
                double x=center+heading*(55+phase*123);
                double y=deck+2+i*2.15;
                Overlay(dc,foamLight,x,y,(11+i*4)*speed,1.05+phase*.42,(1-phase)*.38);
            }
            Overlay(dc,textShade,center,deck-4,172*zoom,14,.52);

            double burst=motion && frame.Shot==Shot.Battle && frame.Age>.13 ? (frame.Age-.13)%2.7 : -1;
            double recoil=frame.RaidStage<2 && burst>=0 && burst<.22 ? -(1-burst/.22)*8 : 0;
            double angle=motion ? Math.Sin(now*1.13)*1.7 : 0;
            dc.PushTransform(new RotateTransform(angle,center,deck-16));
            if (reverse) dc.PushTransform(new ScaleTransform(-1,1,center,0));
            Image(dc,ship,shipX+recoil,shipY+sway,415*zoom,221*zoom,1);
            if (reverse) dc.Pop();
            dc.Pop();
            if (frame.Shot==Shot.Battle) {
                if (motion && burst>=0 && frame.RaidStage<2) DrawVolley(dc,burst,shipX+zoom*342,hullY,variant);
                DrawRaidCrew(dc,shipX+zoom*288,hullY+4,variant,now);
            }
            Image(dc,fog,-drift*.66,9,1200,390,.53);
        }

        private void DrawWater(DrawingContext dc,double now,double speed) {
            for (int i=0;i<68;i++) {
                double row=(i*53%133)/133.0;
                double depth=row*row;
                double x=((i*793.31-now*(12+depth*36)*speed)%1300+1300)%1300-50;
                double y=255+depth*133+Math.Sin(now*.7+i)*.8;
                double width=3+depth*(7+i%37);
                bool reflection=Math.Abs(x-841)<19+depth*123;
                double a=(.09+depth*.11)*(reflection ? 1.65 : .96);
                Overlay(dc,reflection ? mistText : seaLight,x,y,width,.45+depth*.74,a);
            }
        }
        private void DrawVolley(DrawingContext dc,double t,double x,double y,int variant) {
            double targetX=975+variant*28, targetY=254-variant*6;
            if (t<.40) {
                double flick=(1-t/.40);
                Overlay(dc,gunGlow,x+7,y,49+26*t,32+16*t,flick*.57);
                Overlay(dc,flash,x+8,y,12*flick+4,3.7*flick+1,flick*.81);
                Overlay(dc,gunGlow,x-53,y+4,25,17,Math.Max(0,1-Math.Abs(t-.12)*8)*.56);
            }
            for(int i=0;i<9;i++) {
                double a=Clamp((t-i*.021)/1.65);
                if(t<i*.021 || a>=1) continue;
                double n=i*1.83;
                double dx=9+i*4+a*(26+20*Math.Sin(n));
                double dy=-a*(18+21*Math.Abs(Math.Cos(n)))+4*Math.Sin(n);
                Overlay(dc,exhaust,x+dx,y+dy,10+29*a,5+13*a,(1-a)*.71);
            }
            for(int i=0;i<11;i++) {
                double flight=Clamp((t-i*.006)/.49);
                if (t<i*.006 || flight>=1) continue;
                double cx=Lerp(x+8,targetX,flight);
                double cy=Lerp(y,targetY,flight)-52*Math.Sin(flight*Math.PI)+(i-4.5)*.6;
                Overlay(dc,spark,cx,cy,(12-i*.78)*(1-flight*.6),1.4,((11-i)/11.0)*.87);
            }
            double impact=t-.47;
            if (impact<0 || impact>1.85) return;
            Overlay(dc,gunGlow,targetX,targetY,27+impact*38,19+impact*22,Math.Max(0,.70-impact*1.7));
            for(int i=0;i<7;i++) {
                double q=Clamp((impact-i*.025)/1.6);
                if(impact<i*.025 || q>=1) continue;
                double a=.86*i+variant;
                Overlay(dc,exhaust,targetX+(13+q*45)*Math.Sin(a),targetY-q*(20+7*i),7+q*25,7+q*18,(1-q)*.65);
            }
        }

        private void Line(DrawingContext dc,Brush brush,double x,double y,double w,double opacity) {
            dc.PushOpacity(opacity); dc.DrawRectangle(brush,null,new Rect(x,y,w,1)); dc.Pop();
        }
        private FormattedText Text(string value,Typeface face,double font,Brush color,double width) {
            var formatted=new FormattedText(value ?? "",Culture,FlowDirection.LeftToRight,face,font,color,dpi);
            formatted.MaxTextWidth=Math.Max(width,1); formatted.MaxLineCount=1; formatted.Trimming=TextTrimming.CharacterEllipsis;
            return formatted;
        }
        private void Label(DrawingContext dc,string value,Typeface face,double font,Brush color,double x,double y,double width) {
            dc.DrawText(Text(value,face,font,color,width),new Point(x,y));
        }
        private void DrawHud(DrawingContext dc,double w,double h) {
            double left=w>=880 ? 42 : 28;
            double width=Math.Min(w-2*left,Math.Max(280,w*.65));
            string sector;
            switch (frame.Shot) {
                case Shot.Departure: sector="01  /  LEAVING HARBOR"; break;
                case Shot.OpenSea: sector="02  /  OPEN WATER"; break;
                case Shot.Battle: sector="03  /  PORT "+frame.Port.ToString("00",Culture)+"  /  "+PortNames[(frame.Port-1)%PortNames.Length]; break;
                case Shot.Return: sector="04  /  INBOUND"; break;
                default: sector="00  /  AT ANCHOR"; break;
            }
            Label(dc,"✦   THE MIDNIGHT CHART ROOM",codeFace,11,gold,left,24,width);
            Line(dc,green,left,46,56,.61);
            double elapsed=motion ? Math.Max(0,time-labelSince) : .65;
            double glide=motion ? 17*(1-Ease(elapsed/.60)) : 0;
            bool keepsTitle=frame.Shot==Shot.Harbor || frame.Shot==Shot.OpenSea;
            double arriving=motion ? Ease(elapsed/.40) : 1;
            double departing=motion && !keepsTitle && frame.Duration>0 && frame.Age>=frame.Duration-.37
                ? Math.Max(.33,1-Ease((frame.Age-(frame.Duration-.37))/.37)) : 1;
            // Long active battles keep a readable title after the first smoke pulse.
            if(frame.Shot==Shot.Battle && frame.Age>=frame.Duration) departing=1;
            double alpha=arriving*departing;
            double y=h*.34;
            double font=w<720 ? 32 : 44;
            if (motion && elapsed<1.24) {
                double v=Clamp(elapsed/1.24);
                for (int i=0;i<7;i++) {
                    double a=(i*.17+v*.91);
                    double x=left+38+i*27+70*v;
                    Overlay(dc,captionFog,x,y+font*.47-13*v+9*Math.Sin(a*3),23+40*v,7+9*v,Math.Sin(v*Math.PI)*(.32-i*.019));
                }
                dc.PushOpacity(Clamp(Math.Sin(v*Math.PI)*.26));
                Label(dc,frame.Headline,titleFace,font,mistText,left+3+glide,y-2-14*v,width);
                dc.Pop();
            }
            dc.PushOpacity(Clamp(alpha));
            Label(dc,frame.Headline,titleFace,font,ink,left+2+glide,y+2,width);
            Label(dc,frame.Headline,titleFace,font,paper,left+glide,y,width);
            dc.Pop();
            Label(dc,frame.Detail,detailFace,13,mistText,left,y+font+12,width);
            if (frame.Shot==Shot.Battle && y+font+44<h-39) {
                string cue=frame.RaidStage==0 ? frame.RaidAction : frame.RaidPercent.ToString(Culture)+"%  /  "+frame.RaidAction;
                Label(dc,cue,codeFace,11,gold,left,y+font+32,width);
            }
            if (frame.WaitRemaining > 0) {
                double seconds = Math.Max(1,Math.Ceiling(frame.WaitRemaining));
                Line(dc,gold,left,y+font+41,Math.Min(width,7+seconds*11),.69);
            }
            string cargo=String.IsNullOrEmpty(frame.Mode) ? "" : "   ·   "+frame.Mode.ToUpperInvariant();
            Label(dc,sector+cargo,codeFace,11,green,left,h-40,w-2*left);
            Line(dc,green,left,h-20,w-2*left,.28);
            string stamp="BGGG   /   25";
            var mark=Text(stamp,codeFace,10,gold,120);
            dc.DrawText(mark,new Point(w-left-mark.Width,h-40));
        }
    }
}
