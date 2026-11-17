using System;
using System.IO;
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
        private static extern uint waveOutOpen(out IntPtr handle, uint id, ref Format format, UIntPtr callback, UIntPtr instance, uint flags);
        [DllImport("winmm.dll")]
        private static extern uint waveOutPrepareHeader(IntPtr handle, IntPtr header, uint size);
        [DllImport("winmm.dll")]
        private static extern uint waveOutWrite(IntPtr handle, IntPtr header, uint size);
        [DllImport("winmm.dll")]
        private static extern uint waveOutUnprepareHeader(IntPtr handle, IntPtr header, uint size);
        [DllImport("winmm.dll")]
        private static extern uint waveOutReset(IntPtr handle);
        [DllImport("winmm.dll")]
        private static extern uint waveOutSetVolume(IntPtr handle, uint packed);
        [DllImport("winmm.dll")]
        private static extern uint waveOutClose(IntPtr handle);

        private const uint Done=1, BeginLoop=4, EndLoop=8;
        private static readonly uint HeaderSize=(uint)Marshal.SizeOf(typeof(Header));
        private static readonly int FlagsOffset=Marshal.OffsetOf(typeof(Header),"Flags").ToInt32();
        private IntPtr handle, header, data;
        private bool prepared, deviceVolume;

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

        private static uint PackVolume(double level) {
            uint v=(uint)Math.Round(Math.Max(0,Math.Min(1,level))*65535);
            return v|(v<<16);
        }

        private static void Check(uint result,string operation) {
            if (result!=0) throw new InvalidOperationException("Windows audio " + operation + " failed (MMRESULT " + result + ").");
        }

        public PcmVoice(string path,double volume,bool loop) {
            Format format;
            int start,length;
            byte[] bytes=ReadClip(path,out format,out start,out length);
            try {
                Check(waveOutOpen(out handle,UInt32.MaxValue,ref format,UIntPtr.Zero,UIntPtr.Zero,0),"device open");
                deviceVolume=waveOutSetVolume(handle,PackVolume(volume))==0;
                if (!deviceVolume) {
                    double gain=Math.Max(0,Math.Min(1,volume));
                    for (int i=start;i<start+length;i+=2) {
                        int sample=(int)Math.Round(BitConverter.ToInt16(bytes,i)*gain);
                        bytes[i]=(byte)(sample&255);
                        bytes[i+1]=(byte)((sample>>8)&255);
                    }
                }
                data=Marshal.AllocHGlobal(length);
                Marshal.Copy(bytes,start,data,length);
                header=Marshal.AllocHGlobal((int)HeaderSize);
                var block=new Header();
                block.Data=data;
                block.Length=(uint)length;
                if (loop) block.Loops=UInt32.MaxValue;
                Marshal.StructureToPtr(block,header,false);
                Check(waveOutPrepareHeader(handle,header,HeaderSize),"buffer preparation");
                prepared=true;
                if (loop) Marshal.WriteInt32(header,FlagsOffset,Marshal.ReadInt32(header,FlagsOffset)|(int)(BeginLoop|EndLoop));
                Check(waveOutWrite(handle,header,HeaderSize),"playback");
            } catch {
                Dispose();
                throw;
            }
        }

        public double Volume {
            set { if (handle!=IntPtr.Zero && deviceVolume) waveOutSetVolume(handle,PackVolume(value)); }
        }

        public bool Ended {
            get { return !prepared || (((uint)Marshal.ReadInt32(header,FlagsOffset))&Done)!=0; }
        }

        public void Dispose() {
            if (prepared) {
                if (!Ended) Check(waveOutReset(handle),"buffer reset");
                Check(waveOutUnprepareHeader(handle,header,HeaderSize),"buffer release");
                prepared=false;
            }
            if (handle!=IntPtr.Zero) {
                Check(waveOutClose(handle),"device close");
                handle=IntPtr.Zero;
            }
            if (header!=IntPtr.Zero) { Marshal.FreeHGlobal(header); header=IntPtr.Zero; }
            if (data!=IntPtr.Zero) { Marshal.FreeHGlobal(data); data=IntPtr.Zero; }
        }
    }
}
