// BSP 플랫폼 에이전트 — 이미 있는 애드온/플랫폼에 «끼워 넣는» 라이브러리 (net48)
//
//   이 DLL 은 **리빗을 참조하지 않는다.** 그래서 어떤 애드온에도, 어떤 연도에도 끼운다.
//   쓰는 쪽에서 필요한 것은 두 줄이다.
//
//       BspAgent.Attach("2024", Process.GetCurrentProcess().Id);   // IExternalApplication.OnStartup
//       BspAgent.Detach();                                          //                    .OnShutdown
//
//   그러면 밖에서 매니저(bsp-launcher.exe)가 돌기 시작하고, 애드온이 내려가면 같이 끝난다.
//   업데이트·해시검증·잠긴 파일 교체·기록·메모리 감시는 전부 그쪽(별도 프로세스)이 한다.
//
//   내려받기를 «리빗 안 화면» 에서 시키고 싶으면 :
//
//       var a = BspAgent.Install("bsp.hts");      // 백그라운드 스레드에서 부른다
//       if (a.Pending) 사용자에게("리빗을 껐다 켜면 적용됩니다");
//
//   기존 플랫폼의 업데이트 코드를 걷어낼 필요는 없다. 한 제품씩 옮겨도 된다.
using System;
using System.Diagnostics;
using System.IO;
using System.Text;

namespace BSP.Platform.Agent
{
    /// <summary>이 라이브러리의 정문. 다른 타입은 몰라도 된다.</summary>
    public static class BspAgent
    {
        internal static string Year = "";
        internal static int Pid;

        /// <summary>상태 폴더. 로그·설정·설치 목록이 전부 여기 있다.</summary>
        public static string StateDir { get { return LauncherHost.StateDir; } }

        /// <summary>버전 (SDK 계약 버전).</summary>
        public const string Version = "0.1";

        // ------------------------------------------------------------------ 붙이기
        /// <summary>애드온 기동 때 한 번. 세션을 남기고, 매니저가 없으면 띄운다.
        /// **예외를 던지지 않는다** — 리빗 기동을 막으면 안 된다. 실패해도 애드온은 그대로 뜬다.
        /// 오래 걸리지 않지만, 확실히 하려면 백그라운드 스레드에서 불러도 된다.</summary>
        public static bool Attach(string revitYear, int revitPid)
        {
            Year = revitYear ?? "";
            Pid = revitPid > 0 ? revitPid : SafePid();
            var ok = LauncherHost.Ensure(Year, Pid);
            Log("bsp.agent", "attach", ok ? "ok" : "failed", 0, LauncherHost.Last);
            return ok;
        }

        /// <summary>인자 없이 — 지금 프로세스와 주어진 연도로 붙인다.</summary>
        public static bool Attach(string revitYear) { return Attach(revitYear, SafePid()); }

        /// <summary>애드온이 내려갈 때 한 번. 매니저를 죽이지 않는다 — 세션 표시만 지운다.
        /// 마지막 세션이면 매니저가 스스로 마무리(큐 적용·기록 업로드)하고 끝낸다.</summary>
        public static void Detach()
        {
            Log("bsp.agent", "detach", "ok", 0, "");
            LauncherHost.Release(Pid > 0 ? Pid : SafePid());
            Unstage();                       // 이 세션이 쓴 복사본 정리
        }

        // ------------------------------------------------------------------ 시키기
        /// <summary>제품 하나를 지금 받는다. **UI 스레드에서 부르지 않는다.**
        /// 답의 Pending 이 true 면 «리빗을 껐다 켜야 반영» 이라는 뜻이다.</summary>
        public static Answer Install(string productId, int timeoutMs = 120000)
        { return Requests.Send("install", productId, timeoutMs); }

        /// <summary>카탈로그 전체를 한 번 맞춘다.</summary>
        public static Answer SyncAll(int timeoutMs = 120000)
        { return Requests.Send("sync", "", timeoutMs); }

        public static Answer Enable(string productId) { return Requests.Send("enable", productId, 15000); }
        public static Answer Disable(string productId) { return Requests.Send("disable", productId, 15000); }

        // ------------------------------------------------------------------ 동적 로드
        /// <summary>도구를 «원본을 잠그지 않고» 싣기 위한 자리를 만든다.
        ///
        ///   문제 : .NET Framework 는 한 번 로드한 DLL 을 내리지 못하고, 로드된 파일은 잠긴다.
        ///          그래서 리빗이 켜져 있는 동안에는 그 도구를 갈아끼울 수 없다.
        ///   해법 : **세션 폴더로 복사해서 거기서 로드한다.** 원본은 아무도 안 잡고 있으므로
        ///          매니저가 리빗이 켜진 채로도 새 버전을 덮을 수 있다. 반영은 다음 기동.
        ///
        ///   host 쪽 사용법 :
        ///       var dir = BspAgent.Stage("bsp.hts");                 // 복사본 폴더
        ///       var asm = Assembly.LoadFrom(Path.Combine(dir, "BSP.Hub.dll"));   // 첫 클릭 때
        ///
        /// 실패하면 원본 폴더를 그대로 돌려준다 — 못 해도 동작은 한다.</summary>
        public static string Stage(string productId)
        {
            var src = Path.Combine(StateDir, "Tools", productId ?? "");
            try
            {
                if (!Directory.Exists(src)) return src;
                var dst = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "BSP", "Platform", "stage", SafePid().ToString(), productId ?? "");
                Directory.CreateDirectory(dst);

                foreach (var f in Directory.GetFiles(src, "*", SearchOption.AllDirectories))
                {
                    var rel = f.Substring(src.Length).TrimStart(Path.DirectorySeparatorChar);
                    var t = Path.Combine(dst, rel);
                    Directory.CreateDirectory(Path.GetDirectoryName(t));
                    // 이미 같은 내용이면 건너뛴다 (매번 복사하면 기동이 느려진다)
                    if (File.Exists(t) && new FileInfo(t).Length == new FileInfo(f).Length &&
                        File.GetLastWriteTimeUtc(t) == File.GetLastWriteTimeUtc(f)) continue;
                    File.Copy(f, t, true);
                    File.SetLastWriteTimeUtc(t, File.GetLastWriteTimeUtc(f));
                }
                Log(productId, "stage", "ok", 0, dst);
                return dst;
            }
            catch (Exception ex) { Log(productId, "stage", "failed", 0, ex.Message); return src; }
        }

        /// <summary>이 세션이 쓴 복사본을 지운다. Detach 가 자동으로 부른다.</summary>
        static void Unstage()
        {
            try
            {
                var dir = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "BSP", "Platform", "stage", (Pid > 0 ? Pid : SafePid()).ToString());
                if (Directory.Exists(dir)) Directory.Delete(dir, true);
            }
            catch { }   // 잠겨 있으면 다음 세션이 덮어쓴다. 남아도 해롭지 않다
        }

        // ------------------------------------------------------------------ 보기
        /// <summary>매니저가 지금 돌고 있나.</summary>
        public static bool ManagerAlive { get { return LauncherHost.Alive(); } }

        /// <summary>매니저 실행 파일 위치 (없으면 null).</summary>
        public static string ManagerPath { get { return LauncherHost.FindExe(); } }

        /// <summary>마지막 점화 결과 한 줄 — 화면에 그대로 띄워도 되는 문장.</summary>
        public static string LastAction { get { return LauncherHost.Last; } }

        /// <summary>설치 상태 파일(state.json)의 원문. 파싱은 부르는 쪽이 한다
        /// (JSON 라이브러리를 강요하지 않으려고 문자열로 준다). 없으면 null.</summary>
        public static string StateJson()
        {
            try
            {
                var p = Path.Combine(StateDir, "state.json");
                return File.Exists(p) ? File.ReadAllText(p, Encoding.UTF8) : null;
            }
            catch { return null; }
        }

        // ------------------------------------------------------------------ 남기기
        /// <summary>실행 기록 한 줄. 매니저가 걷어서 서버로 올린다(서버가 없으면 로컬에만 쌓인다).
        /// **도면 내용은 절대 넣지 않는다** — 문서명·뷰명·선택 수까지가 한계다.</summary>
        public static void Log(string product, string tool, string outcome, long ms, string note)
        {
            try
            {
                Directory.CreateDirectory(StateDir);
                var line = "{\"t\":\"" + DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss") +
                           "\",\"product\":\"" + Esc(product) + "\",\"tool\":\"" + Esc(tool) +
                           "\",\"outcome\":\"" + Esc(outcome) + "\",\"ms\":" + ms +
                           ",\"host\":\"" + Esc(Environment.MachineName) +
                           "\",\"user\":\"" + Esc(Environment.UserName) +
                           "\",\"note\":\"" + Esc(note) + "\"}\r\n";
                File.AppendAllText(Path.Combine(StateDir, "runlog.jsonl"), line, new UTF8Encoding(false));
            }
            catch { }        // 기록 실패가 업무를 막지 않는다
        }

        /// <summary>도구 실행을 감싼다 — 시간을 재고, 실행 중 표시를 남기고, 결과를 기록한다.
        /// 표시(.running)가 남은 채 리빗이 사라지면 **그 도구가 범인**으로 지목된다.
        /// 예외는 삼키지 않는다. 기록만 남기고 그대로 올려 보낸다.</summary>
        public static T Run<T>(string product, string tool, Func<T> body)
        {
            var sw = Stopwatch.StartNew();
            var mark = Path.Combine(StateDir, ".running");
            try
            {
                Directory.CreateDirectory(StateDir);
                try { File.WriteAllText(mark, tool + "|" + DateTime.Now.ToString("s"), new UTF8Encoding(false)); }
                catch { }
                var r = body();
                Log(product, tool, "succeeded", sw.ElapsedMilliseconds, "");
                return r;
            }
            catch (Exception ex)
            {
                Log(product, tool, "failed", sw.ElapsedMilliseconds, ex.GetType().Name + " : " + ex.Message);
                throw;
            }
            finally { try { File.Delete(mark); } catch { } }
        }

        static int SafePid()
        {
            try { return Process.GetCurrentProcess().Id; } catch { return 0; }
        }

        static string Esc(string s)
        {
            return (s ?? "").Replace("\\", "\\\\").Replace("\"", "\\\"")
                            .Replace("\n", " ").Replace("\r", " ");
        }
    }
}
