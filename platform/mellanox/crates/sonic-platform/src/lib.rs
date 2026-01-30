pub mod chassis;
pub mod fan;
pub mod thermal;

pub use chassis::MlnxChassis;
pub use fan::{
    MlnxFan, Fan, FanDirection, FanDrawer, FanStatus, LedColor, set_fan_speed
};
pub use thermal::{MlnxThermal, Thermal, TemperatureStatus};

use anyhow::Result;
use std::fs;

pub fn detect_platform() -> bool {
    is_mellanox_platform()
}

pub fn is_mellanox_platform() -> bool {
    if let Ok(dmi_board_vendor) = fs::read_to_string("/sys/class/dmi/id/board_vendor") {
        if dmi_board_vendor.to_lowercase().contains("mellanox") {
            return true;
        }
    }

    if let Ok(dmi_sys_vendor) = fs::read_to_string("/sys/class/dmi/id/sys_vendor") {
        if dmi_sys_vendor.to_lowercase().contains("mellanox")
            || dmi_sys_vendor.to_lowercase().contains("nvidia") {
            return true;
        }
    }

    if let Ok(entries) = fs::read_dir("/sys/class/hwmon") {
        for entry in entries.flatten() {
            if let Ok(name) = fs::read_to_string(entry.path().join("name")) {
                if name.trim().contains("mlxsw") {
                    return true;
                }
            }
        }
    }

    false
}

pub fn create_chassis() -> Result<MlnxChassis> {
    MlnxChassis::new()
}
