use anyhow::{Context, Result};
use glob::glob;
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use tracing::{debug, info, warn};

use crate::fan::MlnxFan;
use crate::thermal::MlnxThermal;

pub struct MlnxChassis {
    fans: Vec<Box<dyn sonic_thermalctld::fan::Fan>>,
    fan_drawers: Vec<sonic_thermalctld::fan::FanDrawer>,
    thermals: Vec<Box<dyn sonic_thermalctld::thermal::Thermal>>,
}

impl MlnxChassis {
    pub fn new() -> Result<Self> {
        info!("Initializing Mellanox chassis");

        let mut chassis = Self {
            fans: Vec::new(),
            fan_drawers: Vec::new(),
            thermals: Vec::new(),
        };

        chassis.discover_hwmon_devices()?;

        info!(
            "Mellanox chassis initialized: {} fans, {} thermals",
            chassis.fans.len(),
            chassis.thermals.len()
        );

        Ok(chassis)
    }

    fn discover_hwmon_devices(&mut self) -> Result<()> {
        let hwmon_pattern = "/sys/class/hwmon/hwmon*";

        for entry in glob(hwmon_pattern).context("Failed to read hwmon pattern")? {
            match entry {
                Ok(path) => {
                    if let Err(e) = self.process_hwmon_device(&path) {
                        warn!("Failed to process hwmon device {}: {}", path.display(), e);
                    }
                }
                Err(e) => warn!("Failed to read hwmon entry: {}", e),
            }
        }

        Ok(())
    }

    fn process_hwmon_device(&mut self, hwmon_path: &Path) -> Result<()> {
        let name = self.read_hwmon_name(hwmon_path)?;
        debug!("Processing hwmon device: {} at {}", name, hwmon_path.display());

        if name.contains("mlxsw") {
            self.discover_mlxsw_sensors(hwmon_path, &name)?;
        } else if name.contains("fan") || name.contains("cooling") {
            self.discover_fans(hwmon_path, &name)?;
        } else {
            self.discover_generic_sensors(hwmon_path, &name)?;
        }

        Ok(())
    }

    fn read_hwmon_name(&self, hwmon_path: &Path) -> Result<String> {
        let name_path = hwmon_path.join("name");
        fs::read_to_string(&name_path)
            .context("Failed to read hwmon name")
            .map(|s| s.trim().to_string())
    }

    fn discover_mlxsw_sensors(&mut self, hwmon_path: &Path, _name: &str) -> Result<()> {
        let mut temp_indices = Vec::new();
        let mut fan_indices = Vec::new();
        let mut pwm_indices = Vec::new();

        for entry in fs::read_dir(hwmon_path)? {
            let entry = entry?;
            let filename = entry.file_name();
            let filename_str = filename.to_string_lossy();

            if filename_str.starts_with("temp") && filename_str.ends_with("_input") {
                if let Some(idx_str) = filename_str.strip_prefix("temp").and_then(|s| s.strip_suffix("_input")) {
                    if let Ok(idx) = idx_str.parse::<usize>() {
                        temp_indices.push(idx);
                    }
                }
            } else if filename_str.starts_with("fan") && filename_str.ends_with("_input") {
                if let Some(idx_str) = filename_str.strip_prefix("fan").and_then(|s| s.strip_suffix("_input")) {
                    if let Ok(idx) = idx_str.parse::<usize>() {
                        fan_indices.push(idx);
                    }
                }
            } else if filename_str.starts_with("pwm") && !filename_str.contains('_') {
                if let Some(idx_str) = filename_str.strip_prefix("pwm") {
                    if let Ok(idx) = idx_str.parse::<usize>() {
                        pwm_indices.push(idx);
                    }
                }
            }
        }

        temp_indices.sort_unstable();
        fan_indices.sort_unstable();
        pwm_indices.sort_unstable();

        for temp_idx in temp_indices {
            let name = format!("Thermal {}", temp_idx);
            let thermal = MlnxThermal::new(name, hwmon_path.to_path_buf(), temp_idx);
            self.thermals.push(Box::new(thermal));
            debug!("Added thermal sensor at temp{}", temp_idx);
        }

        for (i, fan_idx) in fan_indices.iter().enumerate() {
            let name = format!("Fan {}", fan_idx);
            let pwm_idx = pwm_indices.get(i).copied();
            let fan = MlnxFan::new(name, hwmon_path.to_path_buf(), *fan_idx, pwm_idx);
            self.fans.push(Box::new(fan));
            debug!("Added fan at fan{} with pwm{:?}", fan_idx, pwm_idx);
        }

        Ok(())
    }

    fn discover_fans(&mut self, hwmon_path: &Path, name: &str) -> Result<()> {
        let mut fan_indices = Vec::new();

        for entry in fs::read_dir(hwmon_path)? {
            let entry = entry?;
            let filename = entry.file_name();
            let filename_str = filename.to_string_lossy();

            if filename_str.starts_with("fan") && filename_str.ends_with("_input") {
                if let Some(idx_str) = filename_str.strip_prefix("fan").and_then(|s| s.strip_suffix("_input")) {
                    if let Ok(idx) = idx_str.parse::<usize>() {
                        fan_indices.push(idx);
                    }
                }
            }
        }

        fan_indices.sort_unstable();

        for fan_idx in fan_indices {
            let fan_name = format!("{} Fan {}", name, fan_idx);
            let fan = MlnxFan::new(fan_name, hwmon_path.to_path_buf(), fan_idx, None);
            self.fans.push(Box::new(fan));
            debug!("Added fan {} at {}", fan_idx, hwmon_path.display());
        }

        Ok(())
    }

    fn discover_generic_sensors(&mut self, hwmon_path: &Path, name: &str) -> Result<()> {
        let mut temp_indices = Vec::new();

        for entry in fs::read_dir(hwmon_path)? {
            let entry = entry?;
            let filename = entry.file_name();
            let filename_str = filename.to_string_lossy();

            if filename_str.starts_with("temp") && filename_str.ends_with("_input") {
                if let Some(idx_str) = filename_str.strip_prefix("temp").and_then(|s| s.strip_suffix("_input")) {
                    if let Ok(idx) = idx_str.parse::<usize>() {
                        temp_indices.push(idx);
                    }
                }
            }
        }

        temp_indices.sort_unstable();

        for temp_idx in temp_indices {
            let thermal_name = format!("{} Thermal {}", name, temp_idx);
            let thermal = MlnxThermal::new(thermal_name, hwmon_path.to_path_buf(), temp_idx);
            self.thermals.push(Box::new(thermal));
            debug!("Added thermal {} at {}", temp_idx, hwmon_path.display());
        }

        Ok(())
    }

    pub fn get_fans(&self) -> &[Box<dyn sonic_thermalctld::fan::Fan>] {
        &self.fans
    }

    pub fn get_fan_drawers(&self) -> &[sonic_thermalctld::fan::FanDrawer] {
        &self.fan_drawers
    }

    pub fn get_thermals(&self) -> &[Box<dyn sonic_thermalctld::thermal::Thermal>] {
        &self.thermals
    }

    pub fn into_components(
        self,
    ) -> (
        Vec<Box<dyn sonic_thermalctld::fan::Fan>>,
        Vec<sonic_thermalctld::fan::FanDrawer>,
        Vec<Box<dyn sonic_thermalctld::thermal::Thermal>>,
    ) {
        (self.fans, self.fan_drawers, self.thermals)
    }
}
