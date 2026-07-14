return [=[<!doctype html>
<html><head><style>body { background-color:#101010 }</style></head><body>
<div id="page0">
<span id="Label1" style="position:absolute; left:4px; top:3px; font-size:12pt; color:#FFFFFF; font-family:AIDA Noto Sans SC; font-weight: bold; font-style: italic; text-decoration: underline line-through; text-shadow: 2px 2px 1px #112233">RemoteSensor&nbsp;Probe</span>
<div style="position:absolute; left:294px; top:3px"><img width=16 height=16 src="probe.png"></div>
<div id="SI3" style="position:absolute; left:4px; top:25px; width:150px; height:35px"><div style="float:left; font-size:11pt; color:#FFFFFF">CPU</div><div id="SIV3" style="position:absolute; left:62px; font-size:11pt; color:#00FFFF">0</div><div style="position:absolute; right:0px; font-size:11pt; color:#FFFFFF">%</div><div id="Bar3bg" style="position:absolute; left:0px; top:22px; width:145px; height:10px; background:linear-gradient(#202020,#151515)"><span id="Bar3fg" style="display:block; width:0%; height:10px; background:linear-gradient(#00FF00,#00AA00)"></span></div></div>
<canvas id="Gph4" width="96px" height="54px" style="position:absolute; left:4px; top:70px"></canvas>
<canvas id="Gph5" width="96px" height="54px" style="position:absolute; left:108px; top:70px"></canvas>
<canvas id="Gph6" width="96px" height="54px" style="position:absolute; left:212px; top:70px"></canvas>
<canvas id="Arc7" width="88px" height="88px" style="position:absolute; left:116px; top:137px"></canvas>
</div>
<div id="page1" style="visibility:hidden">
<span id="Label10" style="position:absolute; left:8px; top:8px; font-size:14pt; color:#00FFFF; font-family:Arial">PAGE TWO</span>
<span style="position:absolute; left:8px; top:40px"><span id="Simple11" style="font-size:18pt; color:#FFFFFF; font-family:Arial">CPU Temp 0C</span></span>
</div>
<script>
var gpharray4=[]; var gphgridofs4=8; if (gpharray4.length > 49) gpharray4.shift();
var gpharray5=[]; var gphgridofs5=8; if (gpharray5.length > 49) gpharray5.shift();
var gpharray6=[]; var gphgridofs6=8; if (gpharray6.length > 49) gpharray6.shift();
DrawGraph("Gph4",gpharray4,gphgridofs4,"LG",1,1,10,0,100,0,0,1,"#000000",1,"#808080",1,"#404040","#00FFFF",1,"Tahoma","#FFFFFF","8pt","normal","normal","normal",0);
DrawGraph("Gph5",gpharray5,gphgridofs5,"AG",1,1,10,0,100,1,0,1,"#000000",1,"#808080",1,"#404040","#0080FF",1,"Tahoma","#FFFFFF","8pt","normal","normal","bold",1);
DrawGraph("Gph6",gpharray6,gphgridofs6,"HG",1,2,10,0,100,0,0,1,"#000000",1,"#808080",1,"#404040","#FF00FF",0,"Tahoma","#FFFFFF","8pt","normal","normal","normal",0);
DrawArcGauge("Arc7",10,-90,0,"#202020","#00FF00",1,"#000000",1,"0","Tahoma","#FFFFFF","12pt","normal","normal","bold");
</script></body></html>]=]
