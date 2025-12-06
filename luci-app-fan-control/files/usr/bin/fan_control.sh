#!/bin/sh

CONFIG_SECTION="fan_control"
CONFIG_FILE="/etc/config/fan_control"

get_config() {
    config_get_bool enabled $1 enabled 0
    config_get sensor $1 sensor
    config_get fan $1 fan
}

load_config() {
    config_load fan_control
    config_foreach get_config fan_control
}

set_fan_speed() {
    local pwm_path="$1"
    local speed="$2"
    
    if [ -w "$pwm_path" ]; then
        echo "$speed" > "$pwm_path"
    fi
}

read_temp() {
    local temp_path="$1"
    if [ -r "$temp_path" ]; then
        cat "$temp_path"
    else
        echo 0
    fi
}

main_loop() {
    while true; do
        load_config
        
        if [ "$enabled" -eq 1 ] && [ -n "$sensor" ] && [ -n "$fan" ]; then
            # Construct paths based on selection
            # Assuming sensor is like "hwmon0" and we want "temp1_input"
            # And fan is like "hwmon1" and we want "pwm1"
            # This logic might need adjustment based on exact sysfs structure
            
            # For simplicity, let's assume the user selects the full path or we construct it
            # But the requirement says "scan /sys/class/hwmon subdir, get data from `name` file"
            # So the config probably stores the 'name' or the hwmon path.
            # Let's assume the config stores the full path to the hwmon dir for now, 
            # or we find it by name.
            
            # Actually, let's look at the requirement: "add a select component for name list"
            # So the value stored is likely the directory name or the content of the 'name' file.
            # Let's assume we store the directory path (e.g., /sys/class/hwmon/hwmon0) 
            # mapped from the friendly name in LuCI.
            
            # Wait, LuCI model will likely store the value selected.
            # Let's assume the value stored is the absolute path to the hwmon directory.
            
            TEMP_INPUT="$sensor/temp1_input"
            PWM_OUTPUT="$fan/pwm1"
            
            if [ -f "$TEMP_INPUT" ]; then
                CURRENT_TEMP=$(read_temp "$TEMP_INPUT")
                # Convert millidegrees to degrees
                CURRENT_TEMP_C=$((CURRENT_TEMP / 1000))
                
                # Simple logic: 
                # < 40C: 0 (Off)
                # 40-50C: 100 (Low)
                # 50-60C: 150 (Medium)
                # > 60C: 255 (High)
                
                TARGET_PWM=0
                if [ "$CURRENT_TEMP_C" -ge 60 ]; then
                    TARGET_PWM=255
                elif [ "$CURRENT_TEMP_C" -ge 50 ]; then
                    TARGET_PWM=150
                elif [ "$CURRENT_TEMP_C" -ge 40 ]; then
                    TARGET_PWM=100
                fi
                
                set_fan_speed "$PWM_OUTPUT" "$TARGET_PWM"
            fi
        fi
        
        sleep 5
    done
}

. /lib/functions.sh

main_loop
