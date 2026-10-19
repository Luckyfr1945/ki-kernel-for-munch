/**
 * Ki-Optimizer WebUI Controller
 * Native JavaScript Bridge for KernelSU WebView
 */

let callbackCounter = 0;
function getUniqueCallbackName(prefix) {
  return `${prefix}_cb_${Date.now()}_${callbackCounter++}`;
}

// Execute Shell Command via KernelSU Bridge
function exec(command, options = {}) {
  if (typeof ksu === "undefined") {
    console.log("[Dev Mode] Shell Exec:", command);
    return Promise.resolve({ errno: 0, stdout: "", stderr: "" });
  }

  return new Promise((resolve, reject) => {
    const callbackFuncName = getUniqueCallbackName("exec");
    window[callbackFuncName] = (errno, stdout, stderr) => {
      resolve({ errno, stdout, stderr });
      delete window[callbackFuncName];
    };

    try {
      ksu.exec(command, JSON.stringify(options), callbackFuncName);
    } catch (error) {
      delete window[callbackFuncName];
      reject(error);
    }
  });
}

// Toast notification helper
function showToast(message) {
  if (typeof ksu !== "undefined" && ksu.toast) {
    ksu.toast(message);
  }
  
  const toastEl = document.getElementById("toast");
  const toastText = document.getElementById("toast-text");
  if (toastEl && toastText) {
    toastText.textContent = message;
    toastEl.classList.add("show");
    setTimeout(() => {
      toastEl.classList.remove("show");
    }, 2500);
  }
}

// UI Elements
const elUnsupportedModal = document.getElementById("unsupported-modal");
const elModalKernelVer = document.getElementById("modal-kernel-ver");

const elCurProfile = document.getElementById("cur-profile");
const elCurBattery = document.getElementById("cur-battery");
const elCurTemp = document.getElementById("cur-temp");
const elDeviceModel = document.getElementById("device-model");

const cardProf0 = document.getElementById("card-prof-0");
const cardProf1 = document.getElementById("card-prof-1");
const cardProf2 = document.getElementById("card-prof-2");

// Feature Rows
const rowMglru = document.getElementById("row-mglru");
const badgeMglru = document.getElementById("badge-mglru");
const mglruBtns = [
  document.getElementById("btn-mglru-0"),
  document.getElementById("btn-mglru-1"),
  document.getElementById("btn-mglru-7")
];
let currentMglruMode = 1;

const rowSwappiness = document.getElementById("row-swappiness");
const rangeSwappiness = document.getElementById("range-swappiness");
const valSwappiness = document.getElementById("val-swappiness");

const rowBypass = document.getElementById("row-bypass");
const toggleBypass = document.getElementById("toggle-bypass");
const badgeBypass = document.getElementById("badge-bypass");

const rowFastCharge = document.getElementById("row-fastcharge");
const toggleFastCharge = document.getElementById("toggle-fastcharge");
const badgeFastCharge = document.getElementById("badge-fastcharge");

const rowScreenOff = document.getElementById("row-screenoff");
const toggleScreenOff = document.getElementById("toggle-screenoff");
const badgeScreenOff = document.getElementById("badge-screenoff");

const rowWakelock = document.getElementById("row-wakelock");
const toggleWakelock = document.getElementById("toggle-wakelock");
const badgeWakelock = document.getElementById("badge-wakelock");

const rowDynFsync = document.getElementById("row-dynfsync");
const toggleDynFsync = document.getElementById("toggle-dynfsync");
const badgeDynFsync = document.getElementById("badge-dynfsync");

const rowThermal = document.getElementById("row-thermal");
const toggleThermal = document.getElementById("toggle-thermal");
const badgeThermal = document.getElementById("badge-thermal");

const rowTcp = document.getElementById("row-tcp");
const selectTcp = document.getElementById("select-tcp");
const badgeTcp = document.getElementById("badge-tcp");

const btnApply = document.getElementById("btn-apply");

let currentProfile = 1;
let isKiKernelActive = true;

// Helper to configure feature row support
function updateFeatureRow(row, input, badge, isSupported, isEnabled, labelOn, labelOff) {
  if (!row) return;
  if (!isSupported) {
    row.classList.add("is-unsupported");
    if (input) input.disabled = true;
    if (badge) {
      badge.textContent = "Unsupported";
      badge.classList.add("is-unsupported");
      badge.classList.remove("is-off");
    }
  } else {
    row.classList.remove("is-unsupported");
    if (input) {
      input.disabled = false;
      input.checked = isEnabled;
    }
    if (badge) {
      badge.classList.remove("is-unsupported");
      badge.textContent = isEnabled ? labelOn : labelOff;
      badge.classList.toggle("is-off", !isEnabled);
    }
  }
}

// Update Active Profile UI
function setActiveProfileUI(profileId) {
  currentProfile = parseInt(profileId, 10);
  [cardProf0, cardProf1, cardProf2].forEach(card => {
    if (card) {
      card.classList.remove("active");
      card.setAttribute("aria-pressed", "false");
    }
  });
  
  if (currentProfile === 0) {
    cardProf0?.classList.add("active");
    cardProf0?.setAttribute("aria-pressed", "true");
    if (elCurProfile) {
      elCurProfile.textContent = "BATTERY";
      elCurProfile.style.color = "var(--accent-green)";
    }
  } else if (currentProfile === 2) {
    cardProf2?.classList.add("active");
    cardProf2?.setAttribute("aria-pressed", "true");
    if (elCurProfile) {
      elCurProfile.textContent = "TURBO";
      elCurProfile.style.color = "var(--accent-green)";
    }
  } else {
    cardProf1?.classList.add("active");
    cardProf1?.setAttribute("aria-pressed", "true");
    if (elCurProfile) {
      elCurProfile.textContent = "BALANCED";
      elCurProfile.style.color = "var(--accent-green)";
    }
  }
}

// Instant Profile Switcher (Fixes UI mental / reverting back to previous profile)
async function setProfileInstant(profileId) {
  if (!isKiKernelActive) return;
  const id = parseInt(profileId, 10);
  setActiveProfileUI(id);
  const names = ["Battery Saver", "Balanced", "Turbo Gaming"];

  try {
    await exec(`
      echo ${id} > /proc/ki_profile 2>/dev/null
      echo ${id} > /sys/kernel/ki_profile/mode 2>/dev/null
      CONF="/sdcard/ki_optimizer.conf"
      if [ -f "$CONF" ]; then
        sed -i -E "s/^KI_PROFILE=.*/KI_PROFILE=${id}/" "$CONF" 2>/dev/null
      fi
    `);
    showToast(`✔ Switched to ${names[id]} profile`);
  } catch (err) {
    console.error("setProfileInstant error:", err);
  }
}

// Update MGLRU Segmented UI
function setMglruUI(mode, isSupported = true) {
  currentMglruMode = parseInt(mode, 10);
  if (!isSupported) {
    rowMglru?.classList.add("is-unsupported");
    mglruBtns.forEach(btn => { if (btn) btn.disabled = true; });
    if (badgeMglru) {
      badgeMglru.textContent = "Unsupported";
      badgeMglru.classList.add("is-unsupported");
    }
    return;
  }

  rowMglru?.classList.remove("is-unsupported");
  mglruBtns.forEach(btn => {
    if (btn) {
      btn.disabled = false;
      const btnMode = parseInt(btn.dataset.mode, 10);
      btn.classList.toggle("active", btnMode === currentMglruMode);
    }
  });

  if (badgeMglru) {
    badgeMglru.classList.remove("is-unsupported");
    if (currentMglruMode === 0) {
      badgeMglru.textContent = "Disabled";
      badgeMglru.classList.add("is-off");
    } else if (currentMglruMode === 1) {
      badgeMglru.textContent = "Standard";
      badgeMglru.classList.remove("is-off");
    } else if (currentMglruMode === 7) {
      badgeMglru.textContent = "Gaming Turbo";
      badgeMglru.classList.remove("is-off");
    }
  }
}

// Read current system and kernel state (Executed on initial load and manual Apply)
async function refreshState() {
  const checkCmd = `
    k_ver="\$(uname -r)"
    is_ki=0
    echo "\$k_ver" | grep -qi ki-kernel && is_ki=1 || [ -e /proc/ki_profile ] && is_ki=1

    prof=\$(cat /sys/kernel/ki_profile/mode 2>/dev/null || cut -d" " -f1 /proc/ki_profile 2>/dev/null || echo 1)

    mglru_sup=0; ([ -e /sys/kernel/mm/lru_gen/enabled ] || [ -e /proc/mglru ]) && mglru_sup=1
    mglru_raw=\$(cat /sys/kernel/mm/lru_gen/enabled 2>/dev/null || echo 0)
    mglru_mode=0
    if [ "\$mglru_raw" = "0x0007" ] || [ "\$mglru_raw" = "0x0003" ] || [ "\$mglru_raw" = "7" ] || [ "\$mglru_raw" = "3" ]; then
      mglru_mode=7
    elif [ "\$mglru_raw" = "0x0001" ] || [ "\$mglru_raw" = "1" ]; then
      mglru_mode=1
    else
      mglru_mode=0
    fi

    bypass_sup=0; ([ -e /proc/bypass_charging ] || [ -e /sys/class/power_supply/battery/bypass_charging ]) && bypass_sup=1
    bypass_en=\$(cat /proc/bypass_charging 2>/dev/null || cat /sys/class/power_supply/battery/bypass_charging 2>/dev/null || echo 0)

    fc_sup=0; ([ -e /sys/kernel/fast_charge/force_fast_charge ] || [ -e /sys/kernel/fast_charge/screen_on_fast_charge ]) && fc_sup=1
    fc_en=\$(cat /sys/kernel/fast_charge/force_fast_charge 2>/dev/null || echo 0)

    sbat_sup=0; [ -e /sys/kernel/ki_profile/screen_off_battery ] && sbat_sup=1
    sbat_en=\$(cat /sys/kernel/ki_profile/screen_off_battery 2>/dev/null || echo 1)

    dfs_sup=0; ([ -e /sys/kernel/dyn_fsync/Dyn_fsync_active ] || [ -e /sys/kernel/dyn_fsync/dyn_fsync_active ]) && dfs_sup=1
    dfs_en=\$(cat /sys/kernel/dyn_fsync/Dyn_fsync_active 2>/dev/null || cat /sys/kernel/dyn_fsync/dyn_fsync_active 2>/dev/null || echo 0)

    throt_sup=0; [ -e /sys/kernel/ki_profile/thermal_throttle ] && throt_sup=1
    throt_en=\$(cat /sys/kernel/ki_profile/thermal_throttle 2>/dev/null || echo 1)

    wl_sup=0; ([ -e /sys/kernel/wakelock_blocker/enabled ] || [ -e /sys/devices/virtual/misc/boeffla_wakelock_blocker/wakelock_blocker ]) && wl_sup=1
    wl_en=\$(cat /sys/kernel/wakelock_blocker/enabled 2>/dev/null || ([ -s /sys/devices/virtual/misc/boeffla_wakelock_blocker/wakelock_blocker ] && echo 1 || echo 0))

    tcp=\$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || echo cubic)
    swap=\$(cat /proc/sys/vm/swappiness 2>/dev/null || echo 80)

    b_cap=\$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo 0)
    b_tmp=\$(cat /sys/class/power_supply/battery/temp 2>/dev/null || echo 300)
    model=\$(getprop ro.product.model 2>/dev/null || echo munch)

    echo "\$is_ki|\$prof|\$mglru_sup|\$mglru_mode|\$mglru_raw|\$bypass_sup|\$bypass_en|\$fc_sup|\$fc_en|\$sbat_sup|\$sbat_en|\$dfs_sup|\$dfs_en|\$throt_sup|\$throt_en|\$tcp|\$swap|\$b_cap|\$b_tmp|\$k_ver|\$model|\$wl_sup|\$wl_en"
  `;

  try {
    const res = await exec(checkCmd);
    if (!res || !res.stdout) return;

    const parts = res.stdout.trim().split("|");
    if (parts.length >= 21) {
      const isKi = parts[0] === "1";
      isKiKernelActive = isKi;

      const pKernel = parts[19].trim();
      const pModel = parts[20].trim();

      // Incompatible Kernel Guard
      if (!isKi) {
        if (elUnsupportedModal) {
          elUnsupportedModal.classList.remove("hidden");
          elModalKernelVer.textContent = pKernel || "Unsupported Kernel";
        }
        btnApply.disabled = true;
        btnApply.style.opacity = "0.5";
        return;
      } else {
        if (elUnsupportedModal) {
          elUnsupportedModal.classList.add("hidden");
        }
        btnApply.disabled = false;
        btnApply.style.opacity = "1";
      }

      const pProfile = parts[1];
      const pMglruSup = parts[2] === "1";
      const pMglruMode = parts[3];

      const pBypassSup = parts[5] === "1";
      const pBypassEn = parts[6] === "1";

      const pFcSup = parts[7] === "1";
      const pFcEn = parts[8] === "1";

      const pSbatSup = parts[9] === "1";
      const pSbatEn = parts[10] === "1";

      const pDfsSup = parts[11] === "1";
      const pDfsEn = parts[12] === "1";

      const pThrotSup = parts[13] === "1";
      const pThrotEn = parts[14] === "1";

      const pTcp = parts[15].trim();
      const pSwappiness = parts[16].trim();
      const pBatCap = parts[17].trim();
      const pBatTempRaw = parseInt(parts[18].trim(), 10) || 300;

      const pWlSup = parts[21] === "1";
      const pWlEn = parts[22] === "1";

      // Set Profile
      setActiveProfileUI(pProfile);

      // Set MGLRU Mode
      setMglruUI(pMglruMode, pMglruSup);

      // Feature Compatibility Updates
      updateFeatureRow(rowBypass, toggleBypass, badgeBypass, pBypassSup, pBypassEn, "Active", "Disabled");
      updateFeatureRow(rowFastCharge, toggleFastCharge, badgeFastCharge, pFcSup, pFcEn, "Active", "Disabled");
      updateFeatureRow(rowScreenOff, toggleScreenOff, badgeScreenOff, pSbatSup, pSbatEn, "Active", "Disabled");
      updateFeatureRow(rowWakelock, toggleWakelock, badgeWakelock, pWlSup, pWlEn, "Active", "Disabled");
      updateFeatureRow(rowDynFsync, toggleDynFsync, badgeDynFsync, pDfsSup, pDfsEn, "Active", "Disabled");
      updateFeatureRow(rowThermal, toggleThermal, badgeThermal, pThrotSup, pThrotEn, "Active", "Disabled");

      // Swappiness
      if (pSwappiness && rangeSwappiness) {
        rangeSwappiness.value = pSwappiness;
        valSwappiness.textContent = pSwappiness;
      }

      // TCP
      if (badgeTcp) badgeTcp.textContent = "Supported";
      if (["bbr", "westwood", "cubic"].includes(pTcp) && selectTcp) {
        selectTcp.value = pTcp;
      }

      // Live Battery & Device info
      elCurBattery.textContent = `${pBatCap}%`;
      const tempC = Math.round(pBatTempRaw / 10);
      elCurTemp.textContent = `${tempC}°C`;
      if (tempC >= 42) {
        elCurTemp.style.color = "var(--danger)";
      } else if (tempC >= 38) {
        elCurTemp.style.color = "var(--warning)";
      } else {
        elCurTemp.style.color = "var(--accent-green)";
      }

      if (pModel) {
        elDeviceModel.textContent = `${pModel} (${pKernel.split("-")[0]})`;
      }
    }
  } catch (err) {
    console.error("refreshState error:", err);
  }
}

// Telemetry Poller (Only updates live sensor numbers, never overwrites user controls)
async function updateTelemetry() {
  if (!isKiKernelActive) return;
  try {
    const res = await exec(`
      b_cap=\$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo 0)
      b_tmp=\$(cat /sys/class/power_supply/battery/temp 2>/dev/null || echo 300)
      echo "\$b_cap|\$b_tmp"
    `);
    if (!res || !res.stdout) return;
    const parts = res.stdout.trim().split("|");
    if (parts.length >= 2) {
      const pBatCap = parts[0].trim();
      const pBatTempRaw = parseInt(parts[1].trim(), 10) || 300;
      elCurBattery.textContent = `${pBatCap}%`;
      const tempC = Math.round(pBatTempRaw / 10);
      elCurTemp.textContent = `${tempC}°C`;
      if (tempC >= 42) {
        elCurTemp.style.color = "var(--danger)";
      } else if (tempC >= 38) {
        elCurTemp.style.color = "var(--warning)";
      } else {
        elCurTemp.style.color = "var(--accent-green)";
      }
    }
  } catch (err) {
    console.error("updateTelemetry error:", err);
  }
}

// Apply All Changes to Kernel & Update /sdcard/ki_optimizer.conf
async function applyChanges(silent = false) {
  if (!isKiKernelActive) {
    showToast("❌ Cannot apply: Incompatible kernel detected!");
    return;
  }

  const prof = currentProfile;
  const mglru = currentMglruMode;
  const bypass = toggleBypass?.checked ? "1" : "0";
  const fastcharge = toggleFastCharge?.checked ? "1" : "0";
  const screenoff = toggleScreenOff?.checked ? "1" : "0";
  const wakelock = toggleWakelock?.checked ? "1" : "0";
  const dynfsync = toggleDynFsync?.checked ? "1" : "0";
  const thermal = toggleThermal?.checked ? "1" : "0";
  const swap = rangeSwappiness?.value || "80";
  const tcp = selectTcp?.value || "bbr";

  // Single shell payload for maximum speed & atomic save
  const script = `
    # 1. Apply CPU Profile
    echo ${prof} > /proc/ki_profile 2>/dev/null
    echo ${prof} > /sys/kernel/ki_profile/mode 2>/dev/null

    # 2. Apply MGLRU
    if [ "${mglru}" = "7" ]; then
      echo 1 > /proc/mglru 2>/dev/null
      echo 0x0007 > /sys/kernel/mm/lru_gen/enabled 2>/dev/null
    elif [ "${mglru}" = "1" ]; then
      echo 0x0001 > /proc/mglru 2>/dev/null
      echo 0x0001 > /sys/kernel/mm/lru_gen/enabled 2>/dev/null
    else
      echo 0 > /proc/mglru 2>/dev/null
      echo 0x0000 > /sys/kernel/mm/lru_gen/enabled 2>/dev/null
    fi

    # 3. Apply Bypass Charging (Direct Wall Power, keep ICL intact)
    echo ${bypass} > /proc/bypass_charging 2>/dev/null
    echo ${bypass} > /sys/class/power_supply/battery/bypass_charging 2>/dev/null

    # 4. Apply Fast Charge
    echo ${fastcharge} > /sys/kernel/fast_charge/force_fast_charge 2>/dev/null
    echo ${fastcharge} > /sys/kernel/fast_charge/screen_on_fast_charge 2>/dev/null

    # 5. Apply Screen-Off Eco
    echo ${screenoff} > /sys/kernel/ki_profile/screen_off_battery 2>/dev/null

    # 6. Apply Wakelock Blocker
    if [ "${wakelock}" = "1" ]; then
      echo 1 > /sys/kernel/wakelock_blocker/enabled 2>/dev/null
      echo 1 > /sys/devices/virtual/misc/boeffla_wakelock_blocker/wakelock_blocker 2>/dev/null
    else
      echo 0 > /sys/kernel/wakelock_blocker/enabled 2>/dev/null
      echo 0 > /sys/devices/virtual/misc/boeffla_wakelock_blocker/wakelock_blocker 2>/dev/null
    fi

    # 7. Apply Dynamic Fsync
    echo ${dynfsync} > /sys/kernel/dyn_fsync/Dyn_fsync_active 2>/dev/null
    echo ${dynfsync} > /sys/kernel/dyn_fsync/dyn_fsync_active 2>/dev/null

    # 8. Apply Thermal Throttle Guard
    echo ${thermal} > /sys/kernel/ki_profile/thermal_throttle 2>/dev/null

    # 9. Apply TCP Congestion
    echo "${tcp}" > /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null

    # 10. Apply Swappiness
    echo ${swap} > /proc/sys/vm/swappiness 2>/dev/null

    # 11. Persist to /sdcard/ki_optimizer.conf
    CONF="/sdcard/ki_optimizer.conf"
    if [ -f "$CONF" ]; then
      sed -i -E "s/^KI_PROFILE=.*/KI_PROFILE=${prof}/" "$CONF" 2>/dev/null
      sed -i -E "s/^MGLRU_MODE=.*/MGLRU_MODE=${mglru}/" "$CONF" 2>/dev/null
      sed -i -E "s/^MGLRU_ENABLED=.*/MGLRU_ENABLED=${mglru}/" "$CONF" 2>/dev/null
      sed -i -E "s/^BYPASS_CHARGING=.*/BYPASS_CHARGING=${bypass}/" "$CONF" 2>/dev/null
      sed -i -E "s/^SCREEN_ON_FAST_CHARGE=.*/SCREEN_ON_FAST_CHARGE=${fastcharge}/" "$CONF" 2>/dev/null
      sed -i -E "s/^FORCE_FAST_CHARGE=.*/FORCE_FAST_CHARGE=${fastcharge}/" "$CONF" 2>/dev/null
      sed -i -E "s/^SCREEN_OFF_BATTERY=.*/SCREEN_OFF_BATTERY=${screenoff}/" "$CONF" 2>/dev/null
      sed -i -E "s/^WAKELOCK_BLOCKER=.*/WAKELOCK_BLOCKER=${wakelock}/" "$CONF" 2>/dev/null
      sed -i -E "s/^THERMAL_THROTTLE=.*/THERMAL_THROTTLE=${thermal}/" "$CONF" 2>/dev/null
      sed -i -E "s/^DYNAMIC_FSYNC=.*/DYNAMIC_FSYNC=${dynfsync}/" "$CONF" 2>/dev/null
      sed -i -E "s/^TCP_CONGESTION=.*/TCP_CONGESTION=\\"${tcp}\\"/" "$CONF" 2>/dev/null
      sed -i -E "s/^SWAPPINESS=.*/SWAPPINESS=${swap}/" "$CONF" 2>/dev/null
    fi
  `;

  try {
    await exec(script);
    if (!silent) {
      const profName = prof === 0 ? "Battery Saver" : prof === 2 ? "Turbo Gaming" : "Balanced";
      showToast(`✔ ${profName} profile & tweaks applied!`);
    }
  } catch (err) {
    console.error("applyChanges error:", err);
    showToast("❌ Failed to apply settings. Check kernel support.");
  }
}

// Event Listeners
cardProf0?.addEventListener("click", () => {
  setProfileInstant(0);
});

cardProf1?.addEventListener("click", () => {
  setProfileInstant(1);
});

cardProf2?.addEventListener("click", () => {
  setProfileInstant(2);
});

mglruBtns.forEach(btn => {
  if (btn) {
    btn.addEventListener("click", () => {
      const mode = parseInt(btn.dataset.mode, 10);
      setMglruUI(mode, true);
    });
  }
});

rangeSwappiness?.addEventListener("input", (e) => {
  if (valSwappiness) valSwappiness.textContent = e.target.value;
});

btnApply?.addEventListener("click", () => {
  applyChanges(false);
});

// Periodic telemetry poll (every 4 seconds for live battery & temp, decoupled from form controls)
setInterval(updateTelemetry, 4000);

// Initialize on Load
document.addEventListener("DOMContentLoaded", () => {
  refreshState();
});
