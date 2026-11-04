$ErrorActionPreference = "Stop"
$out = "C:\project\notenest\deck\build\render"
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory $out | Out-Null
$app = New-Object -ComObject PowerPoint.Application
$pres = $app.Presentations.Open("C:\project\notenest\deck\NoteNest_Presentation.pptx", $true, $false, $false)
$pres.Export($out, "PNG", 1920, 1080)
$pres.SaveAs("C:\project\notenest\deck\build\NoteNest_Presentation.pdf", 32)
"slides: " + $pres.Slides.Count
foreach ($s in $pres.Slides) { "slide " + $s.SlideIndex + " transition effect " + $s.SlideShowTransition.EntryEffect }
$pres.Close()
$app.Quit()
