using System;
using System.Collections.Generic;

namespace Pyrate {
    public enum Shot { Harbor, Departure, OpenSea, Battle, Return }

    public sealed class ShipBellPlan {
        private bool active, batch;

        public bool BeginJob(bool collection, int outputs, bool moreQueued) {
            bool first = !active;
            if (first) { active = true; batch = false; }
            batch = batch || collection || outputs > 1 || moreQueued;
            return first;
        }

        public bool EnterPort(bool moreQueued) {
            if (!active) return false;
            batch = batch || moreQueued;
            return batch;
        }

        public bool Finish(bool moreQueued, string status) {
            if (!active || moreQueued) return false;
            active = false;
            batch = false;
            return !String.Equals(status, "Cancelled", StringComparison.OrdinalIgnoreCase);
        }
    }

    public sealed class VoyageFrame {
        public Shot Shot { get; private set; }
        public double Age { get; private set; }
        public double Duration { get; private set; }
        public double WaitRemaining { get; private set; }
        public int RaidStage { get; private set; }
        public int RaidPercent { get { return VoyageTimeline.MilestonePercent(RaidStage); } }
        public double RaidAge { get; private set; }
        public double RaidSceneAge { get; private set; }
        public double RaidBeat { get; private set; }
        public string RaidAction { get { return VoyageTimeline.MilestoneAction(RaidStage); } }
        public int Port { get; private set; }
        public string Headline { get; private set; }
        public string Detail { get; private set; }
        public string Mode { get; private set; }
        public double Progress { get { return Duration <= 0 ? 0 : Math.Max(0, Math.Min(1, Age / Duration)); } }

        internal VoyageFrame(Shot shot, double age, double duration, int port, string headline, string detail, string mode, double waitRemaining, int raidStage, double raidAge, double raidSceneAge, double raidBeat) {
            Shot=shot; Age=age; Duration=duration; Port=port; Headline=headline; Detail=detail; Mode=mode; WaitRemaining=waitRemaining; RaidStage=raidStage; RaidAge=raidAge; RaidSceneAge=raidSceneAge; RaidBeat=raidBeat;
        }
    }

    public struct RaidMotion {
        public double BoatPresence { get; private set; }
        public double BoatTravel { get; private set; }
        public double BoatLift { get; private set; }
        public double CrewShore { get; private set; }
        public double CrewAboard { get; private set; }
        public double CargoPresence { get; private set; }
        public double CargoStowed { get; private set; }
        public double CargoLift { get; private set; }
        public double OarEffort { get; private set; }
        public double WalkEffort { get; private set; }

        private static double Ease(double x) {
            x=Math.Max(0,Math.Min(1,x));
            return x*x*(3-2*x);
        }
        private static double Span(double t,double from,double until) {
            return Ease((t-from)/(until-from));
        }
        private static double Effort(double t,double from,double until) {
            if (t<=from || t>=until) return 0;
            double p=(t-from)/(until-from);
            return Math.Sin(Math.PI*p);
        }
        // Normalized poses share endpoints so a milestone changes the action, not the actor's location.
        public static RaidMotion Sample(int stage,double t) {
            var state=new RaidMotion();
            if (stage<2) return state;
            state.BoatPresence=stage==2 ? Span(t,0,.18) : 1;
            state.CargoPresence=stage<3 ? 0 : stage==3 ? Span(t,0,.16) : 1;
            switch(stage) {
                case 2:
                    state.BoatTravel=Span(t,0,.62);
                    state.OarEffort=Effort(t,0,.62);
                    state.CrewShore=Span(t,.62,1);
                    state.WalkEffort=Effort(t,.62,1);
                    break;
                case 3:
                    state.BoatTravel=1;
                    state.CrewShore=1-Span(t,0,.86);
                    state.WalkEffort=Effort(t,0,.86);
                    state.CargoStowed=Span(t,.84,1);
                    break;
                case 4:
                    state.BoatTravel=1-Span(t,0,.54);
                    state.OarEffort=Effort(t,0,.54);
                    state.CargoStowed=1;
                    state.CargoLift=Span(t,.54,1);
                    break;
                case 5:
                    state.CargoStowed=1;
                    state.CargoLift=1;
                    state.CrewAboard=Span(t,0,1);
                    break;
                default:
                    state.CargoStowed=1;
                    state.CargoLift=1;
                    state.CrewAboard=1;
                    state.BoatLift=Span(t,0,1);
                    break;
            }
            return state;
        }
    }

    public sealed class VoyageTimeline {
        private sealed class Encounter {
            public int Ordinal;
            public string Mode, Title, Detail;
            public bool Resolved, Started;
            public double WaitUntil, RaidSince, BattleSince, RaidBeat;
            public int TargetStage, VisibleStage;
            public bool Presented;
        }

        private readonly Queue<Encounter> ports = new Queue<Encounter>();
        private Encounter current, reported;
        private Shot shot = Shot.Harbor;
        private double begin, duration;
        private double holdUntil;
        private string waitDetail, result;
        private bool running;
        private bool hasReturned;
        private int serial;
        private int displayPort;
        private string displayMode;
        private string displayDetail;

        public bool Running { get { return running; } }
        public bool ReturnPending { get { return !running && shot != Shot.Harbor; } }
        public bool NeedsClock { get { return running || shot != Shot.Harbor; } }
        public int PortsObserved { get { return serial; } }
        public int Backlog { get { return ports.Count; } }

        private static readonly int[] Milestones={0,30,50,75,80,95,98};
        private static readonly string[] Actions={
            "Cannon fire at the harbor", "Fires spread along the quay", "Dinghies away · Crew ashore",
            "Plunder carried to the dinghies", "Cargo hoisted aboard", "Crew back aboard",
            "Dinghies stowed · Port in ruins"
        };
        public static int MilestonePercent(int stage) { return Milestones[stage]; }
        public static string MilestoneAction(int stage) { return Actions[stage]; }

        public void ReportProgress(double percent) {
            if (reported==null || Double.IsNaN(percent)) return;
            SignalActivity();
            while (reported.TargetStage+1<Milestones.Length && percent>=Milestones[reported.TargetStage+1])
                reported.TargetStage++;
        }

        public void ResolvePort(bool saved) {
            if (saved) ReportProgress(100);
            ResolvePort();
        }

        private double BeatLength() { return ports.Count>=12 ? .58 : ports.Count>=4 ? .72 : .88; }

        private void UpdateRaid(double now, bool motion) {
            if (!motion) {
                current.VisibleStage=current.TargetStage;
                current.RaidSince=now-current.RaidBeat;
                return;
            }
            if (current.VisibleStage<current.TargetStage && now-current.RaidSince>=current.RaidBeat) {
                current.VisibleStage++;
                current.RaidSince=now;
                current.RaidBeat=BeatLength();
            }
        }

        public void Start(double now) {
            if (running) return;
            bool continueAtSea = shot != Shot.Harbor && shot != Shot.Return;
            bool reuseReturn = shot == Shot.Return;
            if (!continueAtSea) {
                ports.Clear();
                serial=0; displayPort=0; current=null; reported=null;
                displayMode=""; displayDetail="";
            }
            running=true; hasReturned=false; result=""; holdUntil=0; waitDetail=null;
            if (!continueAtSea) Cut(reuseReturn ? Shot.OpenSea : Shot.Departure, now, reuseReturn ? 1.0 : 1.65);
        }

        public void EnterPort(string mode, string title, string listPosition) {
            if (!running) return;
            if (reported != null && !reported.Resolved) reported.Resolved=true;
            var next = new Encounter();
            next.Ordinal = ++serial;
            next.Mode = mode == "Captions" ? "Transcript" : mode;
            next.Title = String.IsNullOrWhiteSpace(title) ? "Unnamed cargo" : title.Trim();
            if (reported == null && holdUntil > 0) next.WaitUntil=holdUntil;
            next.Detail = (String.IsNullOrWhiteSpace(listPosition) ? "" : listPosition.Trim() + "  /  ") + next.Title;
            ports.Enqueue(next);
            reported=next;
        }

        public void SignalActivity() {
            holdUntil=0;
            if (reported != null) {
                reported.Started=true;
                reported.WaitUntil=0;
            }
        }

        public void ResolvePort() {
            SignalActivity();
            if (reported != null) {
                reported.Resolved=true;
                reported=null;
            }
        }

        public void BeginWait(double now, double seconds, string detail) {
            if (!running || seconds < 0.15) return;
            double until=now+Math.Min(seconds,3600);
            SetHold(until, detail);
            if (reported != null && !reported.Resolved) reported.WaitUntil=until;
            if (current != null && current == reported && shot == Shot.Battle) Cut(Shot.OpenSea,now,0.35);
        }

        private void SetHold(double until, string detail) {
            holdUntil=until;
            waitDetail=String.IsNullOrWhiteSpace(detail) ? "Waiting on the source" : detail.Trim();
        }

        public void Finish(double now, string status, bool moreQueued) {
            if (!running) return;
            ResolvePort();
            if (moreQueued) return;
            running=false; result=status;
            if (String.Equals(status,"Cancelled",StringComparison.OrdinalIgnoreCase)) {
                ports.Clear(); current=null; reported=null;
                Cut(Shot.Return, now, 1.9);
            }
        }

        private void Cut(Shot next, double now, double length) {
            shot=next; begin=now; duration=length;
        }

        private double Crossing(bool motion) {
            if (!motion) return 0;
            return ports.Count >= 12 ? .28 : ports.Count >= 4 ? .46 : .78;
        }

        private double BattleLength(bool motion) {
            if (!motion) return 0;
            return ports.Count >= 12 ? .86 : ports.Count >= 4 ? 1.06 : 1.46;
        }

        private bool Transition(double now, bool motion) {
            double age=now-begin;
            switch (shot) {
                case Shot.Harbor:
                    return false;
                case Shot.Departure:
                    if (motion && age < duration) return false;
                    Cut(Shot.OpenSea,now,motion ? .6 : 0);
                    return true;
                case Shot.OpenSea:
                    if (motion && age < duration) return false;
                    if (current == null && ports.Count > 0) current=ports.Dequeue();
                    if (current != null) {
                        if (!current.Resolved && (now < current.WaitUntil || !current.Started)) return false;
                        displayPort=current.Ordinal; displayMode=current.Mode; displayDetail=current.Detail;
                        if (!current.Presented) {
                            current.Presented=true; current.RaidSince=now; current.BattleSince=now;
                            current.RaidBeat=BeatLength();
                        }
                        Cut(Shot.Battle,now,BattleLength(motion));
                        return true;
                    }
                    if (!running) { Cut(Shot.Return,now,motion ? 2.65 : 0); return true; }
                    return false;
                case Shot.Battle:
                    if (current == null) { Cut(Shot.OpenSea,now,Crossing(motion)); return true; }
                    UpdateRaid(now,motion);
                    double finalHold=Math.Max(.83,current.RaidBeat);
                    if ((!current.Resolved && now < current.WaitUntil) ||
                        (current.Resolved && (!motion || (age >= duration && current.VisibleStage==current.TargetStage &&
                          (current.TargetStage==0 || now-current.RaidSince>=finalHold))))) {
                        if (current.Resolved) current=null;
                        Cut(Shot.OpenSea,now,(ports.Count > 0 || running || current != null) ? Crossing(motion) : 0);
                        return true;
                    }
                    return false;
                case Shot.Return:
                    if (motion && age < duration) return false;
                    hasReturned=true;
                    Cut(Shot.Harbor,now,0);
                    return true;
            }
            return false;
        }

        public VoyageFrame Tick(double now, bool motion) {
            // A static deck never makes a download wait for the visual timeline.
            for (int i=0; i<2048 && Transition(now,motion); i++) { }
            double age=Math.Max(0,now-begin);
            string headline, detail, mode=displayMode ?? "";
            int port=displayPort;
            double waiting=0;
            switch (shot) {
                case Shot.Departure:
                    headline="Setting sail";
                    detail="Leaving harbor";
                    break;
                case Shot.OpenSea:
                    var target=current ?? (ports.Count > 0 ? ports.Peek() : null);
                    if (!running) waiting=0;
                    else if (target != null && !target.Resolved && target.WaitUntil > now) waiting=target.WaitUntil-now;
                    else if (target == null && holdUntil > now) waiting=holdUntil-now;
                    headline=waiting > 0 ? "Riding out the wait" :
                        displayPort > 0 || (target != null && target.Ordinal > 1) ? "On to the next port" : "Starting our voyage";
                    if (waiting > 0) detail=(waitDetail ?? "Waiting on the source") + "  /  " + Math.Ceiling(waiting) + "s";
                    else if (target != null) detail=target.Detail;
                    else detail=running ? "Open water • Charting the next bearing" : "Leaving the last port";
                    if (target != null) { port=target.Ordinal; mode=target.Mode; }
                    break;
                case Shot.Battle:
                    headline="Plundering in progress";
                    detail=displayDetail ?? "";
                    break;
                case Shot.Return:
                    headline=result == "Cancelled" ? "Turning for harbor" : "Making for harbor";
                    detail=result == "Complete" ? "Last haul secured" : result == "Partial" ? "Returning with the cargo recovered" :
                        result == "Cancelled" ? "Finished cargo is safe" : "The voyage has ended";
                    break;
                default:
                    headline=hasReturned ? "Back at anchor" : "Ready to download";
                    detail=hasReturned ? "The crew is home" : "Paste a link to start a download";
                    port=0; mode="";
                    break;
            }
            bool inRaid=shot==Shot.Battle && current!=null;
            return new VoyageFrame(shot,age,duration,port,headline,detail,mode,waiting,
                inRaid ? current.VisibleStage : 0, inRaid ? Math.Max(0,now-current.RaidSince) : 0,
                inRaid ? Math.Max(0,now-current.BattleSince) : 0, inRaid ? current.RaidBeat : BeatLength());
        }
    }
}
