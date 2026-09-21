// BSP 플랫폼 — 리빗 엔트리포인트 (net48 · Revit 2024)
//
//   애드온은 «점화 플러그» 다. 관리는 밖(bsp-launcher.exe)이 한다.
//   그래서 이 파일은 짧아야 한다 — 여기서 하는 일이 늘어나는 순간
//   관리 기능이 리빗의 수명과 메모리에 다시 묶인다.
//
//   OnStartup 에서 하는 일 (예산 : 리빗 기동에 더하는 시간 50ms 미만)
//     1. 세션 표시를 남긴다            — 지금 어떤 연도의 리빗이 떠 있는가
//     2. 매니저가 없으면 띄운다        — 별도 프로세스 · 종속되지 않음
//     3. 리본 버튼 하나를 만든다       — [상태] 뿐. 도구는 카탈로그가 결정한다
//   전부 백그라운드 스레드에서 한다. 리빗 UI 스레드를 한 순간도 잡지 않는다.
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Threading;
using Autodesk.Revit.Attributes;
using Autodesk.Revit.DB;
using Autodesk.Revit.UI;
using BSP.Platform.Agent;

namespace BSP.Platform.Entry
{
    public class App : IExternalApplication
    {
        internal static string RevitYear = "";
        internal static int Pid;
        internal static long BootMs;

        public Result OnStartup(UIControlledApplication a)
        {
            var sw = Stopwatch.StartNew();
            try
            {
                RevitYear = a.ControlledApplication.VersionNumber;      // "2024"
                Pid = Process.GetCurrentProcess().Id;

                Ribbon(a);

                // 점화는 백그라운드로. 매니저가 느리게 떠도 리빗은 기다리지 않는다.
                var t = new Thread(() => BspAgent.Attach(RevitYear, Pid));
                t.IsBackground = true;
                t.Name = "BSP.Agent.Attach";
                t.Start();
            }
            catch (Exception ex) { Log("기동", "failed", sw.ElapsedMilliseconds, ex.Message); }
            BootMs = sw.ElapsedMilliseconds;
            Log("기동", "ok", BootMs, "revit " + RevitYear);
            return Result.Succeeded;                                    // 무슨 일이 있어도 리빗은 뜬다
        }

        public Result OnShutdown(UIControlledApplication a)
        {
            // 매니저를 죽이지 않는다. 세션 표시만 지우면, 마지막 세션이었을 때
            // 매니저가 스스로 마무리(큐 적용·기록 업로드)하고 끝낸다.
            try { BspAgent.Detach(); } catch { }
            return Result.Succeeded;
        }

        // ------------------------------------------------------------------ 리본
        static void Ribbon(UIControlledApplication a)
        {
            const string TAB = "BSP";
            try { a.CreateRibbonTab(TAB); } catch { }                   // 이미 있으면 그대로 쓴다
            var panel = a.CreateRibbonPanel(TAB, "플랫폼");

            var me = Assembly.GetExecutingAssembly().Location;
            var b = new PushButtonData("BspStatus", "상태", me, typeof(StatusCommand).FullName)
            {
                ToolTip = "백그라운드 매니저 상태",
                LongDescription = "설치된 제품 · 대기 중인 적용 · 매니저 생존 여부를 봅니다.",
            };
            panel.AddItem(b);
        }

        // ------------------------------------------------------------------ 기록
        /// <summary>기록은 라이브러리가 쓴다 — 서식이 한 곳에만 있게 한다.</summary>
        internal static void Log(string tool, string outcome, long ms, string note)
        { BspAgent.Log("bsp.platform", tool, outcome, ms, note); }
    }

    [Transaction(TransactionMode.Manual)]
    public class StatusCommand : IExternalCommand
    {
        public Result Execute(ExternalCommandData c, ref string msg, ElementSet e)
        {
            var sw = Stopwatch.StartNew();
            var alive = BspAgent.ManagerAlive;
            var exe = BspAgent.ManagerPath ?? "(없음)";

            var sb = new StringBuilder();
            sb.AppendLine("매니저 : " + (alive ? "돌고 있음" : "꺼져 있음"));
            sb.AppendLine("실행 파일 : " + exe);
            sb.AppendLine("마지막 점화 : " + BspAgent.LastAction);
            sb.AppendLine("상태 폴더 : " + BspAgent.StateDir);
            sb.AppendLine("이 리빗 : " + App.RevitYear + " · pid " + App.Pid + " · 기동 +" + App.BootMs + "ms");

            var state = Path.Combine(BspAgent.StateDir, "state.json");
            sb.AppendLine("카탈로그 : " + (File.Exists(state)
                ? File.GetLastWriteTime(state).ToString("MM-dd HH:mm") + " 갱신"
                : "아직 받은 적 없음"));

            var d = new TaskDialog("BSP 플랫폼")
            {
                MainInstruction = alive ? "매니저가 돌고 있습니다" : "매니저가 꺼져 있습니다",
                MainContent = sb.ToString(),
                CommonButtons = TaskDialogCommonButtons.Close,
            };
            if (!alive) d.AddCommandLink(TaskDialogCommandLinkId.CommandLink1, "지금 띄우기");
            var r = d.Show();
            if (r == TaskDialogResult.CommandLink1) BspAgent.Attach(App.RevitYear, App.Pid);

            App.Log("상태", "succeeded", sw.ElapsedMilliseconds, alive ? "alive" : "down");
            return Result.Succeeded;
        }
    }
}
