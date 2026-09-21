// bsp-probe.exe — 하네스 : 리빗 없이 «붙여 보는» 도구
//
//   대표님 애드온이 할 일을 그대로 흉내 낸다. 리빗을 켜지 않고,
//   애드온을 고치지 않고, 이 SDK 가 그 자리에서 도는지부터 확인한다.
//
//     bsp-probe cycle [제품id]     붙이기 → 받기 → 실행기록 → 떼기 까지 한 바퀴 (판정표)
//     bsp-probe attach [연도]      붙이기만 하고 기다린다 (Ctrl+C 로 뗀다)
//     bsp-probe install <제품id>   지금 받아 본다
//     bsp-probe status             매니저·설치 상태
//
//   이 파일은 그대로 **붙이는 예제 코드**이기도 하다. 애드온에 옮길 줄은 네 줄뿐이다.
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using BSP.Platform.Agent;

static class Probe
{
    static int pass, fail;

    static void Check(string name, bool ok, string detail)
    {
        if (ok) pass++; else fail++;
        var c = Console.ForegroundColor;
        Console.ForegroundColor = ok ? ConsoleColor.Green : ConsoleColor.Red;
        Console.Write("{0,-6}", ok ? "PASS" : "FAIL");
        Console.ForegroundColor = c;
        Console.WriteLine(" {0,-16} {1}", name, detail);
    }

    static int Main(string[] av)
    {
        try { Console.OutputEncoding = Encoding.UTF8; } catch { }
        var cmd = av.Length > 0 ? av[0].ToLowerInvariant() : "cycle";
        var arg = av.Length > 1 ? av[1] : "";

        Console.WriteLine();
        Console.WriteLine("BSP 하네스 · 상태 폴더 : " + BspAgent.StateDir);
        Console.WriteLine(new string('-', 88));

        switch (cmd)
        {
            case "attach": return Attach(arg.Length > 0 ? arg : "2024");
            case "install": return Install(arg);
            case "status": return Status();
            default: return Cycle(arg);
        }
    }

    // ------------------------------------------------------------------ 한 바퀴
    static int Cycle(string productId)
    {
        var exe = BspAgent.ManagerPath;
        Check("매니저 파일", exe != null, exe ?? "bsp-launcher.exe 를 못 찾음 — 애드온 옆이나 상태 폴더에 두세요");
        if (exe == null) return 1;

        // 1. 붙이기 — 애드온 OnStartup 에 해당
        var sw = Stopwatch.StartNew();
        bool ok = BspAgent.Attach("2024", Process.GetCurrentProcess().Id);
        Check("붙이기", ok, BspAgent.LastAction + "  (" + sw.ElapsedMilliseconds + "ms)");

        // 2. 매니저가 별도 프로세스로 살아났나
        var live = WaitFor(() => BspAgent.ManagerAlive, 15000);
        Check("매니저 기동", live, live ? "별도 프로세스로 돌고 있음" : "15초 안에 뜨지 않음 — agent.err.log 확인");

        // 3. 세션 표시
        var sess = Path.Combine(BspAgent.StateDir, "revit");
        var n = Directory.Exists(sess) ? Directory.GetFiles(sess, "*.json").Length : 0;
        Check("세션 표시", n > 0, n + "개 — 매니저는 이 표시를 보고 수명을 정한다");

        // 4. 받기 (제품을 지정했을 때만)
        if (productId.Length > 0)
        {
            var a = BspAgent.Install(productId, 90000);
            Check("받기", a.Ok, a.Status + (a.Pending ? "  → 리빗 껐다 켤 때 적용" : "") +
                                (a.Message.Length > 0 ? "  · " + a.Message : ""));
        }
        else Console.WriteLine("       (제품 id 를 주면 실제로 받아 봅니다 : bsp-probe cycle <제품id>)");

        // 5. 실행 기록 — 도구 한 번 돌린 셈
        long before = Lines();
        BspAgent.Run("harness", "시험 작업", () => { Thread.Sleep(200); return 0; });
        Check("실행 기록", Lines() > before, "runlog.jsonl 에 한 줄 늘었다");

        // 6. 떼기 — 애드온 OnShutdown 에 해당
        BspAgent.Detach();
        // ★ 다른 리빗이 붙어 있으면 매니저는 **남아 있는 것이 정상**이다.
        //   그 상태에서 «안 죽었다» 고 FAIL 을 내면 거짓 실패가 된다 (실측).
        int others = Sessions();
        if (others > 0)
        {
            Check("떼기", true, "다른 리빗 세션 " + others + "개가 살아 있어 매니저 유지 — 정상");
        }
        else
        {
            var gone = WaitFor(() => !BspAgent.ManagerAlive, 90000);
            Check("떼기", gone, gone ? "마지막 세션이 사라지자 매니저가 스스로 끝냈다"
                                     : "90초가 지나도 매니저가 남아 있다 (config 의 exitGraceSeconds 확인)");
        }

        Console.WriteLine(new string('-', 88));
        Console.WriteLine("결과 : {0} PASS · {1} FAIL", pass, fail);
        if (fail == 0)
            Console.WriteLine("\n이 여섯 줄이 통과하면, 같은 코드를 애드온의 OnStartup/OnShutdown 에 옮기면 됩니다.");
        return fail == 0 ? 0 : 1;
    }

    // ------------------------------------------------------------------ 개별
    static int Attach(string year)
    {
        bool ok = BspAgent.Attach(year, Process.GetCurrentProcess().Id);
        Console.WriteLine("붙이기 : " + ok + "  /  " + BspAgent.LastAction);
        Console.WriteLine("매니저 : " + (BspAgent.ManagerAlive ? "돌고 있음" : "아직") + "  " + BspAgent.ManagerPath);
        Console.WriteLine("\n리빗이 떠 있는 상태를 흉내 냅니다. Ctrl+C 로 끝내면 매니저도 곧 따라 끝납니다.");
        Console.CancelKeyPress += (s, e) => { BspAgent.Detach(); };
        while (true) Thread.Sleep(1000);
    }

    static int Install(string id)
    {
        if (id.Length == 0) { Console.WriteLine("제품 id 가 필요합니다."); return 2; }
        BspAgent.Attach("2024", Process.GetCurrentProcess().Id);
        var a = BspAgent.Install(id, 120000);
        Console.WriteLine((a.Ok ? "받음 : " : "실패 : ") + a.Status + "  " + a.Message);
        if (a.Pending) Console.WriteLine("→ 이미 쓰이는 파일이라 리빗(또는 이 하네스)이 끝난 뒤 적용됩니다.");
        BspAgent.Detach();
        return a.Ok ? 0 : 1;
    }

    static int Status()
    {
        Console.WriteLine("매니저   : " + (BspAgent.ManagerAlive ? "돌고 있음" : "꺼짐"));
        Console.WriteLine("실행파일 : " + (BspAgent.ManagerPath ?? "(못 찾음)"));
        var js = BspAgent.StateJson();
        Console.WriteLine("상태파일 : " + (js == null ? "없음" : js.Length + "바이트"));
        if (js != null)
        {
            foreach (var line in js.Split(new[] { "\"id\":\"" }, StringSplitOptions.None).Skip(1))
                Console.WriteLine("   · " + line.Split('"')[0]);
        }
        return 0;
    }

    /// <summary>지금 살아 있는 애드온 세션 수 (내 것은 이미 뗐다).</summary>
    static int Sessions()
    {
        try
        {
            var dir = Path.Combine(BspAgent.StateDir, "revit");
            if (!Directory.Exists(dir)) return 0;
            int n = 0;
            foreach (var f in Directory.GetFiles(dir, "*.json"))
            {
                var name = Path.GetFileNameWithoutExtension(f);
                int pid;
                if (!int.TryParse(name, out pid)) continue;
                try { using (var p = Process.GetProcessById(pid)) { if (!p.HasExited) n++; } }
                catch { }
            }
            return n;
        }
        catch { return 0; }
    }

    // ------------------------------------------------------------------ 거들기
    static bool WaitFor(Func<bool> cond, int ms)
    {
        var until = Environment.TickCount + ms;
        while (Environment.TickCount < until)
        {
            if (cond()) return true;
            Thread.Sleep(500);
        }
        return cond();
    }

    static long Lines()
    {
        try
        {
            var p = Path.Combine(BspAgent.StateDir, "runlog.jsonl");
            return File.Exists(p) ? new FileInfo(p).Length : 0;
        }
        catch { return 0; }
    }
}
