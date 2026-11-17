using System;
using System.IO;
using System.Collections.Generic;
using System.Threading;
using System.Runtime.InteropServices;

namespace Pyrate {
    // Plays the shipped PCM recordings on the Windows default output device.
    public sealed class PcmVoice : IDisposable {
        [StructLayout(LayoutKind.Sequential, Pack=2)]
        private struct Format {
            public ushort Tag, Channels;
            public uint SamplesPerSecond, BytesPerSecond;
            public ushort BlockAlign, BitsPerSample, ExtraSize;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct Header {
            public IntPtr Data;
            public uint Length, Recorded;
            public UIntPtr User;
            public uint Flags, Loops;
            public IntPtr Next;
            public UIntPtr Reserved;
        }

        [DllImport("winmm.dll")]
        private static extern uint waveOutOpen(out IntPtr handle, uint id, ref Format format, IntPtr callback, UIntPtr instance, uint flags);
        [DllImport("winmm.dll")]
        private static extern uint waveOutPrepareHeader(IntPtr handle, IntPtr header, uint size);
        [DllImport("winmm.dll")]
        private static extern uint waveOutWrite(IntPtr handle, IntPtr header, uint size);
        [DllImport("winmm.dll")]
        private static extern uint waveOutUnprepareHeader(IntPtr handle, IntPtr header, uint size);
        [DllImport("winmm.dll")]
        private static extern uint waveOutReset(IntPtr handle);
        [DllImport("winmm.dll")]
        private static extern uint waveOutClose(IntPtr handle);

        private const uint Done=1, CallbackEvent=0x50000;
        private const int MixRate=44100, Frames=882, StereoSamples=Frames*2;
        private static readonly uint HeaderSize=(uint)Marshal.SizeOf(typeof(Header));
        private static readonly int FlagsOffset=Marshal.OffsetOf(typeof(Header),"Flags").ToInt32();
        private static readonly object Gate=new object();
        private static readonly ManualResetEvent Changed=new ManualResetEvent(false);
        private static readonly List<PcmVoice> Voices=new List<PcmVoice>();
        private static Thread worker;
        private readonly short[] samples;
        private readonly int channels, count;
        private readonly bool loop;
        private readonly double stride;
        private double gain, position;
        private bool submitted;
        private volatile bool ended;
        private volatile string failure;

        private static byte[] ReadClip(string path, out Format format, out int start, out int length) {
            byte[] bytes=File.ReadAllBytes(path);
            format=new Format();
            start=length=0;
            if (bytes.Length<12 || BitConverter.ToUInt32(bytes,0)!=0x46464952 || BitConverter.ToUInt32(bytes,8)!=0x45564157)
                throw new InvalidDataException("Not a RIFF/WAVE recording: " + Path.GetFileName(path));
            long limit=8L+BitConverter.ToUInt32(bytes,4);
            if (limit>bytes.Length) throw new InvalidDataException("Truncated WAVE recording: " + Path.GetFileName(path));
            for (int offset=12; (long)offset+8<=limit;) {
                uint tag=BitConverter.ToUInt32(bytes,offset), size=BitConverter.ToUInt32(bytes,offset+4);
                int first=offset+8;
                long end=(long)first+size;
                if (end>limit) throw new InvalidDataException("Truncated WAVE chunk: " + Path.GetFileName(path));
                if (tag==0x20746d66 && size>=16) {
                    format.Tag=BitConverter.ToUInt16(bytes,first);
                    format.Channels=BitConverter.ToUInt16(bytes,first+2);
                    format.SamplesPerSecond=BitConverter.ToUInt32(bytes,first+4);
                    format.BytesPerSecond=BitConverter.ToUInt32(bytes,first+8);
                    format.BlockAlign=BitConverter.ToUInt16(bytes,first+12);
                    format.BitsPerSample=BitConverter.ToUInt16(bytes,first+14);
                }
                if (tag==0x61746164 && length==0) { start=first; length=(int)size; }
                long next=end+(size&1u);
                if (next>=limit) break;
                offset=(int)next;
            }
            if (format.Tag!=1 || format.Channels<1 || format.Channels>2 || format.BitsPerSample!=16 ||
                format.SamplesPerSecond<8000 || format.SamplesPerSecond>192000 || format.BlockAlign!=format.Channels*2 ||
                format.BytesPerSecond!=format.SamplesPerSecond*format.BlockAlign || length<=0 || length%format.BlockAlign!=0)
                throw new InvalidDataException("Expected a 16-bit mono or stereo PCM recording: " + Path.GetFileName(path));
            return bytes;
        }

        public static double CheckRecording(string path) {
            Format format;
            int start,length;
            ReadClip(path,out format,out start,out length);
            return length/(double)format.BytesPerSecond;
        }

        private static void Check(uint result,string operation) {
            if (result!=0) throw new InvalidOperationException("Windows audio " + operation + " failed (MMRESULT " + result + ").");
        }

        private sealed class Buffer {
            internal IntPtr HeaderPtr, DataPtr;
            internal bool Prepared, Queued;
            internal readonly List<PcmVoice> Finished=new List<PcmVoice>();

            internal void Prepare(IntPtr device) {
                DataPtr=Marshal.AllocHGlobal(StereoSamples*2);
                HeaderPtr=Marshal.AllocHGlobal((int)HeaderSize);
                var block=new Header();
                block.Data=DataPtr;
                block.Length=StereoSamples*2;
                Marshal.StructureToPtr(block,HeaderPtr,false);
                Check(waveOutPrepareHeader(device,HeaderPtr,HeaderSize),"buffer preparation");
                Prepared=true;
            }

            internal bool Ready {
                get { return !Queued || (((uint)Marshal.ReadInt32(HeaderPtr,FlagsOffset))&Done)!=0; }
            }

            internal void Release(IntPtr device,bool reset) {
                // A driver owns submitted pointers until reset and unprepare both succeed.
                if (Prepared && (Queued && !reset || waveOutUnprepareHeader(device,HeaderPtr,HeaderSize)!=0)) return;
                if (HeaderPtr!=IntPtr.Zero) Marshal.FreeHGlobal(HeaderPtr);
                if (DataPtr!=IntPtr.Zero) Marshal.FreeHGlobal(DataPtr);
            }
        }

        public PcmVoice(string path,double volume,bool loop) {
            Format format;
            int start,length;
            byte[] bytes=ReadClip(path,out format,out start,out length);
            Recording=Path.GetFileName(path);
            channels=format.Channels;
            count=length/format.BlockAlign;
            stride=format.SamplesPerSecond/(double)MixRate;
            samples=new short[length/2];
            System.Buffer.BlockCopy(bytes,start,samples,0,length);
            this.loop=loop;
            gain=Limit(volume);
            lock (Gate) {
                Voices.Add(this);
                StartWorker();
            }
            Changed.Set();
        }

        private static double Limit(double value) { return Math.Max(0,Math.Min(1,value)); }

        public double Volume {
            set { lock (Gate) { gain=Limit(value); } }
        }

        public string Recording { get; private set; }
        public bool Ended { get { return ended; } }
        public string Failure { get { return failure; } }

        public void Dispose() {
            lock (Gate) {
                ended=true;
                Voices.Remove(this);
            }
            Changed.Set();
        }

        private static void StartWorker() {
            if (worker!=null || Voices.Count==0) return;
            worker=new Thread(Play);
            worker.IsBackground=true;
            worker.Name="Simple Pyrate PCM mixer";
            worker.Start();
        }

        private static short Sample(double v) {
            if (v>=32767) return 32767;
            if (v<=-32768) return -32768;
            return (short)Math.Round(v);
        }

        private void AddSamples(double[] mix,Buffer buffer) {
            for (int i=0;i<Frames;i++) {
                int index=(int)position;
                int next=index+1<count ? index+1 : (loop ? 0 : index);
                double part=position-index;
                int a=index*channels, b=next*channels, right=channels-1;
                mix[i*2]+=(samples[a]+(samples[b]-samples[a])*part)*gain;
                mix[i*2+1]+=(samples[a+right]+(samples[b+right]-samples[a+right])*part)*gain;
                position+=stride;
                if (position<count) continue;
                if (loop) position%=count;
                else {
                    submitted=true;
                    buffer.Finished.Add(this);
                    break;
                }
            }
        }

        private static void Play() {
            IntPtr device=IntPtr.Zero;
            var buffers=new[] { new Buffer(),new Buffer(),new Buffer() };
            var sum=new double[StereoSamples];
            var pcm=new short[StereoSamples];
            try {
                var format=new Format { Tag=1,Channels=2,SamplesPerSecond=MixRate,BytesPerSecond=MixRate*4,BlockAlign=4,BitsPerSample=16 };
                Check(waveOutOpen(out device,UInt32.MaxValue,ref format,Changed.SafeWaitHandle.DangerousGetHandle(),UIntPtr.Zero,CallbackEvent),"device open");
                foreach (Buffer buffer in buffers) buffer.Prepare(device);
                while (true) {
                    Changed.Reset();
                    bool pending=false;
                    foreach (Buffer buffer in buffers) {
                        if (!buffer.Ready) { pending=true; continue; }
                        buffer.Queued=false;
                        bool mixed=false;
                        lock (Gate) {
                            foreach (PcmVoice completed in buffer.Finished) {
                                completed.ended=true;
                                Voices.Remove(completed);
                            }
                            buffer.Finished.Clear();
                            Array.Clear(sum,0,sum.Length);
                            foreach (PcmVoice voice in Voices) {
                                if (voice.submitted) continue;
                                voice.AddSamples(sum,buffer);
                                mixed=true;
                            }
                        }
                        if (!mixed) continue;
                        for (int i=0;i<pcm.Length;i++) pcm[i]=Sample(sum[i]);
                        Marshal.Copy(pcm,0,buffer.DataPtr,pcm.Length);
                        Check(waveOutWrite(device,buffer.HeaderPtr,HeaderSize),"playback");
                        buffer.Queued=true;
                        pending=true;
                    }
                    if (!pending) {
                        lock (Gate) { if (Voices.Count==0) break; }
                    } else Changed.WaitOne(20);
                }
            } catch (Exception ex) {
                lock (Gate) {
                    foreach (PcmVoice voice in Voices) { voice.failure=ex.Message; voice.ended=true; }
                    Voices.Clear();
                }
            } finally {
                bool reset=device==IntPtr.Zero || waveOutReset(device)==0;
                foreach (Buffer buffer in buffers) buffer.Release(device,reset);
                if (device!=IntPtr.Zero) waveOutClose(device);
                lock (Gate) {
                    worker=null;
                    StartWorker();
                }
            }
        }
    }
}
