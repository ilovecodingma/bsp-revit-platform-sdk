// BSP 플랫폼 — 스토어 화면 (MVP)
//
//   **HTS 가 곧 우리 스토어다.** 그래서 화면은 HTS 도구상자에서 크게 벗어나지 않는다 —
//   같은 팔레트, 같은 뼈대(검색 상자 → 목록 → 개수). 탭 컨트롤 같은 낯선 요소는 쓰지 않고,
//   플레이스토어의 «둘러보기 / 내 앱 / 업데이트» 는 **작은 글자 필터**로만 얹는다.
//
//   HTS 팔레트 (실측) : 바탕 #2E333A · 머리 #1D2127 · 칸 #3A3F48 · 선 #474D57
//                       글자 #D7DBE1 · 흐림 #868E99 · 더흐림 #5E6671 · 강조 #FF7808
//
//   화면은 **판정하지 않는다.** store.json 이 이미 정해 준 action 으로 버튼 글자만 고른다.
//   (SPEC\STORE-UI.md)
//
//   읽기 : %AppData%\BSP\Platform\store.json
//   쓰기 : BspAgent.Install / SyncAll  (백그라운드 스레드에서 — UI 를 붙잡지 않는다)
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Autodesk.Revit.UI;
using BSP.Platform.Agent;
using WTextBox = System.Windows.Controls.TextBox;   // 리빗에도 TextBox 가 있다 — 별칭으로 가른다

namespace BSP.Platform.Entry
{
    /// <summary>store.json 한 줄 = 프로그램 하나 (HTS 가 «프로그램» 이라고 부르는 단위).</summary>
    internal class StoreItem
    {
        public string Id = "", Name = "", Publisher = "", Latest = "", Installed = "",
                      Action = "", Status = "", Shows = "";
        public int ToolCount;
        public List<string> Tools = new List<string>();
    }

    internal class StorePane : UserControl, IDockablePaneProvider
    {
        /// <summary>리빗이 패널을 만들 때 부른다 — 첫 자리만 정해 주고 나머지는 사용자가 옮긴다.</summary>
        public void SetupDockablePane(DockablePaneProviderData data)
        {
            data.FrameworkElement = this;
            data.InitialState = new DockablePaneState
            {
                DockPosition = DockPosition.Tabbed,
                TabBehind = DockablePanes.BuiltInDockablePanes.ProjectBrowser,
            };
        }

        // HTS 도구상자와 같은 색을 쓴다 (다른 색을 쓰면 남의 화면처럼 보인다)
        internal static readonly Brush Bg = F("#2E333A"), Head = F("#1D2127"), Field = F("#3A3F48"),
                                       Line = F("#474D57"), Text = F("#D7DBE1"), Dim = F("#868E99"),
                                       Faint = F("#5E6671"), Accent = F("#FF7808"), Hover = F("#3A3F48");

        readonly WTextBox _search = new WTextBox();
        readonly StackPanel _list = new StackPanel();
        readonly TextBlock _count = new TextBlock();
        readonly StackPanel _filters = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(10, 0, 10, 6) };

        string _mode = "all";              // all · installed · update

        public StorePane()
        {
            Background = Bg;
            var root = new DockPanel();

            var head = new StackPanel { Background = Head };
            // HTS 가 쓰는 말을 그대로 쓴다 — 제품이 아니라 «프로그램», 실행 서랍은 «도구상자»
            head.Children.Add(new TextBlock
            {
                Text = "설치할 프로그램을 고르는 곳입니다.  도구는 도구상자에서 ★ 로 리본에 올립니다.",
                Foreground = Faint, FontSize = 11, TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(10, 8, 10, 0),
            });
            head.Children.Add(SearchBox());
            head.Children.Add(_filters);
            head.Children.Add(_count);
            DockPanel.SetDock(head, Dock.Top);
            root.Children.Add(head);

            root.Children.Add(new ScrollViewer
            {
                Content = _list,
                Background = Bg,
                BorderThickness = new Thickness(0),
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            });

            Content = root;
            Reload();
        }

        UIElement SearchBox()
        {
            _search.Background = Field;
            _search.Foreground = Text;
            _search.BorderBrush = Line;
            _search.Margin = new Thickness(8, 8, 8, 6);
            _search.Padding = new Thickness(6, 4, 6, 4);
            _search.TextChanged += (s, e) => Reload();

            _count.Foreground = Dim;
            _count.Margin = new Thickness(10, 0, 10, 8);
            _count.FontSize = 11;
            return _search;
        }

        /// <summary>탭이 아니라 «작은 글자» 다 — HTS 화면의 결을 유지한다.
        /// (net48 컴파일러는 로컬 함수를 못 쓴다. 그래서 작은 메서드로 나눈다.)</summary>
        void Filters(int all, int installed, int updates)
        {
            _filters.Children.Clear();
            AddFilter("전체", "all", all);
            AddFilter("설치됨", "installed", installed);
            AddFilter("업데이트", "update", updates);
            if (updates > 0)
            {
                var b = Link("모두 업데이트", Accent);
                b.Margin = new Thickness(14, 0, 0, 0);
                b.MouseLeftButtonUp += (s, e) => UpdateAll();
                _filters.Children.Add(b);
            }
        }

        void AddFilter(string label, string mode, int n)
        {
            var t = Link(label + (n > 0 ? " " + n : ""), _mode == mode ? Text : Faint);
            if (_mode == mode) t.FontWeight = FontWeights.Bold;
            t.Margin = new Thickness(0, 0, 12, 0);
            var m = mode;
            t.MouseLeftButtonUp += (s, e) => { _mode = m; Reload(); };
            _filters.Children.Add(t);
        }

        static TextBlock Link(string text, Brush color)
        {
            return new TextBlock { Text = text, Foreground = color, FontSize = 11, Cursor = Cursors.Hand };
        }

        // ── 목록 ────────────────────────────────────────────────────────────
        public void Reload()
        {
            _list.Children.Clear();
            var items = Read();
            int tools = 0, upd = 0, mine = 0;
            foreach (var it in items)
            {
                tools += it.ToolCount;
                if (it.Installed.Length > 0) mine++;
                if (it.Action == "update") upd++;
            }
            Filters(items.Count, mine, upd);

            var q = _search.Text.Trim();
            int shown = 0;
            foreach (var it in items)
            {
                if (_mode == "installed" && it.Installed.Length == 0) continue;
                if (_mode == "update" && it.Action != "update") continue;
                if (!Match(it, q)) continue;
                _list.Children.Add(Row(it));
                shown++;
            }

            if (items.Count == 0)
                _list.Children.Add(Note("목록이 아직 없습니다 — 매니저가 서버에서 받아오면 채워집니다"));
            else if (shown == 0)
                _list.Children.Add(Note("해당하는 것이 없습니다"));

            _count.Text = string.Format("{0} / {1} 프로그램 · 도구 {2}개{3}",
                                        shown, items.Count, tools, upd > 0 ? " · 업데이트 " + upd + "건" : "");
        }

        static TextBlock Note(string s)
        {
            return new TextBlock { Text = s, Foreground = Dim, FontSize = 11, Margin = new Thickness(14, 12, 10, 0), TextWrapping = TextWrapping.Wrap };
        }

        static bool Match(StoreItem it, string q)
        {
            if (q.Length == 0) return true;
            Func<string, bool> has = s => (s ?? "").IndexOf(q, StringComparison.CurrentCultureIgnoreCase) >= 0;
            if (has(it.Name) || has(it.Publisher) || has(it.Id) || has(it.Shows)) return true;
            foreach (var t in it.Tools) if (has(t)) return true;     // 담긴 도구 이름으로도 찾는다
            return false;
        }

        /// <summary>한 줄 = 프로그램 하나. HTS 도구상자의 줄 모양을 그대로 쓴다
        /// (왼쪽 제품 색 점 · 이름 · 아래 흐린 한 줄 · 오른쪽 동작 글자).</summary>
        UIElement Row(StoreItem it)
        {
            var wrap = new StackPanel { Margin = new Thickness(6, 2, 6, 2), Background = Brushes.Transparent };

            var row = new DockPanel { Margin = new Thickness(4, 4, 4, 2) };

            var act = Action(it);
            DockPanel.SetDock(act, Dock.Right);
            row.Children.Add(act);

            row.Children.Add(new Border
            {
                Width = 10, Height = 10, CornerRadius = new CornerRadius(5),
                Background = Tint(it.Id),
                Margin = new Thickness(2, 0, 8, 0),
                VerticalAlignment = VerticalAlignment.Center,
            });

            row.Children.Add(new TextBlock
            {
                Text = it.Name.Length > 0 ? it.Name : it.Id,
                Foreground = Text, VerticalAlignment = VerticalAlignment.Center,
            });
            wrap.Children.Add(row);

            var sub = (it.Publisher.Length > 0 ? it.Publisher + "  ·  " : "") +
                      (it.Installed.Length > 0 ? it.Installed : "미설치") +
                      (it.Installed.Length > 0 && it.Installed != it.Latest ? " → " + it.Latest : "") +
                      (it.ToolCount > 0 ? "  ·  도구 " + it.ToolCount + "개" : "");
            wrap.Children.Add(new TextBlock
            {
                Text = sub, Foreground = Dim, FontSize = 11, Margin = new Thickness(24, 0, 0, 2),
            });

            if (it.Status.Length > 0 && it.Action != "ok")
                wrap.Children.Add(new TextBlock
                {
                    Text = it.Status, Foreground = Faint, FontSize = 11,
                    Margin = new Thickness(24, 0, 0, 2), TextWrapping = TextWrapping.Wrap,
                });

            // 담긴 도구는 접어 둔다 — 30개가 한 번에 쏟아지면 못 읽는다
            if (it.Tools.Count > 0)
            {
                var ex = new Expander
                {
                    Header = "담긴 도구 " + it.Tools.Count + "개",
                    Foreground = Faint, FontSize = 11, Margin = new Thickness(24, 0, 0, 2),
                };
                var inner = new StackPanel();
                foreach (var t in it.Tools)
                    inner.Children.Add(new TextBlock { Text = "· " + t, Foreground = Faint, FontSize = 11, Margin = new Thickness(6, 1, 0, 1) });
                ex.Content = inner;
                wrap.Children.Add(ex);
            }

            wrap.Children.Add(new Border { Height = 1, Background = Line, Margin = new Thickness(0, 4, 0, 0), Opacity = 0.5 });
            wrap.MouseEnter += (s, e) => wrap.Background = Hover;
            wrap.MouseLeave += (s, e) => wrap.Background = Brushes.Transparent;
            return wrap;
        }

        /// <summary>오른쪽 동작 — 버튼 상자 대신 글자 하나. HTS 화면에 버튼이 거의 없다.</summary>
        UIElement Action(StoreItem it)
        {
            string label; Brush color; bool can;
            switch (it.Action)
            {
                case "install": label = "받기"; color = Accent; can = true; break;
                case "update": label = "업데이트"; color = Accent; can = true; break;
                case "pending": label = "다음 기동에 적용"; color = Dim; can = false; break;
                case "blocked": label = "사용 불가"; color = Faint; can = false; break;
                default: label = "최신"; color = Faint; can = false; break;
            }
            var t = Link(label, color);
            t.Margin = new Thickness(8, 0, 4, 0);
            t.VerticalAlignment = VerticalAlignment.Center;
            if (can)
            {
                var id = it.Id; var name = it.Name;
                t.MouseLeftButtonUp += (s, e) => Work(() => BspAgent.Install(id, 120000), name);
            }
            else t.Cursor = Cursors.Arrow;
            return t;
        }

        /// <summary>프로그램마다 같은 색이 나오게 이름에서 계산한다 (HTS 가 제품 색을 쓰는 방식).</summary>
        static Brush Tint(string id)
        {
            int h = 0;
            foreach (var ch in id ?? "") h = unchecked(h * 31 + ch);
            var hue = Math.Abs(h % 360) / 60.0;
            int i = (int)hue % 6; double f = hue - Math.Floor(hue);
            byte v = 235, p = 110, q = (byte)(235 - (235 - 110) * f), w = (byte)(110 + (235 - 110) * f);
            Color c;
            switch (i)
            {
                case 0: c = Color.FromRgb(v, w, p); break;
                case 1: c = Color.FromRgb(q, v, p); break;
                case 2: c = Color.FromRgb(p, v, w); break;
                case 3: c = Color.FromRgb(p, q, v); break;
                case 4: c = Color.FromRgb(w, p, v); break;
                default: c = Color.FromRgb(v, p, q); break;
            }
            var b = new SolidColorBrush(c); b.Freeze(); return b;
        }

        void UpdateAll()
        {
            var ids = new List<string>();
            foreach (var it in Read()) if (it.Action == "update") ids.Add(it.Id);
            if (ids.Count == 0) return;
            Work(() =>
            {
                Answer last = null;
                foreach (var id in ids) last = BspAgent.Install(id, 120000);   // 하나씩 — 동시에 받으면 큐가 엉킨다
                return last ?? new Answer { Ok = true, Status = "할 일 없음" };
            }, ids.Count + "건 업데이트");
        }

        /// <summary>**UI 스레드에서 받지 않는다.** 리빗이 멈춘 것처럼 보인다.</summary>
        void Work(Func<Answer> job, string what)
        {
            _count.Text = what + " … 진행 중";
            var th = new Thread(() =>
            {
                Answer a;
                try { a = job(); }
                catch (Exception ex) { a = new Answer { Status = "실패", Message = ex.Message }; }
                Dispatcher.Invoke(new Action(() =>
                {
                    Reload();
                    _count.Text = a.Status + (a.Pending ? "  —  리빗을 껐다 켜면 적용됩니다" : "") +
                                  (a.Message.Length > 0 ? "  ·  " + a.Message : "");
                }));
            });
            th.IsBackground = true;
            th.Start();
        }

        // ── store.json 읽기 (JSON 라이브러리를 끌어오지 않는다) ──────────────
        internal static List<StoreItem> Read()
        {
            var outp = new List<StoreItem>();
            try
            {
                var p = Path.Combine(BspAgent.StateDir, "store.json");
                if (!File.Exists(p)) return outp;
                var t = File.ReadAllText(p, Encoding.UTF8);

                int i = t.IndexOf("\"products\"", StringComparison.Ordinal);
                if (i < 0) return outp;
                int depth = 0, start = -1;
                for (; i < t.Length; i++)
                {
                    if (t[i] == '{')
                    {
                        if (depth == 0) start = i;
                        depth++;
                    }
                    else if (t[i] == '}')
                    {
                        depth--;
                        if (depth == 0 && start >= 0)
                        {
                            var one = t.Substring(start, i - start + 1);
                            if (one.IndexOf("\"action\"", StringComparison.Ordinal) >= 0) outp.Add(Parse(one));
                            start = -1;
                        }
                    }
                }
            }
            catch { }
            return outp;
        }

        static StoreItem Parse(string o)
        {
            var it = new StoreItem
            {
                Id = S(o, "id"),
                Name = S(o, "name"),
                Publisher = S(o, "publisher"),
                Latest = S(o, "latest"),
                Installed = S(o, "installed"),
                Action = S(o, "action"),
                Status = S(o, "status"),
            };
            int n; int.TryParse(S(o, "toolCount"), out n); it.ToolCount = n;

            int at = o.IndexOf("\"tools\"", StringComparison.Ordinal);
            if (at >= 0)
            {
                var seg = o.Substring(at);
                int pos = 0;
                while (true)
                {
                    int k = seg.IndexOf("\"name\"", pos, StringComparison.Ordinal);
                    if (k < 0) break;
                    var v = S(seg.Substring(k, Math.Min(240, seg.Length - k)), "name");
                    if (v.Length > 0) it.Tools.Add(v.Replace("\\n", " ").Replace("\n", " "));
                    pos = k + 6;
                }
            }
            var shows = new StringBuilder();
            int sa = o.IndexOf("\"shows\"", StringComparison.Ordinal);
            if (sa >= 0)
            {
                int e = o.IndexOf(']', sa);
                if (e > sa) shows.Append(o.Substring(sa, e - sa).Replace("\"shows\"", "").Replace("[", "").Replace("\"", "").Replace(":", ""));
            }
            it.Shows = shows.ToString().Trim();
            return it;
        }

        static string S(string json, string key)
        {
            var k = "\"" + key + "\"";
            int i = json.IndexOf(k, StringComparison.Ordinal);
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
            int j = i;
            while (j < json.Length && json[j] != ',' && json[j] != '}' && json[j] != ']') j++;
            return json.Substring(i, j - i).Trim();
        }

        static Brush F(string hex)
        {
            var b = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));
            b.Freeze();
            return b;
        }
    }
}
