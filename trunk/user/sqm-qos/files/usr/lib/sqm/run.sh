#!/bin/sh

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
#       Copyright (C) 2012-4 Michael D. Taht, Toke Høiland-Jørgensen, Sebastian Moeller


. /etc_ro/sqm.conf

ACTION="${1:-start}"
RUN_IFACE="$2"
[ -d "${SQM_QDISC_STATE_DIR}" ] || ${SQM_LIB_DIR}/update-available-qdiscs

stop_statefile() {
    local f="$1"
    # Source the state file prior to stopping; we need the variables saved in
    # there.
    [ -f "$f" ] && ( . "$f";
                     IFACE=$IFACE SCRIPT=$SCRIPT SQM_DEBUG=$SQM_DEBUG \
                          SQM_DEBUG_LOG=$SQM_DEBUG_LOG \
                          OUTPUT_TARGET=$OUTPUT_TARGET ${SQM_LIB_DIR}/stop-sqm )
}

runmode_1(){
export IFACE="eth2"
}

runmode_2(){
export IFACE="br0"
}

runmode_3(){
export IFACE="br0"
}

runmode_4(){
export IFACE=$(nvram get sqm_active)
}

release_acceleration() {
    # 仍有其他接口启用 SQM 时，继续禁止加速。
    local f
    for f in "${SQM_STATE_DIR}"/*.state; do
        [ -f "$f" ] && return 0
    done
    rm -f "${SQM_STATE_DIR}/accel-block"
    /sbin/rc sync_acceleration
}


start_sqm_section() {
    runmode="$(nvram get sqm_flag)"
    local section="sqm_"

    # 先确定接口，再检查状态，避免使用空接口名或重复启动。
    case "$runmode" in
        1) runmode_1 ;;
        2) runmode_2 ;;
        3) runmode_3 ;;
        *) runmode_4 ;;
    esac
    [ -n "$IFACE" ] && [ -d "/sys/class/net/$IFACE" ] || return 1
    [ -z "$RUN_IFACE" -o "$RUN_IFACE" = "$IFACE" ] || return
    [ "$(nvram get sqm_enable)" = "1" ] || return 0
    [ -f "${SQM_STATE_DIR}/${IFACE}.state" ] && return

    export DOWNLINK=$(nvram get sqm_up_speed)
    export UPLINK=$(nvram get sqm_down_speed)
    export LLAM=$(nvram get sqm_linklayer_adaptation_mechanism)
    export LINKLAYER=$(nvram get sqm_linklayer)
    export OVERHEAD=$(nvram get sqm_overhead)
    export STAB_MTU=$(nvram get sqm_tcMTU)
    export STAB_TSIZE=$(nvram get sqm_tcTSIZE)
    export STAB_MPU=$(nvram get sqm_tcMPU)
    export ILIMIT=$(nvram get sqm_ilimit)
    export ELIMIT=$(nvram get sqm_elimit)
    export ITARGET=$(nvram get sqm_itarget)
    export ETARGET=$(nvram get sqm_etarget)
    export IECN=$(nvram get sqm_ingress_ecn)
    export EECN=$(nvram get sqm_egress_ecn)
    export IQDISC_OPTS=$(nvram get sqm_iqdisc_opts)
    export EQDISC_OPTS=$(nvram get sqm_eqdisc_opts)
    export TARGET=$(nvram get sqm_target)
    export SHAPER_BURST=$(nvram get sqm_shaper_burst)
    export HTB_QUANTUM_FUNCTION=$(nvram get sqm_htb_quantum_function)
    export QDISC=$(nvram get sqm_qdisc)
    export SCRIPT=$(nvram get sqm_script)

    # The UCI names for these two variables are confusing and should have been
    # changed ages ago. For now, keep the bad UCI names but use meaningful
    # variable names in the scripts to not break user configs.
    export ZERO_DSCP_INGRESS=$(nvram get sqm_squash_dscp)
    export IGNORE_DSCP_INGRESS=$(nvram get sqm_squash_ingress)

    # If SQM_DEBUG or SQM_VERBOSITY_* were passed in via the command line make
    # them available to the other scripts this allows to override sqm's log
    # level as set in the GUI for quick debugging without GUI accesss.
    export SQM_DEBUG=${SQM_DEBUG:-$(nvram get sqm_debug_log)}
    export SQM_VERBOSITY_MAX=${SQM_VERBOSITY_MAX:-$(nvram get sqm_log_level)}
    export SQM_VERBOSITY_MIN
    
    # 硬件 NAT 会绕过软件队列；不允许限速与卸载路径同时生效。
    mkdir -p "${SQM_STATE_DIR}" || return 1
    : > "${SQM_STATE_DIR}/accel-block" || return 1
    /sbin/rc sync_acceleration || { release_acceleration; return 1; }
    if grep -qE '^(hw_nat|fast_classifier|shortcut_fe_cm) ' /proc/modules; then
        logger -t SQM "加速模块仍在运行，取消启动限速以免规则被绕过"
        release_acceleration
        return 1
    fi
    "${SQM_LIB_DIR}/start-sqm"
    local status=$?
    # 部分上游脚本失败时也返回零，以实际状态文件作为启动完成的依据。
    if [ "$status" -ne 0 ] || [ ! -f "${SQM_STATE_DIR}/${IFACE}.state" ]; then
        release_acceleration
        return 1
    fi
}

if [ "$ACTION" = "stop" ]; then
    if [ -z "$RUN_IFACE" ]; then
        # Stopping all active interfaces
        for f in ${SQM_STATE_DIR}/*.state; do
            stop_statefile "$f"
        done
    else
        stop_statefile "${SQM_STATE_DIR}/${RUN_IFACE}.state"
    fi
    release_acceleration
else
    start_sqm_section
fi
