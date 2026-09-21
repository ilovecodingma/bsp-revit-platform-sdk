// BSP 플랫폼 — 상주 매니저 점화기 (net48)
//
//   이 파일이 하는 일은 하나다 : «백그라운드 매니저(bsp-launcher.exe)가 돌고 있게 만든다».
//   중요한 것은 «어떻게 띄우느냐» 다.
//
//   ┌ 리빗(Revit.exe) ─────────────┐        ┌ bsp-launcher.exe ────────────┐
//   │  BSP.Platform.Entry.dll      │  점화  │  상주 · 리빗과 수명이 다르다  │
//   │   OnStartup → Ensure()  ─────┼──────▶ │  리빗이 죽어도 산다           │
//   │   (곧바로 돌아온다)          │        │  리빗이 없어도 산다           │
//   └──────────────────────────────┘        └──────────────────────────────┘
//            │                                         ▲
//            └──── 파일(%AppData%\BSP\Platform) ────────┘
//
//   «종속되지 않는다» 는 세 가지를 모두 지켜야 성립한다.
//     1) 표준 입출력을 물려주지 않는다 → DETACHED_PROCESS (파이프를 잡으면 서로 묶인다)
//     2) 핸들을 물려주지 않는다        → bInheritHandles = false
//     3) 작업 개체(Job)에서 빠져나온다 → CREATE_BREAKAWAY_FROM_JOB
//        리빗이 Job 안에서 돌면(배포 관리 도구·일부 MDM·컨테이너) 리빗이 죽을 때
//        자식이 통째로 같이 죽는다. 이 한 줄이 없으면 «상주» 가 거짓말이 된다.
//     그리고 띄운 직후 핸들 두 개를 반드시 닫는다 — 안 닫으면 리빗이 좀비를 들고 있는다.
//
//   실패하면 조용히 다음 방법으로 내려간다. 마지막은 WMI 로 띄우는 것 —
//   이때 부모는 WmiPrvSE 가 되어 리빗과의 관계가 완전히 끊긴다.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace BSP.Platform.Entry
{
    public static class LauncherHost
    {
        public const string MutexName = "BSP.Launcher.Agent.v1";
        const int BeatStaleSeconds = 240;      // 심장박동이 이보다 낡으면 죽은 것으로 본다

        public static string StateDir
        {
            get
            {
                return Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                    "BSP", "Platform");
            }
        }

        public static string BeatFile { get { return Path.Combine(StateDir, "agent.json"); } }
        public static string SessionDir { get { return Path.Combine(StateDir, "revit"); } }

        /// <summary>마지막으로 한 일. 상태 패널에 그대로 보여 준다.</summary>
        public static string Last = "(아직)";

        // ------------------------------------------------------------------ 점화
        /// <summary>매니저가 돌고 있으면 아무것도 하지 않는다. 없으면 «독립 프로세스» 로 띄운다.
        /// 어떤 경우에도 예외를 밖으로 내지 않는다 — 리빗 기동을 막으면 안 된다.</summary>
        public static bool Ensure(string revitYear, int revitPid)
        {
            try
            {
                Directory.CreateDirectory(SessionDir);
                WriteSession(revitYear, revitPid);

                if (Alive()) { Last = "이미 상주 중"; return true; }

                var exe = FindExe();
                if (exe == null) { Last = "bsp-launcher.exe 를 찾지 못함"; return false; }

                var how = Spawn(exe, "watch-revit");
                Last = (how == null) ? "띄우지 못함" : ("띄움 (" + how + ")");
                return how != null;
            }
            catch (Exception ex) { Last = "실패 : " + ex.Message; return false; }
        }

        /// <summary>리빗이 닫힐 때 — 매니저는 죽이지 않는다. 내 자취만 지운다.</summary>
        public static void Release(int revitPid)
        {
            try { File.Delete(Path.Combine(SessionDir, revitPid + ".json")); } catch { }
        }

        // ------------------------------------------------------------------ 살아 있나
        /// <summary>두 가지로 본다 — 자물쇠(진실) 와 심장박동(참고).
        /// 자물쇠는 프로세스가 죽는 순간 OS 가 풀어 준다. 파일은 남을 수 있으므로 믿지 않는다.</summary>
        public static bool Alive()
        {
            foreach (var n in new[] { "Global\\" + MutexName, "Local\\" + MutexName })
            {
                try { using (Mutex.OpenExisting(n)) return true; }
                catch (WaitHandleCannotBeOpenedException) { }        // 없다 → 다음 이름
                catch (UnauthorizedAccessException) { return true; }  // 있다, 권한만 없다
                catch { }
            }
            return BeatFresh();
        }

        static bool BeatFresh()
        {
            try
            {
                if (!File.Exists(BeatFile)) return false;
                var age = DateTime.Now - File.GetLastWriteTime(BeatFile);
                if (age.TotalSeconds > BeatStaleSeconds) return false;
                var pid = PidFromBeat();
                if (pid <= 0) return false;
                using (Process.GetProcessById(pid)) return true;
            }
            catch { return false; }
        }

        static int PidFromBeat()
        {
            try
            {
                var t = File.ReadAllText(BeatFile);
                var i = t.IndexOf("\"pid\"", StringComparison.Ordinal);
                if (i < 0) return 0;
                var j = i + 5; var sb = new StringBuilder();
                while (j < t.Length && (t[j] == ':' || t[j] == ' ')) j++;
                while (j < t.Length && char.IsDigit(t[j])) sb.Append(t[j++]);
                int pid; return int.TryParse(sb.ToString(), out pid) ? pid : 0;
            }
            catch { return 0; }
        }

        // ------------------------------------------------------------------ 어디 있나
        /// <summary>1) 애드온 옆 2) 상태 폴더 3) ProgramData 4) LocalAppData.
        /// 설치 방식에 얽매이지 않는다 — 회사마다 두는 곳이 다르다.</summary>
        public static string FindExe()
        {
            var cands = new List<string>();
            try
            {
                var me = Path.GetDirectoryName(new Uri(
                    System.Reflection.Assembly.GetExecutingAssembly().CodeBase).LocalPath);
                cands.Add(Path.Combine(me, "bsp-launcher.exe"));
                cands.Add(Path.Combine(me, "launcher", "bsp-launcher.exe"));
            }
            catch { }
            cands.Add(Path.Combine(StateDir, "bsp-launcher.exe"));
            cands.Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                                   "BSP", "Platform", "bsp-launcher.exe"));
            cands.Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                                   "BSP", "Platform", "bsp-launcher.exe"));
            foreach (var c in cands) { try { if (File.Exists(c)) return c; } catch { } }
            return null;
        }

        // ------------------------------------------------------------------ 띄우기
        /// <summary>순서가 곧 안전이다. «되는 방법» 이 아니라 «끊어지는 방법» 을 먼저 쓴다.
        ///
        ///   1) detached + breakaway   — 성공하면 작업 개체 밖이다 (윈도우가 보장한다)
        ///   2) 내가 Job 안에 있나?    — 아니면 그냥 detached 로 충분하다
        ///   3) Job 안인데 탈출 거부   — **그냥 띄우면 안 된다.** 같은 Job 에 들어가
        ///      부모가 죽을 때 함께 죽는다. WMI 로 돌려 띄운다 (부모가 WmiPrvSE 가 된다)
        ///
        /// 실측 : kill-on-close Job 안에서 탈출이 거부된 채 detached 로 띄웠더니
        ///        부모가 끝나는 순간 매니저도 함께 사라졌다. 이 순서는 그 사고의 결과다.</summary>
        static string Spawn(string exe, string args)
        {
            if (CreateDetached(exe, args, true)) return "detached+breakaway";
            if (!InJob() && CreateDetached(exe, args, false)) return "detached";
            if (WmiCreate(exe, args)) return "wmi";
            if (CreateDetached(exe, args, false)) return "detached(위험 · Job 안)";
            try
            {
                var psi = new ProcessStartInfo(exe, args)
                {
                    UseShellExecute = true,          // 셸에 맡긴다 — 핸들을 물려주지 않는다
                    CreateNoWindow = true,
                    WindowStyle = ProcessWindowStyle.Hidden,
                    WorkingDirectory = Path.GetDirectoryName(exe),
                };
                using (var p = Process.Start(psi)) { if (p != null) return "shell"; }
            }
            catch { }
            return null;
        }

        const uint DETACHED_PROCESS = 0x00000008;
        const uint CREATE_NEW_PROCESS_GROUP = 0x00000200;   // 리빗의 콘솔 신호와 무관해진다
        const uint CREATE_BREAKAWAY_FROM_JOB = 0x01000000;

        static bool CreateDetached(string exe, string args, bool breakaway)
        {
            var si = new STARTUPINFO(); si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
            PROCESS_INFORMATION pi;
            uint flags = DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP
                       | (breakaway ? CREATE_BREAKAWAY_FROM_JOB : 0u);
            var cmd = new StringBuilder("\"" + exe + "\" " + args);

            bool ok = CreateProcess(exe, cmd, IntPtr.Zero, IntPtr.Zero,
                                    false,            // ← 핸들을 하나도 물려주지 않는다
                                    flags, IntPtr.Zero, Path.GetDirectoryName(exe), ref si, out pi);
            if (!ok) return false;
            // 핸들을 바로 놓는다. 들고 있으면 리빗이 끝난 프로세스를 계속 붙잡고 있게 된다.
            try { if (pi.hThread != IntPtr.Zero) CloseHandle(pi.hThread); } catch { }
            try { if (pi.hProcess != IntPtr.Zero) CloseHandle(pi.hProcess); } catch { }
            return true;
        }

        /// <summary>마지막 수단 — WMI 에게 띄우게 한다. 부모가 WmiPrvSE 가 되어 관계가 완전히 끊긴다.</summary>
        static bool WmiCreate(string exe, string args)
        {
            try
            {
                using (var cls = new System.Management.ManagementClass("Win32_Process"))
                {
                    var p = cls.GetMethodParameters("Create");
                    p["CommandLine"] = "\"" + exe + "\" " + args;
                    p["CurrentDirectory"] = Path.GetDirectoryName(exe);
                    var r = cls.InvokeMethod("Create", p, null);
                    return r != null && Convert.ToInt32(r["ReturnValue"], CultureInfo.InvariantCulture) == 0;
                }
            }
            catch { return false; }
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct STARTUPINFO
        {
            public int cb; public string lpReserved, lpDesktop, lpTitle;
            public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
            public short wShowWindow, cbReserved2;
            public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern bool CreateProcess(string app, StringBuilder cmd, IntPtr pa, IntPtr ta,
            bool inherit, uint flags, IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool CloseHandle(IntPtr h);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool IsProcessInJob(IntPtr proc, IntPtr job, [MarshalAs(UnmanagedType.Bool)] out bool result);

        /// <summary>이 프로세스(=리빗)가 작업 개체 안에 있는가.
        /// 있으면 «그냥 자식으로 띄우기» 는 금지다 — 리빗이 죽을 때 같이 끌려간다.</summary>
        public static bool InJob()
        {
            try
            {
                bool inJob;
                if (!IsProcessInJob(Process.GetCurrentProcess().Handle, IntPtr.Zero, out inJob)) return true;
                return inJob;          // 모르면 «안에 있다» 쪽으로 판단한다 (안전한 쪽)
            }
            catch { return true; }
        }

        // ------------------------------------------------------------------ 세션 표시
        /// <summary>«이 리빗이 지금 켜져 있다» 를 파일로 남긴다 — 매니저는 이것으로
        /// 어떤 연도의 리빗인지, 몇 개가 떠 있는지, 언제 꺼졌는지를 안다(WMI 보다 정확하다).</summary>
        static void WriteSession(string year, int pid)
        {
            try
            {
                var f = Path.Combine(SessionDir, pid + ".json");
                var s = "{\"pid\":" + pid + ",\"year\":\"" + year + "\",\"since\":\"" +
                        DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss") + "\",\"host\":\"" +
                        Environment.MachineName + "\",\"user\":\"" + Environment.UserName + "\"}";
                File.WriteAllText(f, s, new UTF8Encoding(false));
            }
            catch { }
        }
    }
}
