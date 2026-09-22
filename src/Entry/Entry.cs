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
        /// <summary>스토어 패널 식별자 — 리빗이 이 GUID 로 패널 자리를 기억한다. 바꾸면 배치가 초기화된다.</summary>
        internal static readonly DockablePaneId StoreId =
            new DockablePaneId(new Guid("7A1C4E28-9D53-4B6F-8E12-3C5A0F7B9D64"));
        static StorePane _store;
        internal static bool StoreReady;
        internal static string StoreError = "";

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

                // 스토어 패널 — **등록은 기동 시점에만** 가능하다.
                // 실패하면 조용히 넘기지 않는다. 원인을 남겨야 다음에 고칠 수 있다.
                try
                {
                    _store = new StorePane();
                    a.RegisterDockablePane(StoreId, "BSP 스토어", _store);
                    StoreReady = true;
                }
                catch (Exception ex)
                {
                    StoreReady = false;
                    StoreError = ex.GetType().Name + " : " + ex.Message;
                    Log("스토어.등록", "failed", 0, StoreError);
                }

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

            var sb = new PushButtonData("BspStore", "스토어", me, typeof(StoreCommand).FullName)
            {
                ToolTip = "프로그램 받기 · 업데이트",
                LongDescription = "설치할 프로그램을 고르고, 새 버전을 받습니다. 도구는 도구상자에서 ★ 로 리본에 올립니다.",
            };
            panel.AddItem(sb);

            var b = new PushButtonData("BspStatus", "상태", me, typeof(StatusCommand).FullName)
            {
                ToolTip = "백그라운드 매니저 상태",
                LongDescription = "설치된 제품 · 대기 중인 적용 · 매니저 생존 여부를 봅니다.",
            };
            panel.AddItem(b);
        }

        // ------------------------------------------------------------------ 기록
        /// <summary>패널 등록이 실패했을 때의 대체 — 같은 화면을 창으로 띄운다.</summary>
        internal static void ShowStoreWindow()
        {
            var pane = new StorePane();
            var w = new System.Windows.Window
            {
                Title = "BSP 스토어" + (StoreError.Length > 0 ? "  (패널 등록 실패 : " + StoreError + ")" : ""),
                Width = 520,
                Height = 760,
                Content = pane,
                WindowStartupLocation = System.Windows.WindowStartupLocation.CenterScreen,
            };
            new System.Windows.Interop.WindowInteropHelper(w).Owner =
                System.Diagnostics.Process.GetCurrentProcess().MainWindowHandle;
            w.Show();
        }

        /// <summary>패널 목록을 다시 읽는다 (받기가 끝난 뒤·스토어를 열 때).</summary>
        internal static void RefreshStore()
        {
            try { if (_store != null) _store.Reload(); } catch { }
        }

        /// <summary>기록은 라이브러리가 쓴다 — 서식이 한 곳에만 있게 한다.</summary>
        internal static void Log(string tool, string outcome, long ms, string note)
        { BspAgent.Log("bsp.platform", tool, outcome, ms, note); }
    }

    /// <summary>[스토어] — 패널을 띄우고 목록을 새로 읽는다.</summary>
    [Transaction(TransactionMode.Manual)]
    public class StoreCommand : IExternalCommand
    {
        public Result Execute(ExternalCommandData c, ref string msg, ElementSet e)
        {
            var sw = Stopwatch.StartNew();
            try
            {
                if (App.StoreReady)
                {
                    var pane = c.Application.GetDockablePane(App.StoreId);
                    pane.Show();
                    App.RefreshStore();
                }
                else
                {
                    // 패널 등록이 안 됐으면 창으로 띄운다 — 스토어를 못 쓰게 두지 않는다
                    App.ShowStoreWindow();
                }
            }
            catch (Exception ex)
            {
                try { App.ShowStoreWindow(); }
                catch { msg = ex.Message; return Result.Failed; }
            }
            App.Log("스토어", "succeeded", sw.ElapsedMilliseconds, "");
            return Result.Succeeded;
        }
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
            sb.AppendLine("스토어 패널 : " + (App.StoreReady ? "등록됨" : "등록 실패 — " + App.StoreError));
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
