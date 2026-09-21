// 최소 도구 한 개 — 이 SDK 가 요구하는 전부가 이 파일 안에 있다.
//
//   · BSP.Contracts 하나만 참조한다 (플랫폼을 참조하지 않는다)
//   · .addin 을 만들지 않는다. 리본 탭도 만들지 않는다
//   · Transaction · ExternalEvent · try/catch · 파일 경로가 한 번도 안 나온다
//       → 그 넷은 전부 플랫폼이 준다. 도구는 «할 일» 만 쓴다
//
//   빌드 :  .\build.ps1
//   검사 :  ..\..\bin\bsp-verify.exe .\bin --id bsp.sample.hello --version 1.0.0 --target 2024
using System;
using System.Collections.Generic;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Autodesk.Revit.UI;
using BSP.Contracts;

namespace BSP.Sample
{
    public class HelloTool : IBspTool, IBspGuide
    {
        // ── 어디에 어떻게 놓일 것인가 ────────────────────────────────
        public string Product { get { return "샘플"; } }
        public string Group { get { return "10 확인"; } }   // 앞 숫자는 정렬용 (화면에 안 보인다)
        public string Name { get { return "인사\n하기"; } }  // \n 으로 두 줄
        public string Tip { get { return "플랫폼이 도구를 제대로 싣는지 확인합니다"; } }
        public string Help { get { return null; } }
        public bool Pinned { get { return false; } }

        public ImageSource Icon(int px)
        {
            // 아이콘은 코드로 그려도 되고 리소스를 써도 된다. 16 / 32 / 34 로 불린다.
            var dv = new DrawingVisual();
            using (var dc = dv.RenderOpen())
            {
                dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromRgb(0xFF, 0x78, 0x08)),
                                        null, new System.Windows.Rect(0, 0, px, px), px * 0.2, px * 0.2);
            }
            var rtb = new RenderTargetBitmap(px, px, 96, 96, PixelFormats.Pbgra32);
            rtb.Render(dv);
            rtb.Freeze();
            return rtb;
        }

        // ── 할 일 ────────────────────────────────────────────────────
        public Result Run(UIApplication app)
        {
            var doc = app.ActiveUIDocument != null ? app.ActiveUIDocument.Document : null;
            TaskDialog.Show("샘플",
                "플랫폼이 이 도구를 실었습니다.\n\n" +
                "리빗 : " + app.Application.VersionNumber + "\n" +
                "문서 : " + (doc == null ? "(열린 문서 없음)" : doc.Title));
            return Result.Succeeded;
            // 예외를 잡지 않는다. 잡으면 사고가 기록되지 않는다 — 깔때기가 잡아 기록한다.
        }

        // ── 안내 (선택) — 툴팁·F1·설명서가 여기서 나온다 ──────────────
        public Guide Guide
        {
            get
            {
                return new Guide
                {
                    Purpose = "배포와 로드가 정상인지 확인한다",
                    When = "새 PC 에 플랫폼을 깐 직후",
                    Needs = "없음. 문서가 없어도 된다",
                    Steps = new List<string> { "버튼을 누른다", "뜬 창의 내용을 확인한다" },
                    Result = "리빗 연도와 문서 이름이 보이면 정상이다",
                    Notes = new List<string> { "모델을 건드리지 않는다 (needsModel = false)" },
                };
            }
        }
    }
}
