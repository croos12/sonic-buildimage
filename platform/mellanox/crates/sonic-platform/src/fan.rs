use anyhow::{Context, Result};
use sonic_thermalctld::fan::{Fan, FanDirection, LedColor};
use std::fs;
use std::path::{Path, PathBuf};

pub struct MlnxFan {
    name: String,
    hwmon_path: PathBuf,
    fan_index: usize,
    pwm_index: Option<usize>,
}

impl MlnxFan {
    pub fn new(name: String, hwmon_path: PathBuf, fan_index: usize, pwm_index: Option<usize>) -> Self {
        Self {
            name,
            hwmon_path,
            fan_index,
            pwm_index,
        }
    }

    fn read_sysfs_value(&self, filename: &str) -> Result<String> {
        let path = self.hwmon_path.join(filename);
        fs::read_to_string(&path)
            .with_context(|| format!("Failed to read {}", path.display()))
            .map(|s| s.trim().to_string())
    }

    fn read_sysfs_u32(&self, filename: &str) -> Result<u32> {
        self.read_sysfs_value(filename)?
            .parse()
            .with_context(|| format!("Failed to parse {} as u32", filename))
    }

    fn write_sysfs_value(&self, filename: &str, value: &str) -> Result<()> {
        let path = self.hwmon_path.join(filename);
        fs::write(&path, value)
            .with_context(|| format!("Failed to write to {}", path.display()))
    }

    fn rpm_to_percentage(&self, rpm: u32) -> u32 {
        const MAX_RPM: u32 = 25000;
        ((rpm as f32 / MAX_RPM as f32) * 100.0).min(100.0) as u32
    }

    fn pwm_to_percentage(&self, pwm: u32) -> u32 {
        ((pwm as f32 / 255.0) * 100.0) as u32
    }

    fn percentage_to_pwm(&self, percentage: u32) -> u32 {
        ((percentage.min(100) as f32 / 100.0) * 255.0) as u32
    }
}

impl Fan for MlnxFan {
    fn get_name(&self) -> Result<String> {
        Ok(self.name.clone())
    }

    fn get_presence(&self) -> Result<bool> {
        let fault_file = format!("fan{}_fault", self.fan_index);
        match self.read_sysfs_u32(&fault_file) {
            Ok(0) => Ok(true),
            Ok(_) => Ok(false),
            Err(_) => Ok(true),
        }
    }

    fn get_status(&self) -> Result<bool> {
        let fault_file = format!("fan{}_fault", self.fan_index);
        match self.read_sysfs_u32(&fault_file) {
            Ok(0) => Ok(true),
            Ok(_) => Ok(false),
            Err(_) => Ok(true),
        }
    }

    fn get_speed(&self) -> Result<u32> {
        let input_file = format!("fan{}_input", self.fan_index);
        let rpm = self.read_sysfs_u32(&input_file)?;
        Ok(self.rpm_to_percentage(rpm))
    }

    fn get_target_speed(&self) -> Result<u32> {
        if let Some(pwm_idx) = self.pwm_index {
            let pwm_file = format!("pwm{}", pwm_idx);
            let pwm = self.read_sysfs_u32(&pwm_file)?;
            Ok(self.pwm_to_percentage(pwm))
        } else {
            self.get_speed()
        }
    }

    fn is_under_speed(&self) -> Result<bool> {
        let speed = self.get_speed()?;
        let target = self.get_target_speed()?;
        const TOLERANCE: u32 = 20;

        Ok(speed < target.saturating_sub(TOLERANCE))
    }

    fn is_over_speed(&self) -> Result<bool> {
        let speed = self.get_speed()?;
        let target = self.get_target_speed()?;
        const TOLERANCE: u32 = 20;

        Ok(speed > target.saturating_add(TOLERANCE))
    }

    fn get_direction(&self) -> Result<FanDirection> {
        Ok(FanDirection::Intake)
    }

    fn get_model(&self) -> Result<String> {
        let name_file = self.hwmon_path.join("name");
        match fs::read_to_string(&name_file) {
            Ok(name) => Ok(name.trim().to_string()),
            Err(_) => Ok("Mellanox Fan".to_string()),
        }
    }

    fn get_serial(&self) -> Result<String> {
        Ok("N/A".to_string())
    }

    fn is_replaceable(&self) -> Result<bool> {
        Ok(true)
    }

    fn get_position_in_parent(&self) -> Result<usize> {
        Ok(self.fan_index)
    }

    fn set_status_led(&self, _color: LedColor) -> Result<()> {
        Ok(())
    }

    fn get_status_led(&self) -> Result<LedColor> {
        if self.get_status()? {
            Ok(LedColor::Green)
        } else {
            Ok(LedColor::Red)
        }
    }
}

pub fn set_fan_speed(hwmon_path: &Path, pwm_index: usize, speed_percentage: u32) -> Result<()> {
    let pwm_file = format!("pwm{}", pwm_index);
    let pwm_value = ((speed_percentage.min(100) as f32 / 100.0) * 255.0) as u32;

    let path = hwmon_path.join(&pwm_file);
    fs::write(&path, pwm_value.to_string())
        .with_context(|| format!("Failed to set fan speed via {}", path.display()))?;

    Ok(())
}
