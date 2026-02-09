use anyhow::{Context, Result};
use std::fs;
use std::path::PathBuf;

pub trait Thermal: Send + Sync {
    fn get_name(&self) -> Result<String>;

    fn get_temperature(&self) -> Result<f32>;

    fn get_high_threshold(&self) -> Result<f32>;

    fn get_low_threshold(&self) -> Result<f32>;

    fn get_high_critical_threshold(&self) -> Result<f32>;

    fn get_low_critical_threshold(&self) -> Result<f32>;

    fn get_minimum_recorded(&self) -> Result<f32>;

    fn get_maximum_recorded(&self) -> Result<f32>;

    fn is_replaceable(&self) -> Result<bool>;

    fn get_position_in_parent(&self) -> Result<usize>;
}

#[derive(Debug)]
pub struct TemperatureStatus {
    pub temperature: Option<f32>,
    pub over_temperature: bool,
    pub under_temperature: bool,
}

impl TemperatureStatus {
    pub fn new() -> Self {
        Self {
            temperature: None,
            over_temperature: false,
            under_temperature: false,
        }
    }

    pub fn set_temperature(&mut self, name: &str, new_temp: f32) -> bool {
        const TEMPERATURE_DIFF_THRESHOLD: f32 = 10.0;

        if let Some(old_temp) = self.temperature {
            let diff = (new_temp - old_temp).abs();
            if diff > TEMPERATURE_DIFF_THRESHOLD {
                tracing::warn!(
                    "Temperature of {} changed too fast: {} -> {}°C",
                    name,
                    old_temp,
                    new_temp
                );
            }
        }

        let changed = self.temperature.map_or(true, |t| (t - new_temp).abs() > 0.1);
        self.temperature = Some(new_temp);
        changed
    }

    pub fn set_over_temperature(&mut self, temperature: f32, threshold: f32) -> bool {
        const NOT_AVAILABLE: f32 = -999.0;

        if (temperature - NOT_AVAILABLE).abs() < 0.1 || (threshold - NOT_AVAILABLE).abs() < 0.1 {
            return false;
        }

        let new_status = temperature > threshold;
        let changed = self.over_temperature != new_status;
        self.over_temperature = new_status;
        changed
    }

    pub fn set_under_temperature(&mut self, temperature: f32, threshold: f32) -> bool {
        const NOT_AVAILABLE: f32 = -999.0;

        if (temperature - NOT_AVAILABLE).abs() < 0.1 || (threshold - NOT_AVAILABLE).abs() < 0.1 {
            return false;
        }

        let new_status = temperature < threshold;
        let changed = self.under_temperature != new_status;
        self.under_temperature = new_status;
        changed
    }
}

impl Default for TemperatureStatus {
    fn default() -> Self {
        Self::new()
    }
}

pub struct MlnxThermal {
    name: String,
    hwmon_path: PathBuf,
    temp_index: usize,
    min_temp: f32,
    max_temp: f32,
}

impl MlnxThermal {
    pub fn new(name: String, hwmon_path: PathBuf, temp_index: usize) -> Self {
        Self {
            name,
            hwmon_path,
            temp_index,
            min_temp: 1000.0,
            max_temp: -1000.0,
        }
    }

    fn read_sysfs_value(&self, filename: &str) -> Result<String> {
        let path = self.hwmon_path.join(filename);
        fs::read_to_string(&path)
            .with_context(|| format!("Failed to read {}", path.display()))
            .map(|s| s.trim().to_string())
    }

    fn read_sysfs_temp(&self, filename: &str) -> Result<f32> {
        let millidegrees: i32 = self.read_sysfs_value(filename)?
            .parse()
            .with_context(|| format!("Failed to parse {} as temperature", filename))?;

        Ok(millidegrees as f32 / 1000.0)
    }

    fn update_min_max(&mut self, temp: f32) {
        if temp < self.min_temp {
            self.min_temp = temp;
        }
        if temp > self.max_temp {
            self.max_temp = temp;
        }
    }
}

impl Thermal for MlnxThermal {
    fn get_name(&self) -> Result<String> {
        let label_file = format!("temp{}_label", self.temp_index);
        match self.read_sysfs_value(&label_file) {
            Ok(label) => Ok(label),
            Err(_) => Ok(self.name.clone()),
        }
    }

    fn get_temperature(&self) -> Result<f32> {
        let input_file = format!("temp{}_input", self.temp_index);
        let temp = self.read_sysfs_temp(&input_file)?;

        Ok(temp)
    }

    fn get_high_threshold(&self) -> Result<f32> {
        let max_file = format!("temp{}_max", self.temp_index);
        match self.read_sysfs_temp(&max_file) {
            Ok(temp) => Ok(temp),
            Err(_) => Ok(85.0),
        }
    }

    fn get_low_threshold(&self) -> Result<f32> {
        let min_file = format!("temp{}_min", self.temp_index);
        match self.read_sysfs_temp(&min_file) {
            Ok(temp) => Ok(temp),
            Err(_) => Ok(0.0),
        }
    }

    fn get_high_critical_threshold(&self) -> Result<f32> {
        let crit_file = format!("temp{}_crit", self.temp_index);
        match self.read_sysfs_temp(&crit_file) {
            Ok(temp) => Ok(temp),
            Err(_) => Ok(100.0),
        }
    }

    fn get_low_critical_threshold(&self) -> Result<f32> {
        Ok(-10.0)
    }

    fn get_minimum_recorded(&self) -> Result<f32> {
        let lowest_file = format!("temp{}_lowest", self.temp_index);
        match self.read_sysfs_temp(&lowest_file) {
            Ok(temp) => Ok(temp),
            Err(_) => Ok(self.min_temp),
        }
    }

    fn get_maximum_recorded(&self) -> Result<f32> {
        let highest_file = format!("temp{}_highest", self.temp_index);
        match self.read_sysfs_temp(&highest_file) {
            Ok(temp) => Ok(temp),
            Err(_) => Ok(self.max_temp),
        }
    }

    fn is_replaceable(&self) -> Result<bool> {
        Ok(false)
    }

    fn get_position_in_parent(&self) -> Result<usize> {
        Ok(self.temp_index)
    }
}
