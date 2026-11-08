using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

namespace RxGeneratorDesktop
{
    public class RxGeneratorAppForm : Form
    {
        private WebBrowser _webBrowser;
        private Process _beamProcess;
        private IntPtr _jobHandle = IntPtr.Zero;
        private int _allocatedPort = 0;
        private bool _isShuttingDown = false;

        public RxGeneratorAppForm(int port, Process beamProcess, IntPtr jobHandle)
        {
            _allocatedPort = port;
            _beamProcess = beamProcess;
            _jobHandle = jobHandle;

            this.Text = "RxGenerator - Edge Clinical Prescription Engine";
            this.Width = 1280;
            this.Height = 840;
            this.StartPosition = FormStartPosition.CenterScreen;

            // Initialize browser control
            _webBrowser = new WebBrowser();
            _webBrowser.Dock = DockStyle.Fill;
            _webBrowser.IsWebBrowserContextMenuEnabled = false;
            _webBrowser.WebBrowserShortcutsEnabled = true;
            _webBrowser.ScriptErrorsSuppressed = true;
            this.Controls.Add(_webBrowser);

            this.FormClosing += RxGeneratorAppForm_FormClosing;
            this.Load += RxGeneratorAppForm_Load;
        }

        private void RxGeneratorAppForm_Load(object sender, EventArgs e)
        {
            string url = string.Format("http://127.0.0.1:{0}/", _allocatedPort);
            _webBrowser.Navigate(url);
        }

        private void RxGeneratorAppForm_FormClosing(object sender, FormClosingEventArgs e)
        {
            if (_isShuttingDown) return;
            _isShuttingDown = true;

            try
            {
                if (_beamProcess != null && !_beamProcess.HasExited)
                {
                    _beamProcess.Kill();
                }
            }
            catch { }

            if (_jobHandle != IntPtr.Zero)
            {
                CloseHandle(_jobHandle);
            }
        }

        #region Native Job Object API
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        public static extern IntPtr CreateJobObject(IntPtr lpJobAttributes, string lpName);

        [DllImport("kernel32.dll")]
        public static extern bool SetInformationJobObject(IntPtr hJob, int JobObjectInfoClass, IntPtr lpJobObjectInfo, uint cbJobObjectInfoLength);

        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool CloseHandle(IntPtr hObject);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        private const int JobObjectExtendedLimitInformation = 9;
        private const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000;

        [StructLayout(LayoutKind.Sequential)]
        public struct JOBOBJECT_BASIC_LIMIT_INFORMATION
        {
            public Int64 PerProcessUserTimeLimit;
            public Int64 PerJobUserTimeLimit;
            public UInt32 LimitFlags;
            public UIntPtr MinimumWorkingSetSize;
            public UIntPtr MaximumWorkingSetSize;
            public UInt32 ActiveProcessLimit;
            public UIntPtr Affinity;
            public UInt32 PriorityClass;
            public UInt32 SchedulingClass;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct IO_COUNTERS
        {
            public UInt64 ReadOperationCount;
            public UInt64 WriteOperationCount;
            public UInt64 OtherOperationCount;
            public UInt64 ReadTransferCount;
            public UInt64 WriteTransferCount;
            public UInt64 OtherTransferCount;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
        {
            public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
            public IO_COUNTERS IoInfo;
            public UIntPtr ProcessMemoryLimit;
            public UIntPtr JobMemoryLimit;
            public UIntPtr PeakProcessMemoryLimit;
            public UIntPtr PeakJobMemoryLimit;
        }
        #endregion

        public static IntPtr ConfigureKillOnCloseJob()
        {
            IntPtr job = CreateJobObject(IntPtr.Zero, null);
            if (job == IntPtr.Zero) return IntPtr.Zero;

            JOBOBJECT_EXTENDED_LIMIT_INFORMATION info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
            info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;

            int length = Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION));
            IntPtr extendedInfoPtr = Marshal.AllocHGlobal(length);
            try
            {
                Marshal.StructureToPtr(info, extendedInfoPtr, false);
                SetInformationJobObject(job, JobObjectExtendedLimitInformation, extendedInfoPtr, (uint)length);
            }
            finally
            {
                Marshal.FreeHGlobal(extendedInfoPtr);
            }

            return job;
        }

        [STAThread]
        public static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            // Single instance enforcement
            bool createdNew;
            using (Mutex mutex = new Mutex(true, @"Global\RxGenerator_SingleInstance_App_Mutex", out createdNew))
            {
                if (!createdNew)
                {
                    Process current = Process.GetCurrentProcess();
                    foreach (Process process in Process.GetProcessesByName(current.ProcessName))
                    {
                        if (process.Id != current.Id)
                        {
                            SetForegroundWindow(process.MainWindowHandle);
                            break;
                        }
                    }
                    return;
                }

                IntPtr jobHandle = ConfigureKillOnCloseJob();

                // Locate release executable
                string appDir = AppDomain.CurrentDomain.BaseDirectory;
                string relBat = Path.Combine(appDir, "rx_generator.bat");

                if (!File.Exists(relBat))
                {
                    // Fallback to parent directory search or dev path
                    string candidate = Path.Combine(appDir, @"..\rx_generator.bat");
                    if (File.Exists(candidate)) relBat = Path.GetFullPath(candidate);
                }

                int boundPort = 0;
                Process beamProcess = null;

                if (File.Exists(relBat))
                {
                    ProcessStartInfo psi = new ProcessStartInfo();
                    psi.FileName = "cmd.exe";
                    psi.Arguments = string.Format("/c \"\"{0}\" start\"", relBat);
                    psi.UseShellExecute = false;
                    psi.RedirectStandardOutput = true;
                    psi.RedirectStandardError = true;
                    psi.CreateNoWindow = true;

                    beamProcess = new Process();
                    beamProcess.StartInfo = psi;

                    ManualResetEvent portFoundEvent = new ManualResetEvent(false);

                    beamProcess.OutputDataReceived += (s, e) =>
                    {
                        if (e.Data != null)
                        {
                            Match m = Regex.Match(e.Data, @"\[RX_PORT:(\d+)\]");
                            if (m.Success)
                            {
                                boundPort = int.Parse(m.Groups[1].Value);
                                portFoundEvent.Set();
                            }
                        }
                    };

                    beamProcess.Start();
                    if (jobHandle != IntPtr.Zero)
                    {
                        AssignProcessToJobObject(jobHandle, beamProcess.Handle);
                    }

                    beamProcess.BeginOutputReadLine();
                    beamProcess.BeginErrorReadLine();

                    // Wait up to 10 seconds for dynamic port signal
                    portFoundEvent.WaitOne(10000);
                }

                if (boundPort == 0)
                {
                    boundPort = 4000; // default fallback port
                }

                Application.Run(new RxGeneratorAppForm(boundPort, beamProcess, jobHandle));
            }
        }
    }
}

