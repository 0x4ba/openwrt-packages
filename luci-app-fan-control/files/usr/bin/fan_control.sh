#!/bin/sh

. /lib/functions.sh

# Global variables
enabled=""
sensor=""
fan=""
temp_maps=""

# Get main configuration
get_main_config() {
    config_get_bool enabled "$1" enabled 0
    config_get sensor "$1" sensor
    config_get fan "$1" fan
}

# Collect temperature mapping entries
get_temp_map() {
    local temperature speed
    config_get temperature "$1" temperature
    config_get speed "$1" speed

    if [ -n "$temperature" ] && [ -n "$speed" ]; then
        temp_maps="$temp_maps$temperature:$speed "
    fi
}

# Load configuration
load_config() {
    enabled=""
    sensor=""
    fan=""
    temp_maps=""

    config_load fan_control
    config_foreach get_main_config fan_control
    config_foreach get_temp_map map
}

# Set fan speed via PWM
set_fan_speed() {
    local pwm_path="$1"
    local speed="$2"

    if [ -w "$pwm_path" ]; then
        echo "$speed" > "$pwm_path"
    fi
}

# Read temperature from sensor
read_temp() {
    local temp_path="$1"
    if [ -r "$temp_path" ]; then
        cat "$temp_path"
    else
        echo 0
    fi
}

# Find first temp*_input file in sensor directory
find_temp_input() {
    local sensor_dir="$1"
    local temp_file

    for file in "$sensor_dir"/temp*_input; do
        if [ -r "$file" ]; then
            echo "$file"
            return 0
        fi
    done
    return 1
}

# Find first pwm* file in fan directory
find_pwm_output() {
    local fan_dir="$1"
    local pwm_file

    for file in "$fan_dir"/pwm[0-9]*; do
        if [ -w "$file" ]; then
            echo "$file"
            return 0
        fi
    done
    return 1
}

# Calculate target PWM based on temperature mappings
# Logic: Find highest temperature threshold that current temp meets or exceeds
calculate_target_pwm() {
    local current_temp="$1"
    local target_pwm=0
    local highest_matching_temp=-999

    # Parse temperature mappings (format: "temp1:speed1 temp2:speed2 ...")
    for mapping in $temp_maps; do
        local temp="${mapping%%:*}"
        local speed="${mapping##*:}"

        # If current temp >= threshold temp, and this threshold is higher than previous matches
        if [ "$current_temp" -ge "$temp" ] && [ "$temp" -ge "$highest_matching_temp" ]; then
            highest_matching_temp="$temp"
            target_pwm="$speed"
        fi
    done

    echo "$target_pwm"
}

# Main control loop
main_loop() {
    while true; do
        load_config

        if [ "$enabled" -eq 1 ] && [ -n "$sensor" ] && [ -n "$fan" ]; then
            # Find temperature input file
            TEMP_INPUT=$(find_temp_input "$sensor")
            if [ -z "$TEMP_INPUT" ]; then
                sleep 5
                continue
            fi

            # Find PWM output file
            PWM_OUTPUT=$(find_pwm_output "$fan")
            if [ -z "$PWM_OUTPUT" ]; then
                sleep 5
                continue
            fi

            # Read current temperature
            CURRENT_TEMP_MILLI=$(read_temp "$TEMP_INPUT")
            CURRENT_TEMP_C=$((CURRENT_TEMP_MILLI / 1000))

            # Calculate target PWM based on mappings
            TARGET_PWM=$(calculate_target_pwm "$CURRENT_TEMP_C")

            # Set fan speed
            set_fan_speed "$PWM_OUTPUT" "$TARGET_PWM"
        fi

        sleep 5
    done
}

main_loop
