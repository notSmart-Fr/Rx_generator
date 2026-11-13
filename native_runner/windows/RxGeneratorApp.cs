using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace RxGeneratorDesktop
{
    [ComVisible(true)]
    public class RxGeneratorAppForm : Form
    {
        private WebBrowser _webBrowser;
        private Process _beamProcess;
        private IntPtr _jobHandle = IntPtr.Zero;
        private int _allocatedPort = 0;
        private bool _isShuttingDown = false;
        private List<string> _recentLogs;

        public RxGeneratorAppForm(int port, Process beamProcess, IntPtr jobHandle, List<string> recentLogs)
        {
            _allocatedPort = port;
            _beamProcess = beamProcess;
            _jobHandle = jobHandle;
            _recentLogs = recentLogs ?? new List<string>();

            this.Text = "RxGenerator - Edge Clinical Prescription Engine";
            this.Width = 1280;
            this.Height = 840;
            this.StartPosition = FormStartPosition.CenterScreen;

            ConfigureNativePrintSettings();

            // Initialize browser control
            _webBrowser = new WebBrowser();
            _webBrowser.Dock = DockStyle.Fill;
            _webBrowser.IsWebBrowserContextMenuEnabled = false;
            _webBrowser.WebBrowserShortcutsEnabled = true;
            _webBrowser.ScriptErrorsSuppressed = true;
            _webBrowser.ObjectForScripting = this;
            this.Controls.Add(_webBrowser);

            if (_beamProcess != null)
            {
                _beamProcess.EnableRaisingEvents = true;
                _beamProcess.Exited += BeamProcess_Exited;
            }

            this.FormClosing += RxGeneratorAppForm_FormClosing;
            this.Load += RxGeneratorAppForm_Load;
        }

        private void RxGeneratorAppForm_Load(object sender, EventArgs e)
        {
            string url = string.Format("http://127.0.0.1:{0}/", _allocatedPort);
            _webBrowser.Navigate(url);
        }

        private void BeamProcess_Exited(object sender, EventArgs e)
        {
            if (_isShuttingDown) return;

            if (this.IsHandleCreated && !this.IsDisposed)
            {
                this.BeginInvoke(new Action(HandleUnexpectedBeamExit));
            }
        }

        private void HandleUnexpectedBeamExit()
        {
            if (_isShuttingDown) return;
            _isShuttingDown = true;

            string msg = FormatDiagnosticMessage(
                "The RxGenerator background runtime exited unexpectedly.",
                _recentLogs
            );
            MessageBox.Show(msg, "RxGenerator - Runtime Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            this.Close();
        }

        public static void RecordOutputLine(List<string> buffer, string line)
        {
            if (buffer == null || line == null) return;

            lock (buffer)
            {
                if (buffer.Count >= 20)
                {
                    buffer.RemoveAt(0);
                }
                buffer.Add(line);
            }
        }

        public static string FormatDiagnosticMessage(string header, IEnumerable<string> lines)
        {
            StringBuilder sb = new StringBuilder();
            sb.AppendLine(header);
            sb.AppendLine();
            sb.AppendLine("Recent runtime output:");

            bool hasLines = false;
            if (lines != null)
            {
                lock (lines)
                {
                    foreach (string line in lines)
                    {
                        hasLines = true;
                        sb.AppendLine(line);
                    }
                }
            }

            if (!hasLines)
            {
                sb.AppendLine("(no output captured)");
            }

            return sb.ToString();
        }

        public static void ConfigureNativePrintSettings()
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Internet Explorer\PageSetup"))
                {
                    if (key != null)
                    {
                        key.SetValue("header", "");
                        key.SetValue("footer", "");
                        key.SetValue("margin_top", "0.39375");
                        key.SetValue("margin_bottom", "0.39375");
                        key.SetValue("margin_left", "0.39375");
                        key.SetValue("margin_right", "0.39375");
                    }
                }
            }
            catch { }
        }

        public void ShowPrintUI()
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action(ShowPrintUI));
                return;
            }

            try
            {
                PropertyInfo coreWebView2Prop = _webBrowser.GetType().GetProperty("CoreWebView2");
                if (coreWebView2Prop != null)
                {
                    object coreWebView2 = coreWebView2Prop.GetValue(_webBrowser, null);
                    if (coreWebView2 != null)
                    {
                        MethodInfo showPrintMethod = coreWebView2.GetType().GetMethod("ShowPrintUI", Type.EmptyTypes);
                        if (showPrintMethod != null)
                        {
                            showPrintMethod.Invoke(coreWebView2, null);
                            return;
                        }
                    }
                }
            }
            catch { }

            _webBrowser.ShowPrintDialog();
        }

        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            if (keyData == (Keys.Control | Keys.P))
            {
                ShowPrintUI();
                return true;
            }

            return base.ProcessCmdKey(ref msg, keyData);
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
                List<string> recentLogs = new List<string>();

                if (!File.Exists(relBat))
                {
                    MessageBox.Show(
                        "RxGenerator release executable (rx_generator.bat) could not be located.",
                        "RxGenerator - Startup Error",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error
                    );
                    if (jobHandle != IntPtr.Zero) CloseHandle(jobHandle);
                    return;
                }

                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "cmd.exe";
                psi.Arguments = string.Format("/c \"\"{0}\" start\"", relBat);
                psi.UseShellExecute = false;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                psi.CreateNoWindow = true;

                beamProcess = new Process();
                beamProcess.StartInfo = psi;
                beamProcess.EnableRaisingEvents = true;

                ManualResetEvent portFoundEvent = new ManualResetEvent(false);

                beamProcess.OutputDataReceived += (s, e) =>
                {
                    if (e.Data != null)
                    {
                        RecordOutputLine(recentLogs, e.Data);
                        Match m = Regex.Match(e.Data, @"\[RX_PORT:(\d+)\]");
                        if (m.Success)
                        {
                            boundPort = int.Parse(m.Groups[1].Value);
                            portFoundEvent.Set();
                        }
                    }
                };

                beamProcess.ErrorDataReceived += (s, e) =>
                {
                    if (e.Data != null)
                    {
                        RecordOutputLine(recentLogs, "[stderr] " + e.Data);
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
                bool portSignaled = portFoundEvent.WaitOne(10000);

                if (!portSignaled || (beamProcess.HasExited && boundPort == 0))
                {
                    string errMsg = FormatDiagnosticMessage(
                        "RxGenerator failed to start within 10 seconds.",
                        recentLogs
                    );
                    MessageBox.Show(
                        errMsg,
                        "RxGenerator - Startup Error",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error
                    );

                    try
                    {
                        if (!beamProcess.HasExited) beamProcess.Kill();
                    }
                    catch { }

                    if (jobHandle != IntPtr.Zero) CloseHandle(jobHandle);
                    return;
                }

                Application.Run(new RxGeneratorAppForm(boundPort, beamProcess, jobHandle, recentLogs));
            }
        }
    }
}
