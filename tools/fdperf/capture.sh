#!/usr/bin/env bash
# Records Adreno hardware counters while a game runs, as CSV in
# ~/fdperf-capture.csv. Runs as a system service, so it survives the switch
# from Desktop Mode to Game Mode.
#
# Usage: ./capture.sh [delay seconds] [length seconds]   (default 60 180)
#        ./capture.sh --test                             (5 s, right now)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
out="$HOME/fdperf-capture.csv"

# Shader core (SP), texture (TP), cache (UCHE), front end (PC/VFD/VPC),
# render backend (RB/LRZ) and whole-GPU busy counters.
counters=(
  PERF_RBBM_STATUS_MASKED PERF_RBBM_UCHE_BUSY PERF_RBBM_PC_DCALL_BUSY PERF_RBBM_COM_BUSY
  PERF_SP_BUSY_CYCLES PERF_SP_ALU_WORKING_CYCLES PERF_SP_EFU_WORKING_CYCLES
  PERF_SP_STALL_CYCLES_VPC PERF_SP_STALL_CYCLES_TP PERF_SP_STALL_CYCLES_UCHE PERF_SP_STALL_CYCLES_RB
  PERF_SP_NON_EXECUTION_CYCLES PERF_SP_WAVE_CONTEXTS PERF_SP_WAVE_CONTEXT_CYCLES
  PERF_SP_WAVE_ALU_CYCLES PERF_SP_WAVE_EFU_CYCLES PERF_SP_WAVE_NOP_CYCLES PERF_SP_WAVE_WAIT_CYCLES
  PERF_SP_WAVE_FETCH_CYCLES PERF_SP_WAVE_IDLE_CYCLES PERF_SP_ANY_EU_WORKING_FS_STAGE
  PERF_SP_ANY_EU_WORKING_VS_STAGE PERF_SP_ANY_EU_WORKING_CS_STAGE PERF_SP_ICL1_MISSES
  PERF_TP_BUSY_CYCLES PERF_TP_STALL_CYCLES_UCHE PERF_TP_L1_CACHELINE_REQUESTS PERF_TP_L1_CACHELINE_MISSES
  PERF_UCHE_BUSY_CYCLES PERF_UCHE_STALL_CYCLES_ARBITER PERF_UCHE_VBIF_READ_BEATS_TP
  PERF_UCHE_VBIF_READ_BEATS_VFD PERF_UCHE_VBIF_READ_BEATS_SP PERF_UCHE_VBIF_READ_BEATS_CH0
  PERF_UCHE_VBIF_READ_BEATS_CH1 PERF_UCHE_VBIF_WRITE_BEATS_CH0 PERF_UCHE_VBIF_WRITE_BEATS_CH1
  PERF_PC_BUSY_CYCLES PERF_PC_WORKING_CYCLES PERF_PC_STALL_CYCLES_VFD PERF_PC_STALL_CYCLES_VPC
  PERF_PC_STALL_CYCLES_UCHE PERF_VFD_BUSY_CYCLES PERF_VFD_STALL_CYCLES_UCHE
  PERF_VFD_STALL_CYCLES_SP_INFO PERF_VPC_BUSY_CYCLES PERF_VPC_STALL_CYCLES_UCHE
  PERF_TSE_BUSY_CYCLES PERF_RAS_BUSY_CYCLES PERF_RB_BUSY_CYCLES PERF_RB_STALL_CYCLES_CCU
  PERF_RB_STALL_CYCLES_HLSQ PERF_LRZ_BUSY_CYCLES
)
select="$(IFS=,; echo "${counters[*]}")"

if [ "${1:-}" = --test ]; then
  sudo env FDPERF_SELECT="$select" LD_LIBRARY_PATH="$here" "$here/fdperf" -r 500 -l 5
  exit
fi

delay="${1:-60}"
length="${2:-180}"
sudo systemd-run --unit="fdperf-capture-$(date +%s)" --on-active="$delay" \
  --setenv=FDPERF_SELECT="$select" --setenv=LD_LIBRARY_PATH="$here" \
  /bin/sh -c "'$here/fdperf' -r 500 -l $length > '$out' 2> '$out.log'; chown $(id -u):$(id -g) '$out' '$out.log'"
echo "Capture starts in $delay s and lasts $length s: $out"
