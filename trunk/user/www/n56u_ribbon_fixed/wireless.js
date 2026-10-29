var wep1, wep2, wep3, wep4;

function automode_hint() {
    var gmode = document.form.wl_gmode.value;
    if ((gmode == "2" || gmode == "3" || gmode == "4" || gmode == "5") &&
       (document.form.wl_wep_x.value == 1 || document.form.wl_wep_x.value == 2 || document.form.wl_auth_mode.value == "radius" ||
            (document.form.wl_crypto.value.indexOf("tkip") == 0 && !document.form.wl_crypto.disabled)))
        $("wl_gmode_hint").style.display = "block";
    else
        $("wl_gmode_hint").style.display = "none";
}

function nmode_limitation() {
    var gmode = document.form.wl_gmode.value;
    if (gmode == "1" || gmode == "3") {
        if (document.form.wl_auth_mode.selectedIndex == 0 && (document.form.wl_wep_x.selectedIndex == "1" || document.form.wl_wep_x.selectedIndex == "2")) {
            alert("<#WLANConfig11n_nmode_limition_hint#>");
            document.form.wl_auth_mode.selectedIndex = 0;
            document.form.wl_wep_x.selectedIndex = 0;
        }
        else if (document.form.wl_auth_mode.selectedIndex == 1) {
            alert("<#WLANConfig11n_nmode_limition_hint#>");
            document.form.wl_auth_mode.selectedIndex = 3;
            document.form.wl_wpa_mode.value = 2;
        }
        else if (document.form.wl_auth_mode.selectedIndex == 2) {
            alert("<#WLANConfig11n_nmode_limition_hint#>");
            document.form.wl_auth_mode.selectedIndex = 3;
            document.form.wl_wpa_mode.value = 2;
        }
        else if (document.form.wl_auth_mode.selectedIndex == 5) {
            alert("<#WLANConfig11n_nmode_limition_hint#>");
            document.form.wl_auth_mode.selectedIndex = 6;
        }
        else if (document.form.wl_auth_mode.selectedIndex == 7 && (document.form.wl_crypto.selectedIndex == 0 || document.form.wl_crypto.selectedIndex == 2)) {
            alert("<#WLANConfig11n_nmode_limition_hint#>");
            document.form.wl_crypto.selectedIndex = 1;
        }
        wl_auth_mode_change(0);
    }
}

function change_common_wl(o, s, v) {
    change = 1;
    pageChanged = 1;
    if (v == "wl_auth_mode") {
        wl_auth_mode_change(0);

        if (o.value == "psk" || o.value == "wpa") {
            opts = document.form.wl_auth_mode.options;

            if (opts[opts.selectedIndex].text == "WPA-Personal") {
                document.form.wl_wpa_mode.value = "1";
                automode_hint();
            }
            else if (opts[opts.selectedIndex].text == "WPA2-Personal")
                document.form.wl_wpa_mode.value = "2";
            else if (opts[opts.selectedIndex].text == "WPA-Auto-Personal")
                document.form.wl_wpa_mode.value = "0";
            else if (opts[opts.selectedIndex].text == "WPA-Enterprise")
                document.form.wl_wpa_mode.value = "3";
            else if (opts[opts.selectedIndex].text == "WPA-Auto-Enterprise")
                document.form.wl_wpa_mode.value = "4";

            if (o.value == "psk") {
                document.form.wl_wpa_psk.focus();
                document.form.wl_wpa_psk.select();
            }
        }
        else if (o.value == "shared") {
            document.form.wl_key1.focus();
            document.form.wl_key1.select();
        }
        nmode_limitation();
        automode_hint();
    }
    else if (v == "wl_crypto") {
        wl_auth_mode_change(0);
        nmode_limitation();
        automode_hint();
    }
    else if (v == "wl_wep_x") {
        change_wlweptype(o, "WLANConfig11a");
        nmode_limitation();
        automode_hint();
    }
    else if (v == "wl_key") {
        var selected_key = eval("document.form.wl_key" + o.value);

        selected_key.focus();
        selected_key.select();
    }
    else if (v == "wl_country_code") {
        insertChannelOption();
        insertExtChannelOption();
    }
    else if (v == "wl_channel") {
        insertExtChannelOption();
        wifi5UpdateHint();
    }
    else if (v == "wl_HT_BW") {
        if (wifi5PolicyEnabled()) insertChannelOption();
        insertExtChannelOption();
    }
    else if (v == "wl_gmode") {
        enableExtChRows(o);
        if (wifi5PolicyEnabled()) insertChannelOption();
        insertExtChannelOption();
        nmode_limitation();
        automode_hint();
    }
    else if (v == "wl_guest_auth_mode_1")
    {
        wl_auth_mode_change_guest(0);
        if (o.value == "psk") {
            document.form.wl_guest_wpa_psk_1.focus();
            document.form.wl_guest_wpa_psk_1.select();
        }
        else if (o.value == "shared" || o.value == "radius") {
            document.form.wl_guest_phrase_x_1.focus();
            document.form.wl_guest_phrase_x_1.select();
        }
    }
    else if (v == "wl_guest_wep_x_1")
    {
        change_wlweptype_guest(o, "WLANConfig11a");
    }
    else if (v == "wl_guest_crypto_1") {
        wl_auth_mode_change_guest(0);
    }

    return true;
}

function change_wlweptype(o, s, isload) {
    var wflag;
        var wep = "";
    if (o.value == "0") {
        wflag = 0;

        document.form.wl_key1.value = wep;
        document.form.wl_key2.value = wep;
        document.form.wl_key3.value = wep;
        document.form.wl_key4.value = wep;
    }
    else {
        wflag = 1;

        if (document.form.wl_phrase_x.value.length > 0 && isload == 0)
            is_wlphrase("WLANConfig11a", "wl_phrase_x", document.form.wl_phrase_x);
    }

    inputCtrl(document.form.wl_phrase_x, wflag);
    inputCtrl(document.form.wl_key1, wflag);
    inputCtrl(document.form.wl_key2, wflag);
    inputCtrl(document.form.wl_key3, wflag);
    inputCtrl(document.form.wl_key4, wflag);
    inputCtrl(document.form.wl_key, wflag);

    wl_wep_change();
}

function change_wlkey(o, s) {
    var wep;
    if (document.form.current_page.value == "Advanced_WirelessGuest_Content.asp")
        wep = document.form.wl_guest_wep_x_1.value;
    else
        wep = document.form.wl_wep_x.value;

    if (wep == "1") {
        if (o.value.length > 10)
            o.value = o.value.substring(0, 10);
    }
    else if (wep == "2") {
        if (o.value.length > 26)
            o.value = o.value.substring(0, 26);
    }

    return true;
}

function changeWEPType() {
    var wflag;
    if (document.form.wl_wep.value == "0") {
        wflag = 0;
    }
    else {
        wflag = 1;
    }
    inputCtrl(document.form.wl_phrase_x, wflag);
    inputCtrl(document.form.wl_key1, wflag);
    inputCtrl(document.form.wl_key2, wflag);
    inputCtrl(document.form.wl_key3, wflag);
    inputCtrl(document.form.wl_key4, wflag);
    inputCtrl(document.form.wl_key, wflag);
}

function changeAuthType() {
    if (document.form.wl_auth_mode.value == "shared") {
        inputCtrl(document.form.wl_crypto, 0);
        inputCtrl(document.form.wl_wpa_psk, 0);
        inputCtrl(document.form.wl_wep, 1);
        inputCtrl(document.form.wl_phrase_x, 1);
        inputCtrl(document.form.wl_key1, 1);
        inputCtrl(document.form.wl_key2, 1);
        inputCtrl(document.form.wl_key3, 1);
        inputCtrl(document.form.wl_key4, 1);
        inputCtrl(document.form.wl_key, 1);
        inputCtrl(document.form.wl_wpa_gtk_rekey, 0);
    }
    else if (document.form.wl_auth_mode.value == "psk") {
        inputCtrl(document.form.wl_crypto, 1);
        inputCtrl(document.form.wl_wpa_psk, 1);
        inputCtrl(document.form.wl_wep, 1);
        inputCtrl(document.form.wl_phrase_x, 1);
        inputCtrl(document.form.wl_key1, 1);
        inputCtrl(document.form.wl_key2, 1);
        inputCtrl(document.form.wl_key3, 1);
        inputCtrl(document.form.wl_key4, 1);
        inputCtrl(document.form.wl_key, 1);
        inputCtrl(document.form.wl_wpa_gtk_rekey, 0);
    }
    else if (document.form.wl_auth_mode.value == "wpa") {
        inputCtrl(document.form.wl_crypto, 0);
        inputCtrl(document.form.wl_wpa_psk, 0);
        inputCtrl(document.form.wl_wep, 0);
        inputCtrl(document.form.wl_phrase_x, 0);
        inputCtrl(document.form.wl_key1, 0);
        inputCtrl(document.form.wl_key2, 0);
        inputCtrl(document.form.wl_key3, 0);
        inputCtrl(document.form.wl_key4, 0);
        inputCtrl(document.form.wl_key, 0);
        inputCtrl(document.form.wl_wpa_gtk_rekey, 0);
    }
    else if (document.form.wl_auth_mode.value == "radius") {
        inputCtrl(document.form.wl_crypto, 1);
        inputCtrl(document.form.wl_wpa_psk, 1);
        inputCtrl(document.form.wl_wep, 1);
        inputCtrl(document.form.wl_phrase_x, 1);
        inputCtrl(document.form.wl_key1, 1);
        inputCtrl(document.form.wl_key2, 1);
        inputCtrl(document.form.wl_key3, 1);
        inputCtrl(document.form.wl_key4, 1);
        inputCtrl(document.form.wl_key, 1);
        inputCtrl(document.form.wl_wpa_gtk_rekey, 0);
    }
    else {
        inputCtrl(document.form.wl_crypto, 0);
        inputCtrl(document.form.wl_wpa_psk, 0);
        inputCtrl(document.form.wl_wep, 1);
        inputCtrl(document.form.wl_phrase_x, 1);
        inputCtrl(document.form.wl_key1, 1);
        inputCtrl(document.form.wl_key1, 1);
        inputCtrl(document.form.wl_key1, 1);
        inputCtrl(document.form.wl_key1, 1);
        inputCtrl(document.form.wl_key1, 1);
        inputCtrl(document.form.wl_key, 1);
        inputCtrl(document.form.wl_wpa_gtk_rekey, 0);
    }
}
/* input : s: service id, v: value name, o: current value */
/* output: wep key1~4       */
function is_wlphrase(s, v, o) {
    var pseed = new Array;
    var wep_key = new Array(5);

    if (v == 'wl_wpa_psk')
        return(valid_WPAPSK(o));

    if (document.form.current_page.value == "Advanced_WirelessGuest_Content.asp") {
        wepType = document.form.wl_guest_wep_x_1.value;
        wepKey1 = document.form.wl_guest_key1_1;
        wepKey2 = document.form.wl_guest_key2_1;
        wepKey3 = document.form.wl_guest_key3_1;
        wepKey4 = document.form.wl_guest_key4_1;
    }
    else {    // note: current_page == "Advanced_Wireless_Content.asp"
        wepType = document.form.wl_wep_x.value;
        wepKey1 = document.form.wl_key1;
        wepKey2 = document.form.wl_key2;
        wepKey3 = document.form.wl_key3;
        wepKey4 = document.form.wl_key4;
    }

    phrase = o.value;
    if (wepType == "1") {
        for (var i = 0; i < phrase.length; i++) {
            pseed[i % 4] ^= phrase.charCodeAt(i);
        }

        randNumber = pseed[0] | (pseed[1] << 8) | (pseed[2] << 16) | (pseed[3] << 24);
        for (var j = 0; j < 5; j++) {
            randNumber = ((randNumber * 0x343fd) % 0x1000000);
            randNumber = ((randNumber + 0x269ec3) % 0x1000000);
            wep_key[j] = ((randNumber >> 16) & 0xff);
        }

        wepKey1.value = binl2hex_c(wep_key);
        for (var j = 0; j < 5; j++) {
            randNumber = ((randNumber * 0x343fd) % 0x1000000);
            randNumber = ((randNumber + 0x269ec3) % 0x1000000);
            wep_key[j] = ((randNumber >> 16) & 0xff);
        }

        wepKey2.value = binl2hex_c(wep_key);
        for (var j = 0; j < 5; j++) {
            randNumber = ((randNumber * 0x343fd) % 0x1000000);
            randNumber = ((randNumber + 0x269ec3) % 0x1000000);
            wep_key[j] = ((randNumber >> 16) & 0xff);
        }

        wepKey3.value = binl2hex_c(wep_key);
        for (var j = 0; j < 5; j++) {
            randNumber = ((randNumber * 0x343fd) % 0x1000000);
            randNumber = ((randNumber + 0x269ec3) % 0x1000000);
            wep_key[j] = ((randNumber >> 16) & 0xff);
        }

        wepKey4.value = binl2hex_c(wep_key);
    }
    else if (wepType == "2" || wepType == "3") {
        password = "";

        if (phrase.length > 0) {
            for (var i = 0; i < 64; i++) {
                ch = phrase.charAt(i % phrase.length);
                password = password + ch;
            }
        }

        password = calcMD5(password);
        if (wepType == "2") {
            wepKey1.value = password.substr(0, 26);
        }
        else {
            wepKey1.value = password.substr(0, 32);
        }

        wepKey2.value = wepKey1.value;
        wepKey3.value = wepKey1.value;
        wepKey4.value = wepKey1.value;
    }

    return true;
}

function wl_wep_change() {
    var mode = document.form.wl_auth_mode.value;
    var wep = document.form.wl_wep_x.value;

    if (mode == "psk" || mode == "wpa" || mode == "wpa2") {
        if (mode != "wpa" && mode != "wpa2") {
            inputCtrl(document.form.wl_crypto, 1);
            inputCtrl(document.form.wl_wpa_psk, 1);
        }
        inputCtrl(document.form.wl_wpa_gtk_rekey, 1);
        inputCtrl(document.form.wl_wep_x, 0);
        inputCtrl(document.form.wl_phrase_x, 0);
        inputCtrl(document.form.wl_key1, 0);
        inputCtrl(document.form.wl_key2, 0);
        inputCtrl(document.form.wl_key3, 0);
        inputCtrl(document.form.wl_key4, 0);
        inputCtrl(document.form.wl_key, 0);

        $("row_wpa3").style.display = "";
        $("row_wep1").style.display = "none";
        $("row_wep2").style.display = "none";
        $("row_wep3").style.display = "none";
        $("row_wep4").style.display = "none";
        $("row_wep5").style.display = "none";
        $("row_wep6").style.display = "none";
        $("row_wep7").style.display = "none";
    }
    else if (mode == "radius") {
        inputCtrl(document.form.wl_crypto, 0);
        inputCtrl(document.form.wl_wpa_psk, 0);
        inputCtrl(document.form.wl_wpa_gtk_rekey, 0);
        inputCtrl(document.form.wl_wep_x, 0);
        inputCtrl(document.form.wl_phrase_x, 0);
        inputCtrl(document.form.wl_key1, 0);
        inputCtrl(document.form.wl_key2, 0);
        inputCtrl(document.form.wl_key3, 0);
        inputCtrl(document.form.wl_key4, 0);
        inputCtrl(document.form.wl_key, 0);

        $("row_wpa3").style.display = "none";
        $("row_wep1").style.display = "none";
        $("row_wep2").style.display = "none";
        $("row_wep3").style.display = "none";
        $("row_wep4").style.display = "none";
        $("row_wep5").style.display = "none";
        $("row_wep6").style.display = "none";
        $("row_wep7").style.display = "none";
    }
    else {
        inputCtrl(document.form.wl_crypto, 0);
        inputCtrl(document.form.wl_wpa_psk, 0);
        inputCtrl(document.form.wl_wpa_gtk_rekey, 0);
        inputCtrl(document.form.wl_wep_x, 1);

        $("row_wpa3").style.display = "none";
        $("row_wep1").style.display = "";

        if (wep != "0") {
            inputCtrl(document.form.wl_phrase_x, 1);
            inputCtrl(document.form.wl_key1, 1);
            inputCtrl(document.form.wl_key2, 1);
            inputCtrl(document.form.wl_key3, 1);
            inputCtrl(document.form.wl_key4, 1);
            inputCtrl(document.form.wl_key, 1);

            $("row_wep2").style.display = "";
            $("row_wep3").style.display = "";
            $("row_wep4").style.display = "";
            $("row_wep5").style.display = "";
            $("row_wep6").style.display = "";
            $("row_wep7").style.display = "";
        }
        else {
            inputCtrl(document.form.wl_phrase_x, 0);
            inputCtrl(document.form.wl_key1, 0);
            inputCtrl(document.form.wl_key2, 0);
            inputCtrl(document.form.wl_key3, 0);
            inputCtrl(document.form.wl_key4, 0);
            inputCtrl(document.form.wl_key, 0);

            $("row_wep2").style.display = "none";
            $("row_wep3").style.display = "none";
            $("row_wep4").style.display = "none";
            $("row_wep5").style.display = "none";
            $("row_wep6").style.display = "none";
            $("row_wep7").style.display = "none";
        }
    }

    change_key_des();
}

function change_wep_type(mode, isload) {
    var cur_wep = document.form.wl_wep_x.value;
    var wep_type_array;
    var value_array;

    free_options(document.form.wl_wep_x);

    if (mode == "shared") {
        wep_type_array = new Array("WEP-64bits", "WEP-128bits");
        value_array = new Array("1", "2");
    }
    else {
        wep_type_array = new Array("None", "WEP-64bits", "WEP-128bits");
        value_array = new Array("0", "1", "2");
    }

    add_options_x2(document.form.wl_wep_x, wep_type_array, value_array, cur_wep);

    if (mode == "psk" || mode == "wpa" || mode == "wpa2" || mode == "radius")
        document.form.wl_wep_x.value = "0";

    change_wlweptype(document.form.wl_wep_x, "WLANConfig11a", isload);
}

function enableExtChRows(o) {
    if (o.value == "0"){
        $("row_HT_BW").style.display = "none";
        $("row_HT_EXTCHA").style.display = "none";
    }else{
        $("row_HT_BW").style.display = "";
        $("row_HT_EXTCHA").style.display = "";
    }
    if (o.value == "3" || o.value == "4" || o.value == "5")
        insert_vht_bw(1);
    else
        insert_vht_bw(0);
}

function insertChannelOption() {
    if (wifi5PolicyEnabled()) { wifi5PopulateChannels(); return; }
    var channels;
    var country = document.form.wl_country_code.value;
    var orig = document.form.wl_channel.value;
    free_options(document.form.wl_channel);

    if (country == "AL" ||
        country == "DZ" ||
        country == "AU" ||
        country == "BH" ||
        country == "BY" ||
        country == "CA" ||
        country == "CL" ||
        country == "CO" ||
        country == "CR" ||
        country == "DO" ||
        country == "SV" ||
        country == "GT" ||
        country == "HN" ||
        country == "HK" ||
        country == "IN" ||
        country == "IL" ||
        country == "JO" ||
        country == "KZ" ||
        country == "LB" ||
        country == "MO" ||
        country == "MK" ||
        country == "MY" ||
        country == "MX" ||
        country == "NZ" ||
        country == "NO" ||
        country == "OM" ||
        country == "PK" ||
        country == "PA" ||
        country == "PR" ||
        country == "QA" ||
        country == "CN" ||
        country == "RO" ||
        country == "RU" ||
        country == "SA" ||
        country == "SG" ||
        country == "SY" ||
        country == "TH" ||
        country == "UA" ||
        country == "AE" ||
        country == "US" ||
        country == "VN" ||
        country == "YE" ||
        country == "ZW")
        channels = new Array(0, 36, 40, 44, 48, 149, 153, 157, 161, 165); //Region 0

    else if (country == "AT" ||
        country == "BE" ||
        country == "BR" ||
        country == "BG" ||
        country == "CY" ||
        country == "DK" ||
        country == "EE" ||
        country == "FI" ||
        country == "DE" ||
        country == "GR" ||
        country == "HU" ||
        country == "IS" ||
        country == "IE" ||
        country == "IT" ||
        country == "LV" ||
        country == "LI" ||
        country == "LT" ||
        country == "LU" ||
        country == "NL" ||
        country == "PL" ||
        country == "PT" ||
        country == "SK" ||
        country == "SI" ||
        country == "ZA" ||
        country == "ES" ||
        country == "SE" ||
        country == "CH" ||
        country == "GB" ||
        country == "UZ")
        channels = new Array(0, 36, 40, 44, 48); //Region 1

    else if (country == "AM" ||
        country == "AZ" ||
        country == "HR" ||
        country == "CZ" ||
        country == "EG" ||
        country == "FR" ||
        country == "GE" ||
        country == "MC" ||
        country == "TT" ||
        country == "TN" ||
        country == "TR")
        channels = new Array(0, 36, 40, 44, 48); //Region 2

    else if (country == "AR" || country == "TW")
        channels = new Array(0, 149, 153, 157, 161); //Region 3

    else if (country == "BZ" ||
        country == "BO" ||
        country == "BN" ||
        country == "ID" ||
        country == "IR" ||
        country == "PE" ||
        country == "PH")
        channels = new Array(0, 149, 153, 157, 161, 165); //Region 4

    else if (country == "KP" ||
        country == "KR" ||
        country == "UY" ||
        country == "VE")
        channels = new Array(0, 149, 153, 157, 161); //Region 5

    else if (country == "JP")
        channels = new Array(0, 36, 40, 44, 48); //Region 9

    else
        channels = new Array(0, 36, 40, 44, 48, 52, 56, 60, 64, 100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 149, 153, 157, 161, 165); //Region 7

    var ch_v = new Array();
    for (var i = 0; i < channels.length; i++) {
        ch_v[i] = channels[i];
    }
    if (ch_v[0] == "0")
        channels[0] = "<#APChnAuto#>";

    add_options_x2(document.form.wl_channel, channels, ch_v, orig);
}

function insertExtChannelOption() {
}

function insert_vht_bw(ins){
    if (wifi5PolicyEnabled()) { wifi5BandwidthOptions(ins); return; }
    var o = document.form.wl_HT_BW;
    var v = o.value;
    var l = o.options.length;

    if (!ins){
        if (l < 3)
            return;
        o.remove(2);
        if (v == "2")
            o.options[1].selected = 1;
    }else{
        if (l > 2)
            return;
        o.options[2] = new Option("20/40/80 MHz");
        o.options[2].value = "2";
    }
}

function wl_auth_mode_change(isload) {
    var mode = document.form.wl_auth_mode.value;
    var i, cur, algos;

    inputCtrl(document.form.wl_wep_x, 1);

    /* enable/disable crypto algorithm */
    if (mode == "wpa" || mode == "wpa2" || mode == "psk") {
        inputCtrl(document.form.wl_crypto, 1);
        $("row_wpa1").style.display = "";
    }
    else {
        inputCtrl(document.form.wl_crypto, 0);
        $("row_wpa1").style.display = "none";
    }

    /* enable/disable psk passphrase */
    if (mode == "psk") {
        inputCtrl(document.form.wl_wpa_psk, 1);
        $("row_wpa2").style.display = "";
    }
    else {
        inputCtrl(document.form.wl_wpa_psk, 0);
        $("row_wpa2").style.display = "none";
    }

    /* update wl_crypto */
    if (mode == "psk") {
        /* Save current crypto algorithm */
        for (var i = 0; i < document.form.wl_crypto.length; i++) {
            if (document.form.wl_crypto[i].selected) {
                cur = document.form.wl_crypto[i].value;
                break;
            }
        }

        opts = document.form.wl_auth_mode.options;

        if (opts[opts.selectedIndex].text == "WPA-Personal")
            algos = new Array("TKIP");
        else if (opts[opts.selectedIndex].text == "WPA2-Personal")
            algos = new Array("AES");
        else
            algos = new Array("AES", "TKIP+AES");

        /* Reconstruct algorithm array from new crypto algorithms */
        document.form.wl_crypto.length = algos.length;
        for (var i in algos) {
            document.form.wl_crypto[i] = new Option(algos[i], algos[i].toLowerCase());
            document.form.wl_crypto[i].value = algos[i].toLowerCase();

            if (algos[i].toLowerCase() == cur)
                document.form.wl_crypto[i].selected = true;
        }
    }
    else if (mode == "wpa") {
        for (var i = 0; i < document.form.wl_crypto.length; i++) {
            if (document.form.wl_crypto[i].selected) {
                cur = document.form.wl_crypto[i].value;
                break;
            }
        }

        opts = document.form.wl_auth_mode.options;
        if (opts[opts.selectedIndex].text == "WPA-Enterprise")
            algos = new Array("TKIP");
        else
            algos = new Array("AES", "TKIP+AES");

        document.form.wl_crypto.length = algos.length;
        for (var i in algos) {
            document.form.wl_crypto[i] = new Option(algos[i], algos[i].toLowerCase());
            document.form.wl_crypto[i].value = algos[i].toLowerCase();

            if (algos[i].toLowerCase() == cur)
                document.form.wl_crypto[i].selected = true;
        }
    }
    else if (mode == "wpa2") {
        for (var i = 0; i < document.form.wl_crypto.length; i++) {
            if (document.form.wl_crypto[i].selected) {
                cur = document.form.wl_crypto[i].value;
                break;
            }
        }

        algos = new Array("AES");

        document.form.wl_crypto.length = algos.length;
        for (var i in algos) {
            document.form.wl_crypto[i] = new Option(algos[i], algos[i].toLowerCase());
            document.form.wl_crypto[i].value = algos[i].toLowerCase();

            if (algos[i].toLowerCase() == cur)
                document.form.wl_crypto[i].selected = true;
        }
    }

    change_wep_type(mode, isload);

    /* Save current network key index */
    for (var i = 0; i < document.form.wl_key.length; i++) {
        if (document.form.wl_key[i].selected) {
            cur = document.form.wl_key[i].value;
            break;
        }
    }

    /* Define new network key indices */
    if (mode == "wpa" || mode == "wpa2" || mode == "psk" || mode == "radius")
        algos = new Array("2", "3");
    else {
        algos = new Array("1", "2", "3", "4");
        if (!isload)
            cur = "1";
    }

    /* Reconstruct network key indices array from new network key indices */
    document.form.wl_key.length = algos.length;
    for (var i in algos) {
        document.form.wl_key[i] = new Option(algos[i], algos[i]);
        document.form.wl_key[i].value = algos[i];
        if (algos[i] == cur)
            document.form.wl_key[i].selected = true;
    }

    wl_wep_change();
}

function validate_wlkey(key_obj){
	var wep_type = document.form.wl_wep_x.value;
	var iscurrect = true;
	var str = "<#JS_wepkey#>";
	
	if(wep_type == "0")
		iscurrect = true;	// do nothing
	else if(wep_type == "1"){
		if(key_obj.value.length == 5 && validate_string(key_obj)){
			document.form.wl_key_type.value = 1;
			iscurrect = true;
		}
		else if(key_obj.value.length == 10 && validate_hex(key_obj)){
			document.form.wl_key_type.value = 0;
			iscurrect = true;
		}
		else{
			str += "(<#WLANConfig11b_WEPKey_itemtype1#>)";
			
			iscurrect = false;
		}
	}
	else if(wep_type == "2"){
		if(key_obj.value.length == 13 && validate_string(key_obj)){
			document.form.wl_key_type.value = 1;
			iscurrect = true;
		}
		else if(key_obj.value.length == 26 && validate_hex(key_obj)){
			document.form.wl_key_type.value = 0;
			iscurrect = true;
		}
		else{
			str += "(<#WLANConfig11b_WEPKey_itemtype2#>)";
			
			iscurrect = false;
		}
	}
	else{
		alert("System error!");
		iscurrect = false;
	}
	
	if(iscurrect == false){
		alert(str);
		
		key_obj.focus();
		key_obj.select();
	}
	
	return iscurrect;
}


/* 区域数据由后台从共同信道表生成，页面不另存一份信道白名单。 */
function wifi5PolicyEnabled() {
    return typeof wifi5_policy === 'function' && wifi5_policy() !== null;
}
function wifi5Width(row, mode) {
    if (mode === 4) return (row[1] & 8) ? 160 : 0;
    for (var bit = Math.min(mode, 3); bit >= 0; --bit)
        if (row[1] & (1 << bit)) return 20 * Math.pow(2, bit);
    return 0;
}
function wifi5BandwidthOptions(vht) {
    var o = document.form.wl_HT_BW, selected = o.value;
    var labels = ['20 MHz', '20/40 MHz', '20/40/80 MHz', '20/40/80/160 MHz', '160 MHz（固定 AP 带宽）'];
    var count = !vht ? 2 : support_5g_160mhz() ? 5 : 3;
    o.options.length = 0;
    for (var i = 0; i < count; ++i) o.options[i] = new Option(labels[i], String(i));
    o.value = Number(selected) < count ? selected : '1';
}
function wifi5PopulateChannels() {
    var f = document.form, o = f.wl_channel, old = o.value;
    var policy = wifi5_policy(), r = policy[f.wl_country_code.value];
    var rows = r ? r.channels : [], mode = f.wl_HT_BW ? Number(f.wl_HT_BW.value) : 0;
    o.options.length = 0;
    o.options[0] = new Option('自动选择', '0');
    for (var i = 0; i < rows.length; ++i) {
        var row = rows[i], bw = wifi5Width(row, mode);
        if (!bw) continue;
        var bit = Math.round(Math.log(bw / 20) / Math.LN2);
        var needsDfs = !!(row[2] & (1 << bit));
        var condition = needsDfs ? ((row[2] & 1) ? '需 DFS' : bw + ' MHz 时需 DFS') : '无需 DFS';
        var text = String(row[0]) + '（' + (mode === 4 ? '固定 ' : '最高 ') + bw + ' MHz；' + condition + '）';
        o.options[o.options.length] = new Option(text, String(row[0]));
    }
    o.value = old;
    if (o.selectedIndex < 0) o.value = '0';
    wifi5UpdateHint();
}
/* 和驱动的区域、连续带宽组一起判断；主信道号本身不能代表整组频谱。 */
function wifi5CacSeconds(region, ch, bw) {
    if (!region || !bw) return 0;
    var row = null;
    for (var i = 0; i < region.channels.length; ++i)
        if (region.channels[i][0] === ch) row = region.channels[i];
    var bit = Math.round(Math.log(bw / 20) / Math.LN2);
    if (!row || !(row[2] & (1 << bit))) return 0;
    var weather = bw === 160 ? ch >= 100 && ch <= 128 :
        bw >= 40 ? ch >= 116 && ch <= 128 : ch >= 120 && ch <= 128;
    return region.rd === 'CE' && weather ? 605 : 65;
}
function wifi5UpdateHint() {
    var e = document.getElementById('wifi5_dfs_hint');
    if (!e || !wifi5PolicyEnabled()) return;
    var f = document.form, mode = f.wl_HT_BW ? Number(f.wl_HT_BW.value) : 0, ch = Number(f.wl_channel.value);
    var r = wifi5_policy()[f.wl_country_code.value], dfs = false, bw = 0;
    if (r) for (var i = 0; i < r.channels.length; ++i) if (r.channels[i][0] === ch) {
        bw = wifi5Width(r.channels[i], mode);
        dfs = !!(r.channels[i][2] & (1 << Math.round(Math.log(bw / 20) / Math.LN2)));
    }
    var msg = mode === 4 ? '固定 AP 使用连续 160 MHz；终端仍可协商较窄带宽。没有可用的 160 MHz 信道组时暂停 5 GHz 并等待恢复。' :
        '按区域和完整子信道组选择带宽；边界信道可能只能使用 20/40 MHz。';
    if (mode !== 4) msg += ' 列表中的“最高”表示当前模式的带宽上限，不是终端实际连接带宽。';
    if (ch >= 36 && ch <= 48 && bw === 160)
        msg += ' 主信道 36–48 在 20/40/80 MHz 下无需 DFS；160 MHz 覆盖 52–64，因此整组需 DFS。';
    if (ch === 0) msg += ' 自动选到 DFS 组合时会先静默检测，等待时间取决于最终信道和带宽。';
    else if (dfs) msg += ' 此组合启用前需静默检测约 ' + (wifi5CacSeconds(r, ch, bw) === 605 ? '10 分钟' : '65 秒') + '；检测到雷达会避让。';
    else if (bw) msg += ' 当前信道与带宽组合无需 DFS。';
    e.textContent = msg;
    e.style.display = '';
}
function wifi5InitPolicy() {
    if (!wifi5PolicyEnabled()) return;
    var f = document.form, countries = f.wl_country_code, original = countries.value;
    var labels = {US:'美国',AU:'澳大利亚',NO:'挪威',FR:'法国',GB:'英国',TW:'台湾',CN:'中国',KR:'韩国',JP:'日本'};
    var policy = wifi5_policy();
    for (var i = countries.options.length - 1; i >= 0; --i) {
        var cc = countries.options[i].value;
        if (!policy[cc]) countries.remove(i);
        else countries.options[i].text = labels[cc] + '（' + cc + '，含 DFS 信道）';
    }
    if (!policy[original]) {
        countries.options[countries.options.length] = new Option('请选择支持的区域', '');
        countries.value = '';
    }
    wifi5BandwidthOptions(Number(f.wl_gmode.value) >= 3);
    wifi5BindDfsPrompt();
}
function wifi5ValidateSelection() {
    if (!wifi5PolicyEnabled()) return true;
    var f = document.form, r = wifi5_policy()[f.wl_country_code.value];
    var ch = Number(f.wl_channel.value), mode = Number(f.wl_HT_BW.value);
    if (!r || mode < 0 || mode > 4 || (mode >= 2 && Number(f.wl_gmode.value) < 3)) return false;
    if (ch === 0) return true;
    for (var i = 0; i < r.channels.length; ++i)
        if (r.channels[i][0] === ch && wifi5Width(r.channels[i], mode)) return true;
    return false;
}

/* 选定 DFS 组合立即提示；确认只保留表单选择，应用设置仍由原按钮执行。 */
var wifi5PreviousSelection = null;
var wifi5DfsPromptActive = false;
function wifi5Selection() {
    var f = document.form;
    return {country:f.wl_country_code.value, channel:f.wl_channel.value, bw:f.wl_HT_BW ? f.wl_HT_BW.value : '0', ext:f.wl_HT_EXTCHA ? f.wl_HT_EXTCHA.value : null};
}
function wifi5RememberSelection() {
    if (!wifi5DfsPromptActive && wifi5PolicyEnabled()) wifi5PreviousSelection = wifi5Selection();
}
function wifi5BindDfsPrompt() {
    var f = document.form;
    [f.wl_channel, f.wl_HT_BW, f.wl_country_code].forEach(function(o) {
        if (!o || o.wifi5PromptBound) return;
        o.wifi5PromptBound = true;
        ['focus','mousedown','keydown'].forEach(function(event) { o.addEventListener(event, wifi5RememberSelection); });
        o.addEventListener('change', wifi5DfsSelectionChanged);
    });
    wifi5RememberSelection();
}
function wifi5DfsSelectionChanged() {
    if (!wifi5PolicyEnabled() || wifi5DfsPromptActive) return;
    var next = wifi5Selection(), previous = wifi5PreviousSelection || next;
    var region = wifi5_policy()[next.country], ch = Number(next.channel), bw = 0;
    if (region) for (var i = 0; i < region.channels.length; i++)
        if (region.channels[i][0] === ch) bw = wifi5Width(region.channels[i], Number(next.bw));
    var seconds = wifi5CacSeconds(region, ch, bw);
    wifi5UpdateHint();
    if (!seconds || (previous.country === next.country && previous.channel === next.channel && previous.bw === next.bw)) {
        wifi5RememberSelection(); return;
    }
    var box = document.getElementById('wifi5_dfs_confirm');
    if (!box) {
        box = document.createElement('div');box.id = 'wifi5_dfs_confirm';
        box.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,.45);z-index:10020;display:none;';
        box.innerHTML = '<div role="dialog" aria-modal="true" aria-labelledby="wifi5_dfs_title" style="position:absolute;left:50%;top:35%;transform:translate(-50%,-50%);width:460px;max-width:90%;background:#fff;color:#333;border-radius:6px;box-shadow:0 8px 30px #555;padding:24px;box-sizing:border-box;font-size:14px;line-height:1.8">' +
            '<h3 id="wifi5_dfs_title" style="margin:0 0 16px;font-size:18px">DFS 信道提示</h3>' +
            '<p id="wifi5_dfs_message"></p><p style="color:#666">继续仅保留本次选择，点击“应用设置”后才生效。</p>' +
            '<div style="text-align:right;margin-top:20px"><button type="button" id="wifi5_dfs_cancel" class="btn" style="margin-right:12px">取消</button>' +
            '<button type="button" id="wifi5_dfs_continue" class="btn btn-primary">继续</button></div></div>';
        document.body.appendChild(box);
    }
    var message = '主信道 ' + ch + '、' + bw + ' MHz 组合需要 DFS。部分设备可能搜不到或无法连接。应用后预计静默检测约 ' + (seconds === 605 ? '10 分钟' : '65 秒') + '，期间 5 GHz 暂时不可见；检测到雷达会避让。';
    if (ch >= 36 && ch <= 48 && bw === 160) message += ' 此处是因为 160 MHz 同时覆盖 52–64；主信道在 20/40/80 MHz 下无需 DFS。';
    document.getElementById('wifi5_dfs_message').textContent = message;
    var focus = document.activeElement;
    function close(keep) {
        if (!wifi5DfsPromptActive) return;
        wifi5DfsPromptActive = false;box.style.display = 'none';box.removeEventListener('keydown', keys);
        if (!keep) {
            var f = document.form;
            f.wl_country_code.value = previous.country;
            if (f.wl_HT_BW) f.wl_HT_BW.value = previous.bw;
            wifi5PopulateChannels();f.wl_channel.value = previous.channel;
            if (typeof insertExtChannelOption === 'function') insertExtChannelOption();
            if (f.wl_HT_EXTCHA && previous.ext !== null) f.wl_HT_EXTCHA.value = previous.ext;
            wifi5UpdateHint();
        }
        wifi5RememberSelection();
        if (focus && focus.focus) focus.focus();
    }
    function keys(e) {
        if (e.key === 'Escape') { e.preventDefault();close(false); }
        if (e.key === 'Tab') {
            e.preventDefault();
            var id = document.activeElement.id === 'wifi5_dfs_cancel' ? 'wifi5_dfs_continue' : 'wifi5_dfs_cancel';
            document.getElementById(id).focus();
        }
    }
    document.getElementById('wifi5_dfs_cancel').onclick = function(){close(false);};
    document.getElementById('wifi5_dfs_continue').onclick = function(){close(true);};
    wifi5DfsPromptActive = true;box.style.display = 'block';box.addEventListener('keydown', keys);
    document.getElementById('wifi5_dfs_cancel').focus();
}
