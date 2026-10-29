<!DOCTYPE html>
<html>
<head>
<title><#Web_Title#> - <#menu5_6_1#></title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<meta http-equiv="Pragma" content="no-cache">
<meta http-equiv="Expires" content="-1">

<link rel="shortcut icon" href="images/favicon.ico">
<link rel="icon" href="images/favicon.png">
<link rel="stylesheet" type="text/css" href="/bootstrap/css/bootstrap.min.css">
<link rel="stylesheet" type="text/css" href="/bootstrap/css/main.css">

<script type="text/javascript" src="/jquery.js"></script>
<script type="text/javascript" src="/state.js"></script>
<script type="text/javascript" src="/general.js"></script>
<script type="text/javascript" src="/popup.js"></script>
<script>
var $j = jQuery.noConflict();
var modeSubmitting = false;
var modeTarget = "";
var modeAcknowledged = false;
var modeSubmitTimer = null;

function showModeStatus(message, offerRouterLink){
	var loading = document.getElementById("Loading");
	if (loading) loading.style.display = "none";
	document.getElementById("modeSwitchStatus").style.display = "block";
	document.getElementById("modeSwitchMessage").textContent = message;
	var link = document.getElementById("modeSwitchLink");
	link.style.display = "none";
	if (offerRouterLink) {
		var address = document.form.lan_ipaddr.value;
		if (/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/.test(address)) {
			link.href = location.protocol + "//" + address + (location.port ? ":" + location.port : "") + "/";
			link.textContent = "尝试打开 " + address;
			link.style.display = "inline";
		}
	}
}

function modeSwitchCommitted(seconds){
	if (!modeSubmitting || modeAcknowledged) return;
	modeAcknowledged = true;
	clearTimeout(modeSubmitTimer);
	seconds = Number(seconds);
	if (!isFinite(seconds) || seconds <= 0 || seconds > 600) {
		showModeStatus("已收到保存响应，但未取得有效的重启等待时间。请勿重复保存；请刷新并核对实际模式，必要时手动重启。", false);
		return;
	}
	// 重启估计时间不代表终端已经完成 DHCP；先留出自动获取地址的观察窗口。
	var started = Date.now();
	var rebootSeconds = Math.ceil(seconds);
	var addressSeconds = Math.max(rebootSeconds, 120);
	function tick(){
		var elapsed = Math.floor((Date.now() - started) / 1000);
		var remaining = rebootSeconds - elapsed;
		if (remaining > 0) {
			showModeStatus("已提交保存和重启请求，预计还需 " + remaining + " 秒。期间连接会暂时中断，请勿重复操作。", false);
			setTimeout(tick, 1000);
			return;
		}
		if (elapsed < addressSeconds) {
			var addressHint = modeTarget == "3"
				? "AP 的管理地址可能由上级重新分配，请到上级路由器的设备列表查找。"
				: "取得独立 LAN 网段地址后，可使用下方入口访问。";
			showModeStatus("重启预计等待阶段已结束，终端可能仍在自动获取新地址。请先等待，无需立即手动续租或重复切换。" + addressHint + " 本页尚未确认设备及地址是否就绪。", modeTarget != "3");
			setTimeout(tick, 1000);
			return;
		}
		if (modeTarget == "3")
			showModeStatus("自动获取地址的观察时间已到，本页无法确认网络是否恢复。请先查看终端当前地址，并到上级的已连接设备列表查找 AP 管理地址；若 AP 使用静态地址，请使用该静态地址。只有仍保留旧网段或没有地址时，再尝试重连网络或手动续租。本页不会自动跳回旧路由地址。", false);
		else
			showModeStatus("自动获取地址的观察时间已到，本页无法确认网络是否恢复。若终端已取得独立 LAN 网段地址，请打开下方管理地址；只有仍保留旧网段或没有地址时，再尝试重连网络或手动续租，并检查设备是否完成重启。本页不会重复提交切换。", true);
	}
	tick();
}

function initial(){
	show_banner(2);
	show_menu(5,7,3);
	show_footer();

	if(sw_mode == '1' || sw_mode == '3'){
		showhide_div('wl_rt', 1);
		showhide_div('rt_wo_nat', 0);
	}else if(sw_mode == '4'){
		showhide_div('wl_rt', 0);
		showhide_div('rt_wo_nat', 1);
	}

	setScenerion(sw_mode);

	var o1 = document.form.sw_mode;
	var vd = support_btn_mode();
	o1[0].disabled = vd;
	o1[1].disabled = vd;
	o1[2].disabled = vd;
	document.form.button.disabled = vd;
}

function saveMode(){
	if (modeSubmitting) return false;
	var o1 = document.form.sw_mode;
	if(sw_mode == '1'){
		if(o1[0].checked == true){
			alert("<#op_already_configured#>");
			return false;
		}
	}else if(sw_mode == '4'){
		if(o1[1].checked == true){
			alert("<#op_already_configured#>");
			return false;
		}
	}else if(sw_mode == '3'){
		if(o1[2].checked == true){
			alert("<#op_already_configured#>");
			return false;
		}
	}

	var selected = "";
	for (var i = 0; i < o1.length; i++) if (o1[i].checked) selected = o1[i].value;
	if (!selected) return false;
	var details = selected == "3"
		? "切换为 AP 后，将停止路由器的 NAT、DHCP 和现有 DNS 接管，AdGuardHome 可能停止。终端将使用上级网络，管理地址可能由上级重新分配。"
		: "切换为路由器后，恢复独立 LAN 网段和相应路由服务。终端需要重新获取地址，请使用设置的 LAN 管理地址重新访问。";
	if (!confirm(details + "\n\n确认保存并立即重启路由器 吗？重启期间连接会暂时中断；取消则不保存。")) {
		for (var j = 0; j < o1.length; j++) o1[j].checked = o1[j].value == sw_mode;
		setScenerion(sw_mode);
		return false;
	}
	modeSubmitting = true;
	modeTarget = selected;
	modeSubmitTimer = setTimeout(function(){
		if (!modeAcknowledged)
			showModeStatus("尚未收到保存响应，设备可能已在重启或连接已中断。请勿重复保存；请重新获取地址后检查设备，再决定是否重试。", false);
	}, 30000);
	document.form.button.disabled = true;
	showLoading();

	document.form.action_mode.value = " Apply ";
	document.form.current_page.value = "Advanced_OperationMode_Content.asp";
	document.form.next_page.value = "";

	document.form.submit();
}

function done_validating(action){
	refreshpage();
}

function setScenerion(mode){
	if(mode == '1' || mode == '4'){
		$j("#radio2").hide();
		$j("#Internet_span").css("display", "");
		$j("#ap-line").css("display", "none");
		$j(".AP").hide();
		$j("#mode_desc").html("<#OP_GW_desc1#> <#OP_GW_desc2#>");
		$j("#nextButton").attr("value","<#CTL_next#>");
	}
	else if(mode == '3'){
		$j("#radio2").css("display", "none");
		$j("#Internet_span").css("display", "");
		$j("#ap-line").css("display", "none");
		$j(".AP").show();
		$j("#mode_desc").html("<#OP_AP_desc1#> <#OP_AP_desc2#>");
		$j("#nextButton").attr("value","<#CTL_next#>");
	}
}

</script>

<style>
table {width: 100%;}
table td {text-align: center; }
</style>

</head>

<body onload="initial();" onunLoad="return unload_body();">

<div class="wrapper">
    <div class="container-fluid" style="padding-right: 0px">
        <div class="row-fluid">
            <div class="span3"><center><div id="logo"></div></center></div>
            <div class="span9" >
                <div id="TopBanner"></div>
            </div>
        </div>
    </div>

    <div id="Loading" class="popup_bg"></div>

    <iframe name="hidden_frame" id="hidden_frame" src="" width="0" height="0" frameborder="0"></iframe>

    <form method="post" name="form" id="ruleForm" action="/start_apply.htm" target="hidden_frame">
    <input type="hidden" name="sid_list" value="IPConnection;">
    <input type="hidden" name="group_id" value="">
    <input type="hidden" name="action_mode" value="">
    <input type="hidden" name="prev_page" value="">
    <input type="hidden" name="current_page" value="/Advanced_OperationMode_Content.asp">
    <input type="hidden" name="next_page" value="">
    <input type="hidden" name="flag" value="">
    <input type="hidden" name="lan_ipaddr" value="<% nvram_get_x("", "lan_ipaddr"); %>">

    <div class="container-fluid">
        <div class="row-fluid">
            <div class="span3">
                <!--Sidebar content-->
                <!--=====Beginning of Main Menu=====-->
                <div class="well sidebar-nav side_nav" style="padding: 0px;">
                    <ul id="mainMenu" class="clearfix"></ul>
                    <ul class="clearfix">
                        <li>
                            <div id="subMenu" class="accordion"></div>
                        </li>
                    </ul>
                </div>
            </div>

            <div class="span9">
                <!--Body content-->
                <div class="row-fluid">
                    <div class="span12">
                        <div class="box well grad_colour_dark_blue">
                            <h2 class="box_head round_top"><#menu5_6#> - <#t2OP#></h2>
                            <div class="round_bottom">
                                <div class="row-fluid">
                                    <div id="tabMenu" class="submenuBlock"></div>
                                    <div id="modeSwitchStatus" class="alert alert-info" role="status" aria-live="polite" style="display:none; margin:10px;">
                                        <p id="modeSwitchMessage"></p>
                                        <a id="modeSwitchLink" style="display:none;"></a>
                                    </div>
                                        <div style="margin-left: 10px; margin-top: 10px;">
                                            <div class="controls">
                                                <label class="radio inline"><div id="wl_rt" style="display:none;"><input type="radio" name="sw_mode" class="input" value="1" onclick="setScenerion(1);" <% nvram_match_x("IPConnection", "sw_mode", "1", "checked"); %>><#OP_GW_item#></div></label>
                                                <label class="radio inline"><div id="rt_wo_nat" style="display:none;"><input type="radio" name="sw_mode" class="input" value="4" onclick="setScenerion(4);" <% nvram_match_x("IPConnection", "sw_mode", "4", "checked"); %>><#OP_GW_item#></div></label>
                                                <label class="radio inline"><div id="wl_ap"><input type="radio" name="sw_mode" class="input" value="3" onclick="setScenerion(3);" <% nvram_match_x("IPConnection", "sw_mode", "3", "checked"); %>><#OP_AP_item#></div></label>
                                            </div>

                                            <div id="mode_desc" style="margin-left: 0px; margin-top: 10px; margin-right: 10px;" class="alert alert-info"><#OP_GW_desc1#></div>
                                        </div>

                                        <div style="margin-top: 10px; margin-right: 10px; margin-left: 10px;">
                                            <center><div id="Senario" class="span12" style="height: 170px;">
                                                <div class="row-fluid">
                                                    <table style="width: 100%">
                                                        <tr>
                                                            <td><span class="label"><#Wireless_Clients#></span></td>
                                                            <td>&nbsp;</td>
                                                            <td><span class="label label-info"><#Web_Title#></span></td>
                                                            <td class="AP">&nbsp;</td>
                                                            <td class="AP"><span class="label"><#Device_type_02_RT#></span></td>
                                                            <td>&nbsp;</td>
                                                            <td id="Internet_span"><span class="label"><#Internet#></span></td>
                                                        </tr>
                                                        <tr>
                                                            <td><img src="bootstrap/img/wl_device/clients.png"></td>
                                                            <td><img src="bootstrap/img/wl_device/arrow-left.png"></td>
                                                            <td><img src="bootstrap/img/wl_device/n56u.png"></td>
                                                            <td class="AP"><img src="bootstrap/img/wl_device/arrow-left.png"></td>
                                                            <td class="AP"><img src="bootstrap/img/wl_device/server.png"></td>
                                                            <td><img src="bootstrap/img/wl_device/arrow-left.png"></td>
                                                            <td><img src="bootstrap/img/wl_device/globe.png"></td>
                                                        </tr>
                                                    </table>
                                                </div>

                                                <div id="ap-line" style="display: none;position: absolute; margin-left: -10000px"></div>
                                            </div></center>
                                        </div>

                                        <center><input name="button" type="button" class="btn btn-primary" style="width: 219px;" onClick="saveMode();" value="<#CTL_onlysave#>"></center>
                                        <br/>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    </form>

    <div id="footer"></div>
</div>
</body>
</html>
