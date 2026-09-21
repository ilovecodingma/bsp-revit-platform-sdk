// BSP 플랫폼 — 리빗 안에서 «받기» 를 누르는 쪽 (net48)
//
//   대표님이 원하는 그림은 «리빗 안에서 목록을 보고 눌러서 받는 것» 이다.
//   그 경험은 이 파일 하나로 성립한다. 실제로 받고 검증하는 일은 밖(매니저)이 한다.
//
//     리빗 안 화면            매니저(bsp-launcher.exe)
//       Install("bsp.hts") ──▶ cmd\<티켓>.json
//                              ├ 즉시 받기 + SHA-256 검증
//                              ├ 잠기지 않은 파일은 지금 배치
//                              └ 잠긴 파일만 큐 → 리빗 종료 때
//       결과 ◀───────────────  cmd\<티켓>.done.json
//
//   왜 리빗이 직접 받지 않는가
//     · 리빗이 쥐고 있는 DLL 은 리빗 자신도 못 바꾼다 (.NET Framework 는 언로드가 없다)
//     · 회선·인증·재시도를 리빗 UI 스레드에 올리면 도면 작업이 멈춘다
//     · 그래서 «누르는 것» 은 안에서, «바꾸는 것» 은 밖에서 한다. 화면은 똑같이 보인다
using System;
using System.IO;
using System.Text;
using System.Threading;

namespace BSP.Platform.Agent
{
    /// <summary>요청 한 건의 결과.</summary>
    public class Answer
    {
        public bool Ok;
        public string Status = "";     // "설치됨" · "다음 기동에 적용 2개" · "배치 거부 — 해시 불일치 …"
        public string Message = "";
        public bool Pending;           // true 면 «리빗을 껐다 켜야 반영» — 화면에 그대로 알린다
        public override string ToString() { return Status + (Message.Length > 0 ? " · " + Message : ""); }
    }

    internal static class Requests
    {
        public static string CmdDir { get { return Path.Combine(LauncherHost.StateDir, "cmd"); } }

        /// <summary>요청을 넣고 답을 기다린다. **UI 스레드에서 부르지 않는다** — 백그라운드에서 부르고
        /// 결과만 화면에 올린다. 매니저가 죽어 있으면 먼저 깨우고 다시 기다린다.</summary>
        public static Answer Send(string op, string id, int timeoutMs)
        {
            var a = new Answer();
            try
            {
                if (!LauncherHost.Alive())
                    LauncherHost.Ensure(BspAgent.Year, BspAgent.Pid);   // 없으면 깨운다

                Directory.CreateDirectory(CmdDir);
                var ticket = DateTime.Now.ToString("yyyyMMddHHmmssfff") + "-" +
                             Guid.NewGuid().ToString("N").Substring(0, 6);
                var req = Path.Combine(CmdDir, ticket + ".json");
                var done = Path.Combine(CmdDir, ticket + ".done.json");

                File.WriteAllText(req,
                    "{\"op\":\"" + op + "\",\"id\":\"" + (id ?? "") + "\",\"at\":\"" +
                    DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss") + "\"}",
                    new UTF8Encoding(false));

                var until = Environment.TickCount + timeoutMs;
                while (Environment.TickCount < until)
                {
                    if (File.Exists(done))
                    {
                        var t = File.ReadAllText(done);
                        a.Ok = Field(t, "ok") == "true";
                        a.Status = Field(t, "status");
                        a.Message = Field(t, "msg");
                        a.Pending = a.Status.IndexOf("다음 기동", StringComparison.Ordinal) >= 0;
                        try { File.Delete(done); } catch { }
                        return a;
                    }
                    Thread.Sleep(400);
                }
                a.Status = "시간 초과";
                a.Message = "매니저가 답하지 않습니다 — 상태 : " + LauncherHost.Last;
            }
            catch (Exception ex) { a.Status = "실패"; a.Message = ex.Message; }
            return a;
        }

        // 작은 값 몇 개만 꺼내면 되므로 JSON 라이브러리를 끌어오지 않는다.
        static string Field(string json, string key)
        {
            var k = "\"" + key + "\"";
            var i = json.IndexOf(k, StringComparison.Ordinal);
            if (i < 0) return "";
            i = json.IndexOf(':', i + k.Length);
            if (i < 0) return "";
            i++;
            while (i < json.Length && (json[i] == ' ' || json[i] == '\t')) i++;
            if (i < json.Length && json[i] == '"')
            {
                var sb = new StringBuilder(); i++;
                while (i < json.Length && json[i] != '"')
                {
                    if (json[i] == '\\' && i + 1 < json.Length) i++;
                    sb.Append(json[i++]);
                }
                return sb.ToString();
            }
            var j = i;
            while (j < json.Length && json[j] != ',' && json[j] != '}') j++;
            return json.Substring(i, j - i).Trim();
        }
    }
}
